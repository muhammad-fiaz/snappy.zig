---
title: Constants & Format Bounds API
description: Magic numbers, chunk IDs, element tags, and size constants defined in snappy.zig.
keywords: STREAM_IDENTIFIER, CHUNK_COMPRESSED_DATA, MAX_BLOCK_SIZE, TAG_LITERAL, snappy constants, zig 0.17.0
---

# Constants

The following constants are exposed by `snappy` for format introspection, chunk identification, and buffer sizing.

## Stream & Chunk Identifiers

| Constant | Value | Description |
| :--- | :--- | :--- |
| `snappy.STREAM_IDENTIFIER` | `"sNaPpY"` | Magic string contained in the initial stream identifier chunk. |
| `snappy.CHUNK_STREAM_IDENTIFIER` | `0xff` | Chunk type for stream identifier. |
| `snappy.CHUNK_COMPRESSED_DATA` | `0x00` | Chunk type for compressed block payload with 4-byte masked CRC-32C. |
| `snappy.CHUNK_UNCOMPRESSED_DATA` | `0x01` | Chunk type for uncompressed payload with 4-byte masked CRC-32C. |
| `snappy.CHUNK_PADDING` | `0xfe` | Chunk type for padding data, safely skipped by decoders. |

---

## Block Element Tags

| Constant | Value | Description |
| :--- | :--- | :--- |
| `snappy.TAG_LITERAL` | `0x00` | Lower 2 bits = 0: uncompressed literal bytes. |
| `snappy.TAG_COPY_1` | `0x01` | Lower 2 bits = 1: copy match with 1-byte offset (len: 4..11). |
| `snappy.TAG_COPY_2` | `0x02` | Lower 2 bits = 2: copy match with 2-byte little-endian offset (len: 1..64). |
| `snappy.TAG_COPY_4` | `0x03` | Lower 2 bits = 3: copy match with 4-byte little-endian offset (len: 1..64). |

---

## Size & Format Limits

| Constant | Value | Description |
| :--- | :--- | :--- |
| `snappy.BLOCK_LOG` | `16` | Bit width of block size exponent ($2^{16} = 65,536$). |
| `snappy.MAX_BLOCK_SIZE` | `65536` | Maximum uncompressed payload per block/chunk. |
| `snappy.MAX_VARINT_BYTES` | `5` | Maximum bytes in a 32-bit little-endian varint. |
| `snappy.version_string` | `"0.0.1"` | Library version string. |
