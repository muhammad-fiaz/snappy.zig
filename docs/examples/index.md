---
title: Examples Overview
description: Gallery of runnable examples demonstrating the snappy.zig API in native Zig 0.17.0.
keywords: snappy zig examples, runnable code samples, zig build run-all-examples, tutorial, compression guide
---

# Examples Overview

The `examples/` directory contains complete, standalone example programs demonstrating real-world compression patterns with `snappy.zig` on Zig 0.17.0.

Every example is self-contained, adheres to the official Google Snappy format specification, and can be compiled and executed directly using the Zig build system.

---

## Running the Examples

```bash
# Run a specific example
zig build run-basic_compression
zig build run-caller_buffer
zig build run-reusable_context
zig build run-streaming_compression
zig build run-streaming_decompression
zig build run-io_pipeline
zig build run-error_handling
zig build run-format_introspection
zig build run-bit_level
zig build run-compress_file
zig build run-decompress_file

# Run all registered examples sequentially
zig build run-all-examples
```

---

## Example Directory

| Example | File | Command | Description |
| :--- | :--- | :--- | :--- |
| [Basic Compression](./basic_compression) | [`examples/basic_compression.zig`](https://github.com/muhammad-fiaz/snappy.zig/blob/main/examples/basic_compression.zig) | `zig build run-basic_compression` | One-shot framed and raw block compression and decompression with allocator. |
| [Caller Buffers](./caller_buffer) | [`examples/caller_buffer.zig`](https://github.com/muhammad-fiaz/snappy.zig/blob/main/examples/caller_buffer.zig) | `zig build run-caller_buffer` | Zero-allocation compression & decompression into pre-allocated memory slices (`compressInto`, `decompressInto`). |
| [File Compression](./file_compression) | [`examples/compress_file.zig`](https://github.com/muhammad-fiaz/snappy.zig/blob/main/examples/compress_file.zig) | `zig build run-compress_file`<br>`zig build run-decompress_file` | Compressing and decompressing disk files with Zig 0.17 `std.Io`. |
| [Streaming Compression](./streaming_compression) | [`examples/streaming_compression.zig`](https://github.com/muhammad-fiaz/snappy.zig/blob/main/examples/streaming_compression.zig) | `zig build run-streaming_compression` | Push-based incremental chunk compression using `StreamingCompressor`. |
| [Streaming Decompression](./streaming_decompression) | [`examples/streaming_decompression.zig`](https://github.com/muhammad-fiaz/snappy.zig/blob/main/examples/streaming_decompression.zig) | `zig build run-streaming_decompression` | Pull-based incremental chunk decompression using `StreamingDecompressor`. |
| [Reusable Context](./reusable_context) | [`examples/reusable_context.zig`](https://github.com/muhammad-fiaz/snappy.zig/blob/main/examples/reusable_context.zig) | `zig build run-reusable_context` | Amortizing allocation costs across thousands of operations with `Compressor` and `Decompressor`. |
| [Error Handling](./error_handling) | [`examples/error_handling.zig`](https://github.com/muhammad-fiaz/snappy.zig/blob/main/examples/error_handling.zig) | `zig build run-error_handling` | Robust handling of corrupted streams, invalid chunk headers, and CRC-32C checksum mismatches. |
| [Format Introspection](./format_introspection) | [`examples/format_introspection.zig`](https://github.com/muhammad-fiaz/snappy.zig/blob/main/examples/format_introspection.zig) | `zig build run-format_introspection` | Inspecting uncompressed lengths, magic identifiers, and block bounds. |
| [Bit-Level & Tag Encoding](./bit_level) | [`examples/bit_level.zig`](https://github.com/muhammad-fiaz/snappy.zig/blob/main/examples/bit_level.zig) | `zig build run-bit_level` | Understanding Snappy varints, literal tags, and 1/2/4-byte copy offset tags. |
| [I/O Pipeline](./io_pipeline) | [`examples/io_pipeline.zig`](https://github.com/muhammad-fiaz/snappy.zig/blob/main/examples/io_pipeline.zig) | `zig build run-io_pipeline` | Integrating directly with Zig 0.17 `std.Io.Reader` and `std.Io.Writer`. |

---

## Snappy Format & Feature Matrix

| Example | Format Type | Header Emitted | Integrity Check | Memory Model |
|---|---|---|---|---|
| **`basic_compression`** | Framed Stream (`.sz`) | `\xff\x06\x00\x00sNaPpY` | Masked CRC-32C | Dynamic & Stack buffer |
| **`caller_buffer`** | Framed & Raw Block | Auto-detected | Masked CRC-32C / None | **Zero heap allocation** |
| **`file_compression`** | Framed Stream (`.sz`) | `\xff\x06\x00\x00sNaPpY` | Masked CRC-32C | Zig 0.17.0 `std.Io` threaded filesystem |
| **`streaming_compression`** | Framed Stream (`.sz`) | `\xff\x06\x00\x00sNaPpY` | Masked CRC-32C | 64KB staging chunk buffer |
| **`streaming_decompression`**| Framed Stream (`.sz`) | `\xff\x06\x00\x00sNaPpY` | Masked CRC-32C | Push/pull streaming ring buffer |
| **`reusable_context`** | Framed & Raw Block | Configurable | Masked CRC-32C / None | Reused hash tables & scratch memory |
| **`error_handling`** | Framed & Raw Block | Validated | Masked CRC-32C checked | Safe deterministic error returns |
| **`format_introspection`** | Framed & Raw Block | Inspected | Pre-validation | $O(1)$ zero-allocation inspection |
| **`bit_level`** | LEB128 & Tag bytes | Byte-level layout | Polynomial `0x82f63b78` | Bit-level primitives |
| **`io_pipeline`** | Framed Stream (`.sz`) | `\xff\x06\x00\x00sNaPpY` | Masked CRC-32C | `*std.Io.Reader` $\rightarrow$ `*std.Io.Writer` |
