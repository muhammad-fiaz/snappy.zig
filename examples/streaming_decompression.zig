const std = @import("std");
const snappy = @import("snappy");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const source_text = "Incremental chunked decompression in Zig 0.17.0 simulating fragmented network packets.";
    const compressed = try snappy.compressFramed(allocator, source_text, .{});
    defer allocator.free(compressed);

    std.debug.print("Original size: {d} bytes, compressed framed size: {d} bytes\n", .{ source_text.len, compressed.len });

    var sd = snappy.StreamingDecompressor.init(allocator, .{});
    defer sd.deinit();

    // Feed in tiny 7-byte network packets
    var offset: usize = 0;
    var packet_count: usize = 0;

    var restored_buf: [256]u8 = undefined;
    var total_taken: usize = 0;

    while (offset < compressed.len) {
        const chunk_size = @min(7, compressed.len - offset);
        try sd.feed(compressed[offset .. offset + chunk_size]);
        offset += chunk_size;
        packet_count += 1;

        // Drain available uncompressed data
        while (true) {
            const n = try sd.take(restored_buf[total_taken..]);
            if (n == 0) break;
            total_taken += n;
        }
    }

    std.debug.print("Processed {d} fragmented packets.\n", .{packet_count});
    std.debug.print("Restored data ({d} bytes): \"{s}\"\n", .{ total_taken, restored_buf[0..total_taken] });
}
