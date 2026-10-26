#!/usr/bin/env bash
# Findings buffer front door.
#   buffer.sh append < rows.jsonl
#   buffer.sh read [--since <UTC ISO-8601>]
# append redacts each row's string values, caps the row, sets obs_id and ts, and hands the rows to
# the bound adapter: the user-scope binding for this repository, else the one in
# <home>/findings-buffer.yaml (personal overlay findings-buffer.local.yaml; default local-file).
# When that append fails, the rows go to the local-file adapter instead.
# read merges the bound adapter's rows with the local-file rows and drops repeat obs_ids.
# Exit: 0 ok, 1 failure, 2 usage or a malformed row, 3 not in a repository or node/python3 missing.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CORE="$HERE/../../scripts/findings-buffer.mjs"
LOCAL="$HERE/adapters/local-file"

usage() {
  echo "usage: buffer.sh append < rows.jsonl | buffer.sh read [--since <UTC ISO-8601>]" >&2
  exit 2
}

VERB="${1:-}"
[[ $# -gt 0 ]] && shift
SINCE=()
case "$VERB" in
  append)
    [[ $# -eq 0 ]] || usage
    ;;
  read)
    if [[ $# -gt 0 ]]; then
      [[ $# -eq 2 && "$1" == --since ]] || usage
      if [[ ! "$2" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z$ ]]; then
        echo "buffer.sh: --since must be UTC ISO-8601, e.g. 2026-10-21T09:30:00Z" >&2
        exit 2
      fi
      SINCE=(--since "$2")
    fi
    ;;
  *) usage ;;
esac

command -v node >/dev/null 2>&1 || {
  echo "buffer.sh: prerequisite missing: node" >&2
  exit 3
}
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "buffer.sh: not inside a git repository" >&2
  exit 3
}
ADAPTER="$(node "$CORE" adapter --project "$ROOT")" || {
  echo "buffer.sh: could not read the adapter binding; using local-file" >&2
  ADAPTER=local-file
}
[[ "$ADAPTER" != local-file ]] || ADAPTER="$LOCAL"

TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT

if [[ "$VERB" == read ]]; then
  "$ADAPTER/read.sh" ${SINCE[@]+"${SINCE[@]}"} >"$TMP/rows" || exit $?
  if [[ "$ADAPTER" != "$LOCAL" ]]; then
    "$LOCAL/read.sh" ${SINCE[@]+"${SINCE[@]}"} >>"$TMP/rows" || exit $?
  fi
  node "$CORE" dedupe <"$TMP/rows"
  exit $?
fi

command -v python3 >/dev/null 2>&1 || {
  echo "buffer.sh: prerequisite missing: python3" >&2
  exit 3
}
# Redact first, then cap and set obs_id and ts: a row that cannot be redacted is never written.
python3 -I "$HERE/lib/redact_rows.py" >"$TMP/redacted"
RC=$?
if [[ $RC -ne 0 ]]; then
  echo "buffer.sh: redaction failed; nothing appended" >&2
  [[ $RC -eq 2 ]] && exit 2
  exit 1
fi
node "$CORE" prepare <"$TMP/redacted" >"$TMP/rows" || exit $?
[[ -s "$TMP/rows" ]] || exit 0

"$ADAPTER/append.sh" <"$TMP/rows"
RC=$?
if [[ $RC -eq 0 || "$ADAPTER" == "$LOCAL" ]]; then
  exit $RC
fi
echo "buffer.sh: adapter $ADAPTER failed to append (exit $RC); appending to local-file (.work/buffer/) instead" >&2
"$LOCAL/append.sh" <"$TMP/rows"
