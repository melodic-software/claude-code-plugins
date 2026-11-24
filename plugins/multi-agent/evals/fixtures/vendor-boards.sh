#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
case "$mode" in
all-read | one-unread) ;;
*)
  echo "vendor-boards.sh: unknown mode '$mode' (all-read or one-unread)" >&2
  exit 2
  ;;
esac

today="$(date -u +%Y-%m-%d)"
mkdir -p eval-fixtures/boards/www-tbench-ai eval-fixtures/cache

if [[ "$mode" == all-read ]]; then
  cat >eval-fixtures/boards/www-tbench-ai/leaderboard.md <<EOF
# Terminal-Bench Leaderboard

Updated: ${today}

| Rank | Model | Harness | Effort | Score | Error Range | Avg Tokens |
|---|---|---|---|---|---|---|
| 1 | kestrel-1 | claude-code | high | 81.2% | +/- 1.1% | 125000 tokens/task |
| 2 | sparrow-1 | codex | high | 80.9% | +/- 1.1% | 118000 tokens/task |
| 3 | finch-1 | agy | high | 77.4% | +/- 1.2% | 132000 tokens/task |
EOF

  mkdir -p eval-fixtures/boards/cursor-com
  cat >eval-fixtures/boards/cursor-com/cursorbench.md <<EOF
# CursorBench Leaderboard

Changelog: ${today} release

| Model | Effort | Score | Error Range | Avg Tokens |
|---|---|---|---|---|
| kestrel-1 | high | 79.6% | +/- 1.3% | 140000 tokens/task |
| sparrow-1 | high | 79.2% | +/- 1.3% | 135000 tokens/task |
| finch-1 | high | 74.0% | +/- 1.4% | 150000 tokens/task |
EOF

  mkdir -p eval-fixtures/boards/arena-ai/leaderboard/code
  cat >eval-fixtures/boards/arena-ai/leaderboard/code/webdev.md <<EOF
# WebDev Arena Leaderboard

Last updated: ${today}

| Model | Rating | 95% CI |
|---|---|---|
| kestrel-1 | 1420 | +/- 12 |
| sparrow-1 | 1412 | +/- 12 |
| finch-1 | 1416 | +/- 12 |
EOF
else
  cat >eval-fixtures/boards/www-tbench-ai/leaderboard.md <<EOF
# Terminal-Bench Leaderboard

Updated: ${today}

| Rank | Model | Harness | Effort | Score | Error Range |
|---|---|---|---|---|---|
| 1 | sparrow-1 | codex | high | 84.5% | +/- 1.0% |
| 2 | kestrel-1 | claude-code | high | 79.0% | +/- 1.0% |
| 3 | finch-1 | agy | high | 76.2% | +/- 1.2% |
EOF
fi
