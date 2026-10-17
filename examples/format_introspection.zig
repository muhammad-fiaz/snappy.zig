const std = @import("std");
const snappy = @import("snappy");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("=== Snappy Format Introspection ===\n", .{});
    std.debug.print("Package Version: {s}\n", .{snappy.versionString()});
    std.debug.print("Version Number:  0x{x:0>6}\n", .{snappy.versionNumber()});
    std.debug.print("Max Block Size:  {d} bytes\n", .{snappy.types.MAX_BLOCK_SIZE});
    std.debug.print("Stream Magic:    {s}\n\n", .{snappy.types.STREAM_IDENTIFIER});

    const sample = "Structured data for introspection inspection";
    const max_bound = snappy.maxCompressedSize(sample.len);
    const framed_bound = snappy.maxFramedCompressedSize(sample.len);

    std.debug.print("Input size:            {d} bytes\n", .{sample.len});
    std.debug.print("Block Max Bound:       {d} bytes\n", .{max_bound});
    std.debug.print("Framed Max Bound:      {d} bytes\n\n", .{framed_bound});

    // Inspect block format
    const block_comp = try snappy.compressBlock(allocator, sample, .{});
    defer allocator.free(block_comp);

    const is_valid = snappy.isValidCompressedBuffer(block_comp);
    const uncompressed_size = try snappy.uncompressedLength(block_comp);

    std.debug.print("IsValidCompressedBuffer: {}\n", .{is_valid});
    std.debug.print("Uncompressed Length:     {d} bytes\n", .{uncompressed_size});
}
