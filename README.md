<div align="center">

# snappy.zig

<a href="https://muhammad-fiaz.github.io/snappy.zig/"><img src="https://img.shields.io/badge/docs-muhammad--fiaz.github.io-blue" alt="Documentation"></a>
<a href="https://ziglang.org/"><img src="https://img.shields.io/badge/Zig-0.17.0-orange.svg?logo=zig" alt="Zig Version"></a>
<a href="https://github.com/muhammad-fiaz/snappy.zig"><img src="https://img.shields.io/github/stars/muhammad-fiaz/snappy.zig" alt="GitHub stars"></a>
<a href="https://github.com/muhammad-fiaz/snappy.zig/issues"><img src="https://img.shields.io/github/issues/muhammad-fiaz/snappy.zig" alt="GitHub issues"></a>
<a href="https://github.com/muhammad-fiaz/snappy.zig/pulls"><img src="https://img.shields.io/github/issues-pr/muhammad-fiaz/snappy.zig" alt="GitHub pull requests"></a>
<a href="https://github.com/muhammad-fiaz/snappy.zig"><img src="https://img.shields.io/github/last-commit/muhammad-fiaz/snappy.zig" alt="GitHub last commit"></a>
<a href="https://github.com/muhammad-fiaz/snappy.zig/blob/main/LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License"></a>
<img src="https://img.shields.io/badge/platforms-linux%20%7C%20windows%20%7C%20macos-blue" alt="Supported Platforms">
<a href="https://github.com/muhammad-fiaz/snappy.zig/releases/latest"><img src="https://img.shields.io/github/v/release/muhammad-fiaz/snappy.zig?label=Latest%20Release&style=flat-square" alt="Latest Release"></a>
<a href="https://pay.muhammadfiaz.com"><img src="https://img.shields.io/badge/Sponsor-pay.muhammadfiaz.com-ff69b4?style=flat&logo=heart" alt="Sponsor"></a>
<a href="https://github.com/sponsors/muhammad-fiaz"><img src="https://img.shields.io/badge/Sponsor-GitHub-pink?style=social&logo=github" alt="GitHub Sponsors"></a>
<a href="https://hits.sh/muhammad-fiaz/snappy.zig/"><img src="https://hits.sh/muhammad-fiaz/snappy.zig.svg?label=Visitors&extraCount=0&color=green" alt="Repo Visitors"></a>

<p><em>Fast, native Snappy compression for Zig.</em></p>

<b><a href="https://muhammad-fiaz.github.io/snappy.zig/">Documentation</a> |
<a href="https://muhammad-fiaz.github.io/snappy.zig/api/">API Reference</a> |
<a href="https://muhammad-fiaz.github.io/snappy.zig/guide/getting-started">Quick Start</a> |
<a href="CONTRIBUTING.md">Contributing</a></b>

</div>

`snappy.zig` is a high-performance, memory-safe, native Zig implementation of the Snappy lossless compression format and framing specification targeting **Zig 0.17.0**, engineered from first principles with zero C/C++ bindings, no `@cImport`, and zero external runtime dependencies.

> [!TIP]
> If you build with snappy.zig, make sure to give it a star!

> [!NOTE]
> `snappy.zig` implements both the Snappy Block format and Framed Stream format (.sz).
>
> - **Blazing Speed**: Designed for maximum throughput (gigabytes/second) rather than maximum compression ratio.
> - **Full Framing Format**: Standard stream identifier (`0xff 0x06 0x00 0x00 sNaPpY`), compressed chunks (`0x00`), uncompressed chunks (`0x01`), padding chunks (`0xfe`), and skippable chunks (`0x80`..`0xfd`).
> - **Native Castagnoli CRC-32C**: Masked checksum calculation reusing Zig standard library's `std.hash.crc.@"CRC-32/ISCSI"`.
> - **Reusable Contexts**: Initialize once, compress/decompress multiple streams via `reset()`, eliminating heap allocation churn.
> - **Chunked Streaming**: Process arbitrarily fragmented streams without buffering the full input in memory.

---

<details>
<summary><strong>Features</strong> (click to expand)</summary>

| Feature | Description |
|---|---|
| **One-shot Compression** | `snappy.compress(allocator, data)` for single-call framed stream or block compression |
| **One-shot Decompression** | `snappy.decompress(allocator, data)` with automatic format detection (framed stream or block) |
| **Caller-Buffer Operations** | `snappy.compressInto(src, dst)` and `snappy.decompressInto(src, dst)` for zero-allocation efficiency |
| **Compression Levels** | Level 1 (Fastest, default Snappy) and Level 2 (Double Hash) via `CompressionOptions` |
| **Reusable Compressor** | `snappy.Compressor` (`init`, `compress`, `compressInto`, `reset`, `deinit`) |
| **Reusable Decompressor** | `snappy.Decompressor` (`init`, `decompress`, `decompressInto`, `reset`, `deinit`) |
| **I/O Streaming** | `compressStream` and `decompressStream` with Zig 0.17 `std.Io.Reader` & `std.Io.Writer` |
| **Streaming Compressor** | `StreamingCompressor` with `write(chunk, writer)` and `finish(writer)` |
| **Streaming Decompressor** | `StreamingDecompressor` with `feed(chunk)` and `take(out)` |
| **Multi-Frame Concatenation** | Seamlessly decodes concatenated framed streams as specified |
| **Masked CRC-32C** | Compliant Castagnoli CRC-32C masked checksum verification |
| **Resource Limits** | `maxOutputSize` on `DecompressionOptions` to guard against decompression bombs |
| **Canonical Error Set** | Coherent `snappy.Error` and `snappy.StreamError` error sets |
| **Zero Dependencies** | Pure Zig implementation targeting Zig 0.17.0 |

</details>

---

<details>
<summary><strong>Prerequisites and Supported Platforms</strong> (click to expand)</summary>

<br>

## Prerequisites

| Requirement | Version | Notes |
|---|---|---|
| **Zig** | **0.17.0** (required) | Download from [ziglang.org](https://ziglang.org/download/) |
| **Operating System** | Windows 10+, Linux, macOS | Cross-platform support |

---

## Supported Platforms

`snappy.zig` targets these architectures:

| Platform | x86_64 (64-bit) | aarch64 (ARM64) | x86 (32-bit) | arm (32-bit) | riscv64 |
|---|---|---|---|---|---|
| **Linux** | Yes | Yes | Yes | Yes | Yes |
| **Windows** | Yes | Yes | Yes | - | - |
| **macOS** | Yes | Yes (Apple Silicon) | - | - | - |

### Cross-Compilation

Zig makes cross-compilation easy:

```bash
# Build for Linux ARM64
zig build -Dtarget=aarch64-linux

# Build for Windows x86_64
zig build -Dtarget=x86_64-windows

# Build for macOS Apple Silicon
zig build -Dtarget=aarch64-macos

# Build for 32-bit Windows
zig build -Dtarget=x86-windows

# Build for 32-bit ARM Linux
zig build -Dtarget=arm-linux-gnueabihf
```

</details>

---

## Installation

### Stable Release

```bash
zig fetch --save https://github.com/muhammad-fiaz/snappy.zig/archive/refs/tags/0.0.1.tar.gz
```

### Latest / Dev / Nightly

For development builds, nightly updates, or the latest unreleased changes:

```bash
zig fetch --save git+https://github.com/muhammad-fiaz/snappy.zig.git
```

### Wire into `build.zig`

```zig
const target = b.standardTargetOptions(.{});
const optimize = b.standardOptimizeOption(.{});

const snappy_dep = b.dependency("snappy", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("snappy", snappy_dep.module("snappy"));
```

---

## Quick Start

### One-Shot Compression & Decompression

```zig
const std = @import("std");
const snappy = @import("snappy");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const data = "Native Snappy compression in pure Zig 0.17.0!";

    // Compress (standard Snappy framed stream format)
    const compressed = try snappy.compress(allocator, data);
    defer allocator.free(compressed);

    // Decompress (automatically recognizes framed stream or raw block)
    const decompressed = try snappy.decompress(allocator, compressed);
    defer allocator.free(decompressed);

    std.debug.print("Restored: {s}\n", .{decompressed});
}
```

### Zero-Allocation Caller Buffer

```zig
var out_buf: [256]u8 = undefined;
const comp_len = try snappy.compressInto(data, &out_buf);

var restored_buf: [256]u8 = undefined;
const decomp_len = try snappy.decompressInto(out_buf[0..comp_len], &restored_buf);
```

### Advanced Options (camelCase)

```zig
const compressed = try snappy.compressWithOptions(allocator, data, .{
    .level = 2,              // 1 = fastest (default), 2 = higher compression
    .blockMode = .framed,    // .framed (.sz stream) or .block (raw block)
    .blockSize = 65536,      // fragment size up to 64KB
});
defer allocator.free(compressed);

const decompressed = try snappy.decompressWithOptions(allocator, compressed, .{
    .maxOutputSize = 10 * 1024 * 1024, // protect against decompression bombs
    .verifyChecksums = true,           // verify masked CRC-32C in frames
});
defer allocator.free(decompressed);
```

### Reusable Contexts (Zero Allocation Churn)

Initialize the context once with your allocator, reuse across multiple streams via `reset()`, and deinitialize when done:

```zig
var compressor = try snappy.Compressor.init(allocator, .{ .level = 1 });
defer compressor.deinit();

var decompressor = snappy.Decompressor.init(allocator, .{});
defer decompressor.deinit();

// First stream
const comp1 = try compressor.compress(input1);
defer allocator.free(comp1);
const out1 = try decompressor.decompress(comp1);
defer allocator.free(out1);

// Reset state without reallocating buffers
compressor.reset(.{ .level = 2 });
decompressor.reset(.{});

// Second stream
const comp2 = try compressor.compress(input2);
defer allocator.free(comp2);
const out2 = try decompressor.decompress(comp2);
defer allocator.free(out2);
```

### Streaming I/O with `std.Io`

Stream directly between `std.Io.Reader` and `std.Io.Writer`:

```zig
// Stream compression
var reader = std.Io.Reader.fixed(input_bytes);
var writer = std.Io.Writer.fixed(&out_buffer);

try snappy.compressStream(allocator, &reader, &writer, .{});

// Stream decompression
var comp_reader = std.Io.Reader.fixed(writer.buffered());
var decomp_writer = std.Io.Writer.fixed(&decomp_buffer);

try snappy.decompressStream(allocator, &comp_reader, &decomp_writer, .{});
```

### Chunked Streaming Compressor & Decompressor

```zig
// Incremental compression
var sc = try snappy.StreamingCompressor.init(allocator, .{ .level = 1 });
defer sc.deinit();

try sc.write(chunk1, &writer);
try sc.write(chunk2, &writer);
try sc.finish(&writer);

// Incremental decompression
var sd = snappy.StreamingDecompressor.init(allocator, .{});
defer sd.deinit();

try sd.feed(chunk);
var out_buf: [4096]u8 = undefined;
while (!sd.isFinished()) {
    const n = try sd.take(&out_buf);
    if (n == 0) break;
    // process out_buf[0..n]
}
```

---

## API Reference

### Top-Level Functions

| Function | Description |
|---|---|
| `snappy.compress(alloc, src)` | One-shot framed stream compression |
| `snappy.decompress(alloc, src)` | One-shot decompression (auto-detects framed stream vs raw block) |
| `snappy.compressWithOptions(alloc, src, opts)` | Compression with `CompressionOptions` |
| `snappy.decompressWithOptions(alloc, src, opts)` | Decompression with `DecompressionOptions` |
| `snappy.compressBlock(alloc, src, opts)` | Explicit raw block compression |
| `snappy.decompressBlock(alloc, src, opts)` | Explicit raw block decompression |
| `snappy.compressFramed(alloc, src, opts)` | Explicit framed stream compression |
| `snappy.decompressFramed(alloc, src, opts)` | Explicit framed stream decompression |
| `snappy.compressInto(src, dst)` | Compress into caller-allocated buffer |
| `snappy.decompressInto(src, dst)` | Decompress into caller-allocated buffer |
| `snappy.compressStream(alloc, reader, writer, opts)` | Stream compression via `std.Io` |
| `snappy.decompressStream(alloc, reader, writer, opts)` | Stream decompression via `std.Io` |
| `snappy.compressFile(alloc, src, dst, opts)` | Compress file on disk to Snappy framed file |
| `snappy.decompressFile(alloc, src, dst, opts)` | Decompress Snappy framed file on disk |
| `snappy.compressBound(src_size)` / `maxCompressedSize(src_size)` | Calculate upper bound on block compressed size |
| `snappy.maxFramedCompressedSize(src_size)` | Calculate upper bound on framed compressed size |
| `snappy.uncompressedLength(compressed)` | Read uncompressed length from block preamble |
| `snappy.isValidCompressedBuffer(compressed)` | Check syntactic validity of compressed block buffer |
| `snappy.versionString()` / `versionNumber()` | Library version (`0.0.1` / `1`) |

### Types

| Type | Description |
|---|---|
| `snappy.Compressor` | Reusable compressor: `init`, `compress`, `compressInto`, `reset`, `deinit` |
| `snappy.Decompressor` | Reusable decompressor: `init`, `decompress`, `decompressInto`, `reset`, `deinit` |
| `snappy.StreamingCompressor` | Streaming compressor: `write(chunk, writer)`, `finish(writer)`, `deinit()` |
| `snappy.StreamingDecompressor` | Streaming decompressor: `feed(chunk)`, `take(out)`, `reset()`, `deinit()` |
| `snappy.CompressionOptions` | `level`, `blockMode`, `blockSize` |
| `snappy.DecompressionOptions` | `maxOutputSize`, `verifyChecksums` |
| `snappy.BlockMode` | `.framed` (default) or `.block` |
| `snappy.Error` | Canonical error set: `CorruptStream`, `TruncatedInput`, `ChecksumMismatch`, etc. |
| `snappy.StreamError` | Streaming error set combining `snappy.Error` and reader/writer errors |

---

## Examples

The `examples/` directory contains complete, runnable examples:

| Example | File | Description |
|---|---|---|
| `basic_compression` | `examples/basic_compression.zig` | One-shot framed compression and caller-buffer APIs |
| `caller_buffer` | `examples/caller_buffer.zig` | Zero-allocation framed and raw block stack buffer operations |
| `reusable_context` | `examples/reusable_context.zig` | Context reuse via `reset()` without reallocating buffers |
| `streaming_compression` | `examples/streaming_compression.zig` | Chunked streaming compression using `StreamingCompressor` |
| `streaming_decompression` | `examples/streaming_decompression.zig` | Chunked streaming decompression using `StreamingDecompressor` |
| `io_pipeline` | `examples/io_pipeline.zig` | In-memory `std.Io.Reader` & `std.Io.Writer` streaming pipeline |
| `error_handling` | `examples/error_handling.zig` | Corrupted bitstream detection and decompression bomb guards |
| `format_introspection` | `examples/format_introspection.zig` | Library version, format constants, and compressed bounds |
| `bit_level` | `examples/bit_level.zig` | Variable-length integer encoding, tag bytes, and CRC-32C masking |
| `compress_file` | `examples/compress_file.zig` | File compression on disk using `std.Io` |
| `decompress_file` | `examples/decompress_file.zig` | File decompression from disk using `std.Io` |

Run any example:

```bash
zig build run-basic_compression
zig build run-caller_buffer
zig build run-streaming_compression
zig build run-reusable_context
zig build run-all-examples   # Run all 11 examples
```

---

## Building & Testing

```bash
zig build                    # Build native Snappy library and examples
zig build test               # Run all unit and integration tests
zig build test --summary all # Detailed test execution summary
zig build run-all-examples   # Run all 11 example executables
zig build fuzz               # Run decoder robustness fuzzer
zig build docs               # Generate official Zig autodocs in zig-out/docs
zig build check              # Validate compilation across all targets
```

---

## Contributing

Contributions are welcome! Please ensure all tests pass:

```bash
zig fmt src examples build.zig build.zig.zon
zig build test --summary all
zig build run-all-examples
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

## Security

For vulnerability reporting and security guarantees, please see [SECURITY.md](SECURITY.md).

## Acknowledgements

`snappy.zig` is a native Zig implementation of the Snappy format and codec, engineered from first principles in pure Zig.

The [Snappy project](https://github.com/google/snappy/tree/9c28114a38866f6deeaa826db918293bc28ae410) (commit `9c28114a38866f6deeaa826db918293bc28ae410`) is used as a reference standard for the Snappy format, codec behavior, compatibility, and interoperability verification.

This project does not depend on the upstream implementation.

## License

MIT License - see [LICENSE](LICENSE) for details.
