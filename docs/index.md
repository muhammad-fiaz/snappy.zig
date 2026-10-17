---
layout: home
title: Native Snappy Compression & Decompression Library for Zig
titleTemplate: ":title | snappy.zig"
description: Ultra-fast, memory-safe, pure native Zig 0.17.0 implementation of Google's Snappy lossless compression format, standard framing format, streaming pipelines, and reusable contexts.
keywords: native snappy compression and decompression library for zig, zig snappy, pure zig compression, snappy framed format, snappy streaming, crc32c checksum, zig 0.17.0, zero dependencies

hero:
  name: "snappy.zig"
  text: "Ultra-Fast Native Snappy Compression for Zig"
  tagline: "Pure Zig implementation of Google's Snappy compression format targeting Zig 0.17.0. Zero C dependencies, zero overhead, memory-safe."
  actions:
    - theme: brand
      text: Get Started
      link: /guide/getting-started
    - theme: alt
      text: API Reference
      link: /api/
    - theme: alt
      text: Examples
      link: /examples/
    - theme: alt
      text: View on GitHub
      link: https://github.com/muhammad-fiaz/snappy.zig

features:
  - icon: ⚡
    title: Pure Native Zig (0.17.0)
    details: Engineered from first principles in native Zig without `@cImport`, C compiler requirements, or external runtime dependencies.
  - icon: 🚀
    title: High-Throughput Byte-Oriented Codec
    details: Optimized LZ77 byte-tag encoder and decoder achieving gigabytes-per-second decompression speed and hundreds of MB/s compression.
  - icon: 📦
    title: Official Framed & Raw Block Formats
    details: Full interoperability with Google's Snappy specifications, supporting raw blocks and framed streams (`.sz`) with stream IDs and chunk headers.
  - icon: 🛡️
    title: Memory-Safe & Defensive
    details: Strict bounds checking, safe handling of malformed and truncated inputs, and protection against integer overflow attacks.
  - icon: 🌊
    title: Streaming & I/O Pipelines
    details: First-class integration with Zig 0.17 `std.Io.Reader` and `std.Io.Writer` alongside chunked streaming and file processing.
  - icon: 🔄
    title: Context Reuse & Zero Allocation
    details: Reusable `Compressor` and `Decompressor` instances eliminate heap allocation churn; caller-buffer APIs (`compressInto`, `decompressInto`) require zero heap allocations.
---


## Installation

Add `snappy.zig` to your `build.zig.zon`:

```bash
# 1. Stable Release (Tagged)
zig fetch --save https://github.com/muhammad-fiaz/snappy.zig/archive/refs/tags/0.0.1.tar.gz

# 2. Nightly / Latest Development URL
zig fetch --save git+https://github.com/muhammad-fiaz/snappy.zig.git
```

Then expose the module in your `build.zig`:

```zig
const snappy_dep = b.dependency("snappy", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("snappy", snappy_dep.module("snappy"));
```


## Quick Example

Compress and decompress data in just a few lines of idiomatic Zig:

```zig
const std = @import("std");
const snappy = @import("snappy");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const raw_data = "Snappy is a compression/decompression library aimed at very high speeds!";

    // One-shot framed compression (standard .sz stream format)
    const compressed = try snappy.compress(allocator, raw_data);
    defer allocator.free(compressed);

    // One-shot decompression (handles framed streams and raw blocks automatically)
    const restored = try snappy.decompress(allocator, compressed);
    defer allocator.free(restored);

    std.debug.print("Original size:   {d} bytes\n", .{raw_data.len});
    std.debug.print("Compressed size: {d} bytes\n", .{compressed.len});
    std.debug.print("Restored:        {s}\n", .{restored});
}
```
