---
title: Error Taxonomy & Handling API
description: Comprehensive error set, error codes, and safe error-handling patterns in snappy.zig.
keywords: snappy errors zig, Error, StreamError, ChecksumMismatch, CorruptStream, error handling, robust zig
---

# Errors

`snappy.zig` returns typed, structured errors from the canonical error sets:

```zig
pub const Error = error{
    CorruptStream,
    TruncatedInput,
    OutputBufferTooSmall,
    ResourceLimitExceeded,
    InvalidChunkLength,
    UnknownChunkType,
    ChecksumMismatch,
    InvalidMagic,
    InvalidVarint,
    OutOfMemory,
    InputTooLarge,
};

pub const StreamError = Error || std.Io.Writer.Error || std.Io.Reader.Error;
```

---

## Error Descriptions

| Error | Description |
| :--- | :--- |
| `CorruptStream` | Input data is malformed or violates the Snappy format specification (e.g. invalid tag or illegal copy offset). |
| `TruncatedInput` | Input data ended prematurely before all expected bytes or instructions were read. |
| `OutputBufferTooSmall` | Caller-provided output buffer has insufficient capacity. |
| `ResourceLimitExceeded` | Decompressed content exceeds caller-configured `maxOutputSize` limit (decompression bomb protection). |
| `InvalidChunkLength` | Chunk length in framed stream exceeds 65,536 bytes or is less than header minimums. |
| `UnknownChunkType` | Unrecognized unskippable chunk type (`0x02`..`0x7f`) encountered in framed stream. |
| `ChecksumMismatch` | 32-bit masked CRC-32C checksum does not match decoded chunk data. |
| `InvalidMagic` | Stream does not start with the mandatory Snappy stream identifier (`0xff 0x06 0x00 0x00 sNaPpY`). |
| `InvalidVarint` | Little-endian varint encoding is unterminated or overflows 32 bits. |
| `OutOfMemory` | System allocator failed to allocate memory. |
| `InputTooLarge` | Input size exceeds format limits ($2^{32} - 1$ bytes). |

---

## Idiomatic Error Handling Pattern

```zig
const std = @import("std");
const snappy = @import("snappy");

pub fn processInput(allocator: std.mem.Allocator, data: []const u8) !void {
    const uncompressed = snappy.decompress(allocator, data) catch |err| switch (err) {
        error.InvalidMagic => {
            std.debug.print("Not a valid Snappy framed stream\n", .{});
            return;
        },
        error.ChecksumMismatch => {
            std.debug.print("Data integrity check failed: corrupt payload\n", .{});
            return;
        },
        error.CorruptStream, error.TruncatedInput, error.InvalidVarint => {
            std.debug.print("Malformed Snappy data\n", .{});
            return;
        },
        error.ResourceLimitExceeded => {
            std.debug.print("Decompressed payload exceeded safety limit\n", .{});
            return;
        },
        error.OutOfMemory => return err,
        else => {
            std.debug.print("Decompression error: {}\n", .{err});
            return err;
        },
    };
    defer allocator.free(uncompressed);
}
```
