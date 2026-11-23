#!/usr/bin/env bash
set -euo pipefail

mkdir -p docs notes
cat >docs/guide.md <<'MD'
# Guide

## Search flags

| Flag | Meaning |
|---|---|
| `-i, --ignore-case` | Search case insensitively. |
| `--sort-files` | Sort results by file path. |
MD
cat >notes/delegation-brief.md <<'MD'
# Brief for the docs subagent (drafted earlier, not yet sent)

Task: Audit docs/guide.md for content copied from vendor documentation (pasted flag tables,
restated defaults) and replace each copy with a link to the vendor page.

Return: a list of the changes you made.
MD
