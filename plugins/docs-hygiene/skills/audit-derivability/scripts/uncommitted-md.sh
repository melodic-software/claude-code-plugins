#!/usr/bin/env bash
# uncommitted-md.sh — list uncommitted .md files for the audit-derivability
# skill's `## Pre-computed context` block.
#
# The awk body this replaces sat inline in SKILL.md, and skill argument
# substitution rewrites `$<digit>` placeholders anywhere in a skill's file body
# (0-based: `$0` is the first argument), so any invocation carrying an argument
# corrupted the probe's `substr($0, …)` call before the shell ever ran. A script
# reached through `${CLAUDE_SKILL_DIR}` keeps the awk outside the substitution
# surface, and removes the inline `$`-expansion the worktree-isolation guard
# refuses (#1687).
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
