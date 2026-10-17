---
title: Framing & Checksums Guide
description: Understanding Google's Snappy framing format, chunk types, stream identifiers, and masked CRC-32C Castagnoli checksums.
keywords: snappy framing format, snappy chunks, crc32c checksum, masked crc32c, snappy stream identifier, zig 0.17.0
---

# Framing & Checksums Guide

Google's Snappy format specifies both a raw block format and a framing format designed for streams, network protocols, and files (`.sz`).

`snappy.zig` natively implements the complete framing format as specified by Google Snappy.

---

## Stream Structure

A Snappy framed stream consists of a series of chunks. Each chunk begins with a 4-byte header:
- **Byte 0**: Chunk type identifier (`u8`).
- **Bytes 1..3**: 24-bit little-endian payload length (`u24`).

```
+---------------+-------------------+--------------------------------+
| Chunk Type    | Chunk Length      | Chunk Payload                  |
| (1 byte)      | (3 bytes, LE)     | (N bytes)                      |
+---------------+-------------------+--------------------------------+
```

---

## Chunk Types

The Snappy framing specification defines the following chunk types:

| Chunk ID | Type | Description |
| :--- | :--- | :--- |
| `0xff` | **Stream Identifier** | Must appear as the first chunk in the stream. Length is always 6 bytes containing `"sNaPpY"`. |
| `0x00` | **Compressed Data** | Contains a 4-byte masked CRC-32C checksum followed by raw compressed Snappy block data. |
| `0x01` | **Uncompressed Data** | Contains a 4-byte masked CRC-32C checksum followed by uncompressed raw data (used when data is incompressible). |
| `0xfe` | **Padding Chunk** | Skipped by the decoder. Used to align data to sector or block boundaries. |
| `0x80`..`0xfd` | **Skippable Chunks** | Reserved for user metadata and extensions. Safely skipped by compliant decoders. |
| `0x02`..`0x7f` | **Reserved Unskippable** | Reserved for future extensions. Causes compliant decoders to reject the stream with an error. |

---

## Stream Identifier Chunk

Every valid Snappy framed stream begins with the 10-byte sequence:

```
0xff 0x06 0x00 0x00 0x73 0x4e 0x61 0x50 0x70 0x59
\--/ \------------/ \----------------------------/
Type     Length 6               "sNaPpY"
```

If multiple framed streams are concatenated, each new stream may repeat this stream identifier chunk. `snappy.zig` supports multi-frame concatenation seamlessly.

---

## Masked CRC-32C Checksums

Each compressed (`0x00`) and uncompressed (`0x01`) chunk includes a 4-byte checksum of the **uncompressed** chunk payload.

### Polynomial & Implementation

Snappy uses the Castagnoli CRC-32C polynomial (`0x82f63b78`), which is computed natively in `snappy.zig` using Zig's standard library:

```zig
std.hash.crc.@"CRC-32/ISCSI"
```

### Masking Formula

Because CRC values often contain many zeros on typical data, Snappy scrambles the CRC-32C value using a 15-bit circular rotation and constant addition:

```zig
// Mask CRC-32C before writing to stream:
pub fn maskCrc32c(crc: u32) u32 {
    return std.math.rotr(u32, crc, 15) +% 0xa282ead8;
}

// Unmask CRC-32C when reading from stream:
pub fn unmaskCrc32c(masked: u32) u32 {
    const unshifted = masked -% 0xa282ead8;
    return std.math.rotl(u32, unshifted, 15);
}
```

---

## Verifying Checksums

By default, `snappy.decompress` and `snappy.decompressWithOptions` verify the masked CRC-32C checksum for every chunk:

```zig
const opts: snappy.DecompressionOptions = .{
    .verifyChecksums = true,
};
const decomp = try snappy.decompressWithOptions(allocator, data, opts);
```

If any chunk has been corrupted, decompression immediately fails with `error.ChecksumMismatch`.
