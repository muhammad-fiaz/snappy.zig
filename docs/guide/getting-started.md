---
title: Getting Started
description: Quick start guide to compressing and decompressing data with snappy.zig in native Zig 0.17.0.
keywords: snappy zig getting started, zig snappy tutorial, fast compression zig, snappy framed vs raw blocks, native zig 0.17.0
---

# Getting Started

`snappy.zig` is a modern, pure Zig library for Google's Snappy compression format. It provides high-performance compression and decompression without any C runtime bindings, external dependencies, or `@cImport`.

## Key Concepts

Snappy operates on two standard formats:
1. **Snappy Framed Streams (`.sz`)**: The official framing container format beginning with a stream identifier chunk (`0xff 0x06 0x00 0x00 sNaPpY`), chunk headers, compressed data chunks (`0x00`), uncompressed data chunks (`0x01`), skippable chunks, and masked CRC-32C (Castagnoli) checksums. This format is fully compatible with tools like `snappy`, Hadoop, Kafka, and Cassandra.
2. **Snappy Raw Blocks**: The core byte-oriented compressed block format consisting of a little-endian varint uncompressed length prefix followed by literal and copy backreference tags. Raw blocks are widely used in LevelDB, RocksDB, Parquet, and RPC protocols.

`snappy.zig` handles both formats seamlessly.

---

## One-Shot Operations (With Allocator)

When dynamic memory is preferred, pass an `Allocator` as the first argument:

```zig
const std = @import("std");
const snappy = @import("snappy");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const payload = "Hello, high-speed Snappy compression from native Zig!";

    // 1. Compress into an allocated Snappy framed stream (.sz)
    const compressed = try snappy.compress(allocator, payload);
    defer allocator.free(compressed);

    // 2. Decompress into an allocated slice (auto-detects framed streams and raw blocks)
    const decompressed = try snappy.decompress(allocator, compressed);
    defer allocator.free(decompressed);

    std.debug.assert(std.mem.eql(u8, payload, decompressed));
}
```

---

## Raw Block Operations

For database blocks, table files, or embedded protocols where raw block format is expected:

```zig
const std = @import("std");
const snappy = @import("snappy");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const data = "Database column values or key-value record payload.";

    // Compress raw block (starts with varint length prefix)
    const block = try snappy.compressBlock(allocator, data, .{});
    defer allocator.free(block);

    // Decompress raw block
    const restored = try snappy.decompressBlock(allocator, block, .{});
    defer allocator.free(restored);

    std.debug.assert(std.mem.eql(u8, data, restored));
}
```

---

## Zero-Allocation Caller Buffers

For hot paths, embedded environments, or game loops where heap allocation is undesirable, use caller-provided destination buffers:

```zig
const std = @import("std");
const snappy = @import("snappy");

pub fn main() !void {
    const input = "Zero allocation compression is simple and safe in Zig.";

    // Calculate maximum compressed bounds or use fixed stack buffer
    var comp_buffer: [512]u8 = undefined;
    var decomp_buffer: [512]u8 = undefined;

    // Compress directly into buffer
    const comp_bytes = try snappy.compressInto(input, &comp_buffer);

    // Decompress directly from buffer
    const decomp_bytes = try snappy.decompressInto(comp_buffer[0..comp_bytes], &decomp_buffer);

    std.debug.assert(std.mem.eql(u8, input, decomp_buffer[0..decomp_bytes]));
}
```

---

## Reusable Contexts

If your application compresses or decompresses thousands of messages in a loop, avoid repeatedly allocating internal structures. Use `snappy.Compressor` and `snappy.Decompressor`:

```zig
const std = @import("std");
const snappy = @import("snappy");

pub fn processBatches(allocator: std.mem.Allocator, messages: [][]const u8) !void {
    var compressor = try snappy.Compressor.init(allocator, .{});
    defer compressor.deinit();

    for (messages) |msg| {
        const framed = try compressor.compress(msg);
        defer allocator.free(framed);

        // Process compressed framed stream...
    }
}
```

---

## Next Steps

- Check the [Installation Guide](./installation) for build system setup.
- Read [Compression](./compression) to learn about compression modes and caller buffers.
- Explore [Streaming](./streaming) for large files and socket streams.
- Learn about [Framing & Checksums](./framing) for stream structure and CRC-32C verification.
