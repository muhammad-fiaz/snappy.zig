const std = @import("std");
const snappy = @import("snappy");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const source = "Standard Zig 0.17.0 std.Io pipeline processing streams without intermediate file buffering.";

    // 1. Setup Reader and Writer
    var input_reader = std.Io.Reader.fixed(source);

    var comp_storage: [1024]u8 = undefined;
    var comp_writer = std.Io.Writer.fixed(&comp_storage);

    // 2. Stream compression
    try snappy.compressStream(allocator, &input_reader, &comp_writer, .{});
    const compressed_slice = comp_writer.buffered();
    std.debug.print("Stream compressed {d} bytes into {d} bytes.\n", .{ source.len, compressed_slice.len });

    // 3. Stream decompression
    var comp_reader = std.Io.Reader.fixed(compressed_slice);

    var decomp_storage: [1024]u8 = undefined;
    var decomp_writer = std.Io.Writer.fixed(&decomp_storage);

    try snappy.decompressStream(allocator, &comp_reader, &decomp_writer, .{});
    const restored_slice = decomp_writer.buffered();
    std.debug.print("Stream decompressed back to: \"{s}\"\n", .{restored_slice});
}
