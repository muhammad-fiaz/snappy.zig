---
title: Compression Guide
description: In-depth guide to compression levels, format modes, options, and buffer strategies in snappy.zig.
keywords: snappy compression guide, snappy level 1 level 2, zero allocation zig compression, compressInto, compressBlock, snappy framed format
---

# Compression Guide

`snappy.zig` provides flexible, high-throughput compression mechanisms tailored for maximum speed, memory safety, and interoperability with Google's Snappy format.

---

## Compression Levels & Strategies

Snappy is engineered from the ground up for raw throughput, processing data at hundreds of megabytes to gigabytes per second on modern hardware.

`snappy.zig` provides two compression levels via `CompressionOptions`:

1. **`level = 1` (Fastest Throughput - Default Standard Snappy)**:
   - Uses a 16 KiB single-entry hash table to identify repeated byte sequences with minimal CPU overhead.
   - Ideal for network transport, real-time RPC calls, and high-volume message queues.
2. **`level = 2` (Enhanced Compression Ratio)**:
   - Employs a dual-entry hash table matching strategy to find longer and closer backreferences.
   - Increases compression ratio on structured data, JSON, and source code while maintaining high throughput.

### Configuring Levels and Options

Use `snappy.compressWithOptions` to pass custom `CompressionOptions`:

```zig
const std = @import("std");
const snappy = @import("snappy");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const input = "Repeat pattern: abcdefghijklmnopqrstuvwxyz0123456789 -- " ** 100;

    // Level 1: Standard high-speed mode
    const level1_opts: snappy.CompressionOptions = .{
        .level = 1,
    };
    const level1_frame = try snappy.compressWithOptions(allocator, input, level1_opts);
    defer allocator.free(level1_frame);

    // Level 2: Enhanced compression ratio mode
    const level2_opts: snappy.CompressionOptions = .{
        .level = 2,
    };
    const level2_frame = try snappy.compressWithOptions(allocator, input, level2_opts);
    defer allocator.free(level2_frame);

    std.debug.print("Input: {d} bytes | Level 1: {d} bytes | Level 2: {d} bytes\n", .{
        input.len,
        level1_frame.len,
        level2_frame.len,
    });
}
```

---

## Formats: Framed Streams vs. Raw Blocks

### 1. Framed Stream (`snappy.compress` / `snappy.compressFramed`)

The official framing format splits input into chunks of up to 65,536 bytes (`MAX_BLOCK_SIZE = 65536`), calculates a 32-bit masked Castagnoli CRC-32C checksum for each chunk, and prepends the 10-byte stream identifier (`0xff 0x06 0x00 0x00 sNaPpY`).

```zig
// One-shot framed compression (allocating)
const framed = try snappy.compress(allocator, input_data);
defer allocator.free(framed);
```

### 2. Raw Block (`snappy.compressBlock`)

Raw blocks contain only a little-endian varint length prefix followed by Snappy element tags (literals and copy backreferences). This format is standard in LevelDB, RocksDB, and Apache Parquet.

```zig
// Raw block compression (allocating)
const raw_block = try snappy.compressBlock(allocator, input_data, .{});
defer allocator.free(raw_block);
```

---

## Zero-Allocation Caller Buffers

When heap allocation is unwanted or destination buffers are statically allocated, use `compressInto` (for framed streams) or `compressBlockInto` (for raw blocks):

```zig
var dst_buf: [4096]u8 = undefined;

// Compress directly into caller-provided buffer (zero heap allocation)
const bytes_written = try snappy.compressInto(input_data, &dst_buf);
const compressed_slice = dst_buf[0..bytes_written];
```

---

## Calculating Upper Bounds

Before allocating memory for compressed data, compute the guaranteed worst-case output capacity:

```zig
// For raw blocks: 32 + N + N / 6
const max_block = snappy.maxCompressedSize(input.len);
// Equivalent alias:
const max_bound = snappy.compressBound(input.len);

// For framed streams (.sz): accounts for stream identifier, chunk headers, and checksums
const max_framed = snappy.maxFramedCompressedSize(input.len);
```
