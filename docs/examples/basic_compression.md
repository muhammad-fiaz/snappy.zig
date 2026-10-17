---
title: Basic Compression Example
description: One-shot framed compression, decompression, and caller-buffer APIs in snappy.zig.
keywords: basic compression example, snappy.compress, snappy.decompress, compressInto, decompressInto, zig 0.17.0
---

# Basic Compression Example

This example demonstrates the primary one-shot compression and decompression functions in `snappy.zig`, covering both allocator-backed dynamic memory operations and zero-allocation caller-provided buffer operations.

---

## Snappy Format Architecture

Snappy supports two distinct binary layout formats:

1. **Framed Stream Format (`.sz` / framing)**:
   - Starts with a mandatory 10-byte **Stream Identifier** chunk:
     - `0xff`: Stream Identifier chunk type byte.
     - `\x06\x00\x00`: 24-bit little-endian length of 6 bytes.
     - `sNaPpY`: Magic ASCII string (`0x73, 0x4e, 0x61, 0x50, 0x70, 0x59`).
   - Followed by data chunks:
     - `0x00`: Compressed chunk (3-byte length, 4-byte masked CRC-32C, raw compressed block bytes).
     - `0x01`: Uncompressed chunk (used when data is incompressible or uncompressed storage is preferred).
     - `0xfe`: Stream padding.
     - `0x02` - `0x7f`: Skippable custom chunks.
   - Self-terminating, streamable, and protected against data corruption via hardware-accelerated Castagnoli CRC-32C checksums.

2. **Raw Block Format**:
   - Begins with a variable-length integer (varint, 1–5 bytes) storing the uncompressed payload size.
   - Followed by LZ77 byte sequences (literals and copy references) with no framing headers or checksums.

`snappy.compress` and `snappy.compressInto` produce official **Framed Streams** by default, guaranteeing interoperability with standard tools like `python-snappy`, Go `sz`, and the C++ Snappy framing tools. `snappy.decompress` auto-detects framed streams versus raw blocks seamlessly.

---

## Complete Source Code (`examples/basic_compression.zig`)

```zig
const std = @import("std");
const snappy = @import("snappy");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const original_text = "Hello, world! Native Snappy compression in pure Zig 0.17.0!";

    std.debug.print("Original data ({d} bytes): \"{s}\"\n", .{ original_text.len, original_text });

    // 1. One-shot framed stream compression (default)
    const compressed = try snappy.compress(allocator, original_text);
    defer allocator.free(compressed);

    std.debug.print("Compressed framed stream: {d} bytes\n", .{compressed.len});

    // 2. One-shot decompression (automatically detects framed stream format)
    const decompressed = try snappy.decompress(allocator, compressed);
    defer allocator.free(decompressed);

    std.debug.print("Decompressed ({d} bytes): \"{s}\"\n", .{ decompressed.len, decompressed });

    // 3. Zero-allocation caller buffer API
    var caller_out: [256]u8 = undefined;
    const comp_len = try snappy.compressInto(original_text, &caller_out);
    std.debug.print("Caller-buffer compression: {d} bytes written\n", .{comp_len});

    var caller_restored: [256]u8 = undefined;
    const decomp_len = try snappy.decompressInto(caller_out[0..comp_len], &caller_restored);
    std.debug.print("Caller-buffer decompression: {d} bytes: \"{s}\"\n", .{ decomp_len, caller_restored[0..decomp_len] });
}
```

---

## Step-by-Step Code Walkthrough

1. **Module Import & Setup**:
   `const snappy = @import("snappy");` imports the library. `std.heap.page_allocator` provides memory for the one-shot allocator functions.

2. **One-Shot Framed Compression (`snappy.compress`)**:
   `snappy.compress(allocator, original_text)` computes the required framed buffer size using `maxFramedCompressedSize`, allocates the memory, writes the 10-byte `sNaPpY` magic identifier header, emits the data chunk with its 4-byte masked CRC-32C checksum, and returns an owned slice `[]u8`.

3. **Memory Cleanup with `defer`**:
   The caller owns the returned slice and frees it via `defer allocator.free(compressed)`.

4. **One-Shot Decompression (`snappy.decompress`)**:
   `snappy.decompress(allocator, compressed)` inspects the input:
   - Detects the 10-byte framed stream magic header.
   - Validates each chunk header and verifies data integrity against the 32-bit masked CRC-32C checksum.
   - Assembles the decompressed payload into an allocated slice.

5. **Zero-Allocation Stack Buffers (`compressInto` & `decompressInto`)**:
   In embedded systems or high-frequency loops where heap allocation is forbidden, pre-allocated stack arrays (`[256]u8`) are supplied directly:
   - `snappy.compressInto(original_text, &caller_out)` compresses directly into the destination buffer and returns the exact number of bytes written.
   - `snappy.decompressInto(caller_out[0..comp_len], &caller_restored)` decodes the framed bytes directly into the target buffer, returning the restored length.
   - If the destination slice is smaller than required, `error.OutputBufferTooSmall` is returned without modifying invalid memory.

---

## Explicit I/O & Memory Handling

| Phase | Input I/O | Output I/O | Memory Allocation |
|---|---|---|---|
| **`snappy.compress`** | In-memory slice `[]const u8` | Dynamic slice `[]u8` | Single allocation sized by `maxFramedCompressedSize` |
| **`snappy.decompress`** | In-memory slice `[]const u8` | Dynamic slice `[]u8` | Dynamically sized by uncompressed chunk sizes |
| **`snappy.compressInto`** | In-memory slice `[]const u8` | Caller stack/arena slice `[]u8` | **Zero** heap allocations |
| **`snappy.decompressInto`** | In-memory slice `[]const u8` | Caller stack/arena slice `[]u8` | **Zero** heap allocations |

---

## Running the Example

Compile and run directly with the Zig build system:

```bash
zig build run-basic_compression
```

### Expected Output

```console
Original data (59 bytes): "Hello, world! Native Snappy compression in pure Zig 0.17.0!"
Compressed framed stream: 77 bytes
Decompressed (59 bytes): "Hello, world! Native Snappy compression in pure Zig 0.17.0!"
Caller-buffer compression: 77 bytes written
Caller-buffer decompression: 59 bytes: "Hello, world! Native Snappy compression in pure Zig 0.17.0!"
```
