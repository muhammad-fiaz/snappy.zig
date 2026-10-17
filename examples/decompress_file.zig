const std = @import("std");
const snappy = @import("snappy");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    const cwd = std.Io.Dir.cwd();

    const comp_file = "temp_example_comp.sz";
    const decomp_file = "temp_example_restored.txt";
    defer {
        cwd.deleteFile(io, comp_file) catch {};
        cwd.deleteFile(io, decomp_file) catch {};
    }

    // 1. Create a compressed file
    const sample_data =
        "Demonstration of decompressing a Snappy framed .sz file from disk back to plain text.\n" ++
        "Snappy frames include stream identifiers, block tags, and CRC-32C data checksums.\n" ++
        "Native Zig 0.17.0 streaming I/O pipeline verified for roundtrip correctness.\n";
    const comp_bytes = try snappy.compress(allocator, sample_data);
    defer allocator.free(comp_bytes);

    try cwd.writeFile(io, .{ .sub_path = comp_file, .data = comp_bytes });
    std.debug.print("Wrote compressed file '{s}' ({d} bytes)\n", .{ comp_file, comp_bytes.len });

    // 2. Read compressed file from disk
    const read_comp = try cwd.readFileAlloc(io, comp_file, allocator, @fromBackingInt(@intCast(10 * 1024 * 1024)));
    defer allocator.free(read_comp);

    // 3. Decompress using streaming pipeline
    var reader = std.Io.Reader.fixed(read_comp);
    var out_storage: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&out_storage);

    try snappy.decompressStream(allocator, &reader, &writer, .{});
    const restored_bytes = writer.buffered();

    try cwd.writeFile(io, .{ .sub_path = decomp_file, .data = restored_bytes });
    std.debug.print("Successfully restored into '{s}' ({d} bytes)\n", .{ decomp_file, restored_bytes.len });
}
