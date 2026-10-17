---
title: Streaming Decompression Example
description: Incremental pull-based streaming decompression with snappy.StreamingDecompressor.
keywords: streaming decompression example, StreamingDecompressor, feed, take, fragmented packets, zig 0.17.0
---

# Streaming Decompression Example

In network protocols, message brokers (e.g. Kafka, RabbitMQ), and non-blocking event loops (`epoll`, `kqueue`, IOCP), compressed data arrives in fragmented network packets rather than all at once. 

`snappy.StreamingDecompressor` allows callers to feed arbitrary byte slices into the decompressor via `feed()` and drain decompressed bytes on demand via `take()` with zero intermediate file buffering.

---

## Snappy Framing Protocol & Packet Assembly

A standard Snappy framed stream contains:
1. **Magic Header Chunk**: `\xff\x06\x00\x00sNaPpY` (10 bytes).
2. **Chunk Framing**: Each chunk begins with a 4-byte header:
   - Byte 0: Chunk identifier (`0x00` compressed, `0x01` uncompressed, `0xfe` padding, `0x02`-`0x7f` skippable).
   - Bytes 1–3: 24-bit little-endian length $L$.
   - Bytes 4–7 (for data chunks): 32-bit masked Castagnoli CRC-32C checksum.
   - Bytes 8–$(L+3)$: Chunk payload bytes.

`StreamingDecompressor` maintains an internal state machine:
- Accumulates bytes across fragmented packet boundaries until full chunk headers and payloads are gathered.
- Verifies the masked CRC-32C checksum before emitting decompressed data.
- Stages uncompressed bytes in an internal output buffer ready to be drained via `take()`.

---

## Complete Source Code (`examples/streaming_decompression.zig`)

```zig
const std = @import("std");
const snappy = @import("snappy");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const source_text = "Incremental chunked decompression in Zig 0.17.0 simulating fragmented network packets.";
    const compressed = try snappy.compressFramed(allocator, source_text, .{});
    defer allocator.free(compressed);

    std.debug.print("Original size: {d} bytes, compressed framed size: {d} bytes\n", .{ source_text.len, compressed.len });

    var sd = snappy.StreamingDecompressor.init(allocator, .{});
    defer sd.deinit();

    // Feed in tiny 7-byte network packets
    var offset: usize = 0;
    var packet_count: usize = 0;

    var restored_buf: [256]u8 = undefined;
    var total_taken: usize = 0;

    while (offset < compressed.len) {
        const chunk_size = @min(7, compressed.len - offset);
        try sd.feed(compressed[offset .. offset + chunk_size]);
        offset += chunk_size;
        packet_count += 1;

        // Drain available uncompressed data
        while (true) {
            const n = try sd.take(restored_buf[total_taken..]);
            if (n == 0) break;
            total_taken += n;
        }
    }

    std.debug.print("Processed {d} fragmented packets.\n", .{packet_count});
    std.debug.print("Restored data ({d} bytes): \"{s}\"\n", .{ total_taken, restored_buf[0..total_taken] });
}
```

---

## Step-by-Step Code Walkthrough

1. **Test Payload Generation**:
   `snappy.compressFramed(allocator, source_text, .{})` creates a standard 104-byte framed Snappy stream.

2. **Decompressor Initialization**:
   `var sd = snappy.StreamingDecompressor.init(allocator, .{});` initializes internal input and output staging buffers. `defer sd.deinit();` ensures clean release of all allocated memory.

3. **Packet Chunking Simulation**:
   A loop feeds arbitrary slices of only 7 bytes (`@min(7, compressed.len - offset)`) to simulate fragmented TCP packets or socket buffer splits.

4. **Incremental Feeding (`sd.feed`)**:
   `try sd.feed(packet)` ingests the slice into the decompressor's internal buffer and advances the framing decoder. As soon as a chunk is completed, its contents are verified with CRC-32C and decompressed into the output buffer.

5. **Draining Output (`sd.take`)**:
   `sd.take(restored_buf[total_taken..])` copies available decompressed bytes into the caller's buffer slice, returning the number of bytes copied (or 0 when empty).

6. **Resetting**:
   To reuse the same decompressor instance for another stream without reallocating buffers, call `sd.reset()`.

---

## Explicit I/O & Stream Handling

| Method | Role | Data Flow |
|---|---|---|
| **`sd.feed(chunk)`** | Ingest incoming raw bytes | Copies input into internal staging buffer; parses framing chunks |
| **`sd.take(dest)`** | Drain uncompressed bytes | Copies out decoded plaintext into caller's slice |
| **`sd.reset()`** | Clear stream state | Clears internal indices while retaining memory allocations |

---

## Running the Example

Compile and run directly with the Zig build system:

```bash
zig build run-streaming_decompression
```

### Expected Output

```console
Original size: 86 bytes, compressed framed size: 104 bytes
Processed 15 fragmented packets.
Restored data (86 bytes): "Incremental chunked decompression in Zig 0.17.0 simulating fragmented network packets."
```
