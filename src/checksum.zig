const std = @import("std");

/// Implements CRC-32C calculation and masking as defined in the Snappy framing specification.
const Crc32C = std.hash.crc.@"CRC-32/ISCSI";

/// Re-export the standard library CRC-32/ISCSI hasher for incremental calculation.
pub const Hasher = Crc32C;

/// Mask constant used by Snappy framing format: 0xa282ead8.
pub const MASK_DELTA: u32 = 0xa282ead8;

/// Computes the raw CRC-32C of the input slice using the standard iSCSI Castagnoli polynomial.
pub fn hash(data: []const u8) u32 {
    return Crc32C.hash(data);
}

/// Computes the masked CRC-32C of the input slice as required by Snappy framed chunks.
/// Masking: Rotate right by 15 bits, then add constant 0xa282ead8 with 32-bit wraparound.
pub fn maskedHash(data: []const u8) u32 {
    return maskChecksum(hash(data));
}

/// Applies the Snappy checksum masking transformation:
/// `((crc >> 15) | (crc << 17)) +% 0xa282ead8`
pub fn maskChecksum(crc: u32) u32 {
    const rotated = std.math.rotr(u32, crc, 15);
    return rotated +% MASK_DELTA;
}

/// Inverts the Snappy checksum masking transformation:
/// Subtracts 0xa282ead8 with 32-bit wraparound, then rotates left by 15 bits.
pub fn unmaskChecksum(masked: u32) u32 {
    const diff = masked -% MASK_DELTA;
    return std.math.rotl(u32, diff, 15);
}

test "crc32c standard vector" {
    // RFC 3720 test vector: "123456789" produces 0xe3069283
    const val = hash("123456789");
    try std.testing.expectEqual(@as(u32, 0xe3069283), val);
}

test "mask and unmask reversibility" {
    const values = [_]u32{ 0, 1, 0x12345678, 0xe3069283, 0xffffffff };
    for (values) |v| {
        const masked = maskChecksum(v);
        const unmasked = unmaskChecksum(masked);
        try std.testing.expectEqual(v, unmasked);
    }
}
