#!/usr/bin/env bash
set -u

MAX="${1:-10}"
EXT_LIST="$(dirname "${BASH_SOURCE[0]}")/code-extensions.txt"
EXTS=""
[[ -f "$EXT_LIST" && -r "$EXT_LIST" ]] && EXTS="$(tr -d '\r' <"$EXT_LIST" | grep . | paste -sd'|' -)"
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
