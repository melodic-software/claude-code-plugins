#!/usr/bin/env bash
# Seeds a README with terse reference tables and one clipped troubleshooting paragraph.
set -euo pipefail

mkdir -p docs
cat > docs/exporter.md <<'MD'
# Report exporter

## Options

| Flag | Meaning |
|---|---|
| `--fmt` | out fmt, csv/json |
| `--dry` | no write, print count |

## Commands

| Command | Does |
|---|---|
| `exporter run` | export now |
| `exporter ls` | list jobs |

## When an export fails

Job fail → check creds, re-auth w/ token. Retry = rerun job, same args. Logs in tmp dir.

The exporter writes its log to `/var/log/exporter.log` and keeps the last seven files.
MD
