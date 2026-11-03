#!/usr/bin/env bash
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/../fixtures/repo.sh"
mkdir -p .work/buffer
printf '*\n' >.work/.gitignore
signal="When a test fails before any edit to its code, run it on the base commit before debugging it as caused by this change"
printf '{"obs_id":"a1","ts":"2026-11-01T10:00:00Z","producer":"corrections/codify-note","signal":"%s","source_id":"#42","location":"CLAUDE.md","kind":"applied"}\n' "$signal" >.work/buffer/findings.jsonl
printf '{"obs_id":"m1","ts":"2026-11-02T10:00:00Z","producer":"corrections/codify-note","signal":"%s","source_id":"session:2026-11-02T10:00:00Z"}\n' "$signal" >>.work/buffer/findings.jsonl
