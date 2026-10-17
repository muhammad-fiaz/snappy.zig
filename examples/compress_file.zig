const std = @import("std");
const snappy = @import("snappy");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    const cwd = std.Io.Dir.cwd();

    const sample_file = "temp_example_input.txt";
    const comp_file = "temp_example_output.sz";
    defer {
        cwd.deleteFile(io, sample_file) catch {};
        cwd.deleteFile(io, comp_file) catch {};
    }

    // Create a sample text file
    const sample_content =
        "This is a demonstration of file compression using snappy.zig on Windows/Linux/macOS.\n" ++
        "Snappy prioritizes extreme compression and decompression throughput.\n" ++
        "Native Zig implementation with zero external dependencies and memory safety.\n";
    try cwd.writeFile(io, .{ .sub_path = sample_file, .data = sample_content });

    std.debug.print("Created sample input file '{s}' ({d} bytes)\n", .{ sample_file, sample_content.len });

    // Read and compress
    const in_data = try cwd.readFileAlloc(io, sample_file, allocator, @fromBackingInt(@intCast(10 * 1024 * 1024)));
    defer allocator.free(in_data);

    var reader = std.Io.Reader.fixed(in_data);
    var out_storage: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&out_storage);

    try snappy.compressStream(allocator, &reader, &writer, .{});

    const compressed_data = writer.buffered();
    try cwd.writeFile(io, .{ .sub_path = comp_file, .data = compressed_data });

    std.debug.print("Successfully compressed into '{s}' ({d} bytes)\n", .{ comp_file, compressed_data.len });
}
