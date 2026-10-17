---
title: StreamingCompressor API
description: Chunked push-based streaming compressor for incrementally building standard Snappy framed streams.
keywords: StreamingCompressor, push streaming zig, std.io.writer compression, chunked snappy, streaming compression
---

# `snappy.StreamingCompressor`

`StreamingCompressor` enables push-based, chunk-by-chunk compression where data arrives in arbitrary increments and is emitted directly into a `std.Io.Writer` as an official Snappy framed stream (`.sz`).

```zig
pub const StreamingCompressor = struct {
    allocator: std.mem.Allocator,
    options: CompressionOptions,
    buffer: std.ArrayList(u8),
    header_written: bool,
    // ...
};
```

---

## Methods

### `init`

```zig
pub fn init(allocator: std.mem.Allocator, options: CompressionOptions) Error!StreamingCompressor
```

Initializes the streaming compressor with the specified allocator and options.

---

### `deinit`

```zig
pub fn deinit(self: *StreamingCompressor) void
```

Releases all internal streaming buffers.

---

### `reset`

```zig
pub fn reset(self: *StreamingCompressor, new_options: CompressionOptions) void
```

Clears buffered data and resets header state and compression options without re-allocating.

---

### `write`

```zig
pub fn write(self: *StreamingCompressor, chunk: []const u8, writer: *std.Io.Writer) StreamError!void
```

Appends `chunk` to the compressor. On the first call, the 10-byte Snappy stream identifier (`0xff 0x06 0x00 0x00 sNaPpY`) is written to `writer`.

Whenever the accumulated buffer reaches `MAX_BLOCK_SIZE` (65,536 bytes), a full chunk is compressed (or emitted as uncompressed if incompressible) with its 4-byte masked CRC-32C checksum and written immediately to `writer`.

---

### `finish`

```zig
pub fn finish(self: *StreamingCompressor, writer: *std.Io.Writer) StreamError!void
```

Compresses and emits any remaining buffered bytes as the final chunk, and resets the internal buffer.

---

## Example Usage

```zig
const std = @import("std");
const snappy = @import("snappy");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var sc = try snappy.StreamingCompressor.init(allocator, .{ .level = 1 });
    defer sc.deinit();

    var out_storage: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&out_storage);

    // Push chunks incrementally as they arrive
    try sc.write("First payload chunk: headers and metadata\n", &writer);
    try sc.write("Second payload chunk: query results batch #1\n", &writer);
    try sc.write("Third payload chunk: query results batch #2\n", &writer);

    // Finalize the framed stream
    try sc.finish(&writer);

    const compressed_data = writer.buffered();
    std.debug.print("Completed framed stream: {d} bytes written\n", .{compressed_data.len});
}
```
