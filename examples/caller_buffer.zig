const std = @import("std");
const snappy = @import("snappy");

pub fn main() !void {
    const data = "Fixed stack memory buffers eliminate heap allocations entirely!";

    var framed_storage: [256]u8 = undefined;
    var block_storage: [256]u8 = undefined;
    var restored_storage: [256]u8 = undefined;

    // 1. Zero-allocation framed compression & decompression
    const framed_len = try snappy.compressInto(data, &framed_storage);
    const framed_restored_len = try snappy.decompressInto(framed_storage[0..framed_len], &restored_storage);

    std.debug.print("Zero-allocation framed roundtrip succeeded: \"{s}\" ({d} bytes)\n", .{
        restored_storage[0..framed_restored_len],
        framed_restored_len,
    });

    // 2. Zero-allocation raw block compression & decompression
    const block_len = try snappy.compressBlockInto(data, &block_storage, .{});
    const block_restored_len = try snappy.decompressBlockInto(block_storage[0..block_len], &restored_storage, .{});

    std.debug.print("Zero-allocation block roundtrip succeeded: \"{s}\" ({d} bytes)\n", .{
        restored_storage[0..block_restored_len],
        block_restored_len,
    });
}
