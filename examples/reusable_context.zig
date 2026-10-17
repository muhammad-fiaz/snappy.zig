const std = @import("std");
const snappy = @import("snappy");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Initialize reusable contexts once
    var compressor = try snappy.Compressor.init(allocator, .{ .blockMode = .framed, .level = 1 });
    defer compressor.deinit();

    var decompressor = snappy.Decompressor.init(allocator, .{});
    defer decompressor.deinit();

    const messages = [_][]const u8{
        "Transaction #1: User authenticated successfully",
        "Transaction #2: Payment processed for order #98214",
        "Transaction #3: Shipping notification dispatched via webhook",
    };

    for (messages, 0..) |msg, i| {
        // Compress using existing context
        const comp = try compressor.compress(msg);
        defer allocator.free(comp);

        // Decompress using existing context
        const decomp = try decompressor.decompress(comp);
        defer allocator.free(decomp);

        std.debug.print("Message {d} ({d} bytes -> {d} bytes): \"{s}\"\n", .{
            i + 1, msg.len, comp.len, decomp,
        });
    }

    // Reset options dynamically without reallocating buffers
    compressor.reset(.{ .blockMode = .block, .level = 2 });
    decompressor.reset(.{});

    const block_msg = "Level 2 raw block stream without framing header";
    const comp_block = try compressor.compress(block_msg);
    defer allocator.free(comp_block);

    const decomp_block = try decompressor.decompress(comp_block);
    defer allocator.free(decomp_block);

    std.debug.print("Raw block roundtrip: \"{s}\"\n", .{decomp_block});
}
