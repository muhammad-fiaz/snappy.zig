---
title: Format Introspection Example
description: Inspecting Snappy stream identifiers, block bounds, varints, and uncompressed lengths before decoding.
keywords: format introspection example, isValidCompressedBuffer, uncompressedLength, maxCompressedSize, versionString, zig 0.17.0
---

# Format Introspection Example

Before dedicating memory or CPU cycles to decompression, high-performance systems frequently need to introspect compressed buffers: determining the uncompressed payload size, verifying structural validity, and calculating exact worst-case output bounds.

---

## Snappy Format Inspection Architecture

1. **Uncompressed Length Header (Raw Block)**:
   - Snappy raw blocks store the total uncompressed length in a 32-bit little-endian variable-length integer (varint) in the first 1 to 5 bytes.
   - `snappy.uncompressedLength(buffer)` decodes this varint directly without decompressing or parsing the LZ77 elements.
   - `snappy.isValidCompressedBuffer(buffer)` verifies that the buffer starts with a syntactically valid varint that does not exceed 32 bits or 5 bytes.

2. **Stream Magic Identifier (Framed Format)**:
   - Official framed streams begin with `\xff\x06\x00\x00sNaPpY` (`snappy.STREAM_IDENTIFIER`).

3. **Worst-Case Expansion Bounds**:
   - For raw blocks:
     $$\text{maxCompressedSize}(n) = 32 + n + \lfloor n / 6 \rfloor$$
   - For framed streams:
     $$\text{maxFramedCompressedSize}(n) = 10 + \lceil n / 65536 \rceil \times (4 + \text{maxCompressedSize}(65536))$$

---

## Complete Source Code (`examples/format_introspection.zig`)

```zig
const std = @import("std");
const snappy = @import("snappy");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("=== Snappy Format Introspection ===\n", .{});
    std.debug.print("Package Version: {s}\n", .{snappy.versionString()});
    std.debug.print("Version Number:  0x{x:0>6}\n", .{snappy.versionNumber()});
    std.debug.print("Max Block Size:  {d} bytes\n", .{snappy.types.MAX_BLOCK_SIZE});
    std.debug.print("Stream Magic:    {s}\n\n", .{snappy.types.STREAM_IDENTIFIER});

    const sample = "Structured data for introspection inspection";
    const max_bound = snappy.maxCompressedSize(sample.len);
    const framed_bound = snappy.maxFramedCompressedSize(sample.len);

    std.debug.print("Input size:            {d} bytes\n", .{sample.len});
    std.debug.print("Block Max Bound:       {d} bytes\n", .{max_bound});
    std.debug.print("Framed Max Bound:      {d} bytes\n\n", .{framed_bound});

    // Inspect block format
    const block_comp = try snappy.compressBlock(allocator, sample, .{});
    defer allocator.free(block_comp);

    const is_valid = snappy.isValidCompressedBuffer(block_comp);
    const uncompressed_size = try snappy.uncompressedLength(block_comp);

    std.debug.print("IsValidCompressedBuffer: {}\n", .{is_valid});
    std.debug.print("Uncompressed Length:     {d} bytes\n", .{uncompressed_size});
}
```

---

## Step-by-Step Code Walkthrough

1. **Version Querying**:
   - `snappy.versionString()` returns `"0.0.1"`.
   - `snappy.versionNumber()` returns `0x000001` (`(0 << 16) | (0 << 8) | 1`).
2. **Format Constants**:
   - `snappy.types.MAX_BLOCK_SIZE` is `65536` bytes (the maximum uncompressed payload per Snappy chunk).
   - `snappy.types.STREAM_IDENTIFIER` is `"sNaPpY"`.
3. **Worst-Case Buffer Calculations**:
   - `snappy.maxCompressedSize(44)` calculates $32 + 44 + \lfloor 44 / 6 \rfloor = 83$ bytes.
   - `snappy.maxFramedCompressedSize(44)` calculates the framed bound with 10-byte header, chunk header, and 64KB chunk padding.
4. **Header Introspection**:
   - `snappy.compressBlock` compresses the sample into a raw Snappy block.
   - `snappy.isValidCompressedBuffer(block_comp)` returns `true` after verifying the varint prefix.
   - `snappy.uncompressedLength(block_comp)` parses the varint and returns `44` bytes in $O(1)$ time with zero memory allocations.

---

## Running the Example

Compile and run directly with the Zig build system:

```bash
zig build run-format_introspection
```

### Expected Output

```console
=== Snappy Format Introspection ===
Package Version: 0.0.1
Version Number:  0x000001
Max Block Size:  65536 bytes
Stream Magic:    sNaPpY

Input size:            44 bytes
Block Max Bound:       83 bytes
Framed Max Bound:      76508 bytes

IsValidCompressedBuffer: true
Uncompressed Length:     44 bytes
```
