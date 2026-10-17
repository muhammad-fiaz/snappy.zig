---
title: File Compression Example
description: Compressing and decompressing disk files with snappy.zig and Zig 0.17 std.Io.
keywords: file compression example, compress_file, decompress_file, std.Io, disk files, snappy.sz
---

# File Compression Example

This guide explains how to compress and decompress on-disk files using `snappy.zig` and Zig 0.17.0's `std.Io` engine. Snappy compressed files conventionally use the `.sz` extension and strictly follow the official Google Snappy Framed Stream format.

---

## Snappy `.sz` File Format Architecture

When writing a compressed file to disk:
1. **File Header**: Every valid `.sz` file begins with the 10-byte sequence:
   ```
   [0xff, 0x06, 0x00, 0x00, 's', 'N', 'a', 'P', 'p', 'Y']
   ```
2. **Chunking**: Input data is split into blocks of at most 65,536 bytes (`snappy.MAX_BLOCK_SIZE`).
3. **Integrity Protection**: Each chunk is stamped with its Castagnoli CRC-32C checksum masked with:
   $$\text{MaskedCRC} = ((\text{CRC} \gg 15) \mid (\text{CRC} \ll 17)) + \text{0xa282ead8}$$
4. **Interoperability**: Any `.sz` file produced by `snappy.zig` can be decompressed by Google's C++ tool `snappy`, Linux command-line tools, Python `snappy`, or Go's `sz` package.

---

## Compressing a File (`examples/compress_file.zig`)

```zig
const std = @import("std");
const snappy = @import("snappy");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    const cwd = std.Io.Dir.cwd();

    const sample_file = "temp_example_input.txt";
    const comp_file = "temp_example_output.sz";
    defer {
        cwd.deleteFile(io, sample_file) catch {};
        cwd.deleteFile(io, comp_file) catch {};
    }

    // Create a sample text file
    const sample_content =
        "This is a demonstration of file compression using snappy.zig on Windows/Linux/macOS.\n" ++
        "Snappy prioritizes extreme compression and decompression throughput.\n" ++
        "Native Zig implementation with zero external dependencies and memory safety.\n";
    try cwd.writeFile(io, .{ .sub_path = sample_file, .data = sample_content });

    std.debug.print("Created sample input file '{s}' ({d} bytes)\n", .{ sample_file, sample_content.len });

    // Read and compress
    const in_data = try cwd.readFileAlloc(io, sample_file, allocator, @fromBackingInt(@intCast(10 * 1024 * 1024)));
    defer allocator.free(in_data);

    var reader = std.Io.Reader.fixed(in_data);
    var out_storage: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&out_storage);

    try snappy.compressStream(allocator, &reader, &writer, .{});

    const compressed_data = writer.buffered();
    try cwd.writeFile(io, .{ .sub_path = comp_file, .data = compressed_data });

    std.debug.print("Successfully compressed into '{s}' ({d} bytes)\n", .{ comp_file, compressed_data.len });
}
```

### Step-by-Step Breakdown (Compression)

1. **`std.Io.Threaded` Initialization**: Zig 0.17.0 unifies non-blocking and threaded filesystem operations under `std.Io`. `threaded.io()` provides the `io: std.Io` handle passed to all filesystem operations.
2. **File Creation**: `cwd.writeFile` creates the source file `temp_example_input.txt`.
3. **Data Ingestion**: `cwd.readFileAlloc` reads up to 10MB into memory.
4. **Stream Compression (`snappy.compressStream`)**: Reads through `std.Io.Reader.fixed`, writes the framed stream into `std.Io.Writer.fixed`, and handles chunk boundaries and CRC checksums.
5. **Disk Write**: The resulting framed `.sz` payload is persisted using `cwd.writeFile`.
6. **Cleanup**: Both temporary files are unlinked in the `defer` block.

---

## Decompressing a File (`examples/decompress_file.zig`)

```zig
const std = @import("std");
const snappy = @import("snappy");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    const cwd = std.Io.Dir.cwd();

    const comp_file = "temp_example_comp.sz";
    const decomp_file = "temp_example_restored.txt";
    defer {
        cwd.deleteFile(io, comp_file) catch {};
        cwd.deleteFile(io, decomp_file) catch {};
    }

    // 1. Create a compressed file
    const sample_data =
        "Demonstration of decompressing a Snappy framed .sz file from disk back to plain text.\n" ++
        "Snappy frames include stream identifiers, block tags, and CRC-32C data checksums.\n" ++
        "Native Zig 0.17.0 streaming I/O pipeline verified for roundtrip correctness.\n";
    const comp_bytes = try snappy.compress(allocator, sample_data);
    defer allocator.free(comp_bytes);

    try cwd.writeFile(io, .{ .sub_path = comp_file, .data = comp_bytes });
    std.debug.print("Wrote compressed file '{s}' ({d} bytes)\n", .{ comp_file, comp_bytes.len });

    // 2. Read compressed file from disk
    const read_comp = try cwd.readFileAlloc(io, comp_file, allocator, @fromBackingInt(@intCast(10 * 1024 * 1024)));
    defer allocator.free(read_comp);

    // 3. Decompress using streaming pipeline
    var reader = std.Io.Reader.fixed(read_comp);
    var out_storage: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&out_storage);

    try snappy.decompressStream(allocator, &reader, &writer, .{});
    const restored_bytes = writer.buffered();

    try cwd.writeFile(io, .{ .sub_path = decomp_file, .data = restored_bytes });
    std.debug.print("Successfully restored into '{s}' ({d} bytes)\n", .{ decomp_file, restored_bytes.len });
}
```

### Step-by-Step Breakdown (Decompression)

1. **File Reading**: `cwd.readFileAlloc` reads the `.sz` compressed file from disk.
2. **Stream Validation & Decoding**: `snappy.decompressStream` processes the stream byte-by-byte:
   - Validates the 10-byte `\xff\x06\x00\x00sNaPpY` header.
   - Computes CRC-32C on decoded payload and verifies against the chunk checksum.
   - Emits uncompressed plaintext to the writer.
3. **Restoration**: `cwd.writeFile` writes `temp_example_restored.txt` containing the restored content.

---

## One-Shot Disk File Helpers

`snappy.zig` also provides convenience functions to compress or decompress on-disk files in a single call:

```zig
// Compress directly from disk file to .sz file:
try snappy.compressFile(allocator, "data.csv", "data.csv.sz", .{});

// Decompress directly from .sz file to disk file:
try snappy.decompressFile(allocator, "data.csv.sz", "data.csv", .{});
```

These functions automatically initialize `std.Io.Threaded`, open streaming readers and writers, and flush all compressed/decompressed chunks to disk.

---

## Running the Examples

Compile and run with the Zig build system:

```bash
zig build run-compress_file
zig build run-decompress_file
```

### Expected Output

**`run-compress_file`**:
```console
Created sample input file 'temp_example_input.txt' (231 bytes)
Successfully compressed into 'temp_example_output.sz' (226 bytes)
```

**`run-decompress_file`**:
```console
Wrote compressed file 'temp_example_comp.sz' (258 bytes)
Successfully restored into 'temp_example_restored.txt' (245 bytes)
```
