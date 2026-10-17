const std = @import("std");
const types = @import("types.zig");
const block = @import("block.zig");
const framing = @import("framing.zig");
const checksum = @import("checksum.zig");

/// Implements streaming compression and decompression using Zig 0.17.0 `std.Io`.
/// Streams uncompressed data from `reader`, compresses it into Snappy framed format, and writes to `writer`.
pub fn compressStream(
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
    writer: *std.Io.Writer,
    options: types.CompressionOptions,
) types.StreamError!void {
    _ = allocator;
    try writer.writeAll(&framing.STREAM_HEADER);

    var raw_chunk: [framing.MAX_CHUNK_PAYLOAD]u8 = undefined;
    var comp_chunk: [block.maxCompressedSize(framing.MAX_CHUNK_PAYLOAD)]u8 = undefined;

    while (true) {
        var bytes_read: usize = 0;
        while (bytes_read < raw_chunk.len) {
            const n = reader.readSliceShort(raw_chunk[bytes_read..]) catch return error.CorruptStream;
            if (n == 0) break;
            bytes_read += n;
        }

        if (bytes_read == 0) break;

        const chunk_slice = raw_chunk[0..bytes_read];
        const masked_crc = checksum.maskedHash(chunk_slice);

        const comp_len = block.compressInto(chunk_slice, &comp_chunk, options) catch 0;

        if (comp_len > 0 and comp_len < bytes_read) {
            const payload_len = 4 + comp_len;
            var header: [8]u8 = undefined;
            header[0] = types.CHUNK_COMPRESSED_DATA;
            header[1] = @as(u8, @truncate(payload_len));
            header[2] = @as(u8, @truncate(payload_len >> 8));
            header[3] = @as(u8, @truncate(payload_len >> 16));
            std.mem.writeInt(u32, header[4..8], masked_crc, .little);

            try writer.writeAll(&header);
            try writer.writeAll(comp_chunk[0..comp_len]);
        } else {
            const payload_len = 4 + bytes_read;
            var header: [8]u8 = undefined;
            header[0] = types.CHUNK_UNCOMPRESSED_DATA;
            header[1] = @as(u8, @truncate(payload_len));
            header[2] = @as(u8, @truncate(payload_len >> 8));
            header[3] = @as(u8, @truncate(payload_len >> 16));
            std.mem.writeInt(u32, header[4..8], masked_crc, .little);

            try writer.writeAll(&header);
            try writer.writeAll(chunk_slice);
        }
    }
}

/// Reads a Snappy framed stream from `reader`, decompresses each chunk, and writes to `writer`.
pub fn decompressStream(
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
    writer: *std.Io.Writer,
    options: types.DecompressionOptions,
) types.StreamError!void {
    var stream_header: [framing.STREAM_HEADER.len]u8 = undefined;
    reader.readSliceAll(&stream_header) catch return error.TruncatedInput;
    if (!std.mem.eql(u8, &stream_header, &framing.STREAM_HEADER)) {
        return error.InvalidMagic;
    }

    var payload_buf: [block.maxCompressedSize(framing.MAX_CHUNK_PAYLOAD) + 4]u8 = undefined;
    var decomp_buf: [framing.MAX_CHUNK_PAYLOAD]u8 = undefined;
    var total_decompressed: usize = 0;

    while (true) {
        var ch_hdr: [4]u8 = undefined;
        var hdr_read: usize = 0;
        while (hdr_read < 4) {
            const n = reader.readSliceShort(ch_hdr[hdr_read..]) catch return error.CorruptStream;
            if (n == 0) break;
            hdr_read += n;
        }

        if (hdr_read == 0) break; // Clean EOF
        if (hdr_read < 4) return error.TruncatedInput;

        const chunk_type = ch_hdr[0];
        const chunk_len = @as(usize, ch_hdr[1]) |
            (@as(usize, ch_hdr[2]) << 8) |
            (@as(usize, ch_hdr[3]) << 16);

        var payload_slice: []u8 = undefined;
        var dynamic_alloc: ?[]u8 = null;
        defer if (dynamic_alloc) |da| allocator.free(da);

        if (chunk_len <= payload_buf.len) {
            payload_slice = payload_buf[0..chunk_len];
        } else {
            dynamic_alloc = allocator.alloc(u8, chunk_len) catch return error.OutOfMemory;
            payload_slice = dynamic_alloc.?;
        }

        var pl_read: usize = 0;
        while (pl_read < chunk_len) {
            const n = reader.readSliceShort(payload_slice[pl_read..]) catch return error.CorruptStream;
            if (n == 0) return error.TruncatedInput;
            pl_read += n;
        }

        switch (chunk_type) {
            types.CHUNK_STREAM_IDENTIFIER => {
                if (chunk_len != 6 or !std.mem.eql(u8, payload_slice, types.STREAM_IDENTIFIER)) {
                    return error.CorruptStream;
                }
            },
            types.CHUNK_COMPRESSED_DATA => {
                if (chunk_len < 4) return error.InvalidChunkLength;
                const expected_masked_crc = std.mem.readInt(u32, payload_slice[0..4], .little);
                const block_data = payload_slice[4..];

                const decomp_len = try block.decompressInto(
                    block_data,
                    &decomp_buf,
                    .{ .maxOutputSize = framing.MAX_CHUNK_PAYLOAD },
                );
                const uncomp_slice = decomp_buf[0..decomp_len];

                if (options.verifyChecksums) {
                    const actual_masked_crc = checksum.maskedHash(uncomp_slice);
                    if (actual_masked_crc != expected_masked_crc) {
                        return error.ChecksumMismatch;
                    }
                }

                if (options.maxOutputSize > 0 and total_decompressed + decomp_len > options.maxOutputSize) {
                    return error.ResourceLimitExceeded;
                }

                try writer.writeAll(uncomp_slice);
                total_decompressed += decomp_len;
            },
            types.CHUNK_UNCOMPRESSED_DATA => {
                if (chunk_len < 4) return error.InvalidChunkLength;
                const uncomp_len = chunk_len - 4;
                if (uncomp_len > framing.MAX_CHUNK_PAYLOAD) return error.InvalidChunkLength;

                const expected_masked_crc = std.mem.readInt(u32, payload_slice[0..4], .little);
                const uncomp_slice = payload_slice[4..];

                if (options.verifyChecksums) {
                    const actual_masked_crc = checksum.maskedHash(uncomp_slice);
                    if (actual_masked_crc != expected_masked_crc) {
                        return error.ChecksumMismatch;
                    }
                }

                if (options.maxOutputSize > 0 and total_decompressed + uncomp_len > options.maxOutputSize) {
                    return error.ResourceLimitExceeded;
                }

                try writer.writeAll(uncomp_slice);
                total_decompressed += uncomp_len;
            },
            types.CHUNK_PADDING => {},
            0x02...0x7f => return error.UnknownChunkType,
            0x80...0xfd => {},
        }
    }
}

/// Incremental streaming compressor that allows callers to feed arbitrary slices.
pub const StreamingCompressor = struct {
    allocator: std.mem.Allocator,
    options: types.CompressionOptions,
    buffer: std.ArrayList(u8),
    header_written: bool,

    pub fn init(allocator: std.mem.Allocator, options: types.CompressionOptions) types.Error!StreamingCompressor {
        return StreamingCompressor{
            .allocator = allocator,
            .options = options,
            .buffer = .empty,
            .header_written = false,
        };
    }

    pub fn deinit(self: *StreamingCompressor) void {
        self.buffer.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn reset(self: *StreamingCompressor, new_options: types.CompressionOptions) void {
        self.options = new_options;
        self.buffer.clearRetainingCapacity();
        self.header_written = false;
    }

    pub fn write(self: *StreamingCompressor, chunk: []const u8, writer: *std.Io.Writer) types.StreamError!void {
        if (!self.header_written) {
            try writer.writeAll(&framing.STREAM_HEADER);
            self.header_written = true;
        }

        try self.buffer.appendSlice(self.allocator, chunk);

        var scratch: [block.maxCompressedSize(framing.MAX_CHUNK_PAYLOAD)]u8 = undefined;

        while (self.buffer.items.len >= framing.MAX_CHUNK_PAYLOAD) {
            const chunk_slice = self.buffer.items[0..framing.MAX_CHUNK_PAYLOAD];
            const masked_crc = checksum.maskedHash(chunk_slice);
            const comp_len = block.compressInto(chunk_slice, &scratch, self.options) catch 0;

            if (comp_len > 0 and comp_len < framing.MAX_CHUNK_PAYLOAD) {
                const payload_len = 4 + comp_len;
                var hdr: [8]u8 = undefined;
                hdr[0] = types.CHUNK_COMPRESSED_DATA;
                hdr[1] = @as(u8, @truncate(payload_len));
                hdr[2] = @as(u8, @truncate(payload_len >> 8));
                hdr[3] = @as(u8, @truncate(payload_len >> 16));
                std.mem.writeInt(u32, hdr[4..8], masked_crc, .little);
                try writer.writeAll(&hdr);
                try writer.writeAll(scratch[0..comp_len]);
            } else {
                const payload_len = 4 + framing.MAX_CHUNK_PAYLOAD;
                var hdr: [8]u8 = undefined;
                hdr[0] = types.CHUNK_UNCOMPRESSED_DATA;
                hdr[1] = @as(u8, @truncate(payload_len));
                hdr[2] = @as(u8, @truncate(payload_len >> 8));
                hdr[3] = @as(u8, @truncate(payload_len >> 16));
                std.mem.writeInt(u32, hdr[4..8], masked_crc, .little);
                try writer.writeAll(&hdr);
                try writer.writeAll(chunk_slice);
            }

            // Slide buffer
            std.mem.copyForwards(u8, self.buffer.items, self.buffer.items[framing.MAX_CHUNK_PAYLOAD..]);
            self.buffer.items.len -= framing.MAX_CHUNK_PAYLOAD;
        }
    }

    pub fn finish(self: *StreamingCompressor, writer: *std.Io.Writer) types.StreamError!void {
        if (!self.header_written) {
            try writer.writeAll(&framing.STREAM_HEADER);
            self.header_written = true;
        }

        if (self.buffer.items.len > 0) {
            const chunk_slice = self.buffer.items;
            const masked_crc = checksum.maskedHash(chunk_slice);
            var scratch: [block.maxCompressedSize(framing.MAX_CHUNK_PAYLOAD)]u8 = undefined;
            const comp_len = block.compressInto(chunk_slice, &scratch, self.options) catch 0;

            if (comp_len > 0 and comp_len < chunk_slice.len) {
                const payload_len = 4 + comp_len;
                var hdr: [8]u8 = undefined;
                hdr[0] = types.CHUNK_COMPRESSED_DATA;
                hdr[1] = @as(u8, @truncate(payload_len));
                hdr[2] = @as(u8, @truncate(payload_len >> 8));
                hdr[3] = @as(u8, @truncate(payload_len >> 16));
                std.mem.writeInt(u32, hdr[4..8], masked_crc, .little);
                try writer.writeAll(&hdr);
                try writer.writeAll(scratch[0..comp_len]);
            } else {
                const payload_len = 4 + chunk_slice.len;
                var hdr: [8]u8 = undefined;
                hdr[0] = types.CHUNK_UNCOMPRESSED_DATA;
                hdr[1] = @as(u8, @truncate(payload_len));
                hdr[2] = @as(u8, @truncate(payload_len >> 8));
                hdr[3] = @as(u8, @truncate(payload_len >> 16));
                std.mem.writeInt(u32, hdr[4..8], masked_crc, .little);
                try writer.writeAll(&hdr);
                try writer.writeAll(chunk_slice);
            }
            self.buffer.clearRetainingCapacity();
        }
    }
};

/// Incremental streaming decompressor.
pub const StreamingDecompressor = struct {
    allocator: std.mem.Allocator,
    options: types.DecompressionOptions,
    in_buffer: std.ArrayList(u8),
    out_buffer: std.ArrayList(u8),
    header_verified: bool,

    pub fn init(allocator: std.mem.Allocator, options: types.DecompressionOptions) StreamingDecompressor {
        return StreamingDecompressor{
            .allocator = allocator,
            .options = options,
            .in_buffer = .empty,
            .out_buffer = .empty,
            .header_verified = false,
        };
    }

    pub fn deinit(self: *StreamingDecompressor) void {
        self.in_buffer.deinit(self.allocator);
        self.out_buffer.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn reset(self: *StreamingDecompressor, new_options: types.DecompressionOptions) void {
        self.options = new_options;
        self.in_buffer.clearRetainingCapacity();
        self.out_buffer.clearRetainingCapacity();
        self.header_verified = false;
    }

    pub fn feed(self: *StreamingDecompressor, chunk: []const u8) types.Error!void {
        try self.in_buffer.appendSlice(self.allocator, chunk);
        try self.process();
    }

    fn process(self: *StreamingDecompressor) types.Error!void {
        if (!self.header_verified) {
            if (self.in_buffer.items.len < framing.STREAM_HEADER.len) return;
            if (!std.mem.startsWith(u8, self.in_buffer.items, &framing.STREAM_HEADER)) {
                return error.InvalidMagic;
            }
            std.mem.copyForwards(u8, self.in_buffer.items, self.in_buffer.items[framing.STREAM_HEADER.len..]);
            self.in_buffer.items.len -= framing.STREAM_HEADER.len;
            self.header_verified = true;
        }

        var scratch: [framing.MAX_CHUNK_PAYLOAD]u8 = undefined;

        while (self.in_buffer.items.len >= 4) {
            const chunk_type = self.in_buffer.items[0];
            const chunk_len = @as(usize, self.in_buffer.items[1]) |
                (@as(usize, self.in_buffer.items[2]) << 8) |
                (@as(usize, self.in_buffer.items[3]) << 16);

            if (self.in_buffer.items.len < 4 + chunk_len) return; // Wait for full chunk

            const payload = self.in_buffer.items[4 .. 4 + chunk_len];

            switch (chunk_type) {
                types.CHUNK_STREAM_IDENTIFIER => {
                    if (chunk_len != 6 or !std.mem.eql(u8, payload, types.STREAM_IDENTIFIER)) {
                        return error.CorruptStream;
                    }
                },
                types.CHUNK_COMPRESSED_DATA => {
                    if (chunk_len < 4) return error.InvalidChunkLength;
                    const expected_crc = std.mem.readInt(u32, payload[0..4], .little);
                    const decomp_len = try block.decompressInto(payload[4..], &scratch, .{ .maxOutputSize = framing.MAX_CHUNK_PAYLOAD });
                    const uncomp = scratch[0..decomp_len];
                    if (self.options.verifyChecksums) {
                        if (checksum.maskedHash(uncomp) != expected_crc) return error.ChecksumMismatch;
                    }
                    try self.out_buffer.appendSlice(self.allocator, uncomp);
                },
                types.CHUNK_UNCOMPRESSED_DATA => {
                    if (chunk_len < 4) return error.InvalidChunkLength;
                    const expected_crc = std.mem.readInt(u32, payload[0..4], .little);
                    const uncomp = payload[4..];
                    if (self.options.verifyChecksums) {
                        if (checksum.maskedHash(uncomp) != expected_crc) return error.ChecksumMismatch;
                    }
                    try self.out_buffer.appendSlice(self.allocator, uncomp);
                },
                types.CHUNK_PADDING => {},
                0x02...0x7f => return error.UnknownChunkType,
                0x80...0xfd => {},
            }

            // Consume processed chunk
            std.mem.copyForwards(u8, self.in_buffer.items, self.in_buffer.items[4 + chunk_len ..]);
            self.in_buffer.items.len -= 4 + chunk_len;
        }
    }

    pub fn take(self: *StreamingDecompressor, out_slice: []u8) types.Error!usize {
        const count = @min(out_slice.len, self.out_buffer.items.len);
        if (count == 0) return 0;
        @memcpy(out_slice[0..count], self.out_buffer.items[0..count]);
        std.mem.copyForwards(u8, self.out_buffer.items, self.out_buffer.items[count..]);
        self.out_buffer.items.len -= count;
        return count;
    }

    pub fn isFinished(self: *const StreamingDecompressor) bool {
        return self.in_buffer.items.len == 0 and self.out_buffer.items.len == 0;
    }
};

/// Compresses a file from disk into a Snappy framed file using Zig 0.17.0 std.Io.
pub fn compressFile(
    allocator: std.mem.Allocator,
    src_path: []const u8,
    dst_path: []const u8,
    options: types.CompressionOptions,
) !void {
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    const cwd = std.Io.Dir.cwd();

    const src_file = try cwd.openFile(io, src_path, .{ .mode = .read_only });
    defer src_file.close(io);

    const dst_file = try cwd.createFile(io, dst_path, .{});
    defer dst_file.close(io);

    var read_buf: [65536]u8 = undefined;
    var write_buf: [65536]u8 = undefined;

    var file_reader = src_file.reader(io, &read_buf);
    var file_writer = dst_file.writer(io, &write_buf);

    try compressStream(allocator, &file_reader.interface, &file_writer.interface, options);
    try file_writer.interface.flush();
}

/// Decompresses a Snappy framed file from disk using Zig 0.17.0 std.Io.
pub fn decompressFile(
    allocator: std.mem.Allocator,
    src_path: []const u8,
    dst_path: []const u8,
    options: types.DecompressionOptions,
) !void {
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    const cwd = std.Io.Dir.cwd();

    const src_file = try cwd.openFile(io, src_path, .{ .mode = .read_only });
    defer src_file.close(io);

    const dst_file = try cwd.createFile(io, dst_path, .{});
    defer dst_file.close(io);

    var read_buf: [65536]u8 = undefined;
    var write_buf: [65536]u8 = undefined;

    var file_reader = src_file.reader(io, &read_buf);
    var file_writer = dst_file.writer(io, &write_buf);

    try decompressStream(allocator, &file_reader.interface, &file_writer.interface, options);
    try file_writer.interface.flush();
}

test "streaming compression and decompression via std.Io" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const original_text = "Testing std.Io streaming compression and decompression in Zig 0.17.0 with Snappy framing!";

    var input_reader = std.Io.Reader.fixed(original_text);

    var comp_storage: [1024]u8 = undefined;
    var comp_writer = std.Io.Writer.fixed(&comp_storage);

    try compressStream(alloc, &input_reader, &comp_writer, .{});

    const compressed_bytes = comp_writer.buffered();
    try testing.expect(compressed_bytes.len > 0);

    var comp_reader = std.Io.Reader.fixed(compressed_bytes);
    var decomp_storage: [1024]u8 = undefined;
    var decomp_writer = std.Io.Writer.fixed(&decomp_storage);

    try decompressStream(alloc, &comp_reader, &decomp_writer, .{});

    const restored_bytes = decomp_writer.buffered();
    try testing.expectEqualStrings(original_text, restored_bytes);
}

test "chunked streaming compressor and decompressor" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var sc = try StreamingCompressor.init(alloc, .{});
    defer sc.deinit();

    var comp_storage: [2048]u8 = undefined;
    var comp_writer = std.Io.Writer.fixed(&comp_storage);

    try sc.write("Chunk 1: Hello ", &comp_writer);
    try sc.write("Chunk 2: Native ", &comp_writer);
    try sc.write("Chunk 3: Snappy!", &comp_writer);
    try sc.finish(&comp_writer);

    const comp_bytes = comp_writer.buffered();

    var sd = StreamingDecompressor.init(alloc, .{});
    defer sd.deinit();

    // Feed in small arbitrary byte slices
    var feed_idx: usize = 0;
    while (feed_idx < comp_bytes.len) {
        const slice_len = @min(10, comp_bytes.len - feed_idx);
        try sd.feed(comp_bytes[feed_idx .. feed_idx + slice_len]);
        feed_idx += slice_len;
    }

    var restored: [256]u8 = undefined;
    var total_taken: usize = 0;
    while (!sd.isFinished()) {
        const n = try sd.take(restored[total_taken..]);
        if (n == 0) break;
        total_taken += n;
    }

    try testing.expectEqualStrings("Chunk 1: Hello Chunk 2: Native Chunk 3: Snappy!", restored[0..total_taken]);
}

test "compressFile and decompressFile disk roundtrip" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var threaded = std.Io.Threaded.init(alloc, .{});
    defer threaded.deinit();
    const io = threaded.io();
    const cwd = std.Io.Dir.cwd();

    const in_file = "test_io_input.txt";
    const comp_file = "test_io_output.sz";
    const restored_file = "test_io_restored.txt";
    defer {
        cwd.deleteFile(io, in_file) catch {};
        cwd.deleteFile(io, comp_file) catch {};
        cwd.deleteFile(io, restored_file) catch {};
    }

    const content = "Testing file compression and decompression roundtrip with Snappy framing in Zig 0.17.0.";
    try cwd.writeFile(io, .{ .sub_path = in_file, .data = content });

    try compressFile(alloc, in_file, comp_file, .{});
    try decompressFile(alloc, comp_file, restored_file, .{});

    const restored_content = try cwd.readFileAlloc(io, restored_file, alloc, @fromBackingInt(@intCast(1024)));
    defer alloc.free(restored_content);

    try testing.expectEqualStrings(content, restored_content);
}
