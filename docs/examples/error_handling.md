---
title: Error Handling Example
description: Defensive handling of invalid headers, checksum mismatches, decompression bombs, and truncated blocks with snappy.zig.
keywords: error handling example, corrupted stream, checksum mismatch, maxOutputSize, truncated block, zig 0.17.0
---

# Error Handling Example

Snappy is widely used in multi-tenant RPC servers, storage layers, and network services where incoming payloads may be corrupt, truncated, or adversarially crafted. `snappy.zig` is engineered with defensive programming principles: all decoders reject malformed inputs deterministically without panicking, crashing, or leaking memory.

---

## Snappy Format Security & Error Taxonomy

| Error Code | Format Condition Triggered | Defensive Guarantee |
|---|---|---|
| **`error.CorruptStream`** | Stream does not start with `\xff\x06\x00\x00sNaPpY`, or contains an unrecognized reserved chunk ID in range `[0x80, 0xfd]`. | Rejects non-Snappy files immediately before allocation. |
| **`error.ChecksumMismatch`** | Unmasked CRC-32C of chunk payload does not match the 4-byte chunk header checksum. | Prevents silent data corruption from disk or network bit flips. |
| **`error.ResourceLimitExceeded`** | Claimed uncompressed size exceeds user-configured `maxOutputSize` (decompression bomb protection). | Mitigates Denial-of-Service (DoS) memory exhaustion attacks. |
| **`error.TruncatedInput`** | Block terminates mid-stream before literal bytes, copy offsets, or chunk payload finishes. | Prevents buffer out-of-bounds reads. |
| **`error.InvalidVarint`** | Varint header exceeds 5 bytes or overflows 32-bit integer range. | Protects integer overflow invariants. |
| **`error.InvalidCopyOffset`** | LZ77 copy offset is 0 or points before the beginning of the decoded output buffer. | Eliminates out-of-bounds pointer dereferences. |
| **`error.OutputBufferTooSmall`** | Pre-allocated caller destination buffer is too small to receive output. | Guarantees zero buffer overflow in caller memory. |

---

## Complete Source Code (`examples/error_handling.zig`)

```zig
const std = @import("std");
const snappy = @import("snappy");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("=== Snappy Error Diagnostics and Security Checks ===\n\n", .{});

    // 1. Invalid magic header test
    const bad_magic = "NOT_SNAPPY_STREAM_HEADER";
    if (snappy.decompress(allocator, bad_magic)) |_| {
        std.debug.print("Unexpected success on bad magic!\n", .{});
    } else |err| {
        std.debug.print("Expected error caught on invalid stream header: {}\n", .{err});
    }

    // 2. Corrupted checksum test
    const valid_comp = try snappy.compress(allocator, "Data protected with CRC-32C checksum");
    defer allocator.free(valid_comp);

    var corrupted = try allocator.alloc(u8, valid_comp.len);
    defer allocator.free(corrupted);
    @memcpy(corrupted, valid_comp);
    corrupted[corrupted.len - 1] ^= 0xff; // Corrupt payload byte

    if (snappy.decompress(allocator, corrupted)) |_| {
        std.debug.print("Unexpected success on corrupted payload!\n", .{});
    } else |err| {
        std.debug.print("Expected error caught on checksum tampering: {}\n", .{err});
    }

    // 3. Decompression bomb protection via maxOutputSize
    const repetitive = try allocator.alloc(u8, 50_000);
    defer allocator.free(repetitive);
    @memset(repetitive, 'Z');

    const compressed_rep = try snappy.compress(allocator, repetitive);
    defer allocator.free(compressed_rep);

    std.debug.print("Compressed 50,000 bytes into {d} bytes.\n", .{compressed_rep.len});

    // Limit output to at most 1024 bytes
    if (snappy.decompressWithOptions(allocator, compressed_rep, .{ .maxOutputSize = 1024 })) |_| {
        std.debug.print("Unexpected success exceeding resource limit!\n", .{});
    } else |err| {
        std.debug.print("Expected error caught on decompression bomb protection: {}\n", .{err});
    }

    // 4. Truncated block test
    const truncated_block = [_]u8{ 0x80, 0x01 }; // Varint 128, but 0 payload bytes follow
    if (snappy.decompressBlock(allocator, &truncated_block, .{})) |_| {
        std.debug.print("Unexpected success on truncated block!\n", .{});
    } else |err| {
        std.debug.print("Expected error caught on truncated block: {}\n", .{err});
    }
}
```

---

## Step-by-Step Code Walkthrough

1. **Invalid Stream Magic Check**:
   Supplying an invalid byte sequence causes `snappy.decompress` to reject the buffer immediately, returning `error.CorruptStream` without allocating payload buffers.
2. **Checksum Integrity Enforcement**:
   Flipping a single payload bit in a valid compressed stream causes the recalculation of the Castagnoli CRC-32C to fail, triggering `error.ChecksumMismatch`.
3. **Decompression Bomb Protection**:
   A 50,000-byte run of `'Z'` compresses down to just 25,029 bytes. By passing `.{ .maxOutputSize = 1024 }` to `decompressWithOptions`, the decompressor aborts with `error.ResourceLimitExceeded` as soon as the declared uncompressed size exceeds 1,024 bytes.
4. **Truncated Block Handling**:
   The varint `[0x80, 0x01]` announces 128 bytes of uncompressed data, but no data follows. The block decoder detects the incomplete input and cleanly returns `error.TruncatedInput`.

---

## Running the Example

Compile and run directly with the Zig build system:

```bash
zig build run-error_handling
```

### Expected Output

```console
=== Snappy Error Diagnostics and Security Checks ===

Expected error caught on invalid stream header: error.CorruptStream
Expected error caught on checksum tampering: error.ChecksumMismatch
Compressed 50,000 bytes into 25029 bytes.
Expected error caught on decompression bomb protection: error.ResourceLimitExceeded
Expected error caught on truncated block: error.TruncatedInput
```
