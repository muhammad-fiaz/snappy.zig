const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Core module export
    const snappy_mod = b.addModule("snappy", .{
        .root_source_file = b.path("src/snappy.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = false,
    });

    // Static library artifact
    const lib = b.addLibrary(.{
        .name = "snappy",
        .root_module = snappy_mod,
    });
    b.installArtifact(lib);

    // Main test suite
    const test_step = b.step("test", "Run all tests");
    const tests = b.addTest(.{
        .root_module = snappy_mod,
    });
    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);

    // Fuzz test suite
    const fuzz_mod = b.createModule(.{
        .root_source_file = b.path("src/fuzz.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = false,
        .imports = &.{
            .{ .name = "snappy", .module = snappy_mod },
        },
    });
    const fuzz_tests = b.addTest(.{
        .root_module = fuzz_mod,
    });
    const run_fuzz = b.addRunArtifact(fuzz_tests);
    const fuzz_step = b.step("fuzz", "Run the decoder robustness fuzzer");
    fuzz_step.dependOn(&run_fuzz.step);

    // Documentation generation step (`zig build docs`)
    const docs_step = b.step("docs", "Generate documentation");
    const docs = b.addTest(.{
        .root_module = snappy_mod,
    });
    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    docs_step.dependOn(&install_docs.step);

    // Registered standalone examples
    const examples = [_]struct { name: []const u8, file: []const u8 }{
        .{ .name = "basic_compression", .file = "examples/basic_compression.zig" },
        .{ .name = "caller_buffer", .file = "examples/caller_buffer.zig" },
        .{ .name = "reusable_context", .file = "examples/reusable_context.zig" },
        .{ .name = "streaming_compression", .file = "examples/streaming_compression.zig" },
        .{ .name = "streaming_decompression", .file = "examples/streaming_decompression.zig" },
        .{ .name = "io_pipeline", .file = "examples/io_pipeline.zig" },
        .{ .name = "error_handling", .file = "examples/error_handling.zig" },
        .{ .name = "format_introspection", .file = "examples/format_introspection.zig" },
        .{ .name = "bit_level", .file = "examples/bit_level.zig" },
        .{ .name = "compress_file", .file = "examples/compress_file.zig" },
        .{ .name = "decompress_file", .file = "examples/decompress_file.zig" },
    };

    const run_all = b.step("run-all-examples", "Run all examples");
    const check_step = b.step("check", "Check compilation of library, tests, and examples");
    check_step.dependOn(&lib.step);
    check_step.dependOn(&tests.step);
    check_step.dependOn(&fuzz_tests.step);

    inline for (examples) |example| {
        const run_step = b.step(
            "run-" ++ example.name,
            "Run " ++ example.name ++ " example",
        );

        const exe = b.addExecutable(.{
            .name = "example-" ++ example.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(example.file),
                .target = target,
                .optimize = optimize,
                .link_libc = false,
                .imports = &.{
                    .{ .name = "snappy", .module = snappy_mod },
                },
            }),
        });

        check_step.dependOn(&exe.step);
        const run_exe = b.addRunArtifact(exe);
        run_step.dependOn(&run_exe.step);
        run_all.dependOn(&run_exe.step);
        run_exe.step.dependOn(&lib.step);
    }
}
