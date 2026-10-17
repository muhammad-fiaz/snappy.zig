const std = @import("std");
const snappy = @import("snappy");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("=== Snappy Error Diagnostics and Security Checks ===\n\n", .{});

    // 1. Invalid magic header test
    const bad_magic = "NOT_SNAPPY_STREAM_HEADER";
    if (snappy.decompress(allocator, bad_magic)) |_| {
        std.debug.print("Unexpected success on bad magic!\n", .{});
    } else |err| {
        std.debug.print("Expected error caught on invalid stream header: {}\n", .{err});
    }

    // 2. Corrupted checksum test
    const valid_comp = try snappy.compress(allocator, "Data protected with CRC-32C checksum");
    defer allocator.free(valid_comp);

    var corrupted = try allocator.alloc(u8, valid_comp.len);
    defer allocator.free(corrupted);
    @memcpy(corrupted, valid_comp);
    corrupted[corrupted.len - 1] ^= 0xff; // Corrupt payload byte

    if (snappy.decompress(allocator, corrupted)) |_| {
        std.debug.print("Unexpected success on corrupted payload!\n", .{});
    } else |err| {
        std.debug.print("Expected error caught on checksum tampering: {}\n", .{err});
    }

    // 3. Decompression bomb protection via maxOutputSize
    const repetitive = try allocator.alloc(u8, 50_000);
    defer allocator.free(repetitive);
    @memset(repetitive, 'Z');

    const compressed_rep = try snappy.compress(allocator, repetitive);
    defer allocator.free(compressed_rep);

    std.debug.print("Compressed 50,000 bytes into {d} bytes.\n", .{compressed_rep.len});

    // Limit output to at most 1024 bytes
    if (snappy.decompressWithOptions(allocator, compressed_rep, .{ .maxOutputSize = 1024 })) |_| {
        std.debug.print("Unexpected success exceeding resource limit!\n", .{});
    } else |err| {
        std.debug.print("Expected error caught on decompression bomb protection: {}\n", .{err});
    }

    // 4. Truncated block test
    const truncated_block = [_]u8{ 0x80, 0x01 }; // Varint 128, but 0 payload bytes follow
    if (snappy.decompressBlock(allocator, &truncated_block, .{})) |_| {
        std.debug.print("Unexpected success on truncated block!\n", .{});
    } else |err| {
        std.debug.print("Expected error caught on truncated block: {}\n", .{err});
    }
}
