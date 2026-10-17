const std = @import("std");
const types = @import("types.zig");

/// Implements varint encoding and decoding as specified by the Snappy format.
pub const MaxBytes = 5;

pub const DecodeResult = struct {
    value: u32,
    bytes_read: usize,
};

/// Encodes a 32-bit unsigned integer into Snappy's variable-length format.
/// Returns the number of bytes written (between 1 and 5).
pub fn encode(val: u32, out: []u8) usize {
    var v = val;
    var i: usize = 0;
    while (v >= 0x80) {
        out[i] = @as(u8, @truncate(v | 0x80));
        v >>= 7;
        i += 1;
    }
    out[i] = @as(u8, @truncate(v));
    return i + 1;
}

/// Decodes a 32-bit unsigned integer from a Snappy variable-length prefix.
/// Validates bounds, termination, and overflow.
pub fn decode(input: []const u8) types.Error!DecodeResult {
    if (input.len == 0) return error.TruncatedInput;

    var result: u32 = 0;
    var shift: u5 = 0;
    var i: usize = 0;

    while (i < MaxBytes) : (i += 1) {
        if (i >= input.len) return error.TruncatedInput;
        const b = input[i];

        if (i == 4) {
            // 5th byte: bits 28..31.
            // Any bit >= 16 or continuation bit >= 128 overflows u32.
            if (b >= 16) return error.InvalidVarint;
            result |= @as(u32, b) << shift;
            return DecodeResult{
                .value = result,
                .bytes_read = i + 1,
            };
        }

        result |= @as(u32, b & 0x7f) << shift;
        if (b < 0x80) {
            return DecodeResult{
                .value = result,
                .bytes_read = i + 1,
            };
        }
        shift += 7;
    }

    // Unterminated after 5 bytes.
    return error.InvalidVarint;
}

test "varint basic roundtrip" {
    var buf: [MaxBytes]u8 = undefined;
    const test_values = [_]u32{
        0,
        1,
        64,
        127,
        128,
        255,
        256,
        16383,
        16384,
        2097150, // 0x1FFFFE
        2097151,
        2097152,
        268435455,
        268435456,
        0xffffffff,
    };

    for (test_values) |expected| {
        const written = encode(expected, &buf);
        const res = try decode(buf[0..written]);
        try std.testing.expectEqual(written, res.bytes_read);
        try std.testing.expectEqual(expected, res.value);
    }
}

test "varint format description example" {
    // 64 -> 0x40
    var buf: [MaxBytes]u8 = undefined;
    var len = encode(64, &buf);
    try std.testing.expectEqual(@as(usize, 1), len);
    try std.testing.expectEqual(@as(u8, 0x40), buf[0]);

    // 2097150 (0x1FFFFE) -> 0xFE 0xFF 0x7F
    len = encode(2097150, &buf);
    try std.testing.expectEqual(@as(usize, 3), len);
    try std.testing.expectEqual(@as(u8, 0xFE), buf[0]);
    try std.testing.expectEqual(@as(u8, 0xFF), buf[1]);
    try std.testing.expectEqual(@as(u8, 0x7F), buf[2]);

    const res = try decode(buf[0..len]);
    try std.testing.expectEqual(@as(u32, 2097150), res.value);
}

test "varint rejection of truncated and invalid input" {
    // Empty
    try std.testing.expectError(error.TruncatedInput, decode(&[_]u8{}));

    // Truncated varint: 0xf0 has continuation bit set but input ends
    try std.testing.expectError(error.TruncatedInput, decode(&[_]u8{0xf0}));

    // Unterminated varint (5 bytes with continuation bit set)
    try std.testing.expectError(
        error.InvalidVarint,
        decode(&[_]u8{ 0x80, 0x80, 0x80, 0x80, 0x80, 0x0a }),
    );

    // Overflowing varint (5th byte has value >= 16)
    try std.testing.expectError(
        error.InvalidVarint,
        decode(&[_]u8{ 0xfb, 0xff, 0xff, 0xff, 0x7f }),
    );
}
