const std = @import("std");
const types = @import("types.zig");
const varint = @import("varint.zig");

/// Implements the Snappy block format defined by Google's Snappy format specification.
pub const HASH_TABLE_BITS = 14;
pub const HASH_TABLE_SIZE = 1 << HASH_TABLE_BITS; // 16384 entries
const HASH_MULTIPLIER: u32 = 0x1e35a7bd;
const SECONDARY_MULTIPLIER: u32 = 0x9e3779b1;

/// Calculates the upper bound of compressed bytes for an input of length `source_bytes`.
/// Formula: 32 + source_bytes + source_bytes / 6.
pub fn maxCompressedSize(source_bytes: usize) usize {
    if (source_bytes > (std.math.maxInt(usize) - 32) / 7 * 6) {
        return std.math.maxInt(usize);
    }
    return 32 + source_bytes + source_bytes / 6;
}

/// Inspects the uncompressed length of a Snappy block without decompressing it.
pub fn uncompressedLength(compressed: []const u8) types.Error!usize {
    const res = try varint.decode(compressed);
    return res.value;
}

/// Checks if a buffer represents a syntactically valid Snappy compressed block.
pub fn isValidCompressedBuffer(compressed: []const u8) bool {
    const dec_var = varint.decode(compressed) catch return false;
    const expected_len: usize = dec_var.value;
    var in_pos: usize = dec_var.bytes_read;
    var out_produced: usize = 0;

    while (out_produced < expected_len) {
        if (in_pos >= compressed.len) return false;
        const tag = compressed[in_pos];
        in_pos += 1;

        const tag_type = tag & 0x03;
        switch (tag_type) {
            types.TAG_LITERAL => {
                const len_tag = tag >> 2;
                var lit_len: usize = 0;
                if (len_tag < 60) {
                    lit_len = len_tag + 1;
                } else {
                    const extra_bytes: usize = (len_tag - 59);
                    if (in_pos + extra_bytes > compressed.len) return false;
                    var extra_len: u64 = 0;
                    for (0..extra_bytes) |b_idx| {
                        extra_len |= @as(u64, compressed[in_pos + b_idx]) << @as(u6, @intCast(b_idx * 8));
                    }
                    in_pos += extra_bytes;
                    const total_len = extra_len + 1;
                    if (total_len > @as(u64, expected_len - out_produced)) return false;
                    lit_len = @as(usize, @intCast(total_len));
                }

                if (lit_len > expected_len - out_produced) return false;
                if (lit_len > compressed.len - in_pos) return false;
                out_produced += lit_len;
                in_pos += lit_len;
            },
            types.TAG_COPY_1 => {
                const copy_len = @as(usize, (tag >> 2) & 7) + 4;
                if (in_pos >= compressed.len) return false;
                const offset = (@as(usize, (tag >> 5) & 7) << 8) | compressed[in_pos];
                in_pos += 1;

                if (offset == 0 or offset > out_produced) return false;
                if (copy_len > expected_len - out_produced) return false;
                out_produced += copy_len;
            },
            types.TAG_COPY_2 => {
                const copy_len = @as(usize, tag >> 2) + 1;
                if (in_pos + 2 > compressed.len) return false;
                const offset = std.mem.readInt(u16, compressed[in_pos..][0..2], .little);
                in_pos += 2;

                if (offset == 0 or offset > out_produced) return false;
                if (copy_len > expected_len - out_produced) return false;
                out_produced += copy_len;
            },
            types.TAG_COPY_4 => {
                const copy_len = @as(usize, tag >> 2) + 1;
                if (in_pos + 4 > compressed.len) return false;
                const offset = std.mem.readInt(u32, compressed[in_pos..][0..4], .little);
                in_pos += 4;

                if (offset == 0 or offset > out_produced) return false;
                if (copy_len > expected_len - out_produced) return false;
                out_produced += copy_len;
            },
            else => return false,
        }
    }

    return (out_produced == expected_len and in_pos == compressed.len);
}

/// Helper for copying backreferences with support for run-length encoding (overlapping copies).
inline fn copyMatch(dst: []u8, out_pos: usize, offset: usize, len: usize) void {
    const src_pos = out_pos - offset;
    if (offset >= 8 and len <= offset) {
        @memcpy(dst[out_pos .. out_pos + len], dst[src_pos .. src_pos + len]);
    } else if (offset == 1) {
        @memset(dst[out_pos .. out_pos + len], dst[src_pos]);
    } else {
        var i: usize = 0;
        while (i < len) : (i += 1) {
            dst[out_pos + i] = dst[src_pos + i];
        }
    }
}

/// Compresses a Snappy block into a caller-provided destination buffer.
pub fn compressInto(
    input: []const u8,
    output: []u8,
    options: types.CompressionOptions,
) types.Error!usize {
    if (input.len > std.math.maxInt(u32)) return error.InputTooLarge;
    const required_bound = maxCompressedSize(input.len);
    if (output.len < required_bound) {
        return error.OutputBufferTooSmall;
    }

    var varint_buf: [varint.MaxBytes]u8 = undefined;
    const varint_len = varint.encode(@as(u32, @intCast(input.len)), &varint_buf);
    if (output.len < varint_len) return error.OutputBufferTooSmall;
    @memcpy(output[0..varint_len], varint_buf[0..varint_len]);
    var op = varint_len;

    if (input.len == 0) {
        return op;
    }

    var table: [HASH_TABLE_SIZE]u16 = undefined;
    var table2: [HASH_TABLE_SIZE]u16 = undefined;

    var in_offset: usize = 0;
    while (in_offset < input.len) {
        const fragment_len = @min(input.len - in_offset, types.MAX_BLOCK_SIZE);
        const fragment = input[in_offset .. in_offset + fragment_len];

        const written = try compressFragment(
            fragment,
            output[op..],
            &table,
            if (options.level >= 2) &table2 else null,
        );
        op += written;
        in_offset += fragment_len;
    }

    return op;
}

/// Emits literal bytes to the output buffer according to the Snappy specification.
fn emitLiteral(literal: []const u8, out: []u8) usize {
    const len = literal.len;
    if (len == 0) return 0;
    var op: usize = 0;

    if (len <= 60) {
        out[op] = types.TAG_LITERAL | (@as(u8, @truncate(len - 1)) << 2);
        op += 1;
    } else if (len <= 256) {
        out[op] = types.TAG_LITERAL | (60 << 2);
        out[op + 1] = @as(u8, @truncate(len - 1));
        op += 2;
    } else if (len <= 65536) {
        out[op] = types.TAG_LITERAL | (61 << 2);
        std.mem.writeInt(u16, out[op + 1 ..][0..2], @as(u16, @truncate(len - 1)), .little);
        op += 3;
    } else if (len <= (1 << 24)) {
        out[op] = types.TAG_LITERAL | (62 << 2);
        out[op + 1] = @as(u8, @truncate(len - 1));
        out[op + 2] = @as(u8, @truncate((len - 1) >> 8));
        out[op + 3] = @as(u8, @truncate((len - 1) >> 16));
        op += 4;
    } else {
        out[op] = types.TAG_LITERAL | (63 << 2);
        std.mem.writeInt(u32, out[op + 1 ..][0..4], @as(u32, @truncate(len - 1)), .little);
        op += 5;
    }

    @memcpy(out[op .. op + len], literal);
    return op + len;
}

/// Emits a copy instruction (backreference) with optimal tag selection.
fn emitCopy(offset: usize, length: usize, out: []u8) usize {
    var op: usize = 0;
    var rem_len = length;

    while (rem_len >= 68) {
        out[op] = types.TAG_COPY_2 | (63 << 2);
        std.mem.writeInt(u16, out[op + 1 ..][0..2], @as(u16, @truncate(offset)), .little);
        op += 3;
        rem_len -= 64;
    }

    if (rem_len > 64) {
        out[op] = types.TAG_COPY_2 | (59 << 2);
        std.mem.writeInt(u16, out[op + 1 ..][0..2], @as(u16, @truncate(offset)), .little);
        op += 3;
        rem_len -= 60;
    }

    if (rem_len < 12 and offset < 2048 and rem_len >= 4) {
        const len_field = @as(u8, @truncate(rem_len - 4));
        const off_hi = @as(u8, @truncate((offset >> 8) & 0x07));
        out[op] = types.TAG_COPY_1 | (len_field << 2) | (off_hi << 5);
        out[op + 1] = @as(u8, @truncate(offset & 0xff));
        op += 2;
    } else if (offset <= 65535) {
        out[op] = types.TAG_COPY_2 | (@as(u8, @truncate(rem_len - 1)) << 2);
        std.mem.writeInt(u16, out[op + 1 ..][0..2], @as(u16, @truncate(offset)), .little);
        op += 3;
    } else {
        out[op] = types.TAG_COPY_4 | (@as(u8, @truncate(rem_len - 1)) << 2);
        std.mem.writeInt(u32, out[op + 1 ..][0..4], @as(u32, @truncate(offset)), .little);
        op += 5;
    }

    return op;
}

/// Compresses a single fragment (at most 65536 bytes) using Snappy's fast LZ77 match finder.
fn compressFragment(
    input: []const u8,
    output: []u8,
    table: *[HASH_TABLE_SIZE]u16,
    table2: ?*[HASH_TABLE_SIZE]u16,
) types.Error!usize {
    @memset(table, 0);
    if (table2) |t2| @memset(t2, 0);

    if (input.len < 4) {
        return emitLiteral(input, output);
    }

    const shift = 32 - HASH_TABLE_BITS;
    var ip: usize = 0;
    var next_emit: usize = 0;
    var op: usize = 0;
    var skip: usize = 32;

    const ip_limit = if (input.len >= 15) input.len - 15 else 0;

    while (ip <= ip_limit) {
        const dword = std.mem.readInt(u32, input[ip..][0..4], .little);
        const hash = (dword *% HASH_MULTIPLIER) >> shift;
        const candidate = @as(usize, table[hash]);
        table[hash] = @as(u16, @truncate(ip));

        var match_len: usize = 0;
        var match_cand = candidate;

        if (candidate < ip and ip - candidate < types.MAX_BLOCK_SIZE) {
            if (std.mem.readInt(u32, input[candidate..][0..4], .little) == dword) {
                match_len = 4;
                while (ip + match_len < input.len and candidate + match_len < ip and
                    input[ip + match_len] == input[candidate + match_len])
                {
                    match_len += 1;
                }
            }
        }

        if (table2) |t2| {
            const hash2 = (dword *% SECONDARY_MULTIPLIER) >> shift;
            const cand2 = @as(usize, t2[hash2]);
            t2[hash2] = @as(u16, @truncate(ip));

            if (cand2 < ip and ip - cand2 < types.MAX_BLOCK_SIZE) {
                if (std.mem.readInt(u32, input[cand2..][0..4], .little) == dword) {
                    var len2: usize = 4;
                    while (ip + len2 < input.len and cand2 + len2 < ip and
                        input[ip + len2] == input[cand2 + len2])
                    {
                        len2 += 1;
                    }
                    if (len2 > match_len) {
                        match_len = len2;
                        match_cand = cand2;
                    }
                }
            }
        }

        if (match_len >= 4) {
            // Emit any pending literal bytes prior to this match.
            if (ip > next_emit) {
                op += emitLiteral(input[next_emit..ip], output[op..]);
            }

            // Emit the match copy instruction.
            const offset = ip - match_cand;
            op += emitCopy(offset, match_len, output[op..]);

            ip += match_len;
            next_emit = ip;
            skip = 32;
        } else {
            // Snappy dynamic skipping heuristic for non-compressible data.
            const step = skip >> 5;
            skip += step;
            ip += step;
        }
    }

    // Emit any remaining bytes as literal.
    if (next_emit < input.len) {
        op += emitLiteral(input[next_emit..], output[op..]);
    }

    return op;
}

/// Decompresses a Snappy block into a caller-provided destination buffer.
pub fn decompressInto(
    input: []const u8,
    output: []u8,
    options: types.DecompressionOptions,
) types.Error!usize {
    const dec_var = try varint.decode(input);
    const expected_len: usize = dec_var.value;

    if (options.maxOutputSize > 0 and expected_len > options.maxOutputSize) {
        return error.ResourceLimitExceeded;
    }
    if (output.len < expected_len) {
        return error.OutputBufferTooSmall;
    }

    var in_pos: usize = dec_var.bytes_read;
    var out_pos: usize = 0;

    while (out_pos < expected_len) {
        if (in_pos >= input.len) return error.TruncatedInput;
        const tag = input[in_pos];
        in_pos += 1;

        const tag_type = tag & 0x03;
        switch (tag_type) {
            types.TAG_LITERAL => {
                const len_tag = tag >> 2;
                var lit_len: usize = 0;
                if (len_tag < 60) {
                    lit_len = len_tag + 1;
                } else {
                    const extra_bytes: usize = (len_tag - 59);
                    if (in_pos + extra_bytes > input.len) return error.TruncatedInput;
                    var extra_len: u64 = 0;
                    for (0..extra_bytes) |b_idx| {
                        extra_len |= @as(u64, input[in_pos + b_idx]) << @as(u6, @intCast(b_idx * 8));
                    }
                    in_pos += extra_bytes;
                    const total_len = extra_len + 1;
                    if (total_len > @as(u64, expected_len - out_pos)) return error.CorruptStream;
                    lit_len = @as(usize, @intCast(total_len));
                }

                if (lit_len > expected_len - out_pos) return error.CorruptStream;
                if (lit_len > input.len - in_pos) return error.TruncatedInput;

                @memcpy(output[out_pos .. out_pos + lit_len], input[in_pos .. in_pos + lit_len]);
                out_pos += lit_len;
                in_pos += lit_len;
            },
            types.TAG_COPY_1 => {
                const copy_len = @as(usize, (tag >> 2) & 7) + 4;
                if (in_pos >= input.len) return error.TruncatedInput;
                const offset = (@as(usize, (tag >> 5) & 7) << 8) | input[in_pos];
                in_pos += 1;

                if (offset == 0 or offset > out_pos) return error.CorruptStream;
                if (copy_len > expected_len - out_pos) return error.CorruptStream;

                copyMatch(output, out_pos, offset, copy_len);
                out_pos += copy_len;
            },
            types.TAG_COPY_2 => {
                const copy_len = @as(usize, tag >> 2) + 1;
                if (in_pos + 2 > input.len) return error.TruncatedInput;
                const offset = std.mem.readInt(u16, input[in_pos..][0..2], .little);
                in_pos += 2;

                if (offset == 0 or offset > out_pos) return error.CorruptStream;
                if (copy_len > expected_len - out_pos) return error.CorruptStream;

                copyMatch(output, out_pos, offset, copy_len);
                out_pos += copy_len;
            },
            types.TAG_COPY_4 => {
                const copy_len = @as(usize, tag >> 2) + 1;
                if (in_pos + 4 > input.len) return error.TruncatedInput;
                const offset = std.mem.readInt(u32, input[in_pos..][0..4], .little);
                in_pos += 4;

                if (offset == 0 or offset > out_pos) return error.CorruptStream;
                if (copy_len > expected_len - out_pos) return error.CorruptStream;

                copyMatch(output, out_pos, offset, copy_len);
                out_pos += copy_len;
            },
            else => unreachable,
        }
    }

    if (out_pos != expected_len) return error.CorruptStream;
    if (in_pos != input.len) return error.CorruptStream;

    return out_pos;
}

/// Compresses a Snappy block using the provided allocator.
pub fn compress(
    allocator: std.mem.Allocator,
    input: []const u8,
    options: types.CompressionOptions,
) types.Error![]u8 {
    const max_len = maxCompressedSize(input.len);
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

/// Decompresses a Snappy block using the provided allocator.
pub fn decompress(
    allocator: std.mem.Allocator,
    input: []const u8,
    options: types.DecompressionOptions,
) types.Error![]u8 {
    const expected_len = try uncompressedLength(input);
    if (options.maxOutputSize > 0 and expected_len > options.maxOutputSize) {
        return error.ResourceLimitExceeded;
    }

    const out = try allocator.alloc(u8, expected_len);
    errdefer allocator.free(out);

    const produced = try decompressInto(input, out, options);
    if (produced != expected_len) return error.CorruptStream;
    return out;
}

test "block empty input roundtrip" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const comp = try compress(alloc, "", .{});
    defer alloc.free(comp);

    const decomp = try decompress(alloc, comp, .{});
    defer alloc.free(decomp);

    try testing.expectEqualStrings("", decomp);
}

test "block small strings roundtrip" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const test_cases = [_][]const u8{
        "a",
        "ab",
        "abc",
        "abcd",
        "Hello, World!",
        "Native Zig Snappy 0.17.0 implementation!",
    };

    for (test_cases) |tc| {
        const comp = try compress(alloc, tc, .{});
        defer alloc.free(comp);

        try testing.expect(isValidCompressedBuffer(comp));

        const decomp = try decompress(alloc, comp, .{});
        defer alloc.free(decomp);

        try testing.expectEqualStrings(tc, decomp);
    }
}

test "block repetitive pattern run-length encoding" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const pattern = "ABCDEF123456";
    const src = try alloc.alloc(u8, pattern.len * 100);
    defer alloc.free(src);
    for (0..100) |i| {
        @memcpy(src[i * pattern.len .. (i + 1) * pattern.len], pattern);
    }

    const comp = try compress(alloc, src, .{});
    defer alloc.free(comp);

    try testing.expect(comp.len < src.len);
    try testing.expect(isValidCompressedBuffer(comp));

    const decomp = try decompress(alloc, comp, .{});
    defer alloc.free(decomp);

    try testing.expectEqualStrings(src, decomp);
}

test "block large buffer exceeding 64KB fragment" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const size = 150_000;
    const big_buf = try alloc.alloc(u8, size);
    defer alloc.free(big_buf);

    for (big_buf, 0..) |*b, i| {
        b.* = @as(u8, @truncate(i ^ (i >> 3)));
    }

    const comp = try compress(alloc, big_buf, .{});
    defer alloc.free(comp);

    try testing.expect(isValidCompressedBuffer(comp));

    const decomp = try decompress(alloc, comp, .{});
    defer alloc.free(decomp);

    try testing.expectEqualSlices(u8, big_buf, decomp);
}

test "block level 2 compression" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const pattern = "The quick brown fox jumps over the lazy dog. ";
    const text = try alloc.alloc(u8, pattern.len * 200);
    defer alloc.free(text);
    for (0..200) |i| {
        @memcpy(text[i * pattern.len .. (i + 1) * pattern.len], pattern);
    }

    const comp1 = try compress(alloc, text, .{ .level = 1 });
    defer alloc.free(comp1);

    const comp2 = try compress(alloc, text, .{ .level = 2 });
    defer alloc.free(comp2);

    const decomp2 = try decompress(alloc, comp2, .{});
    defer alloc.free(decomp2);

    try testing.expectEqualStrings(text, decomp2);
}

test "block zero offset corruption rejection" {
    const testing = std.testing;
    // Length 64 (0x40), then copy with offset 0
    const bad_data = [_]u8{ 0x40, 0x12, 0x00, 0x00 };
    var out_buf: [100]u8 = undefined;
    try testing.expectError(error.CorruptStream, decompressInto(&bad_data, &out_buf, .{}));
    try testing.expect(!isValidCompressedBuffer(&bad_data));
}

test "block literal length u32 overflow rejection" {
    const testing = std.testing;
    // Expected len 65536 (0x80, 0x80, 0x04)
    // 1-byte literal 'D' (0x00, 'D')
    // Poison tag 0xfc with length bytes 0xff, 0xff, 0xff, 0xff
    const comp_data = [_]u8{
        0x80, 0x80, 0x04, // Expected length: 65536
        0x00, 'D', // 1-byte literal 'D'
        0xfc, 0xff, 0xff, 0xff, 0xff, // Poison literal tag 0xfc with length 0xffffffff
    };

    var out_buf: [65536]u8 = undefined;
    try testing.expectError(error.CorruptStream, decompressInto(&comp_data, &out_buf, .{}));
    try testing.expect(!isValidCompressedBuffer(&comp_data));
}
