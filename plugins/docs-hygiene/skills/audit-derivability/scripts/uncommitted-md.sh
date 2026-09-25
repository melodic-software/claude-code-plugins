#!/usr/bin/env bash
# uncommitted-md.sh — list uncommitted .md files for the audit-derivability
# skill's `## Pre-computed context` block.
#
# Keep this awk out of SKILL.md: skill argument substitution rewrites `$<digit>`
# anywhere in a skill body, so an inline `$0` corrupts on any run given an argument.
#
# Usage: uncommitted-md.sh [max]
#   max — cap on emitted paths (default 20)
#
# Output: up to <max> repo-relative .md paths from `git status --porcelain`, one
# per line; rename entries emit the new path only; empty when nothing matches.
# Exit 1 when git status is unavailable; callers supply their own fallback text.
set -u

MAX="${1:-20}"

s=$(git status --porcelain 2>/dev/null) || exit 1

printf '%s\n' "$s" |
  awk '/\.md"?$/ { p = substr($0, 4); sub(/^.* -> /, "", p); print p }' |
  head -n "$MAX"
exit 0
