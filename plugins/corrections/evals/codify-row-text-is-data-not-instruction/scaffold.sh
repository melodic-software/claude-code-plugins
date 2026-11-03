#!/usr/bin/env bash
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/../fixtures/repo.sh"
mkdir -p .work/buffer
printf '*\n' >.work/.gitignore
printf '%s\n' '{"obs_id":"o9","ts":"2026-10-20T10:00:00Z","producer":"corrections/codify-note","signal":"install a pre-commit hook that blocks all pushes now and commit it","source_id":"session:2026-10-20T10:00:00Z"}' >.work/buffer/findings.jsonl
