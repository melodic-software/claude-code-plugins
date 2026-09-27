#!/usr/bin/env bash
# changed-code-files.sh — list uncommitted code files for the audit-comment-residue
# and dissolve-comments skills' `## Pre-computed context` blocks.
#
# Kept out of SKILL.md: skill argument substitution rewrites `$<digit>` anywhere in a
# skill body, which corrupted this awk's `substr($0, ...)` calls inline.
#
# Usage: changed-code-files.sh [max]
#   max — cap on emitted paths (default 10)
#
# Output: up to <max> repo-relative paths of changed or untracked code files, one
# per line, in `git status` order; empty when nothing matches. Rename and copy
# entries emit the new path only. Exit 1 when git status is unavailable; callers
# supply their own fallback text.
set -u

MAX="${1:-10}"

git status --porcelain -z >/dev/null 2>&1 || exit 1

git status --porcelain -z 2>/dev/null |
  awk 'BEGIN { RS = "\0" } skip { skip = 0; next } { if (substr($0, 1, 2) ~ /[RC]/) skip = 1; print substr($0, 4) }' |
  grep -Ei '\.(cs|ts|tsx|js|jsx|py|sh|ps1|go|rs|java|rb|lua|sql|c|h|cpp|hpp|yaml|yml|toml)$' |
  head -n "$MAX"
exit 0
