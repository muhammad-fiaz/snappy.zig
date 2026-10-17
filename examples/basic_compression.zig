const std = @import("std");
const snappy = @import("snappy");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const original_text = "Hello, world! Native Snappy compression in pure Zig 0.17.0!";

    std.debug.print("Original data ({d} bytes): \"{s}\"\n", .{ original_text.len, original_text });

    // 1. One-shot framed stream compression (default)
    const compressed = try snappy.compress(allocator, original_text);
    defer allocator.free(compressed);

    std.debug.print("Compressed framed stream: {d} bytes\n", .{compressed.len});

    // 2. One-shot decompression (automatically detects framed stream format)
    const decompressed = try snappy.decompress(allocator, compressed);
    defer allocator.free(decompressed);

    std.debug.print("Decompressed ({d} bytes): \"{s}\"\n", .{ decompressed.len, decompressed });

    // 3. Zero-allocation caller buffer API
    var caller_out: [256]u8 = undefined;
    const comp_len = try snappy.compressInto(original_text, &caller_out);
    std.debug.print("Caller-buffer compression: {d} bytes written\n", .{comp_len});

    var caller_restored: [256]u8 = undefined;
    const decomp_len = try snappy.decompressInto(caller_out[0..comp_len], &caller_restored);
    std.debug.print("Caller-buffer decompression: {d} bytes: \"{s}\"\n", .{ decomp_len, caller_restored[0..decomp_len] });
}
