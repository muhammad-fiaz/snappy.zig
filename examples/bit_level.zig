const std = @import("std");
const snappy = @import("snappy");

pub fn main() !void {
    std.debug.print("=== Snappy Bit-Level Encodings ===\n\n", .{});

    // 1. Varint variable-length integers
    var varint_buf: [5]u8 = undefined;
    const test_lengths = [_]u32{ 64, 2097150, 65536 };

    for (test_lengths) |val| {
        const bytes_written = snappy.varint.encode(val, &varint_buf);
        const decoded = try snappy.varint.decode(varint_buf[0..bytes_written]);

        std.debug.print("Varint {d}: [", .{val});
        for (varint_buf[0..bytes_written], 0..) |b, i| {
            if (i > 0) std.debug.print(" ", .{});
            std.debug.print("0x{x:0>2}", .{b});
        }
        std.debug.print("] -> decoded: {d}\n", .{decoded.value});
    }

    // 2. Tag byte structures
    std.debug.print("\nTag byte types:\n", .{});
    std.debug.print("  TAG_LITERAL: 0b00 (0x{x:0>2})\n", .{snappy.types.TAG_LITERAL});
    std.debug.print("  TAG_COPY_1:  0b01 (0x{x:0>2})\n", .{snappy.types.TAG_COPY_1});
    std.debug.print("  TAG_COPY_2:  0b10 (0x{x:0>2})\n", .{snappy.types.TAG_COPY_2});
    std.debug.print("  TAG_COPY_4:  0b11 (0x{x:0>2})\n", .{snappy.types.TAG_COPY_4});

    // 3. CRC-32C and masking
    const sample_data = "123456789";
    const crc = snappy.checksum.hash(sample_data);
    const masked = snappy.checksum.maskChecksum(crc);
    const unmasked = snappy.checksum.unmaskChecksum(masked);

    std.debug.print("\nCRC-32C of \"{s}\":\n", .{sample_data});
    std.debug.print("  Raw CRC:   0x{x:0>8}\n", .{crc});
    std.debug.print("  Masked:    0x{x:0>8}\n", .{masked});
    std.debug.print("  Unmasked:  0x{x:0>8}\n", .{unmasked});
}
