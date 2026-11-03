#!/usr/bin/env bash
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/../fixtures/repo.sh"
mkdir -p .work/buffer
printf '*\n' >.work/.gitignore
{
  printf '%s\n' '{"obs_id":"o1","ts":"2026-10-03T09:00:00Z","producer":"corrections/codify-note","signal":"handlers build SQL by string concatenation","source_id":"3f2a1bc"}'
  printf '%s\n' '{"obs_id":"o2","ts":"2026-10-10T09:00:00Z","producer":"corrections/codify-note","signal":"a handler concatenates user input into a SQL string","source_id":"91ac0de"}'
  printf '%s\n' '{"obs_id":"o3","ts":"2026-10-12T09:00:00Z","producer":"corrections/codify-note","signal":"new endpoints skip the shared auth helper","source_id":"5be7712"}'
  printf '%s\n' '{"obs_id":"o4","ts":"2026-09-12T08:00:00Z","producer":"corrections/codify-note","signal":"handlers build SQL by string concatenation","source_id":"c04e8d1"}'
} >.work/buffer/findings.jsonl
