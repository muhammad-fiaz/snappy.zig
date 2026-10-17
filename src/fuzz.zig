const std = @import("std");
const snappy = @import("snappy.zig");

/// Fuzz testing harness for Snappy block and framed stream decoders.
/// Ensures arbitrary, truncated, and corrupted inputs fail safely without panics or memory leaks.
pub fn fuzzBlockDecoder(allocator: std.mem.Allocator, data: []const u8) void {
    _ = snappy.isValidCompressedBuffer(data);

    var stack_buf: [1024]u8 = undefined;
    _ = snappy.decompressBlockInto(data, &stack_buf, .{ .maxOutputSize = 65536 }) catch {};

    const alloc_res = snappy.decompressBlock(allocator, data, .{ .maxOutputSize = 65536 }) catch return;
    allocator.free(alloc_res);
}

pub fn fuzzFramedDecoder(allocator: std.mem.Allocator, data: []const u8) void {
    var stack_buf: [1024]u8 = undefined;
    _ = snappy.decompressFramedInto(data, &stack_buf, .{ .maxOutputSize = 65536 }) catch {};

    const alloc_res = snappy.decompressFramed(allocator, data, .{ .maxOutputSize = 65536 }) catch return;
    allocator.free(alloc_res);
}

pub fn fuzzAutoDecoder(allocator: std.mem.Allocator, data: []const u8) void {
    var stack_buf: [1024]u8 = undefined;
    _ = snappy.decompressInto(data, &stack_buf) catch {};

    const alloc_res = snappy.decompress(allocator, data) catch return;
    allocator.free(alloc_res);
}

test "fuzz random bytes against block decoder" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var prng = std.Random.DefaultPrng.init(0x1337c0de);
    const random = prng.random();

    var fuzz_buf: [512]u8 = undefined;

    for (0..200) |_| {
        const len = random.uintLessThan(usize, fuzz_buf.len);
        random.bytes(fuzz_buf[0..len]);
        fuzzBlockDecoder(alloc, fuzz_buf[0..len]);
    }
}

test "fuzz random bytes against framed decoder" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var prng = std.Random.DefaultPrng.init(0xfeedface);
    const random = prng.random();

    var fuzz_buf: [512]u8 = undefined;

    for (0..200) |_| {
        const len = random.uintLessThan(usize, fuzz_buf.len);
        random.bytes(fuzz_buf[0..len]);
        fuzzFramedDecoder(alloc, fuzz_buf[0..len]);
    }
}

test "fuzz bit flips on valid compressed data" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const original_text = "The quick brown fox jumps over the lazy dog. Repetition repetition repetition!";

    // Block bit flips
    const comp_block = try snappy.compressBlock(alloc, original_text, .{});
    defer alloc.free(comp_block);

    var corrupted_block = try alloc.alloc(u8, comp_block.len);
    defer alloc.free(corrupted_block);

    for (0..comp_block.len) |byte_idx| {
        for (0..8) |bit_idx| {
            @memcpy(corrupted_block, comp_block);
            corrupted_block[byte_idx] ^= @as(u8, 1) << @as(u3, @intCast(bit_idx));
            fuzzBlockDecoder(alloc, corrupted_block);
        }
    }

    // Framed bit flips
    const comp_framed = try snappy.compressFramed(alloc, original_text, .{});
    defer alloc.free(comp_framed);

    var corrupted_framed = try alloc.alloc(u8, comp_framed.len);
    defer alloc.free(corrupted_framed);

    for (0..comp_framed.len) |byte_idx| {
        for (0..8) |bit_idx| {
            @memcpy(corrupted_framed, comp_framed);
            corrupted_framed[byte_idx] ^= @as(u8, 1) << @as(u3, @intCast(bit_idx));
            fuzzFramedDecoder(alloc, corrupted_framed);
        }
    }
}

test "fuzz progressive truncation" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const original_text = "Snappy progressive truncation test input with diverse patterns and symbols 1234567890!@#$%^&*()";

    const comp_block = try snappy.compressBlock(alloc, original_text, .{});
    defer alloc.free(comp_block);

    for (0..comp_block.len) |prefix_len| {
        fuzzBlockDecoder(alloc, comp_block[0..prefix_len]);
    }

    const comp_framed = try snappy.compressFramed(alloc, original_text, .{});
    defer alloc.free(comp_framed);

    for (0..comp_framed.len) |prefix_len| {
        fuzzFramedDecoder(alloc, comp_framed[0..prefix_len]);
    }
}
