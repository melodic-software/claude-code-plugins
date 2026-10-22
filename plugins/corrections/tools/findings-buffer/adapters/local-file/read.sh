#!/usr/bin/env bash
# local-file findings buffer: read.sh [--since <UTC ISO-8601>]
# Writes stored rows as JSONL. With --since, writes at least every row with ts >= since.
# Exit: 0 ok, 1 read failure, 2 usage, 3 not in a repository or jq missing.
set -uo pipefail

SINCE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since)
      if [[ $# -lt 2 ]]; then
        echo "read.sh: --since needs a value" >&2
        exit 2
      fi
      SINCE="$2"
      shift 2
      ;;
    *)
      echo "usage: read.sh [--since <UTC ISO-8601>]" >&2
      exit 2
      ;;
  esac
done

if [[ -n "$SINCE" && ! "$SINCE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z$ ]]; then
  echo "read.sh: --since must be UTC ISO-8601, e.g. 2026-10-21T09:30:00Z" >&2
  exit 2
fi

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "read.sh: not inside a git repository" >&2
  exit 3
}

FILE="$ROOT/.work/buffer/findings.jsonl"
for p in "$ROOT/.work" "$ROOT/.work/buffer" "$FILE"; do
  if [[ -L "$p" ]]; then
    echo "read.sh: $p is a symlink; the buffer must be a plain directory in the repository" >&2
    exit 2
  fi
done
[[ -f "$FILE" ]] || exit 0

if [[ -z "$SINCE" ]]; then
  cat "$FILE" || exit 1
  exit 0
fi

command -v jq >/dev/null 2>&1 || {
  echo "read.sh: prerequisite missing: jq" >&2
  exit 3
}

# Compare the top-level ts to the second only: a fraction would sort wrongly against
# a bare "Z", and the contract allows returning rows older than --since. A row with
# no string ts is kept.
jq -c --arg s "${SINCE:0:19}" \
  'select((.ts | type) != "string" or .ts[0:19] >= $s)' "$FILE" || exit 1
