#!/usr/bin/env bash
# changed-code-files.sh — list uncommitted code files for remove-comments' audit
# action.
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
# supply their own fallback text. Exit 4, naming the file, when the shared
# extension list (code-extensions.txt beside this script) cannot be read.
set -u

MAX="${1:-10}"
EXT_LIST="$(dirname "${BASH_SOURCE[0]}")/code-extensions.txt"
EXTS="$(tr -d '\r' <"$EXT_LIST" 2>/dev/null | grep . | paste -sd'|' -)"
if [[ -z "$EXTS" ]]; then
  printf 'changed-code-files: cannot read the extension list %s\n' "$EXT_LIST" >&2
  exit 4
fi

git status --porcelain -z >/dev/null 2>&1 || exit 1

git status --porcelain -z 2>/dev/null |
  awk 'BEGIN { RS = "\0" } skip { skip = 0; next } { if (substr($0, 1, 2) ~ /[RC]/) skip = 1; print substr($0, 4) }' |
  grep -Ei "\\.($EXTS)\$" |
  head -n "$MAX"
exit 0
