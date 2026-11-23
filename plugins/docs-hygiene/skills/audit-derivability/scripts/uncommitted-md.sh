#!/usr/bin/env bash
# Keep this awk out of SKILL.md: skill argument substitution rewrites `$<digit>`
# anywhere in a skill body, so an inline `$0` corrupts on any run given an argument.
# Exit 1 when git status is unavailable; callers supply their own fallback text.
set -u

MAX="${1:-20}"

s=$(git status --porcelain 2>/dev/null) || exit 1

printf '%s\n' "$s" |
  awk '/\.md"?$/ { p = substr($0, 4); sub(/^.* -> /, "", p); print p }' |
  head -n "$MAX"
exit 0
