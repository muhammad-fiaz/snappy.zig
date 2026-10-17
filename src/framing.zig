const std = @import("std");
const types = @import("types.zig");
const block = @import("block.zig");
const checksum = @import("checksum.zig");

/// Implements the official Snappy framing format as specified in `framing_format.txt`.
/// Header bytes for the stream identifier chunk: 0xff 0x06 0x00 0x00 "sNaPpY".
pub const STREAM_HEADER = [_]u8{
    types.CHUNK_STREAM_IDENTIFIER,
    0x06,
    0x00,
    0x00,
    's',
    'N',
    'a',
    'P',
    'p',
    'Y',
};

/// Maximum allowable uncompressed chunk payload in a framed stream.
pub const MAX_CHUNK_PAYLOAD = 65536;

/// Calculates the maximum possible size of a framed Snappy stream for the given input length.
pub fn maxFramedCompressedSize(input_len: usize) usize {
    if (input_len == 0) return STREAM_HEADER.len;
    const chunk_overhead = 8 + block.maxCompressedSize(MAX_CHUNK_PAYLOAD);
    const num_chunks = (input_len / MAX_CHUNK_PAYLOAD) + if (input_len % MAX_CHUNK_PAYLOAD != 0) @as(usize, 1) else @as(usize, 0);
    if (num_chunks > (std.math.maxInt(usize) - STREAM_HEADER.len) / chunk_overhead) {
        return std.math.maxInt(usize);
    }
    return STREAM_HEADER.len + num_chunks * chunk_overhead;
}

/// Compresses data into Snappy framed format in a caller-provided destination buffer.
pub fn compressInto(
    input: []const u8,
    output: []u8,
    options: types.CompressionOptions,
) types.Error!usize {
    const required_max = maxFramedCompressedSize(input.len);
    if (output.len < required_max and output.len < input.len + 32) {
        return error.OutputBufferTooSmall;
    }
    if (output.len < STREAM_HEADER.len) {
        return error.OutputBufferTooSmall;
    }

    @memcpy(output[0..STREAM_HEADER.len], &STREAM_HEADER);
    var op = STREAM_HEADER.len;

    if (input.len == 0) {
        return op;
    }

    var scratch_block: [block.maxCompressedSize(MAX_CHUNK_PAYLOAD)]u8 = undefined;

    var in_pos: usize = 0;
    while (in_pos < input.len) {
        const chunk_size = @min(input.len - in_pos, MAX_CHUNK_PAYLOAD);
        const chunk_data = input[in_pos .. in_pos + chunk_size];
        const masked_crc = checksum.maskedHash(chunk_data);

        // Try compressing the chunk as a raw block.
        const comp_len = block.compressInto(chunk_data, &scratch_block, options) catch 0;

        // Snappy framing specification:
        // If compressed chunk is smaller than uncompressed, emit compressed chunk (0x00).
        // Otherwise, emit uncompressed chunk (0x01).
        if (comp_len > 0 and comp_len < chunk_size) {
            // Compressed chunk: 1 byte type + 3 bytes len + 4 bytes CRC + compressed payload
            const payload_len = 4 + comp_len;
            if (op + 4 + payload_len > output.len) return error.OutputBufferTooSmall;

            output[op] = types.CHUNK_COMPRESSED_DATA;
            output[op + 1] = @as(u8, @truncate(payload_len));
            output[op + 2] = @as(u8, @truncate(payload_len >> 8));
            output[op + 3] = @as(u8, @truncate(payload_len >> 16));
            op += 4;

            std.mem.writeInt(u32, output[op..][0..4], masked_crc, .little);
            op += 4;

            @memcpy(output[op .. op + comp_len], scratch_block[0..comp_len]);
            op += comp_len;
        } else {
            // Uncompressed chunk: 1 byte type + 3 bytes len + 4 bytes CRC + raw payload
            const payload_len = 4 + chunk_size;
            if (op + 4 + payload_len > output.len) return error.OutputBufferTooSmall;

            output[op] = types.CHUNK_UNCOMPRESSED_DATA;
            output[op + 1] = @as(u8, @truncate(payload_len));
            output[op + 2] = @as(u8, @truncate(payload_len >> 8));
            output[op + 3] = @as(u8, @truncate(payload_len >> 16));
            op += 4;

            std.mem.writeInt(u32, output[op..][0..4], masked_crc, .little);
            op += 4;

            @memcpy(output[op .. op + chunk_size], chunk_data);
            op += chunk_size;
        }

        in_pos += chunk_size;
    }

    return op;
}

/// Compresses data into Snappy framed format using the provided allocator.
pub fn compress(
    allocator: std.mem.Allocator,
    input: []const u8,
    options: types.CompressionOptions,
) types.Error![]u8 {
    const max_len = maxFramedCompressedSize(input.len);
    const buf = try allocator.alloc(u8, max_len);
    errdefer allocator.free(buf);

    const actual_len = try compressInto(input, buf, options);
    if (actual_len == buf.len) return buf;

    const trimmed = allocator.realloc(buf, actual_len) catch {
        const copy = try allocator.alloc(u8, actual_len);
        @memcpy(copy, buf[0..actual_len]);
        allocator.free(buf);
        return copy;
    };
    return trimmed;
}

/// Decompresses Snappy framed data into a caller-provided destination buffer.
pub fn decompressInto(
    input: []const u8,
    output: []u8,
    options: types.DecompressionOptions,
) types.Error!usize {
    if (input.len < STREAM_HEADER.len) return error.TruncatedInput;
    if (!std.mem.startsWith(u8, input, &STREAM_HEADER)) {
        return error.InvalidMagic;
    }

    var in_pos: usize = STREAM_HEADER.len;
    var out_pos: usize = 0;

    var scratch_decomp: [MAX_CHUNK_PAYLOAD]u8 = undefined;

    while (in_pos < input.len) {
        if (in_pos + 4 > input.len) return error.TruncatedInput;
        const chunk_type = input[in_pos];
        const chunk_len = @as(usize, input[in_pos + 1]) |
            (@as(usize, input[in_pos + 2]) << 8) |
            (@as(usize, input[in_pos + 3]) << 16);
        in_pos += 4;

        if (in_pos + chunk_len > input.len) return error.TruncatedInput;
        const chunk_payload = input[in_pos .. in_pos + chunk_len];
        in_pos += chunk_len;

        switch (chunk_type) {
            types.CHUNK_STREAM_IDENTIFIER => {
                // Subsequent stream identifiers are valid (concatenation).
                // Must have length 6 and payload "sNaPpY".
                if (chunk_len != 6 or !std.mem.eql(u8, chunk_payload, types.STREAM_IDENTIFIER)) {
                    return error.CorruptStream;
                }
            },
            types.CHUNK_COMPRESSED_DATA => {
                if (chunk_len < 4) return error.InvalidChunkLength;
                const expected_masked_crc = std.mem.readInt(u32, chunk_payload[0..4], .little);
                const block_data = chunk_payload[4..];

                const chunk_decomp_len = try block.decompressInto(
                    block_data,
                    &scratch_decomp,
                    .{ .maxOutputSize = MAX_CHUNK_PAYLOAD },
                );
                const uncomp_slice = scratch_decomp[0..chunk_decomp_len];

                if (options.verifyChecksums) {
                    const actual_masked_crc = checksum.maskedHash(uncomp_slice);
                    if (actual_masked_crc != expected_masked_crc) {
                        return error.ChecksumMismatch;
                    }
                }

                if (options.maxOutputSize > 0 and out_pos + chunk_decomp_len > options.maxOutputSize) {
                    return error.ResourceLimitExceeded;
                }
                if (out_pos + chunk_decomp_len > output.len) {
                    return error.OutputBufferTooSmall;
                }

                @memcpy(output[out_pos .. out_pos + chunk_decomp_len], uncomp_slice);
                out_pos += chunk_decomp_len;
            },
            types.CHUNK_UNCOMPRESSED_DATA => {
                if (chunk_len < 4) return error.InvalidChunkLength;
                const uncomp_len = chunk_len - 4;
                if (uncomp_len > MAX_CHUNK_PAYLOAD) return error.InvalidChunkLength;

                const expected_masked_crc = std.mem.readInt(u32, chunk_payload[0..4], .little);
                const uncomp_slice = chunk_payload[4..];

                if (options.verifyChecksums) {
                    const actual_masked_crc = checksum.maskedHash(uncomp_slice);
                    if (actual_masked_crc != expected_masked_crc) {
                        return error.ChecksumMismatch;
                    }
                }

                if (options.maxOutputSize > 0 and out_pos + uncomp_len > options.maxOutputSize) {
                    return error.ResourceLimitExceeded;
                }
                if (out_pos + uncomp_len > output.len) {
                    return error.OutputBufferTooSmall;
                }

                @memcpy(output[out_pos .. out_pos + uncomp_len], uncomp_slice);
                out_pos += uncomp_len;
            },
            types.CHUNK_PADDING => {
                // Padding chunks: skip.
            },
            0x02...0x7f => {
                // Reserved unskippable chunk: error according to specification.
                return error.UnknownChunkType;
            },
            0x80...0xfd => {
                // Reserved skippable chunk: skip.
            },
        }
    }

    return out_pos;
}

/// Decompresses Snappy framed data using the provided allocator.
pub fn decompress(
    allocator: std.mem.Allocator,
    input: []const u8,
    options: types.DecompressionOptions,
) types.Error![]u8 {
    // Dynamic ArrayList for assembling uncompressed chunks.
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);

    if (input.len < STREAM_HEADER.len) return error.TruncatedInput;
    if (!std.mem.startsWith(u8, input, &STREAM_HEADER)) {
        return error.InvalidMagic;
    }

    var in_pos: usize = STREAM_HEADER.len;
    var scratch_decomp: [MAX_CHUNK_PAYLOAD]u8 = undefined;

    while (in_pos < input.len) {
        if (in_pos + 4 > input.len) return error.TruncatedInput;
        const chunk_type = input[in_pos];
        const chunk_len = @as(usize, input[in_pos + 1]) |
            (@as(usize, input[in_pos + 2]) << 8) |
            (@as(usize, input[in_pos + 3]) << 16);
        in_pos += 4;

        if (in_pos + chunk_len > input.len) return error.TruncatedInput;
        const chunk_payload = input[in_pos .. in_pos + chunk_len];
        in_pos += chunk_len;

        switch (chunk_type) {
            types.CHUNK_STREAM_IDENTIFIER => {
                if (chunk_len != 6 or !std.mem.eql(u8, chunk_payload, types.STREAM_IDENTIFIER)) {
                    return error.CorruptStream;
                }
            },
            types.CHUNK_COMPRESSED_DATA => {
                if (chunk_len < 4) return error.InvalidChunkLength;
                const expected_masked_crc = std.mem.readInt(u32, chunk_payload[0..4], .little);
                const block_data = chunk_payload[4..];

                const chunk_decomp_len = try block.decompressInto(
                    block_data,
                    &scratch_decomp,
                    .{ .maxOutputSize = MAX_CHUNK_PAYLOAD },
                );
                const uncomp_slice = scratch_decomp[0..chunk_decomp_len];

                if (options.verifyChecksums) {
                    const actual_masked_crc = checksum.maskedHash(uncomp_slice);
                    if (actual_masked_crc != expected_masked_crc) {
                        return error.ChecksumMismatch;
                    }
                }

                if (options.maxOutputSize > 0 and list.items.len + chunk_decomp_len > options.maxOutputSize) {
                    return error.ResourceLimitExceeded;
                }

                try list.appendSlice(allocator, uncomp_slice);
            },
            types.CHUNK_UNCOMPRESSED_DATA => {
                if (chunk_len < 4) return error.InvalidChunkLength;
                const uncomp_len = chunk_len - 4;
                if (uncomp_len > MAX_CHUNK_PAYLOAD) return error.InvalidChunkLength;

                const expected_masked_crc = std.mem.readInt(u32, chunk_payload[0..4], .little);
                const uncomp_slice = chunk_payload[4..];

                if (options.verifyChecksums) {
                    const actual_masked_crc = checksum.maskedHash(uncomp_slice);
                    if (actual_masked_crc != expected_masked_crc) {
                        return error.ChecksumMismatch;
                    }
                }

                if (options.maxOutputSize > 0 and list.items.len + uncomp_len > options.maxOutputSize) {
                    return error.ResourceLimitExceeded;
                }

                try list.appendSlice(allocator, uncomp_slice);
            },
            types.CHUNK_PADDING => {},
            0x02...0x7f => return error.UnknownChunkType,
            0x80...0xfd => {},
        }
    }

    return list.toOwnedSlice(allocator);
}

test "framed stream empty roundtrip" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const comp = try compress(alloc, "", .{});
    defer alloc.free(comp);

    try testing.expectEqualSlices(u8, &STREAM_HEADER, comp);

    const decomp = try decompress(alloc, comp, .{});
    defer alloc.free(decomp);

    try testing.expectEqualStrings("", decomp);
}

test "framed stream basic text roundtrip" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const text = "Snappy framing format test with checksum validation in Zig 0.17.0!";
    const comp = try compress(alloc, text, .{});
    defer alloc.free(comp);

    const decomp = try decompress(alloc, comp, .{});
    defer alloc.free(decomp);

    try testing.expectEqualStrings(text, decomp);
}

test "framed stream multi-chunk large buffer" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const size = 200_000; // Across multiple 64KB chunks
    const data = try alloc.alloc(u8, size);
    defer alloc.free(data);

    for (data, 0..) |*b, i| {
        b.* = @as(u8, @truncate((i * 17) ^ (i >> 5)));
    }

    const comp = try compress(alloc, data, .{});
    defer alloc.free(comp);

    const decomp = try decompress(alloc, comp, .{});
    defer alloc.free(decomp);

    try testing.expectEqualSlices(u8, data, decomp);
}

test "framed stream concatenated frames" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const part1 = "Stream Part 1 - Hello";
    const part2 = "Stream Part 2 - World";

    const comp1 = try compress(alloc, part1, .{});
    defer alloc.free(comp1);

    const comp2 = try compress(alloc, part2, .{});
    defer alloc.free(comp2);

    const combined = try alloc.alloc(u8, comp1.len + comp2.len);
    defer alloc.free(combined);
    @memcpy(combined[0..comp1.len], comp1);
    @memcpy(combined[comp1.len..], comp2);

    const decomp = try decompress(alloc, combined, .{});
    defer alloc.free(decomp);

    const expected = "Stream Part 1 - HelloStream Part 2 - World";
    try testing.expectEqualStrings(expected, decomp);
}

test "framed stream corruption and checksum mismatch detection" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const text = "Data to test checksum corruption";
    const comp = try compress(alloc, text, .{});
    defer alloc.free(comp);

    var corrupted = try alloc.alloc(u8, comp.len);
    defer alloc.free(corrupted);
    @memcpy(corrupted, comp);

    // Corrupt one byte in the payload
    corrupted[corrupted.len - 1] ^= 0x55;

    try testing.expectError(error.ChecksumMismatch, decompress(alloc, corrupted, .{}));
}

test "framed stream skippable and unskippable chunks" {
    const testing = std.testing;
    const alloc = testing.allocator;

    // Build a stream with a skippable chunk (0x80)
    var stream: std.ArrayList(u8) = .empty;
    defer stream.deinit(alloc);

    try stream.appendSlice(alloc, &STREAM_HEADER);

    // Skippable chunk: 0x80, len 3, payload "foo"
    try stream.appendSlice(alloc, &[_]u8{ 0x80, 0x03, 0x00, 0x00, 'f', 'o', 'o' });

    // Uncompressed chunk: 0x01, len 4 + 4, CRC + "test"
    const text = "test";
    const crc = checksum.maskedHash(text);
    var uncomp_header = [_]u8{ 0x01, 0x08, 0x00, 0x00, 0, 0, 0, 0 };
    std.mem.writeInt(u32, uncomp_header[4..8], crc, .little);
    try stream.appendSlice(alloc, &uncomp_header);
    try stream.appendSlice(alloc, text);

    const decomp = try decompress(alloc, stream.items, .{});
    defer alloc.free(decomp);
    try testing.expectEqualStrings("test", decomp);

    // Add unskippable chunk: 0x02
    try stream.appendSlice(alloc, &[_]u8{ 0x02, 0x01, 0x00, 0x00, 'x' });
    try testing.expectError(error.UnknownChunkType, decompress(alloc, stream.items, .{}));
}
