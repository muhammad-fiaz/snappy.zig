---
title: Decompression Guide
description: Decompressing framed streams, raw blocks, enforcing security limits, and format introspection with snappy.zig.
keywords: snappy decompression guide, safe decompression zig, maxOutputSize, checksum verification, decompressInto, snappy varint
---

# Decompression Guide

`snappy.zig` provides safe, high-speed decompression with automatic format detection, CRC-32C checksum validation, and defensive protection against malformed or malicious inputs.

---

## Automatic Format Detection

The high-level `snappy.decompress` and `snappy.decompressWithOptions` functions automatically inspect the input header:
- If the first 10 bytes match `0xff 0x06 0x00 0x00 sNaPpY` (`STREAM_IDENTIFIER`), the input is decoded as an official **Snappy Framed Stream**.
- Otherwise, the input is decoded as a **Raw Snappy Block** by parsing its varint length prefix.

```zig
const std = @import("std");
const snappy = @import("snappy");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Decompress any valid Snappy data (framed stream or raw block)
    const decompressed = try snappy.decompress(allocator, compressed_data);
    defer allocator.free(decompressed);

    std.debug.print("Decompressed size: {d} bytes\n", .{decompressed.len});
}
```

---

## Decompression Security & Resource Limits

Untrusted data from network sockets or untrusted files can present denial-of-service risks (e.g. decompression bombs with oversized length headers).

To guard against memory exhaustion, specify `maxOutputSize`:

```zig
const opts: snappy.DecompressionOptions = .{
    .maxOutputSize = 10 * 1024 * 1024, // Enforce a 10 MiB limit
    .verifyChecksums = true,
};

const safe_decompressed = try snappy.decompressWithOptions(allocator, untrusted_data, opts);
defer allocator.free(safe_decompressed);
```

If the uncompressed content exceeds `maxOutputSize`, decompression safely terminates with `error.ResourceLimitExceeded` without overflowing memory.

---

## Zero-Allocation Caller Buffer

To decompress into a pre-allocated slice without any heap allocation:

```zig
var out_buf: [4096]u8 = undefined;

const decoded_len = try snappy.decompressInto(compressed_slice, &out_buf);
const result = out_buf[0..decoded_len];
```

---

## Format Introspection

You can inspect compressed data before allocating buffers:

```zig
// Read the uncompressed length from a raw block varint prefix
const expected_len = try snappy.uncompressedLength(raw_block_slice);
std.debug.print("Expected uncompressed length: {d} bytes\n", .{expected_len});

// Verify whether the buffer starts with a valid varint prefix
if (snappy.isValidCompressedBuffer(raw_block_slice)) {
    std.debug.print("Valid Snappy block header\n", .{});
}
```

---

## Error Handling

All decoders in `snappy.zig` strictly validate slice boundaries, varints, element tags, and backreference offsets, returning structured errors from the canonical error set:

```zig
const data = snappy.decompress(allocator, untrusted_slice) catch |err| switch (err) {
    error.CorruptStream, error.InvalidVarint, error.InvalidCopyOffset => {
        std.debug.print("Invalid or corrupt Snappy sequence\n", .{});
        return;
    },
    error.TruncatedInput => {
        std.debug.print("Incomplete or truncated Snappy payload\n", .{});
        return;
    },
    error.ChecksumMismatch => {
        std.debug.print("CRC-32C checksum mismatch detected!\n", .{});
        return;
    },
    error.ResourceLimitExceeded => {
        std.debug.print("Decompressed size exceeded max safety limits\n", .{});
        return;
    },
    error.OutputBufferTooSmall => {
        std.debug.print("Destination buffer has insufficient capacity\n", .{});
        return;
    },
    error.OutOfMemory => return err,
    else => return err,
};
defer allocator.free(data);
```
