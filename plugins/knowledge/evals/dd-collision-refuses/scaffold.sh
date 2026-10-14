#!/usr/bin/env bash
# Seed a work root whose slug matches https://docs.example.com/api/overview
# but whose checklist records a different canonical URL. The working directory
# is made its own git toplevel, because the skill resolves .work/ against
# `git rev-parse --show-toplevel` and the eval home above it is a repository.
set -euo pipefail

git init -q

root=.work/docs-example-com-api-overview-138253a9
mkdir -p "$root"
printf '*\n' >.work/.gitignore
cat >"$root/docpage-digest-checklist.md" <<'MD'
# Docpage digest checklist

## Provenance

- Canonical URL: https://docs.example.com/other/overview
- Work root: .work/docs-example-com-api-overview-138253a9
- Fetch date: 2026-09-30
- Channel: markdown

## Phases

- [x] Phase 1. Fetch
- [ ] Phase 2. Inventory
MD
printf '# Other overview\n\nOriginal snapshot of a different page.\n' >"$root/source.md"
