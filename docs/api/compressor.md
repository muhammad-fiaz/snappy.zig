---
title: Compressor API
description: Reusable compression context struct for maintaining state, options, and scratch buffers across multiple operations.
keywords: snappy Compressor, reusable context zig, reset compressor, zero allocation loop
---

# `snappy.Compressor`

The `Compressor` struct maintains a persistent configuration, memory allocator, and pre-allocated scratch buffer. Reusing a `Compressor` instance avoids re-allocating working scratch buffers across multiple compression calls.

```zig
pub const Compressor = struct {
    allocator: std.mem.Allocator,
    options: CompressionOptions,
    scratch: []u8,
    // ...
};
```

---

## Methods

### `init`

```zig
pub fn init(allocator: std.mem.Allocator, options: CompressionOptions) Error!Compressor
```

Initializes a new `Compressor` instance with the specified allocator and compression options, pre-allocating internal scratch memory.

#### Parameters
- `allocator`: Memory allocator used for internal scratch buffers and allocated outputs.
- `options`: Configuration options (`blockMode`, etc.).

---

### `deinit`

```zig
pub fn deinit(self: *Compressor) void
```

Releases all internal scratch buffers owned by the compressor.

---

### `reset`

```zig
pub fn reset(self: *Compressor, new_options: CompressionOptions) void
```

Resets the compressor options without re-allocating scratch memory.

---

### `compress`

```zig
pub fn compress(self: *Compressor, input: []const u8) Error![]u8
```

Compresses `input` into a newly allocated slice according to `options.blockMode` (`.framed` or `.block`). The caller owns the returned slice and must free it using `self.allocator`.

#### Errors
- `error.OutOfMemory`: Failed to allocate output buffer.
- `error.InputTooLarge`: Input exceeds format limits.

---

### `compressInto`

```zig
pub fn compressInto(self: *Compressor, input: []const u8, output: []u8) Error!usize
```

Compresses `input` directly into the caller-provided `output` buffer without any heap allocations. Returns the number of compressed bytes written.

#### Errors
- `error.OutputBufferTooSmall`: Output buffer has insufficient capacity.

---

## Example Usage

```zig
const std = @import("std");
const snappy = @import("snappy");

pub fn processMessages(allocator: std.mem.Allocator, messages: [][]const u8) !void {
    var compressor = try snappy.Compressor.init(allocator, .{
        .blockMode = .framed,
    });
    defer compressor.deinit();

    for (messages) |msg| {
        const compressed = try compressor.compress(msg);
        defer allocator.free(compressed);

        // Process compressed message...
    }
}
```
