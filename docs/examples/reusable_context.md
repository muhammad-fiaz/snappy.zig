---
title: Reusable Context Example
description: Amortizing allocation overhead across high-throughput loops using snappy.Compressor and snappy.Decompressor.
keywords: reusable context example, Compressor.init, Decompressor.init, reset, zero heap churn, zig 0.17.0
---

# Reusable Context Example

When compressing or decompressing thousands of messages per second in an RPC service, high-performance messaging pipeline, or database engine, repeatedly allocating and deallocating internal hash tables (16,384 entry LZ77 match tables) causes heap churn and cache misses.

`snappy.Compressor` and `snappy.Decompressor` retain their working structures across calls, amortizing memory overhead down to near zero.

---

## Format Modes Supported

A reusable context can seamlessly switch between formats via `.reset()`:

1. **`.framed` Mode (Default)**:
   - Encapsulates every message in a standard Snappy framed stream (`.sz`).
   - Writes the 10-byte stream magic `\xff\x06\x00\x00sNaPpY` and masked Castagnoli CRC-32C checksums.
2. **`.block` Mode**:
   - Emits raw Snappy blocks beginning with a varint payload length.
   - Ideal for internal IPC protocols, database storage engines (e.g. RocksDB, Cassandra, Bigtable), and RPC envelopes where outer transport framing already handles framing and checksumming.

---

## Complete Source Code (`examples/reusable_context.zig`)

```zig
const std = @import("std");
const snappy = @import("snappy");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Initialize reusable contexts once
    var compressor = try snappy.Compressor.init(allocator, .{ .blockMode = .framed, .level = 1 });
    defer compressor.deinit();

    var decompressor = snappy.Decompressor.init(allocator, .{});
    defer decompressor.deinit();

    const messages = [_][]const u8{
        "Transaction #1: User authenticated successfully",
        "Transaction #2: Payment processed for order #98214",
        "Transaction #3: Shipping notification dispatched via webhook",
    };

    for (messages, 0..) |msg, i| {
        // Compress using existing context
        const comp = try compressor.compress(msg);
        defer allocator.free(comp);

        // Decompress using existing context
        const decomp = try decompressor.decompress(comp);
        defer allocator.free(decomp);

        std.debug.print("Message {d} ({d} bytes -> {d} bytes): \"{s}\"\n", .{
            i + 1, msg.len, comp.len, decomp,
        });
    }

    // Reset options dynamically without reallocating buffers
    compressor.reset(.{ .blockMode = .block, .level = 2 });
    decompressor.reset(.{});

    const block_msg = "Level 2 raw block stream without framing header";
    const comp_block = try compressor.compress(block_msg);
    defer allocator.free(comp_block);

    const decomp_block = try decompressor.decompress(comp_block);
    defer allocator.free(decomp_block);

    std.debug.print("Raw block roundtrip: \"{s}\"\n", .{decomp_block});
}
```

---

## Step-by-Step Code Walkthrough

1. **Context Creation**:
   `var compressor = try snappy.Compressor.init(allocator, .{ .blockMode = .framed, .level = 1 });` pre-allocates the LZ77 hash table and scratch working buffers. `snappy.Decompressor.init(allocator, .{})` prepares the decompressor.
2. **Message Compression Loop**:
   For each transaction message, `compressor.compress(msg)` runs the compression using pre-allocated state without reallocating scratch tables.
3. **Decompression & Verification**:
   `decompressor.decompress(comp)` detects the framed stream, verifies CRC-32C, and returns the restored slice.
4. **Zero-Reallocation Mode Switch (`.reset`)**:
   `compressor.reset(.{ .blockMode = .block, .level = 2 })` switches compression mode from `.framed` to raw `.block` and selects match Level 2 (2-table matching) with **zero** memory reallocations.
5. **Raw Block Roundtrip**:
   `compressor.compress(block_msg)` outputs a raw Snappy block, verified by `decompressor.decompress(comp_block)`.
6. **Destruction (`deinit`)**:
   `compressor.deinit()` and `decompressor.deinit()` free internal resources when the application terminates.

---

## Explicit Memory Lifecycle & Reuse

| API | Allocation | Heap Reallocation |
|---|---|---|
| **`Compressor.init`** | Allocates match tables and scratch buffers | Once at initialization |
| **`compressor.compress`** | Allocates only the output slice | **Zero** scratch buffer allocation |
| **`compressor.compressInto`** | Uses caller slice | **Zero** heap allocations |
| **`compressor.reset`** | Clears indices and updates options | **Zero** allocations |
| **`Compressor.deinit`** | Frees match tables | Destructor |

---

## Running the Example

Compile and run directly with the Zig build system:

```bash
zig build run-reusable_context
```

### Expected Output

```console
Message 1 (47 bytes -> 65 bytes): "Transaction #1: User authenticated successfully"
Message 2 (50 bytes -> 68 bytes): "Transaction #2: Payment processed for order #98214"
Message 3 (60 bytes -> 78 bytes): "Transaction #3: Shipping notification dispatched via webhook"
Raw block roundtrip: "Level 2 raw block stream without framing header"
```
