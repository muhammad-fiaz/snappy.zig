---
title: Bit-Level & Tag Encoding Example
description: Understanding Snappy varints, literal tags, copy tags, and CRC-32C masking at the byte level.
keywords: bit level example, varint encoding, TAG_LITERAL, TAG_COPY_1, maskChecksum, CRC-32C, zig 0.17.0
---

# Bit-Level & Tag Encoding Example

This example explores the fundamental low-level binary encodings that define Google's Snappy format: variable-length integers (varints), element tag structures, and masked Castagnoli CRC-32C checksums.

---

## Snappy Wire Format Specification

### 1. Variable-Length Integers (Varints)
Snappy uses unsigned Little-Endian Base-128 (LEB128) varints for block lengths:
- Each byte carries 7 bits of mathematical value (bits 0–6).
- Bit 7 is the continuation bit: `1` indicates more bytes follow; `0` terminates the sequence.
- 32-bit integers consume 1 to 5 bytes:
  - Values $< 128$: 1 byte (e.g. $64 \rightarrow \text{0x40}$).
  - Values $< 16,384$: 2 bytes.
  - Values $< 2,097,152$: 3 bytes (e.g. $2,097,150 \rightarrow \text{0xfe 0xff 0x7f}$).
  - Values $< 268,435,456$: 4 bytes.
  - Maximum 32-bit values: 5 bytes.

### 2. Element Tag Bytes (Lower 2 Bits)
After the uncompressed length varint, the payload consists of an unbroken sequence of elements. The lower 2 bits of each element's first byte indicate its type:

| Tag Bits | Type | Length Representation | Offset Representation |
|---|---|---|---|
| `00` (`TAG_LITERAL`) | Literal uncompressed bytes | Bits 2–7 $< 60$: length $= (\text{tag} \gg 2) + 1$<br>Bits 2–7 $= 60..63$: length stored in next 1..4 little-endian bytes | None |
| `01` (`TAG_COPY_1`) | 1-byte offset copy | Bits 2–4: length $= ((\text{tag} \gg 2) \& 0x07) + 4$ (4..11 bytes) | Bits 5–7 combined with next byte: offset $= ((\text{tag} \gg 5) \ll 8) \mid \text{byte}$ (1..2047 bytes) |
| `10` (`TAG_COPY_2`) | 2-byte offset copy | Bits 2–7: length $= (\text{tag} \gg 2) + 1$ (1..64 bytes) | Next 2 bytes little-endian (1..65535 bytes) |
| `11` (`TAG_COPY_4`) | 4-byte offset copy | Bits 2–7: length $= (\text{tag} \gg 2) + 1$ (1..64 bytes) | Next 4 bytes little-endian (1..4GB) |

### 3. Castagnoli CRC-32C and Masking
Snappy framing uses the Castagnoli CRC-32 polynomial (`0x82f63b78` / `@"CRC-32/ISCSI"` in Zig). To prevent checksum collisions when compressed streams are themselves nested inside other checksummed envelopes, Snappy masks the raw CRC:

$$\text{MaskedCRC} = ((\text{CRC} \gg 15) \mid (\text{CRC} \ll 17)) + \text{0xa282ead8} \pmod{2^{32}}$$

Unmasking is strictly reversible:

$$\text{Rotated} = \text{MaskedCRC} - \text{0xa282ead8} \pmod{2^{32}}$$
$$\text{CRC} = (\text{Rotated} \ll 15) \mid (\text{Rotated} \gg 17)$$

---

## Complete Source Code (`examples/bit_level.zig`)

```zig
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
```

---

## Step-by-Step Code Walkthrough

1. **Varint Encoding & Decoding**:
   - `snappy.varint.encode(64, &varint_buf)` encodes 64 as a single byte `[0x40]`.
   - `snappy.varint.encode(2097150, &varint_buf)` encodes $2^{21}-2$ as three bytes `[0xfe 0xff 0x7f]`.
   - `snappy.varint.decode` parses the byte slice and returns `.value` and `.bytes_consumed`.
2. **Tag Constant Inspection**:
   - `TAG_LITERAL` (`0b00`), `TAG_COPY_1` (`0b01`), `TAG_COPY_2` (`0b10`), `TAG_COPY_4` (`0b11`).
3. **Hardware CRC-32C & Masking**:
   - Computes standard CRC-32C for `"123456789"` yielding official standard check value `0xe3069283`.
   - Masks the value to `0xc78ab0e5` for storage in framed headers.
   - Restores the original `0xe3069283` via `unmaskChecksum`.

---

## Running the Example

Compile and run directly with the Zig build system:

```bash
zig build run-bit_level
```

### Expected Output

```console
=== Snappy Bit-Level Encodings ===

Varint 64: [0x40] -> decoded: 64
Varint 2097150: [0xfe 0xff 0x7f] -> decoded: 2097150
Varint 65536: [0x80 0x80 0x04] -> decoded: 65536

Tag byte types:
  TAG_LITERAL: 0b00 (0x00)
  TAG_COPY_1:  0b01 (0x01)
  TAG_COPY_2:  0b10 (0x02)
  TAG_COPY_4:  0b11 (0x03)

CRC-32C of "123456789":
  Raw CRC:   0xe3069283
  Masked:    0xc78ab0e5
  Unmasked:  0xe3069283
```
