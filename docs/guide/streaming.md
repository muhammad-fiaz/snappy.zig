---
title: Streaming Guide
description: Streaming compression and decompression using Zig 0.17 std.Io readers/writers and chunked streaming processors.
keywords: snappy streaming zig, std.io reader writer, StreamingCompressor, StreamingDecompressor, compressStream, decompressStream, compressFile, decompressFile
---

# Streaming Guide

`snappy.zig` offers two streaming models:
1. **Standard I/O Pipelines**: Direct stream-to-stream processing using Zig 0.17's standard `std.Io.Reader` and `std.Io.Writer`.
2. **Stateful Chunked Streaming**: `StreamingCompressor` and `StreamingDecompressor` for network sockets, event loops, and incremental chunk buffers.

---

## Standard I/O Pipelines (`compressStream` & `decompressStream`)

For files, pipes, sockets, and memory streams wrapped in `std.Io.Reader` and `std.Io.Writer`:

```zig
const std = @import("std");
const snappy = @import("snappy");

pub fn compressPipeline(
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
    writer: *std.Io.Writer,
) !void {
    // Stream compression into Snappy framed format (.sz)
    try snappy.compressStream(allocator, reader, writer, .{});
}

pub fn decompressPipeline(
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
    writer: *std.Io.Writer,
) !void {
    // Stream decompression from Snappy framed format (.sz)
    try snappy.decompressStream(allocator, reader, writer, .{});
}
```

---

## File Compression Convenience Functions

For direct on-disk operations, `snappy.zig` provides ready-to-use file helpers leveraging Zig 0.17 `std.Io`:

```zig
const std = @import("std");
const snappy = @import("snappy");

pub fn processFiles(allocator: std.mem.Allocator) !void {
    // Compress directly to a Snappy framed (.sz) file on disk
    try snappy.compressFile(allocator, "dataset.csv", "dataset.csv.sz", .{});

    // Decompress a Snappy framed file back to plain text
    try snappy.decompressFile(allocator, "dataset.csv.sz", "dataset_restored.csv", .{});
}
```

---

## Stateful Chunked Streaming

When dealing with asynchronous network sockets or chunked protocols, data arrives in arbitrary fragment sizes.

### Incremental Compression (`StreamingCompressor`)

```zig
const std = @import("std");
const snappy = @import("snappy");

pub fn streamChunks(allocator: std.mem.Allocator, chunks: [][]const u8, out_writer: *std.Io.Writer) !void {
    var compressor = try snappy.StreamingCompressor.init(allocator, .{});
    defer compressor.deinit();

    // Write chunks incrementally as they arrive
    for (chunks) |chunk| {
        try compressor.write(chunk, out_writer);
    }

    // Flush any pending uncompressed data as final chunk
    try compressor.finish(out_writer);
}
```

### Incremental Decompression (`StreamingDecompressor`)

Feed compressed byte slices into the decompressor, and extract decompressed bytes into your output buffers:

```zig
const std = @import("std");
const snappy = @import("snappy");

pub fn consumeStream(allocator: std.mem.Allocator, network_chunks: [][]const u8) !void {
    var decompressor = snappy.StreamingDecompressor.init(allocator, .{});
    defer decompressor.deinit();

    var temp_buf: [4096]u8 = undefined;

    for (network_chunks) |chunk| {
        // 1. Feed incoming chunk
        try decompressor.feed(chunk);

        // 2. Drain available uncompressed data
        while (true) {
            const count = try decompressor.take(&temp_buf);
            if (count == 0) break;

            // Process decompressed buffer fragment...
            std.debug.print("Extracted {d} decompressed bytes\n", .{count});
        }
    }
}
```
