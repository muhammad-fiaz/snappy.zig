---
title: API Reference Overview
description: Overview of the public API symbols and functions exposed by snappy.zig.
keywords: snappy zig api reference, compressWithOptions, decompressWithOptions, compressStream, snappy functions, zig 0.17.0
---

# API Reference Overview

The `snappy.zig` public interface provides both top-level one-shot functions and specialized struct types for fine-grained control.

## Top-Level One-Shot Functions

| Function | Signature | Description |
| :--- | :--- | :--- |
| `snappy.compress` | `(allocator, src) ![]u8` | Compresses `src` into a standard Snappy framed stream (`.sz`). |
| `snappy.compressWithOptions` | `(allocator, src, opts) ![]u8` | Compresses `src` with custom `CompressionOptions`. |
| `snappy.compressInto` | `(src, dst) !usize` | Compresses `src` into caller-allocated `dst` slice (zero heap allocation). |
| `snappy.decompress` | `(allocator, src) ![]u8` | Decompresses `src`, auto-detecting framed streams and raw blocks. |
| `snappy.decompressWithOptions` | `(allocator, src, opts) ![]u8` | Decompresses `src` with custom `DecompressionOptions` (e.g. `maxOutputSize`). |
| `snappy.decompressInto` | `(src, dst) !usize` | Decompresses `src` directly into caller-allocated `dst` slice. |
| `snappy.compressFramed` | `(allocator, src) ![]u8` | Explicit framed stream compression. |
| `snappy.decompressFramed` | `(allocator, src) ![]u8` | Explicit framed stream decompression. |
| `snappy.compressBlock` | `(allocator, src) ![]u8` | Compresses raw Snappy block with varint length prefix. |
| `snappy.decompressBlock` | `(allocator, src) ![]u8` | Decompresses raw Snappy block with varint length prefix. |

---

## Streaming & I/O Functions

| Function | Signature | Description |
| :--- | :--- | :--- |
| `snappy.compressStream` | `(allocator, reader, writer, opts) StreamError!void` | Compresses stream from `std.Io.Reader` to `std.Io.Writer`. |
| `snappy.decompressStream` | `(allocator, reader, writer, opts) StreamError!void` | Decompresses stream from `std.Io.Reader` to `std.Io.Writer`. |
| `snappy.compressFile` | `(allocator, in_path, out_path, opts) !void` | Compresses an on-disk file into a Snappy framed file. |
| `snappy.decompressFile` | `(allocator, in_path, out_path, opts) !void` | Decompresses an on-disk Snappy framed file. |

---

## Bounds & Metadata Functions

| Function | Signature | Description |
| :--- | :--- | :--- |
| `snappy.maxCompressedSize(len)` | `(usize) usize` | Calculates upper bound for raw block compression (`32 + N + N / 6`). |
| `snappy.compressBound(len)` | `(usize) usize` | Alias for `maxCompressedSize`. |
| `snappy.maxFramedCompressedSize(len)` | `(usize) usize` | Calculates upper bound for framed stream (`.sz`) compression. |
| `snappy.uncompressedLength(src)` | `([]const u8) !usize` | Parses expected uncompressed length from a raw block varint prefix. |
| `snappy.isValidCompressedBuffer(src)` | `([]const u8) bool` | Checks if a buffer begins with a valid varint length header. |
| `snappy.versionString()` | `() []const u8` | Returns library version string (`0.0.1`). |
| `snappy.versionNumber()` | `() u32` | Returns integer version code (`(major << 16) \| (minor << 8) \| patch`). |
