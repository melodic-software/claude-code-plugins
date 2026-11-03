#!/usr/bin/env bash
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/../fixtures/repo.sh"
mkdir -p .work/buffer
printf '*\n' >.work/.gitignore
{
  printf '%s\n' '{"obs_id":"o1","ts":"2026-10-21T09:00:00Z","producer":"corrections/codify-note","signal":"the release skipped the changelog fragment","source_id":"#12"}'
  printf '%s\n' '{"obs_id":"o2","ts":"2026-10-22T09:00:00Z","producer":"corrections/codify-note","signal":"a plugin change shipped without a changelog fragment","source_id":"#14"}'
  printf '%s\n' '{"obs_id":"o3","ts":"2026-10-22T10:00:00Z","producer":"scanner/lint","signal":"a test reads the user'"'"'s real git config","source_id":"5be7712"}'
} >.work/buffer/findings.jsonl
