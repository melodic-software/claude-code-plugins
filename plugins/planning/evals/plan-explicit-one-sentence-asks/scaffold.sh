#!/usr/bin/env bash
# Seeds the eval workspace with one small Python module whose rename fits one sentence.
set -euo pipefail

mkdir -p utils
printf '%s\n' \
  'def tally(rows):' \
  '    cnt = 0' \
  '    for row in rows:' \
  '        if row.get("ok"):' \
  '            cnt += 1' \
  '    return cnt' >utils/stats.py
