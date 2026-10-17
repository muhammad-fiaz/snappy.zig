const std = @import("std");
const types = @import("types.zig");
const varint = @import("varint.zig");

/// Implements the Snappy block format defined by Google's Snappy format specification.
pub const MAX_HASH_TABLE_BITS = 15;
pub const MAX_HASH_TABLE_SIZE = 1 << MAX_HASH_TABLE_BITS; // 32768 entries (64 KB)
pub const MIN_HASH_TABLE_BITS = 8;
pub const MIN_HASH_TABLE_SIZE = 1 << MIN_HASH_TABLE_BITS; // 256 entries

// Backward compatibility aliases
pub const HASH_TABLE_BITS = MAX_HASH_TABLE_BITS;
pub const HASH_TABLE_SIZE = MAX_HASH_TABLE_SIZE;

/// Calculates the upper bound of compressed bytes for an input of length `source_bytes`.
/// Formula: 32 + source_bytes + source_bytes / 6.
pub fn maxCompressedSize(source_bytes: usize) usize {
    if (source_bytes > (std.math.maxInt(usize) - 32) / 7 * 6) {
        return std.math.maxInt(usize);
    }
    return 32 + source_bytes + source_bytes / 6;
}

/// Dynamically computes the hash table size for a fragment, matching Google Snappy's CalculateTableSize.
pub fn calculateTableSize(input_size: usize) usize {
    if (input_size > MAX_HASH_TABLE_SIZE) return MAX_HASH_TABLE_SIZE;
    if (input_size < MIN_HASH_TABLE_SIZE) return MIN_HASH_TABLE_SIZE;
    return std.math.ceilPowerOfTwo(usize, input_size) catch MAX_HASH_TABLE_SIZE;
}

/// Inspects the uncompressed length of a Snappy block without decompressing it.
pub fn uncompressedLength(compressed: []const u8) types.Error!usize {
    const res = try varint.decode(compressed);
    return res.value;
}

/// Checks if a buffer represents a syntactically valid Snappy compressed block.
pub fn isValidCompressedBuffer(compressed: []const u8) bool {
    const dec_var = varint.decode(compressed) catch return false;
    const expected_len: usize = dec_var.value;
    var in_pos: usize = dec_var.bytes_read;
    var out_produced: usize = 0;

    while (out_produced < expected_len) {
        if (in_pos >= compressed.len) return false;
        const tag = compressed[in_pos];
        in_pos += 1;

        const tag_type = tag & 0x03;
        switch (tag_type) {
            types.TAG_LITERAL => {
                const len_tag = tag >> 2;
                var lit_len: usize = 0;
                if (len_tag < 60) {
                    lit_len = len_tag + 1;
                } else {
                    const extra_bytes: usize = (len_tag - 59);
                    if (in_pos + extra_bytes > compressed.len) return false;
                    var extra_len: u64 = 0;
                    for (0..extra_bytes) |b_idx| {
                        extra_len |= @as(u64, compressed[in_pos + b_idx]) << @as(u6, @intCast(b_idx * 8));
                    }
                    in_pos += extra_bytes;
                    const total_len = extra_len + 1;
                    if (total_len > @as(u64, expected_len - out_produced)) return false;
                    lit_len = @as(usize, @intCast(total_len));
                }

                if (lit_len > expected_len - out_produced) return false;
                if (lit_len > compressed.len - in_pos) return false;
                out_produced += lit_len;
                in_pos += lit_len;
            },
            types.TAG_COPY_1 => {
                const copy_len = @as(usize, (tag >> 2) & 7) + 4;
                if (in_pos >= compressed.len) return false;
                const offset = (@as(usize, (tag >> 5) & 7) << 8) | compressed[in_pos];
                in_pos += 1;

                if (offset == 0 or offset > out_produced) return false;
                if (copy_len > expected_len - out_produced) return false;
                out_produced += copy_len;
            },
            types.TAG_COPY_2 => {
                const copy_len = @as(usize, tag >> 2) + 1;
                if (in_pos + 2 > compressed.len) return false;
                const offset = std.mem.readInt(u16, compressed[in_pos..][0..2], .little);
                in_pos += 2;

                if (offset == 0 or offset > out_produced) return false;
                if (copy_len > expected_len - out_produced) return false;
                out_produced += copy_len;
            },
            types.TAG_COPY_4 => {
                const copy_len = @as(usize, tag >> 2) + 1;
                if (in_pos + 4 > compressed.len) return false;
                const offset = std.mem.readInt(u32, compressed[in_pos..][0..4], .little);
                in_pos += 4;

                if (offset == 0 or offset > out_produced) return false;
                if (copy_len > expected_len - out_produced) return false;
                out_produced += copy_len;
            },
            else => return false,
        }
    }

    return (out_produced == expected_len and in_pos == compressed.len);
}

/// Helper for copying backreferences with support for run-length encoding (overlapping copies).
inline fn copyMatch(dst: []u8, out_pos: usize, offset: usize, len: usize) void {
    const src_pos = out_pos - offset;
    if (offset >= 8 and len <= offset) {
        @memcpy(dst[out_pos .. out_pos + len], dst[src_pos .. src_pos + len]);
    } else if (offset == 1) {
        @memset(dst[out_pos .. out_pos + len], dst[src_pos]);
    } else {
        var i: usize = 0;
        while (i < len) : (i += 1) {
            dst[out_pos + i] = dst[src_pos + i];
        }
    }
}

inline fn tableEntryL1(table: []u16, bytes: u32, mask: usize) *u16 {
    const kMagic: u32 = 0x1e35a7bd;
    const hash: u32 = (kMagic *% bytes) >> (31 - MAX_HASH_TABLE_BITS);
    const idx = (hash >> 1) & mask;
    return &table[idx];
}

inline fn tableEntry4Byte(table: []u16, bytes: u32, mask: usize) *u16 {
    const kMagic: u32 = 2654435761;
    const hash: u32 = (kMagic *% bytes) >> (32 - MAX_HASH_TABLE_BITS);
    const idx = (hash >> 1) & mask;
    return &table[idx];
}

inline fn tableEntry8Byte(table: []u16, bytes: u64, mask: usize) *u16 {
    const kMagic: u64 = 58295818150454627;
    const hash: u32 = @truncate((kMagic *% bytes) >> (64 - MAX_HASH_TABLE_BITS));
    const idx = (hash >> 1) & mask;
    return &table[idx];
}

/// Emits literal bytes according to the official Google Snappy specification.
inline fn emitLiteral(literal: []const u8, out: []u8) usize {
    const len = literal.len;
    if (len == 0) return 0;
    const n = len - 1;
    var op: usize = 0;

    if (n < 60) {
        out[op] = types.TAG_LITERAL | (@as(u8, @truncate(n)) << 2);
        op += 1;
    } else if (n < 256) {
        out[op] = types.TAG_LITERAL | (60 << 2);
        out[op + 1] = @as(u8, @truncate(n));
        op += 2;
    } else if (n < 65536) {
        out[op] = types.TAG_LITERAL | (61 << 2);
        std.mem.writeInt(u16, out[op + 1 ..][0..2], @as(u16, @truncate(n)), .little);
        op += 3;
    } else if (n < (1 << 24)) {
        out[op] = types.TAG_LITERAL | (62 << 2);
        out[op + 1] = @as(u8, @truncate(n));
        out[op + 2] = @as(u8, @truncate(n >> 8));
        out[op + 3] = @as(u8, @truncate(n >> 16));
        op += 4;
    } else {
        out[op] = types.TAG_LITERAL | (63 << 2);
        std.mem.writeInt(u32, out[op + 1 ..][0..4], @as(u32, @truncate(n)), .little);
        op += 5;
    }

    @memcpy(out[op .. op + len], literal);
    return op + len;
}

inline fn emitCopyAtMost64(offset: usize, len: usize, out: []u8) usize {
    std.debug.assert(len >= 4 and len <= 64);
    if (len < 12 and offset < 2048) {
        const len_field = @as(u8, @truncate(len - 4));
        const off_hi = @as(u8, @truncate((offset >> 8) & 0x07));
        out[0] = types.TAG_COPY_1 | (len_field << 2) | (off_hi << 5);
        out[1] = @as(u8, @truncate(offset & 0xff));
        return 2;
    } else if (offset <= 65535) {
        out[0] = types.TAG_COPY_2 | (@as(u8, @truncate(len - 1)) << 2);
        std.mem.writeInt(u16, out[1..3], @as(u16, @truncate(offset)), .little);
        return 3;
    } else {
        out[0] = types.TAG_COPY_4 | (@as(u8, @truncate(len - 1)) << 2);
        std.mem.writeInt(u32, out[1..5], @as(u32, @truncate(offset)), .little);
        return 5;
    }
}

inline fn emitCopy(offset: usize, mut_len: usize, out: []u8) usize {
    var op: usize = 0;
    var len = mut_len;
    while (len >= 68) {
        op += emitCopyAtMost64(offset, 64, out[op..]);
        len -= 64;
    }
    if (len > 64) {
        op += emitCopyAtMost64(offset, 60, out[op..]);
        len -= 60;
    }
    op += emitCopyAtMost64(offset, len, out[op..]);
    return op;
}

inline fn findMatchLengthPlain(s1: []const u8, s2: []const u8) usize {
    const limit = @min(s1.len, s2.len);
    var matched: usize = 0;
    while (matched + 8 <= limit) {
        const a1 = std.mem.readInt(u64, s1[matched..][0..8], .little);
        const a2 = std.mem.readInt(u64, s2[matched..][0..8], .little);
        if (a1 == a2) {
            matched += 8;
        } else {
            const xorval = a1 ^ a2;
            const shift = @ctz(xorval);
            matched += shift >> 3;
            return matched;
        }
    }
    while (matched < limit and s1[matched] == s2[matched]) {
        matched += 1;
    }
    return matched;
}

/// Google Snappy Level 1 compression fragment match finder.
fn compressFragmentL1(
    input: []const u8,
    output: []u8,
    table: []u16,
) usize {
    const table_size = calculateTableSize(input.len);
    const sub_table = table[0..table_size];
    @memset(sub_table, 0);
    const mask = table_size - 1;

    if (input.len < 15) {
        return emitLiteral(input, output);
    }

    const ip_limit = input.len - 15;
    var ip: usize = 0;
    var next_emit: usize = 0;
    var op: usize = 0;
    var skip: usize = 32;

    var preload: u32 = std.mem.readInt(u32, input[ip + 1 ..][0..4], .little);

    main_loop: while (true) {
        next_emit = ip;
        ip += 1;
        var data: u64 = std.mem.readInt(u64, input[ip..][0..8], .little);
        skip = 32;

        var candidate: usize = undefined;

        if (ip_limit - ip >= 16) {
            const delta = ip;
            for (0..4) |j| {
                for (0..4) |k| {
                    const i = 4 * j + k;
                    const dword: u32 = if (i == 0) preload else @truncate(data);
                    const entry = tableEntryL1(sub_table, dword, mask);
                    candidate = entry.*;
                    entry.* = @truncate(delta + i);
                    if (std.mem.readInt(u32, input[candidate..][0..4], .little) == dword) {
                        ip += i;
                        if (ip > next_emit) {
                            op += emitLiteral(input[next_emit..ip], output[op..]);
                        }
                        // Enter emit_match loop
                        while (true) {
                            const base = ip;
                            const matched = 4 + findMatchLengthPlain(input[candidate + 4 ..], input[ip + 4 ..]);
                            ip += matched;
                            const offset = base - candidate;
                            op += emitCopy(offset, matched, output[op..]);
                            if (ip >= ip_limit) break :main_loop;

                            const dword_prev = std.mem.readInt(u32, input[ip - 1 ..][0..4], .little);
                            tableEntryL1(sub_table, dword_prev, mask).* = @truncate(ip - 1);

                            const dword_curr = std.mem.readInt(u32, input[ip..][0..4], .little);
                            const curr_entry = tableEntryL1(sub_table, dword_curr, mask);
                            candidate = curr_entry.*;
                            curr_entry.* = @truncate(ip);

                            if (std.mem.readInt(u32, input[candidate..][0..4], .little) != dword_curr) {
                                break;
                            }
                        }
                        preload = std.mem.readInt(u32, input[ip + 1 ..][0..4], .little);
                        continue :main_loop;
                    }
                    data >>= 8;
                }
                if (j < 3) {
                    data = std.mem.readInt(u64, input[ip + 4 * j + 4 ..][0..8], .little);
                }
            }
            ip += 16;
            skip += 16;
        }

        while (true) {
            const dword: u32 = @truncate(data);
            const entry = tableEntryL1(sub_table, dword, mask);
            const bytes_between = skip >> 5;
            skip += bytes_between;
            const next_ip = ip + bytes_between;
            if (next_ip > ip_limit) {
                ip = next_emit;
                break :main_loop;
            }
            candidate = entry.*;
            entry.* = @truncate(ip);
            if (dword == std.mem.readInt(u32, input[candidate..][0..4], .little)) {
                break;
            }
            data = std.mem.readInt(u64, input[next_ip..][0..8], .little);
            ip = next_ip;
        }

        if (ip > next_emit) {
            op += emitLiteral(input[next_emit..ip], output[op..]);
        }

        while (true) {
            const base = ip;
            const matched = 4 + findMatchLengthPlain(input[candidate + 4 ..], input[ip + 4 ..]);
            ip += matched;
            const offset = base - candidate;
            op += emitCopy(offset, matched, output[op..]);
            if (ip >= ip_limit) break :main_loop;

            const dword_prev = std.mem.readInt(u32, input[ip - 1 ..][0..4], .little);
            tableEntryL1(sub_table, dword_prev, mask).* = @truncate(ip - 1);

            const dword_curr = std.mem.readInt(u32, input[ip..][0..4], .little);
            const curr_entry = tableEntryL1(sub_table, dword_curr, mask);
            candidate = curr_entry.*;
            curr_entry.* = @truncate(ip);

            if (std.mem.readInt(u32, input[candidate..][0..4], .little) != dword_curr) {
                break;
            }
        }
        preload = std.mem.readInt(u32, input[ip + 1 ..][0..4], .little);
    }

    if (ip < input.len) {
        op += emitLiteral(input[ip..], output[op..]);
    }
    return op;
}

/// Google Snappy Level 2 double-hash match finder.
fn compressFragmentL2(
    input: []const u8,
    output: []u8,
    table: []u16,
) usize {
    const table_size = calculateTableSize(input.len);
    const half_size = table_size >> 1;
    const t4 = table[0..half_size];
    const t8 = table[half_size..table_size];
    @memset(table[0..table_size], 0);
    const mask = half_size - 1;

    if (input.len < 15) {
        return emitLiteral(input, output);
    }

    const ip_limit = input.len - 15;
    var ip: usize = 0;
    var next_emit: usize = 0;
    var op: usize = 0;

    main_loop: while (true) {
        next_emit = ip;
        ip += 1;
        var data: u64 = std.mem.readInt(u64, input[ip..][0..8], .little);
        var skip: usize = 512;

        var candidate: usize = undefined;
        var candidate_len: usize = undefined;

        while (true) {
            const entry8 = tableEntry8Byte(t8, data, mask);
            const bytes_between = skip >> 9;
            skip += 1;
            const next_ip = ip + bytes_between;
            if (next_ip > ip_limit) {
                ip = next_emit;
                break :main_loop;
            }
            candidate = entry8.*;
            entry8.* = @truncate(ip);

            if (@as(u32, @truncate(data)) == std.mem.readInt(u32, input[candidate..][0..4], .little)) {
                candidate_len = 4 + findMatchLengthPlain(input[candidate + 4 ..], input[ip + 4 ..]);
                break;
            }

            const entry4 = tableEntry4Byte(t4, @truncate(data), mask);
            candidate = entry4.*;
            entry4.* = @truncate(ip);

            if (@as(u32, @truncate(data)) == std.mem.readInt(u32, input[candidate..][0..4], .little)) {
                candidate_len = 4 + findMatchLengthPlain(input[candidate + 4 ..], input[ip + 4 ..]);
                const next_data = std.mem.readInt(u64, input[ip + 1 ..][0..8], .little);
                const entry8_next = tableEntry8Byte(t8, next_data, mask);
                const candidate2 = entry8_next.*;
                const candidate_len2 = findMatchLengthPlain(input[candidate2..], input[ip + 1 ..]);
                if (candidate_len2 > candidate_len) {
                    entry8_next.* = @truncate(ip + 1);
                    candidate = candidate2;
                    candidate_len = candidate_len2;
                    ip += 1;
                }
                break;
            }

            data = std.mem.readInt(u64, input[next_ip..][0..8], .little);
            ip = next_ip;
        }

        // Backtrack to the point it matches fully
        while (ip > next_emit and candidate > 0 and input[ip - 1] == input[candidate - 1]) {
            ip -= 1;
            candidate -= 1;
            candidate_len += 1;
        }

        if (ip + 8 <= input.len) {
            tableEntry8Byte(t8, std.mem.readInt(u64, input[ip + 1 ..][0..8], .little), mask).* = @truncate(ip + 1);
            if (ip + 9 <= input.len) {
                tableEntry8Byte(t8, std.mem.readInt(u64, input[ip + 2 ..][0..8], .little), mask).* = @truncate(ip + 2);
            }
        }
        tableEntry4Byte(t4, std.mem.readInt(u32, input[ip + 1 ..][0..4], .little), mask).* = @truncate(ip + 1);

        if (ip > next_emit) {
            op += emitLiteral(input[next_emit..ip], output[op..]);
        }

        while (true) {
            const base = ip;
            ip += candidate_len;
            const offset = base - candidate;
            op += emitCopy(offset, candidate_len, output[op..]);
            if (ip >= ip_limit) break :main_loop;

            if (ip > 7) {
                tableEntry8Byte(t8, std.mem.readInt(u64, input[ip - 7 ..][0..8], .little), mask).* = @truncate(ip - 7);
                tableEntry8Byte(t8, std.mem.readInt(u64, input[ip - 4 ..][0..8], .little), mask).* = @truncate(ip - 4);
            }
            if (ip > 3) {
                tableEntry8Byte(t8, std.mem.readInt(u64, input[ip - 3 ..][0..8], .little), mask).* = @truncate(ip - 3);
            }
            if (ip > 2) {
                tableEntry8Byte(t8, std.mem.readInt(u64, input[ip - 2 ..][0..8], .little), mask).* = @truncate(ip - 2);
                tableEntry4Byte(t4, std.mem.readInt(u32, input[ip - 2 ..][0..4], .little), mask).* = @truncate(ip - 2);
            }
            tableEntry4Byte(t4, std.mem.readInt(u32, input[ip - 1 ..][0..4], .little), mask).* = @truncate(ip - 1);

            const curr_data = std.mem.readInt(u64, input[ip..][0..8], .little);
            const entry8 = tableEntry8Byte(t8, curr_data, mask);
            candidate = entry8.*;
            entry8.* = @truncate(ip);

            if (std.mem.readInt(u32, input[ip..][0..4], .little) == std.mem.readInt(u32, input[candidate..][0..4], .little)) {
                candidate_len = 4 + findMatchLengthPlain(input[candidate + 4 ..], input[ip + 4 ..]);
                continue;
            }

            const entry4 = tableEntry4Byte(t4, @truncate(curr_data), mask);
            candidate = entry4.*;
            entry4.* = @truncate(ip);

            if (std.mem.readInt(u32, input[ip..][0..4], .little) == std.mem.readInt(u32, input[candidate..][0..4], .little)) {
                candidate_len = 4 + findMatchLengthPlain(input[candidate + 4 ..], input[ip + 4 ..]);
                continue;
            }

            break;
        }
    }

    if (ip < input.len) {
        op += emitLiteral(input[ip..], output[op..]);
    }
    return op;
}

/// Compresses a Snappy block into a caller-provided destination buffer with custom table.
pub fn compressIntoWithTable(
    input: []const u8,
    output: []u8,
    table: []u16,
    options: types.CompressionOptions,
) types.Error!usize {
    if (input.len > std.math.maxInt(u32)) return error.InputTooLarge;
    const required_bound = maxCompressedSize(input.len);
    if (output.len < required_bound) {
        return error.OutputBufferTooSmall;
    }

    var varint_buf: [varint.MaxBytes]u8 = undefined;
    const varint_len = varint.encode(@as(u32, @intCast(input.len)), &varint_buf);
    if (output.len < varint_len) return error.OutputBufferTooSmall;
    @memcpy(output[0..varint_len], varint_buf[0..varint_len]);
    var op = varint_len;

    if (input.len == 0) {
        return op;
    }

    var in_offset: usize = 0;
    while (in_offset < input.len) {
        const fragment_len = @min(input.len - in_offset, types.MAX_BLOCK_SIZE);
        const fragment = input[in_offset .. in_offset + fragment_len];

        const written = if (options.level >= 2)
            compressFragmentL2(fragment, output[op..], table)
        else
            compressFragmentL1(fragment, output[op..], table);
        op += written;
        in_offset += fragment_len;
    }

    return op;
}

/// Compresses a Snappy block into a caller-provided destination buffer.
pub fn compressInto(
    input: []const u8,
    output: []u8,
    options: types.CompressionOptions,
) types.Error!usize {
    var table: [MAX_HASH_TABLE_SIZE]u16 = undefined;
    return compressIntoWithTable(input, output, &table, options);
}

/// Decompresses a Snappy block into a caller-provided destination buffer.
pub fn decompressInto(
    input: []const u8,
    output: []u8,
    options: types.DecompressionOptions,
) types.Error!usize {
    const dec_var = try varint.decode(input);
    const expected_len: usize = dec_var.value;

    if (options.maxOutputSize > 0 and expected_len > options.maxOutputSize) {
        return error.ResourceLimitExceeded;
    }
    if (output.len < expected_len) {
        return error.OutputBufferTooSmall;
    }

    var in_pos: usize = dec_var.bytes_read;
    var out_pos: usize = 0;

    while (out_pos < expected_len) {
        if (in_pos >= input.len) return error.TruncatedInput;
        const tag = input[in_pos];
        in_pos += 1;

        const tag_type = tag & 0x03;
        switch (tag_type) {
            types.TAG_LITERAL => {
                const len_tag = tag >> 2;
                var lit_len: usize = 0;
                if (len_tag < 60) {
                    lit_len = len_tag + 1;
                } else {
                    const extra_bytes: usize = (len_tag - 59);
                    if (in_pos + extra_bytes > input.len) return error.TruncatedInput;
                    var extra_len: u64 = 0;
                    for (0..extra_bytes) |b_idx| {
                        extra_len |= @as(u64, input[in_pos + b_idx]) << @as(u6, @intCast(b_idx * 8));
                    }
                    in_pos += extra_bytes;
                    const total_len = extra_len + 1;
                    if (total_len > @as(u64, expected_len - out_pos)) return error.CorruptStream;
                    lit_len = @as(usize, @intCast(total_len));
                }

                if (lit_len > expected_len - out_pos) return error.CorruptStream;
                if (lit_len > input.len - in_pos) return error.TruncatedInput;

                @memcpy(output[out_pos .. out_pos + lit_len], input[in_pos .. in_pos + lit_len]);
                out_pos += lit_len;
                in_pos += lit_len;
            },
            types.TAG_COPY_1 => {
                const copy_len = @as(usize, (tag >> 2) & 7) + 4;
                if (in_pos >= input.len) return error.TruncatedInput;
                const offset = (@as(usize, (tag >> 5) & 7) << 8) | input[in_pos];
                in_pos += 1;

                if (offset == 0 or offset > out_pos) return error.CorruptStream;
                if (copy_len > expected_len - out_pos) return error.CorruptStream;

                copyMatch(output, out_pos, offset, copy_len);
                out_pos += copy_len;
            },
            types.TAG_COPY_2 => {
                const copy_len = @as(usize, tag >> 2) + 1;
                if (in_pos + 2 > input.len) return error.TruncatedInput;
                const offset = std.mem.readInt(u16, input[in_pos..][0..2], .little);
                in_pos += 2;

                if (offset == 0 or offset > out_pos) return error.CorruptStream;
                if (copy_len > expected_len - out_pos) return error.CorruptStream;

                copyMatch(output, out_pos, offset, copy_len);
                out_pos += copy_len;
            },
            types.TAG_COPY_4 => {
                const copy_len = @as(usize, tag >> 2) + 1;
                if (in_pos + 4 > input.len) return error.TruncatedInput;
                const offset = std.mem.readInt(u32, input[in_pos..][0..4], .little);
                in_pos += 4;

                if (offset == 0 or offset > out_produced_pos: {
                    break :out_produced_pos out_pos;
                }) return error.CorruptStream;
                if (copy_len > expected_len - out_pos) return error.CorruptStream;

                copyMatch(output, out_pos, offset, copy_len);
                out_pos += copy_len;
            },
            else => unreachable,
        }
    }

    if (out_pos != expected_len) return error.CorruptStream;
    if (in_pos != input.len) return error.CorruptStream;

    return out_pos;
}

/// Compresses a Snappy block using the provided allocator.
pub fn compress(
    allocator: std.mem.Allocator,
    input: []const u8,
    options: types.CompressionOptions,
) types.Error![]u8 {
    const max_len = maxCompressedSize(input.len);
    const buf = try allocator.alloc(u8, max_len);
    errdefer allocator.free(buf);

    const actual_len = try compressInto(input, buf, options);
    if (actual_len == buf.len) return buf;

    const trimmed = allocator.realloc(buf, actual_len) catch {
        const copy = try allocator.alloc(u8, actual_len);
        @memcpy(copy, buf[0..actual_len]);
        allocator.free(buf);
        return copy;
    };
    return trimmed;
}

/// Decompresses a Snappy block using the provided allocator.
pub fn decompress(
    allocator: std.mem.Allocator,
    input: []const u8,
    options: types.DecompressionOptions,
) types.Error![]u8 {
    const expected_len = try uncompressedLength(input);
    if (options.maxOutputSize > 0 and expected_len > options.maxOutputSize) {
        return error.ResourceLimitExceeded;
    }

    const out = try allocator.alloc(u8, expected_len);
    errdefer allocator.free(out);

    const produced = try decompressInto(input, out, options);
    if (produced != expected_len) {
        allocator.free(out);
        return error.CorruptStream;
    }
    return out;
}

test "block empty input roundtrip" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const comp = try compress(alloc, "", .{});
    defer alloc.free(comp);

    const decomp = try decompress(alloc, comp, .{});
    defer alloc.free(decomp);

    try testing.expectEqualStrings("", decomp);
}

test "block small strings roundtrip" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const test_cases = [_][]const u8{
        "a",
        "ab",
        "abc",
        "abcd",
        "Hello, World!",
        "Native Zig Snappy 0.17.0 implementation!",
    };

    for (test_cases) |tc| {
        const comp = try compress(alloc, tc, .{});
        defer alloc.free(comp);

        try testing.expect(isValidCompressedBuffer(comp));

        const decomp = try decompress(alloc, comp, .{});
        defer alloc.free(decomp);

        try testing.expectEqualStrings(tc, decomp);
    }
}

test "block repetitive pattern run-length encoding" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const pattern = "ABCDEF123456";
    const src = try alloc.alloc(u8, pattern.len * 100);
    defer alloc.free(src);
    for (0..100) |i| {
        @memcpy(src[i * pattern.len .. (i + 1) * pattern.len], pattern);
    }

    const comp = try compress(alloc, src, .{});
    defer alloc.free(comp);

    try testing.expect(comp.len < src.len);
    try testing.expect(isValidCompressedBuffer(comp));

    const decomp = try decompress(alloc, comp, .{});
    defer alloc.free(decomp);

    try testing.expectEqualStrings(src, decomp);
}

test "block large buffer exceeding 64KB fragment" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const size = 150_000;
    const big_buf = try alloc.alloc(u8, size);
    defer alloc.free(big_buf);

    for (big_buf, 0..) |*b, i| {
        b.* = @as(u8, @truncate(i ^ (i >> 3)));
    }

    const comp = try compress(alloc, big_buf, .{});
    defer alloc.free(comp);

    try testing.expect(isValidCompressedBuffer(comp));

    const decomp = try decompress(alloc, comp, .{});
    defer alloc.free(decomp);

    try testing.expectEqualSlices(u8, big_buf, decomp);
}

test "block level 1 and level 2 compression" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const pattern = "The quick brown fox jumps over the lazy dog. ";
    const text = try alloc.alloc(u8, pattern.len * 200);
    defer alloc.free(text);
    for (0..200) |i| {
        @memcpy(text[i * pattern.len .. (i + 1) * pattern.len], pattern);
    }

    const comp1 = try compress(alloc, text, .{ .level = 1 });
    defer alloc.free(comp1);

    const comp2 = try compress(alloc, text, .{ .level = 2 });
    defer alloc.free(comp2);

    try testing.expect(comp2.len <= comp1.len);

    const decomp1 = try decompress(alloc, comp1, .{});
    defer alloc.free(decomp1);
    try testing.expectEqualStrings(text, decomp1);

    const decomp2 = try decompress(alloc, comp2, .{});
    defer alloc.free(decomp2);
    try testing.expectEqualStrings(text, decomp2);
}

test "block zero offset corruption rejection" {
    const testing = std.testing;
    // Length 64 (0x40), then copy with offset 0
    const bad_data = [_]u8{ 0x40, 0x12, 0x00, 0x00 };
    var out_buf: [100]u8 = undefined;
    try testing.expectError(error.CorruptStream, decompressInto(&bad_data, &out_buf, .{}));
    try testing.expect(!isValidCompressedBuffer(&bad_data));
}

test "block literal length u32 overflow rejection" {
    const testing = std.testing;
    // Expected len 65536 (0x80, 0x80, 0x04)
    // 1-byte literal 'D' (0x00, 'D')
    // Poison tag 0xfc with length bytes 0xff, 0xff, 0xff, 0xff
    const comp_data = [_]u8{
        0x80, 0x80, 0x04, // Expected length: 65536
        0x00, 'D', // 1-byte literal 'D'
        0xfc, 0xff, 0xff, 0xff, 0xff, // Poison literal tag 0xfc with length 0xffffffff
    };

    var out_buf: [65536]u8 = undefined;
    try testing.expectError(error.CorruptStream, decompressInto(&comp_data, &out_buf, .{}));
    try testing.expect(!isValidCompressedBuffer(&comp_data));
}

test "official testdata alice29.txt level 1 and level 2 compression" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const data = @embedFile("testdata/alice29.txt");
    const comp1 = try compress(alloc, data, .{ .level = 1 });
    defer alloc.free(comp1);

    // Google C++ Snappy compresses alice29.txt to 86727 bytes (CRLF) or 85905 bytes (LF)
    try testing.expect(comp1.len == 86727 or comp1.len == 85905);

    const decomp1 = try decompress(alloc, comp1, .{});
    defer alloc.free(decomp1);
    try testing.expectEqualSlices(u8, data, decomp1);

    const comp2 = try compress(alloc, data, .{ .level = 2 });
    defer alloc.free(comp2);

    try testing.expect(comp2.len <= comp1.len);

    const decomp2 = try decompress(alloc, comp2, .{});
    defer alloc.free(decomp2);
    try testing.expectEqualSlices(u8, data, decomp2);
}

test "official testdata html level 1 and level 2 compression" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const data = @embedFile("testdata/html");
    const comp1 = try compress(alloc, data, .{ .level = 1 });
    defer alloc.free(comp1);

    // Google C++ Snappy achieves high compression ratio on html
    try testing.expect(comp1.len <= 23628);

    const decomp1 = try decompress(alloc, comp1, .{});
    defer alloc.free(decomp1);
    try testing.expectEqualSlices(u8, data, decomp1);

    const comp2 = try compress(alloc, data, .{ .level = 2 });
    defer alloc.free(comp2);

    try testing.expect(comp2.len <= comp1.len);

    const decomp2 = try decompress(alloc, comp2, .{});
    defer alloc.free(decomp2);
    try testing.expectEqualSlices(u8, data, decomp2);
}

test "official testdata baddata rejection" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const bad1 = @embedFile("testdata/baddata1.snappy");
    const bad2 = @embedFile("testdata/baddata2.snappy");
    const bad3 = @embedFile("testdata/baddata3.snappy");

    try testing.expect(!isValidCompressedBuffer(bad1));
    try testing.expectError(error.CorruptStream, decompress(alloc, bad1, .{}));

    try testing.expect(!isValidCompressedBuffer(bad2));
    try testing.expectError(error.CorruptStream, decompress(alloc, bad2, .{}));

    try testing.expect(!isValidCompressedBuffer(bad3));
    try testing.expectError(error.CorruptStream, decompress(alloc, bad3, .{}));
}
