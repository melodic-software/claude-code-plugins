#!/usr/bin/env bash
set -euo pipefail

mkdir -p docs/migrations docs/v2 docs/v3

cat >VERSION <<'EOF'
3.2.0
EOF

cat >README.md <<'EOF'
# packctl

`packctl` creates deterministic release archives for deployment artifacts.

## Quick start

```bash
packctl bundle ./dist -o release.tar.gz
```

By default, `packctl bundle` compresses archives with `gzip`. Pass `--compress <algo>` (for example `--compress none`) to override the default compression algorithm.

See `docs/quickstart.md` for examples and `CHANGELOG.md` for release history.
EOF

cat >docs/quickstart.md <<'EOF'
# packctl Quickstart

To package a directory with the default `gzip` compression:

```bash
packctl bundle ./build -o artifact.bundle
```

To select a different algorithm:

```bash
packctl bundle ./build --compress gzip -o artifact.bundle
```
EOF

cat >docs/v2/cli-reference.md <<'EOF'
# packctl v2 CLI Reference

## `packctl bundle`

- Default compression: `gzip`
- `--compress <gzip|lz4|none>`: select archive compression algorithm (default: `gzip`).
EOF

cat >CHANGELOG.md <<'EOF'
# Changelog

## [3.2.0] - 2026-08-14

### Fixed

- Preserved relative symbolic links when bundling nested directories.
- Normalized SHA-256 manifest output on Windows.

## [3.1.0] - 2026-06-02

### Added

- Added `--json` progress reporting for CI logs.

## [3.0.0] - 2026-03-19

### Changed

- Breaking: `packctl bundle` now defaults to `zstd` archive compression instead of `gzip`.
- Breaking: removed `--compress` and replaced it with `--codec <zstd|gzip|none>`. See `docs/migrations/v2-to-v3.md`.

## [2.4.0] - 2025-11-05

### Added

- Experimental `lz4` support via `--compress lz4`.
EOF

cat >docs/migrations/v2-to-v3.md <<'EOF'
# Migrating from packctl v2 to v3

Version `3.0.0` changed archive compression defaults and CLI flags:

1. Default compression changed from `gzip` to `zstd`.
2. Replace every `--compress <algo>` invocation with `--codec <algo>`.
EOF

cat >docs/v3/cli-reference.md <<'EOF'
# packctl v3 CLI Reference

Applies to releases `3.0.0` through the current `3.2.0` release.

## `packctl bundle`

- Default compression: `zstd` (changed from `gzip` in `3.0.0`).
- `--codec <zstd|gzip|none>`: override the archive compression algorithm (replaced `--compress` in `3.0.0`).
EOF
