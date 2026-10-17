const std = @import("std");

/// Semantic version of snappy.zig.
pub const version = std.SemanticVersion{
    .major = 0,
    .minor = 0,
    .patch = 1,
};

/// String representation of library version.
pub const version_string = "0.0.1";

/// Integer representation of library version ((major << 16) | (minor << 8) | patch).
pub const version_number: u32 = (version.major << 16) | (version.minor << 8) | version.patch;

/// Returns the library version string.
pub fn versionString() []const u8 {
    return version_string;
}

/// Returns the library version number.
pub fn versionNumber() u32 {
    return version_number;
}

/// Snappy block format constants.
pub const BLOCK_LOG: u5 = 16;
pub const MAX_BLOCK_SIZE: usize = 1 << BLOCK_LOG; // 65536 bytes
pub const MAX_VARINT_BYTES: usize = 5;

/// Magic stream identifier for the Snappy framed format.
pub const STREAM_IDENTIFIER = "sNaPpY";
pub const STREAM_IDENTIFIER_MAGIC: [6]u8 = "sNaPpY".*;

/// Framing chunk identifiers.
pub const CHUNK_COMPRESSED_DATA: u8 = 0x00;
pub const CHUNK_UNCOMPRESSED_DATA: u8 = 0x01;
pub const CHUNK_PADDING: u8 = 0xfe;
pub const CHUNK_STREAM_IDENTIFIER: u8 = 0xff;

/// Block tag identifiers.
pub const TAG_LITERAL: u8 = 0x00;
pub const TAG_COPY_1: u8 = 0x01;
pub const TAG_COPY_2: u8 = 0x02;
pub const TAG_COPY_4: u8 = 0x03;

/// Block or framed stream mode.
pub const BlockMode = enum {
    framed,
    block,
};

/// Compression options.
pub const CompressionOptions = struct {
    /// Compression level:
    /// - 1: Fastest throughput (default standard Snappy)
    /// - 2: Higher compression ratio (double-hash matching)
    level: u8 = 1,
    /// Format mode: framed stream (default) or raw block
    blockMode: BlockMode = .framed,
    /// Maximum fragment size for framed stream chunks (max 65536)
    blockSize: usize = MAX_BLOCK_SIZE,
};

/// Decompression options.
pub const DecompressionOptions = struct {
    /// Maximum allowed uncompressed output size (0 = no limit).
    /// Used to defend against decompression bombs.
    maxOutputSize: usize = 0,
    /// Whether to verify masked CRC-32C checksums in framed streams.
    verifyChecksums: bool = true,
};

/// Canonical error set for snappy operations.
pub const Error = error{
    /// Input data is malformed or violates the Snappy format specification.
    CorruptStream,
    /// Input data ended unexpectedly before all required bytes were parsed.
    TruncatedInput,
    /// Caller-provided output buffer has insufficient capacity.
    OutputBufferTooSmall,
    /// Decompressed size exceeds caller-configured maxOutputSize limit.
    ResourceLimitExceeded,
    /// Chunk length in framed stream is invalid or exceeds maximum allowable size.
    InvalidChunkLength,
    /// Unrecognized unskippable chunk type encountered in framed stream.
    UnknownChunkType,
    /// CRC-32C checksum does not match uncompressed chunk payload.
    ChecksumMismatch,
    /// Stream does not begin with the required Snappy framing identifier.
    InvalidMagic,
    /// Varint integer encoding is invalid or overflows 32 bits.
    InvalidVarint,
    /// Memory allocation failed.
    OutOfMemory,
    /// Input size exceeds allowable format limits (e.g. 2^32 - 1).
    InputTooLarge,
};

/// Combined error set for streaming I/O operations including reader/writer errors.
pub const StreamError = Error || std.Io.Writer.Error || std.Io.Reader.Error;
