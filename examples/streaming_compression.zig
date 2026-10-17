const std = @import("std");
const snappy = @import("snappy");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var sc = try snappy.StreamingCompressor.init(allocator, .{ .level = 1 });
    defer sc.deinit();

    var out_storage: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&out_storage);

    std.debug.print("Streaming multiple chunks into compressed stream...\n", .{});

    try sc.write("First payload chunk: headers and metadata\n", &writer);
    try sc.write("Second payload chunk: query results batch #1\n", &writer);
    try sc.write("Third payload chunk: query results batch #2\n", &writer);
    try sc.finish(&writer);

    const compressed_data = writer.buffered();
    std.debug.print("Completed framed stream: {d} bytes written\n", .{compressed_data.len});

    // Decompress and verify
    const restored = try snappy.decompress(allocator, compressed_data);
    defer allocator.free(restored);

    std.debug.print("\nRestored Stream Content:\n{s}", .{restored});
}
