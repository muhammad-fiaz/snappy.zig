---
title: CompressionOptions API
description: Complete specification of compression options, levels, and block modes in snappy.zig.
keywords: CompressionOptions, BlockMode, blockSize, compressionLevel, snappy options, zig 0.17.0
---

# `snappy.CompressionOptions`

`CompressionOptions` configures how data is compressed into Snappy framed streams or raw blocks.

```zig
pub const CompressionOptions = struct {
    /// Compression level:
    /// - 1: Fastest throughput (default standard Snappy)
    /// - 2: Higher compression ratio (double-hash matching)
    level: u8 = 1,
    /// Format mode: framed stream (default) or raw block
    blockMode: BlockMode = .framed,
    /// Maximum fragment size for framed stream chunks (max 65536)
    blockSize: usize = MAX_BLOCK_SIZE,
};
```

---

## Fields

### `level`
- **Type**: `u8`
- **Default**: `1`
- **Description**: Compression match-finding heuristic:
  - `1`: Standard fast single-hash search with adaptive skip heuristic on non-compressible data.
  - `2`: Double-hash table match finding exploring longer backreferences for improved compression ratio.

### `blockMode`
- **Type**: `BlockMode`
- **Default**: `.framed`
- **Options**:
  - `.framed`: Produces an official Snappy framed stream (`.sz`) beginning with stream identifier `0xff 0x06 0x00 0x00 sNaPpY`, chunk headers, and CRC-32C checksums.
  - `.block`: Produces a raw Snappy block starting with a varint length prefix followed directly by element tags.

### `blockSize`
- **Type**: `usize`
- **Default**: `MAX_BLOCK_SIZE` (65,536 bytes)
- **Description**: Maximum uncompressed chunk payload size used when chunking large inputs in framed streams. Must not exceed 65,536 bytes per the Snappy framing specification.
