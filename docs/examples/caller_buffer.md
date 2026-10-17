---
title: Caller Buffer Example
description: Zero-allocation framed and raw block compression and decompression using pre-allocated memory buffers.
keywords: caller buffer example, zero allocation compression zig, compressInto, decompressInto, stack buffers, snappy
---

# Caller Buffer Example

In latency-critical applications such as game engines, high-frequency trading platforms, kernel-adjacent drivers, and embedded systems, dynamic heap allocations (`malloc`, `page_allocator`, `GPA`) are strictly forbidden due to unpredictable latency and fragmentation.

`snappy.zig` provides caller-buffer APIs for both framed streams and raw blocks that execute with **zero** heap allocations:
- **`snappy.compressInto`** & **`snappy.decompressInto`**: Full Snappy framed streams (`.sz`) with stream headers and CRC-32C verification.
- **`snappy.compressBlockInto`** & **`snappy.decompressBlockInto`**: Bare raw Snappy blocks without stream headers.

---

## Snappy Format Context

- **Framed Format (`compressInto` / `decompressInto`)**:
  - Automatically writes the 10-byte stream identifier `\xff\x06\x00\x00sNaPpY`.
  - Encapsulates chunks with chunk types, lengths, and 4-byte masked CRC-32C checksums.
  - Required buffer size: `snappy.maxFramedCompressedSize(input.len)`.
- **Raw Block Format (`compressBlockInto` / `decompressBlockInto`)**:
  - Begins with a varint-encoded uncompressed length (1 to 5 bytes).
  - Emits LZ77 copy and literal tags.
  - Required buffer size: `snappy.maxCompressedSize(input.len)` (or `snappy.compressBound(input.len)`).

---

## Complete Source Code (`examples/caller_buffer.zig`)

```zig
const std = @import("std");
const snappy = @import("snappy");

pub fn main() !void {
    const data = "Fixed stack memory buffers eliminate heap allocations entirely!";

    var framed_storage: [256]u8 = undefined;
    var block_storage: [256]u8 = undefined;
    var restored_storage: [256]u8 = undefined;

    // 1. Zero-allocation framed compression & decompression
    const framed_len = try snappy.compressInto(data, &framed_storage);
    const framed_restored_len = try snappy.decompressInto(framed_storage[0..framed_len], &restored_storage);

    std.debug.print("Zero-allocation framed roundtrip succeeded: \"{s}\" ({d} bytes)\n", .{
        restored_storage[0..framed_restored_len],
        framed_restored_len,
    });

    // 2. Zero-allocation raw block compression & decompression
    const block_len = try snappy.compressBlockInto(data, &block_storage, .{});
    const block_restored_len = try snappy.decompressBlockInto(block_storage[0..block_len], &restored_storage, .{});

    std.debug.print("Zero-allocation block roundtrip succeeded: \"{s}\" ({d} bytes)\n", .{
        restored_storage[0..block_restored_len],
        block_restored_len,
    });
}
```

---

## Step-by-Step Code Walkthrough

1. **Stack Buffer Allocation**:
   `var framed_storage: [256]u8 = undefined;` and `var block_storage: [256]u8 = undefined;` pre-allocate memory on the thread execution stack. No system calls or allocator locks are performed.

2. **Framed Compression (`snappy.compressInto`)**:
   `snappy.compressInto(data, &framed_storage)` formats the input into a standard Snappy framed stream, verifies that `framed_storage.len >= maxFramedCompressedSize(data.len)`, writes the header and checksummed chunks, and returns the exact number of bytes written (`framed_len`).

3. **Framed Decompression (`snappy.decompressInto`)**:
   `snappy.decompressInto(framed_storage[0..framed_len], &restored_storage)` parses the framed stream, validates chunk boundaries and CRC-32C checksums, and decompresses into `restored_storage`, returning the restored byte count.

4. **Raw Block Compression (`snappy.compressBlockInto`)**:
   `snappy.compressBlockInto(data, &block_storage, .{})` compresses the raw block without writing the 10-byte framing header or chunk headers, returning the compressed block size.

5. **Raw Block Decompression (`snappy.decompressBlockInto`)**:
   `snappy.decompressBlockInto(block_storage[0..block_len], &restored_storage, .{})` reads the leading varint length and decodes literals and copy offsets into `restored_storage`.

---

## Explicit I/O & Buffer Safety

All caller-buffer operations enforce strict bounds checking:
- If the destination slice is too small to receive the worst-case compressed output, `error.OutputBufferTooSmall` is returned immediately before any memory is written.
- If during decompression the uncompressed payload exceeds the destination buffer length, `error.OutputBufferTooSmall` is returned.
- Caller retains total ownership of all buffers.

---

## Running the Example

Compile and run directly with the Zig build system:

```bash
zig build run-caller_buffer
```

### Expected Output

```console
Zero-allocation framed roundtrip succeeded: "Fixed stack memory buffers eliminate heap allocations entirely!" (63 bytes)
Zero-allocation block roundtrip succeeded: "Fixed stack memory buffers eliminate heap allocations entirely!" (63 bytes)
```
