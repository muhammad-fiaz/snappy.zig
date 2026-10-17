---
title: Streaming Compression Example
description: Incremental push-based streaming compression with snappy.StreamingCompressor and Zig 0.17 std.Io.
keywords: streaming compression example, StreamingCompressor, push streaming, snappy.write, snappy.finish, zig 0.17.0
---

# Streaming Compression Example

When processing large datasets, network streams, database query results, or logs of unknown size, holding the entire dataset in memory before compressing is impractical. `snappy.StreamingCompressor` enables push-based, chunk-by-chunk compression that flushes framed Snappy chunks directly into an output `std.Io.Writer`.

---

## Snappy Streaming Protocol

The streaming compressor operates in strict compliance with the Snappy framing specification:
1. **Initial Chunk**: On the very first call to `write`, the 10-byte Stream Identifier (`\xff\x06\x00\x00sNaPpY`) is emitted to the writer.
2. **Chunk Aggregation**: Incoming byte slices are accumulated internally up to 65,536 bytes (`snappy.MAX_BLOCK_SIZE`).
3. **Chunk Emission**: Whenever the accumulated buffer reaches 64KB, or when `finish()` is explicitly invoked:
   - The block is compressed with Snappy LZ77.
   - The 32-bit masked Castagnoli CRC-32C of the uncompressed chunk is computed.
   - If the compressed representation is smaller than the original, chunk type `0x00` (compressed) is written; otherwise chunk type `0x01` (uncompressed) is written.
   - The internal buffer is reset and reused.

---

## Complete Source Code (`examples/streaming_compression.zig`)

```zig
const std = @import("std");
const snappy = @import("snappy");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var sc = try snappy.StreamingCompressor.init(allocator, .{ .level = 1 });
    defer sc.deinit();

    var out_storage: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&out_storage);

    std.debug.print("Streaming multiple chunks into compressed stream...\n", .{});

    try sc.write("First payload chunk: headers and metadata\n", &writer);
    try sc.write("Second payload chunk: query results batch #1\n", &writer);
    try sc.write("Third payload chunk: query results batch #2\n", &writer);
    try sc.finish(&writer);

    const compressed_data = writer.buffered();
    std.debug.print("Completed framed stream: {d} bytes written\n", .{compressed_data.len});

    // Decompress and verify
    const restored = try snappy.decompress(allocator, compressed_data);
    defer allocator.free(restored);

    std.debug.print("\nRestored Stream Content:\n{s}", .{restored});
}
```

---

## Step-by-Step Code Walkthrough

1. **Compressor Allocation**:
   `var sc = try snappy.StreamingCompressor.init(allocator, .{ .level = 1 });` initializes internal staging buffers. `defer sc.deinit();` ensures all allocated staging memory is freed.

2. **Writer Configuration**:
   `var writer = std.Io.Writer.fixed(&out_storage);` wraps a pre-allocated stack storage slice into a Zig 0.17.0 `std.Io.Writer`.

3. **Incremental Push (`sc.write`)**:
   Successive calls to `sc.write(chunk, &writer)` pass slices of arbitrary size (from a few bytes to megabytes). If a chunk crosses the 64KB block boundary, full Snappy chunks are compressed and flushed to `writer` immediately.

4. **Flushing the Stream (`sc.finish`)**:
   `try sc.finish(&writer);` flushes any remaining buffered bytes as the final chunk and marks the stream finished.

5. **Validation**:
   `writer.buffered()` retrieves the completed framed slice, and `snappy.decompress` verifies roundtrip fidelity.

---

## Explicit I/O Architecture

| Component | Responsibility | Memory Reuse |
|---|---|---|
| **`sc.write(slice, &writer)`** | Consumes slice, compresses when buffer reaches 64KB | Internal 64KB staging buffer reused across chunks |
| **`sc.finish(&writer)`** | Emits trailing partial chunk to `writer` | Flushes internal staging buffer |
| **`std.Io.Writer`** | Destination interface for compressed bytes | Can be a network socket, file writer, or memory buffer |

---

## Running the Example

Compile and run directly with the Zig build system:

```bash
zig build run-streaming_compression
```

### Expected Output

```console
Streaming multiple chunks into compressed stream...
Completed framed stream: 107 bytes written

Restored Stream Content:
First payload chunk: headers and metadata
Second payload chunk: query results batch #1
Third payload chunk: query results batch #2
```
