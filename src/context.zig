const std = @import("std");
const types = @import("types.zig");
const block = @import("block.zig");
const framing = @import("framing.zig");

/// Reusable compression context that minimizes allocation churn.
pub const Compressor = struct {
    allocator: std.mem.Allocator,
    options: types.CompressionOptions,
    scratch: []u8,

    /// Initializes a reusable compressor.
    pub fn init(allocator: std.mem.Allocator, options: types.CompressionOptions) types.Error!Compressor {
        const scratch_size = block.maxCompressedSize(types.MAX_BLOCK_SIZE) + types.MAX_BLOCK_SIZE;
        const scratch = allocator.alloc(u8, scratch_size) catch return error.OutOfMemory;
        return Compressor{
            .allocator = allocator,
            .options = options,
            .scratch = scratch,
        };
    }

    /// Releases resources allocated by the compressor.
    pub fn deinit(self: *Compressor) void {
        self.allocator.free(self.scratch);
        self.* = undefined;
    }

    /// Resets configuration options without reallocating buffers.
    pub fn reset(self: *Compressor, new_options: types.CompressionOptions) void {
        self.options = new_options;
    }

    /// Compresses data into an allocated buffer according to the configured mode.
    pub fn compress(self: *Compressor, input: []const u8) types.Error![]u8 {
        return switch (self.options.blockMode) {
            .framed => framing.compress(self.allocator, input, self.options),
            .block => block.compress(self.allocator, input, self.options),
        };
    }

    /// Compresses data into a caller-provided destination buffer.
    pub fn compressInto(self: *Compressor, input: []const u8, output: []u8) types.Error!usize {
        return switch (self.options.blockMode) {
            .framed => framing.compressInto(input, output, self.options),
            .block => block.compressInto(input, output, self.options),
        };
    }
};

/// Reusable decompression context.
pub const Decompressor = struct {
    allocator: std.mem.Allocator,
    options: types.DecompressionOptions,

    /// Initializes a reusable decompressor.
    pub fn init(allocator: std.mem.Allocator, options: types.DecompressionOptions) Decompressor {
        return Decompressor{
            .allocator = allocator,
            .options = options,
        };
    }

    /// Releases resources (if any).
    pub fn deinit(self: *Decompressor) void {
        self.* = undefined;
    }

    /// Resets options without reallocation.
    pub fn reset(self: *Decompressor, new_options: types.DecompressionOptions) void {
        self.options = new_options;
    }

    /// Decompresses either a framed stream or a raw block automatically.
    pub fn decompress(self: *Decompressor, input: []const u8) types.Error![]u8 {
        if (input.len >= framing.STREAM_HEADER.len and std.mem.startsWith(u8, input, &framing.STREAM_HEADER)) {
            return framing.decompress(self.allocator, input, self.options);
        }
        return block.decompress(self.allocator, input, self.options);
    }

    /// Decompresses into a caller-provided buffer.
    pub fn decompressInto(self: *Decompressor, input: []const u8, output: []u8) types.Error!usize {
        if (input.len >= framing.STREAM_HEADER.len and std.mem.startsWith(u8, input, &framing.STREAM_HEADER)) {
            return framing.decompressInto(input, output, self.options);
        }
        return block.decompressInto(input, output, self.options);
    }
};

test "reusable compressor and decompressor lifecycle" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var comp = try Compressor.init(alloc, .{ .blockMode = .framed });
    defer comp.deinit();

    var decomp = Decompressor.init(alloc, .{});
    defer decomp.deinit();

    const data1 = "First stream for reusable context!";
    const c1 = try comp.compress(data1);
    defer alloc.free(c1);

    const out1 = try decomp.decompress(c1);
    defer alloc.free(out1);
    try testing.expectEqualStrings(data1, out1);

    // Reset with block mode
    comp.reset(.{ .blockMode = .block, .level = 2 });
    decomp.reset(.{});

    const data2 = "Second stream in raw block mode!";
    const c2 = try comp.compress(data2);
    defer alloc.free(c2);

    const out2 = try decomp.decompress(c2);
    defer alloc.free(out2);
    try testing.expectEqualStrings(data2, out2);
}
