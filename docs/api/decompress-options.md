---
title: DecompressionOptions API
description: Complete specification of decompression options and security limits in snappy.zig.
keywords: DecompressionOptions, maxOutputSize, verifyChecksums, decompression bomb defense, zig 0.17.0
---

# `snappy.DecompressionOptions`

`DecompressionOptions` controls safety limits and validation behavior during decompression.

```zig
pub const DecompressionOptions = struct {
    /// Maximum allowed uncompressed output size (0 = no limit).
    /// Used to defend against decompression bombs.
    maxOutputSize: usize = 0,
    /// Whether to verify masked CRC-32C checksums in framed streams.
    verifyChecksums: bool = true,
};
```

---

## Fields

### `maxOutputSize`
- **Type**: `usize`
- **Default**: `0` (unlimited)
- **Description**: Maximum allowable uncompressed output size in bytes. If decompression would produce more bytes than this limit, the decoder safely aborts with `error.ResourceLimitExceeded`, preventing untrusted payload decompression bomb attacks.

### `verifyChecksums`
- **Type**: `bool`
- **Default**: `true`
- **Description**: When `true`, every compressed (`0x00`) and uncompressed (`0x01`) chunk in a framed stream has its uncompressed payload verified against the 4-byte masked CRC-32C checksum embedded in the chunk header. If a discrepancy is detected, decompression fails immediately with `error.ChecksumMismatch`.
