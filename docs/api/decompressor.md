---
title: Decompressor API
description: Reusable decompression context struct for maintaining state, options, and security limits across multiple operations.
keywords: snappy Decompressor, reusable context zig, reset decompressor, maxOutputSize
---

# `snappy.Decompressor`

The `Decompressor` struct maintains a persistent configuration, memory allocator, and security settings across multiple decompression operations.

```zig
pub const Decompressor = struct {
    allocator: std.mem.Allocator,
    options: DecompressionOptions,
    // ...
};
```

---

## Methods

### `init`

```zig
pub fn init(allocator: std.mem.Allocator, options: DecompressionOptions) Decompressor
```

Initializes a new `Decompressor` instance with the specified allocator and decompression options.

#### Parameters
- `allocator`: Memory allocator used for dynamically allocated outputs.
- `options`: Security options such as `maxOutputSize` and `verifyChecksums`.

---

### `deinit`

```zig
pub fn deinit(self: *Decompressor) void
```

Releases any resources held by the decompressor.

---

### `reset`

```zig
pub fn reset(self: *Decompressor, new_options: DecompressionOptions) void
```

Updates the decompressor options without re-allocating.

---

### `decompress`

```zig
pub fn decompress(self: *Decompressor, input: []const u8) Error![]u8
```

Decompresses `input` into an allocated slice. Auto-detects whether `input` is a Snappy framed stream or a raw block. The caller owns the returned slice and must free it using `self.allocator`.

#### Errors
- `error.OutOfMemory`: Failed to allocate output buffer.
- `error.ResourceLimitExceeded`: Decompressed payload exceeds `options.maxOutputSize`.
- `error.ChecksumMismatch`: CRC-32C checksum verification failed.
- `error.CorruptStream`: Malformed or corrupt Snappy stream.

---

### `decompressInto`

```zig
pub fn decompressInto(self: *Decompressor, input: []const u8, output: []u8) Error!usize
```

Decompresses `input` directly into the caller-provided `output` buffer without heap allocations.

#### Errors
- `error.OutputBufferTooSmall`: Output buffer has insufficient capacity.
- `error.ChecksumMismatch`: CRC-32C checksum verification failed.
- `error.CorruptStream`: Malformed or corrupt Snappy stream.

---

## Example Usage

```zig
const std = @import("std");
const snappy = @import("snappy");

pub fn processIncoming(allocator: std.mem.Allocator, packets: [][]const u8) !void {
    var decompressor = snappy.Decompressor.init(allocator, .{
        .maxOutputSize = 1024 * 1024,
        .verifyChecksums = true,
    });
    defer decompressor.deinit();

    var buffer: [8192]u8 = undefined;

    for (packets) |pkt| {
        const len = try decompressor.decompressInto(pkt, &buffer);
        // Process buffer[0..len]...
        _ = len;
    }
}
```
