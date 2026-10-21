#!/usr/bin/env bash
# local-file findings buffer: append.sh < rows.jsonl
# Stores each row in .work/buffer/findings.jsonl under the repository root.
# Exit: 0 every row durable, 1 storage failure, 2 usage, 3 not in a repository.
set -uo pipefail

if [[ $# -gt 0 ]]; then
  echo "usage: append.sh < rows.jsonl (takes no arguments)" >&2
  exit 2
fi

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "append.sh: not inside a git repository" >&2
  exit 3
}

TMP="$(mktemp)" || exit 1
trap 'rm -f "$TMP"' EXIT

# Validate first, so a malformed row stores nothing from this call.
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%$'\r'}"
  [[ -z "${line//[[:space:]]/}" ]] && continue
  if [[ ! "$line" =~ ^\{.*\}$ ]]; then
    echo "append.sh: each row must be a single-line JSON object" >&2
    exit 2
  fi
  printf '%s\n' "$line" >>"$TMP" || exit 1
done

DIR="$ROOT/.work/buffer"
FILE="$DIR/findings.jsonl"
mkdir -p "$DIR" || exit 1
[[ -s "$TMP" ]] || exit 0

write_rows() {
  cat "$TMP" >>"$FILE" || return 1
  sync "$FILE" 2>/dev/null || true
}

if command -v flock >/dev/null 2>&1; then
  (
    flock -x 9 || exit 1
    write_rows
  ) 9>"$DIR/.lock" || exit 1
else
  # Portable fallback: mkdir is atomic.
  LOCKDIR="$DIR/.lockdir"
  tries=0
  until mkdir "$LOCKDIR" 2>/dev/null; do
    tries=$((tries + 1))
    if [[ $tries -gt 600 ]]; then
      echo "append.sh: could not take the buffer lock" >&2
      exit 1
    fi
    sleep 0.05
  done
  write_rows
  rc=$?
  rmdir "$LOCKDIR" 2>/dev/null
  [[ $rc -eq 0 ]] || exit 1
fi
exit 0
