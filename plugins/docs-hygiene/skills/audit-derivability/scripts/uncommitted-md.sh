#!/usr/bin/env bash
# Exit 1 when git status is unavailable; callers supply their own fallback text.
set -u

MAX="${1:-20}"

s=$(git status --porcelain 2>/dev/null) || exit 1

printf '%s\n' "$s" |
  awk '/\.md"?$/ { p = substr($0, 4); sub(/^.* -> /, "", p); print p }' |
  head -n "$MAX"
exit 0
