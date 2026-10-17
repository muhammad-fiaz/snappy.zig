---
title: Framing & Block Format API
description: Google Snappy Framing specification, chunk structure, raw block tags, and format introspection in snappy.zig.
keywords: Snappy Framing, ChunkType, STREAM_IDENTIFIER, raw block tags, uncompressedLength, isValidCompressedBuffer
---

# Framing & Block Format

`snappy.zig` natively implements both Google's **Snappy Framing Format** and **Snappy Raw Block Format**.

---

## 1. Framed Stream Format (`.sz`)

A Snappy framed stream is a sequence of variable-length chunks designed for streams and files:

```
+---------------+-------------------+--------------------------------+
| Chunk Type    | Chunk Length      | Chunk Payload                  |
| (1 byte)      | (3 bytes, LE)     | (N bytes)                      |
+---------------+-------------------+--------------------------------+
```

### Chunk Identifiers

```zig
pub const CHUNK_STREAM_IDENTIFIER: u8 = 0xff; // First chunk in stream, length 6 ("sNaPpY")
pub const CHUNK_COMPRESSED_DATA: u8   = 0x00; // 4-byte CRC-32C + raw Snappy block
pub const CHUNK_UNCOMPRESSED_DATA: u8 = 0x01; // 4-byte CRC-32C + raw bytes
pub const CHUNK_PADDING: u8           = 0xfe; // Skipped padding chunk
// 0x80...0xfd: Skippable custom metadata chunks
// 0x02...0x7f: Reserved unskippable chunks (rejected by decoder)
```

### Stream Identifier Chunk

Every valid stream begins with:
```
0xff 0x06 0x00 0x00 0x73 0x4e 0x61 0x50 0x70 0x59
\--/ \------------/ \----------------------------/
Type   Length (6)               "sNaPpY"
```

---

## 2. Raw Block Format

Snappy raw blocks consist of:
1. **Uncompressed Length**: Encoded as a little-endian varint (1 to 5 bytes).
2. **Element Sequences**: Consecutive tags representing literals or backreference copies.

### Tag Types (Lower 2 bits of Tag Byte)

| Tag Bits | Name | Value | Description |
| :--- | :--- | :--- | :--- |
| `00` | `TAG_LITERAL` | `0x00` | Literal bytes copied directly from the input. |
| `01` | `TAG_COPY_1` | `0x01` | Copy match with 1-byte offset (offset: 0..2047, len: 4..11). |
| `10` | `TAG_COPY_2` | `0x02` | Copy match with 2-byte little-endian offset (len: 1..64). |
| `11` | `TAG_COPY_4` | `0x03` | Copy match with 4-byte little-endian offset (len: 1..64). |

---

## 3. Format Introspection

### `uncompressedLength`

```zig
pub fn uncompressedLength(input: []const u8) Error!usize
```

Parses the expected uncompressed size from the varint header of a raw Snappy block without executing decompression.

### `isValidCompressedBuffer`

```zig
pub fn isValidCompressedBuffer(input: []const u8) bool
```

Checks if `input` starts with a well-formed little-endian varint within 32-bit limits.
