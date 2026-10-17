const std = @import("std");

pub const types = @import("types.zig");
pub const block = @import("block.zig");
pub const framing = @import("framing.zig");
pub const checksum = @import("checksum.zig");
pub const varint = @import("varint.zig");
pub const context = @import("context.zig");
pub const streaming = @import("streaming.zig");

// Re-export core types, errors, and metadata
pub const version = types.version;
pub const version_string = types.version_string;
pub const version_number = types.version_number;
pub const versionString = types.versionString;
pub const versionNumber = types.versionNumber;

pub const Error = types.Error;
pub const StreamError = types.StreamError;
pub const BlockMode = types.BlockMode;
pub const CompressionOptions = types.CompressionOptions;
pub const DecompressionOptions = types.DecompressionOptions;

pub const Compressor = context.Compressor;
pub const Decompressor = context.Decompressor;
pub const StreamingCompressor = streaming.StreamingCompressor;
pub const StreamingDecompressor = streaming.StreamingDecompressor;

/// Calculates the maximum possible compressed size for raw block compression.
pub inline fn maxCompressedSize(source_bytes: usize) usize {
    return block.maxCompressedSize(source_bytes);
}

/// Alias for `maxCompressedSize` conforming to common compression library conventions.
pub inline fn compressBound(source_bytes: usize) usize {
    return block.maxCompressedSize(source_bytes);
}

/// Calculates the maximum possible size for framed stream compression.
pub inline fn maxFramedCompressedSize(source_bytes: usize) usize {
    return framing.maxFramedCompressedSize(source_bytes);
}

/// Inspects the uncompressed length of a Snappy raw block from its preamble.
pub inline fn uncompressedLength(compressed: []const u8) Error!usize {
    return block.uncompressedLength(compressed);
}

/// Alias for `uncompressedLength`.
pub inline fn getUncompressedLength(compressed: []const u8) Error!usize {
    return block.uncompressedLength(compressed);
}

/// Checks if a buffer represents a syntactically valid Snappy raw block.
pub inline fn isValidCompressedBuffer(compressed: []const u8) bool {
    return block.isValidCompressedBuffer(compressed);
}

/// Compresses data in one shot. By default, generates a Snappy framed stream (.sz format).
pub fn compress(allocator: std.mem.Allocator, input: []const u8) Error![]u8 {
    return compressWithOptions(allocator, input, .{});
}

/// Compresses data in one shot with custom compression options.
pub fn compressWithOptions(
    allocator: std.mem.Allocator,
    input: []const u8,
    options: CompressionOptions,
) Error![]u8 {
    return switch (options.blockMode) {
        .framed => framing.compress(allocator, input, options),
        .block => block.compress(allocator, input, options),
    };
}

/// Compresses data directly as a Snappy raw block.
pub fn compressBlock(
    allocator: std.mem.Allocator,
    input: []const u8,
    options: CompressionOptions,
) Error![]u8 {
    return block.compress(allocator, input, options);
}

/// Compresses data directly as a Snappy framed stream.
pub fn compressFramed(
    allocator: std.mem.Allocator,
    input: []const u8,
    options: CompressionOptions,
) Error![]u8 {
    return framing.compress(allocator, input, options);
}

/// Compresses data into a caller-provided destination buffer (default framed format).
pub fn compressInto(input: []const u8, output: []u8) Error!usize {
    return compressWithOptionsInto(input, output, .{});
}

/// Compresses data into a caller-provided destination buffer with custom options.
pub fn compressWithOptionsInto(
    input: []const u8,
    output: []u8,
    options: CompressionOptions,
) Error!usize {
    return switch (options.blockMode) {
        .framed => framing.compressInto(input, output, options),
        .block => block.compressInto(input, output, options),
    };
}

/// Compresses a raw Snappy block into a caller-provided destination buffer.
pub fn compressBlockInto(
    input: []const u8,
    output: []u8,
    options: CompressionOptions,
) Error!usize {
    return block.compressInto(input, output, options);
}

/// Compresses a framed Snappy stream into a caller-provided destination buffer.
pub fn compressFramedInto(
    input: []const u8,
    output: []u8,
    options: CompressionOptions,
) Error!usize {
    return framing.compressInto(input, output, options);
}

/// Decompresses data in one shot. Automatically detects framed streams vs raw blocks.
pub fn decompress(allocator: std.mem.Allocator, input: []const u8) Error![]u8 {
    return decompressWithOptions(allocator, input, .{});
}

/// Decompresses data in one shot with custom decompression options.
pub fn decompressWithOptions(
    allocator: std.mem.Allocator,
    input: []const u8,
    options: DecompressionOptions,
) Error![]u8 {
    if (input.len >= framing.STREAM_HEADER.len and std.mem.startsWith(u8, input, &framing.STREAM_HEADER)) {
        return framing.decompress(allocator, input, options);
    }
    return block.decompress(allocator, input, options);
}

/// Decompresses a raw Snappy block using the provided allocator.
pub fn decompressBlock(
    allocator: std.mem.Allocator,
    input: []const u8,
    options: DecompressionOptions,
) Error![]u8 {
    return block.decompress(allocator, input, options);
}

/// Decompresses a framed Snappy stream using the provided allocator.
pub fn decompressFramed(
    allocator: std.mem.Allocator,
    input: []const u8,
    options: DecompressionOptions,
) Error![]u8 {
    return framing.decompress(allocator, input, options);
}

/// Decompresses data into a caller-provided buffer (auto-detects framed vs raw block).
pub fn decompressInto(input: []const u8, output: []u8) Error!usize {
    return decompressWithOptionsInto(input, output, .{});
}

/// Decompresses data into a caller-provided buffer with options.
pub fn decompressWithOptionsInto(
    input: []const u8,
    output: []u8,
    options: DecompressionOptions,
) Error!usize {
    if (input.len >= framing.STREAM_HEADER.len and std.mem.startsWith(u8, input, &framing.STREAM_HEADER)) {
        return framing.decompressInto(input, output, options);
    }
    return block.decompressInto(input, output, options);
}

/// Decompresses a raw Snappy block into a caller-provided buffer.
pub fn decompressBlockInto(
    input: []const u8,
    output: []u8,
    options: DecompressionOptions,
) Error!usize {
    return block.decompressInto(input, output, options);
}

/// Decompresses a framed Snappy stream into a caller-provided buffer.
pub fn decompressFramedInto(
    input: []const u8,
    output: []u8,
    options: DecompressionOptions,
) Error!usize {
    return framing.decompressInto(input, output, options);
}

/// Compresses from `std.Io.Reader` to `std.Io.Writer`.
pub fn compressStream(
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
    writer: *std.Io.Writer,
    options: CompressionOptions,
) StreamError!void {
    return streaming.compressStream(allocator, reader, writer, options);
}

/// Decompresses from `std.Io.Reader` to `std.Io.Writer`.
pub fn decompressStream(
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
    writer: *std.Io.Writer,
    options: DecompressionOptions,
) StreamError!void {
    return streaming.decompressStream(allocator, reader, writer, options);
}

/// Compresses a file from disk to Snappy framed format.
pub fn compressFile(
    allocator: std.mem.Allocator,
    src_path: []const u8,
    dst_path: []const u8,
    options: CompressionOptions,
) !void {
    return streaming.compressFile(allocator, src_path, dst_path, options);
}

/// Decompresses a Snappy framed file from disk.
pub fn decompressFile(
    allocator: std.mem.Allocator,
    src_path: []const u8,
    dst_path: []const u8,
    options: DecompressionOptions,
) !void {
    return streaming.decompressFile(allocator, src_path, dst_path, options);
}

test {
    _ = types;
    _ = checksum;
    _ = varint;
    _ = block;
    _ = framing;
    _ = context;
    _ = streaming;
    _ = @import("fuzz.zig");
}
