---
title: I/O Pipeline Example
description: Processing data directly between std.Io.Reader and std.Io.Writer with snappy.compressStream and snappy.decompressStream.
keywords: io pipeline example, std.Io.Reader, std.Io.Writer, compressStream, decompressStream, zig 0.17.0
---

# I/O Pipeline Example

In production pipelines (HTTP servers, RPC proxies, data migration tools, log collectors), data must flow directly from input streams to output streams without accumulating the full dataset in memory or writing temporary files to disk.

`snappy.compressStream` and `snappy.decompressStream` accept any Zig 0.17.0 `*std.Io.Reader` and `*std.Io.Writer`, delivering streaming Snappy framed compression with bounded memory usage.

---

## Snappy Streaming Format Architecture

- **Framed Stream Output**: The writer receives a valid Snappy framed stream (`.sz`):
  - 10-byte Stream Identifier: `\xff\x06\x00\x00sNaPpY`.
  - Individual 64KB chunks stamped with 4-byte masked Castagnoli CRC-32C checksums.
- **Bounded Buffer Consumption**: The reader is consumed in 65,536-byte blocks (`snappy.MAX_BLOCK_SIZE`). Memory consumption remains constant regardless of whether the stream carries 100 bytes or 100 gigabytes.
- **Zero Disk Spillage**: Data is compressed on the fly and emitted directly to the target writer.

---

## Complete Source Code (`examples/io_pipeline.zig`)

```zig
const std = @import("std");
const snappy = @import("snappy");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const source = "Standard Zig 0.17.0 std.Io pipeline processing streams without intermediate file buffering.";

    // 1. Setup Reader and Writer
    var input_reader = std.Io.Reader.fixed(source);

    var comp_storage: [1024]u8 = undefined;
    var comp_writer = std.Io.Writer.fixed(&comp_storage);

    // 2. Stream compression
    try snappy.compressStream(allocator, &input_reader, &comp_writer, .{});
    const compressed_slice = comp_writer.buffered();
    std.debug.print("Stream compressed {d} bytes into {d} bytes.\n", .{ source.len, compressed_slice.len });

    // 3. Stream decompression
    var comp_reader = std.Io.Reader.fixed(compressed_slice);

    var decomp_storage: [1024]u8 = undefined;
    var decomp_writer = std.Io.Writer.fixed(&decomp_storage);

    try snappy.decompressStream(allocator, &comp_reader, &decomp_writer, .{});
    const restored_slice = decomp_writer.buffered();
    std.debug.print("Stream decompressed back to: \"{s}\"\n", .{restored_slice});
}
```

---

## Step-by-Step Code Walkthrough

1. **Fixed Memory Streams**:
   - `std.Io.Reader.fixed(source)` exposes an in-memory slice through the `std.Io.Reader` interface.
   - `std.Io.Writer.fixed(&comp_storage)` wraps a stack buffer into the `std.Io.Writer` interface.
2. **Streaming Compression (`snappy.compressStream`)**:
   - Reads chunks from `&input_reader`.
   - Writes the 10-byte `\xff\x06\x00\x00sNaPpY` header and compressed chunks into `&comp_writer`.
   - `comp_writer.buffered()` retrieves the written slice (109 bytes).
3. **Streaming Decompression (`snappy.decompressStream`)**:
   - Wraps the compressed slice into `&comp_reader`.
   - `snappy.decompressStream` decodes the framed chunks, validates CRC-32C checksums, and emits uncompressed plaintext to `&decomp_writer`.
4. **Verification**:
   - `decomp_writer.buffered()` returns the exact original plaintext string.

---

## Explicit I/O Interfaces

| Operation | Reader Interface | Writer Interface | Internal Memory |
|---|---|---|---|
| **`compressStream`** | `*std.Io.Reader` (File, socket, buffer) | `*std.Io.Writer` (File, socket, buffer) | Fixed 64KB staging chunk buffer |
| **`decompressStream`** | `*std.Io.Reader` (File, socket, buffer) | `*std.Io.Writer` (File, socket, buffer) | Fixed 64KB staging chunk buffer |

---

## Running the Example

Compile and run directly with the Zig build system:

```bash
zig build run-io_pipeline
```

### Expected Output

```console
Stream compressed 91 bytes into 109 bytes.
Stream decompressed back to: "Standard Zig 0.17.0 std.Io pipeline processing streams without intermediate file buffering."
```
