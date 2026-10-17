---
title: StreamingDecompressor API
description: Chunked pull-based streaming decompressor for consuming incoming compressed fragments.
keywords: StreamingDecompressor, pull decompression zig, feed take streaming, chunked decompressor, stream reading
---

# `snappy.StreamingDecompressor`

`StreamingDecompressor` enables pull-based, chunk-by-chunk decompression of Snappy framed streams (`.sz`). Compressed byte slices are fed as they arrive from a socket, pipe, or file, and decompressed bytes are drained into caller-provided buffers.

```zig
pub const StreamingDecompressor = struct {
    allocator: std.mem.Allocator,
    options: DecompressionOptions,
    in_buffer: std.ArrayListUnmanaged(u8),
    out_buffer: std.ArrayListUnmanaged(u8),
    header_verified: bool,
    // ...
};
```

---

## Methods

### `init`

```zig
pub fn init(allocator: std.mem.Allocator, options: DecompressionOptions) StreamingDecompressor
```

Initializes an incremental decompressor with the specified options.

---

### `deinit`

```zig
pub fn deinit(self: *StreamingDecompressor) void
```

Frees internal accumulation buffers.

---

### `reset`

```zig
pub fn reset(self: *StreamingDecompressor, new_options: DecompressionOptions) void
```

Clears buffers and resets state for decoding a new stream while retaining allocated capacity.

---

### `feed`

```zig
pub fn feed(self: *StreamingDecompressor, chunk: []const u8) Error!void
```

Appends `chunk` of compressed data to the internal input buffer, and processes any complete chunks present.

---

### `take`

```zig
pub fn take(self: *StreamingDecompressor, dst: []u8) Error!usize
```

Extracts available uncompressed bytes into `dst`. Returns the number of bytes written. If more decompressed data is available than can fit in `dst`, subsequent calls to `take` will continue draining the buffer until it returns `0`.

---

### `isFinished`

```zig
pub fn isFinished(self: *const StreamingDecompressor) bool
```

Returns `true` when all input chunks have been completely decoded and all uncompressed data has been drained via `take`.

---

## Example Usage

```zig
const std = @import("std");
const snappy = @import("snappy");

pub fn processStream(allocator: std.mem.Allocator, chunks: [][]const u8) !void {
    var decompressor = snappy.StreamingDecompressor.init(allocator, .{
        .verifyChecksums = true,
    });
    defer decompressor.deinit();

    var output_buf: [4096]u8 = undefined;

    for (chunks) |chunk| {
        try decompressor.feed(chunk);

        while (true) {
            const count = try decompressor.take(&output_buf);
            if (count == 0) break;

            // Handle uncompressed bytes in output_buf[0..count]
            _ = count;
        }
    }
}
```
