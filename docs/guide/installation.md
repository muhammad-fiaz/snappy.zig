---
title: Installation & Setup
description: How to add and integrate snappy.zig in your Zig projects using the Zig 0.17.0 build system.
keywords: install snappy zig, build.zig.zon snappy, zig package manager, zig 0.17.0 dependencies, fetch snappy
---

# Installation & Setup

`snappy.zig` is packaged using the standard Zig package manager and targets **Zig 0.17.0**. It has zero external dependencies, requires no C compiler or `@cImport`, and builds cleanly across all major platforms.

Repository: [https://github.com/muhammad-fiaz/snappy.zig](https://github.com/muhammad-fiaz/snappy.zig)

---

## Prerequisites

- **Zig Compiler**: Version **0.17.0** or compatible.
  - Verify your installed toolchain: `zig version`
  - Download official prebuilt binaries from [ziglang.org/download](https://ziglang.org/download/).

---

## Adding to `build.zig.zon`

Add `snappy.zig` to your project's `build.zig.zon` using `zig fetch`.

### Option 1: Stable Release

To install the verified stable release archive:

```bash
zig fetch --save https://github.com/muhammad-fiaz/snappy.zig/archive/refs/tags/0.0.1.tar.gz
```

Your `build.zig.zon` will be updated with:

```zig
.{
    .name = .my_project,
    .version = "0.1.0",
    .fingerprint = 0x1234567890abcdef,
    .dependencies = .{
        .snappy = .{
            .url = "https://github.com/muhammad-fiaz/snappy.zig/archive/refs/tags/0.0.1.tar.gz",
            .hash = "snappy-0.0.1-...",
        },
    },
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
    },
}
```

### Option 2: Latest / Nightly URL

To follow the latest changes on the `main` branch:

```bash
zig fetch --save git+https://github.com/muhammad-fiaz/snappy.zig.git
```

This generates:

```zig
.{
    .name = .my_project,
    .version = "0.1.0",
    .fingerprint = 0x1234567890abcdef,
    .dependencies = .{
        .snappy = .{
            .url = "git+https://github.com/muhammad-fiaz/snappy.zig.git",
            .hash = "snappy-...",
        },
    },
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
    },
}
```

---

## Configuring `build.zig`

Import the `snappy` dependency in your project's `build.zig` and attach it to your executable, library, or test target:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 1. Resolve the snappy package dependency
    const snappy_dep = b.dependency("snappy", .{
        .target = target,
        .optimize = optimize,
    });
    const snappy_mod = snappy_dep.module("snappy");

    // 2. Attach to your application executable
    const exe = b.addExecutable(.{
        .name = "my-app",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "snappy", .module = snappy_mod },
            },
        }),
    });

    b.installArtifact(exe);

    // 3. Alternatively, attach via root_module helper
    // exe.root_module.addImport("snappy", snappy_mod);
}
```

---

## Importing in Code

In your source code (`src/main.zig`), import the library directly:

```zig
const std = @import("std");
const snappy = @import("snappy");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const original = "Hello from snappy.zig on Zig 0.17.0!";

    const comp = try snappy.compress(allocator, original);
    defer allocator.free(comp);

    std.debug.print("Compressed to {d} bytes (bound: {d})\n", .{
        comp.len,
        snappy.maxCompressedSize(original.len),
    });

    const decomp = try snappy.decompress(allocator, comp);
    defer allocator.free(decomp);

    std.debug.print("Restored: {s}\n", .{decomp});
}
```

---

## Cross-Compilation

Because `snappy.zig` is implemented entirely in pure native Zig with no C dependencies or host-specific assumptions, cross-compilation requires no external sysroots:

```bash
# Build for 64-bit Linux ARM64
zig build -Dtarget=aarch64-linux

# Build for 64-bit Windows x86_64
zig build -Dtarget=x86_64-windows

# Build for macOS Apple Silicon
zig build -Dtarget=aarch64-macos

# Build for 32-bit Linux x86
zig build -Dtarget=x86-linux

# Build for 32-bit Windows x86
zig build -Dtarget=x86-windows

# Build for RISC-V 64 Linux
zig build -Dtarget=riscv64-linux
```
