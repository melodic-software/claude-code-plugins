#!/usr/bin/env bash
# local-file findings buffer: append.sh < rows.jsonl
# Stores each row in .work/buffer/findings.jsonl under the repository root.
# Exit: 0 every row durable, 1 storage failure, 2 usage, 3 not in a repository or jq missing.
set -uo pipefail

if [[ $# -gt 0 ]]; then
  echo "usage: append.sh < rows.jsonl (takes no arguments)" >&2
  exit 2
fi

command -v jq >/dev/null 2>&1 || {
  echo "append.sh: prerequisite missing: jq" >&2
  exit 3
}

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "append.sh: not inside a git repository" >&2
  exit 3
}

DIR="$ROOT/.work/buffer"
FILE="$DIR/findings.jsonl"
LOCKDIR="$DIR/.lockdir"
HELD=0
TMP="$(mktemp)" || exit 1
# Remove the lock only while it is still ours: a taker may have moved it aside.
trap 'rm -f "$TMP"; if [[ $HELD -eq 1 && "$(cat "$LOCKDIR/pid" 2>/dev/null)" == "$$" ]]; then rm -rf "$LOCKDIR"; fi' EXIT
trap 'exit 1' HUP INT TERM

# Validate every line first, so a malformed row stores nothing from this call.
# One program over all lines (-n with inputs): jq's exit status reflects only the
# last input when each line is its own program, so an early bad line would pass.
if ! jq -nRc '
  [inputs | select(test("[^[:space:]]"))
    | (try fromjson catch error("not JSON"))
    | if type == "object" and (.obs_id | type) == "string" and (.ts | type) == "string"
      then . else error("not a row") end]
  | .[]' >"$TMP" 2>/dev/null; then
  echo "append.sh: each row must be one JSON object with string obs_id and ts" >&2
  exit 2
fi

mkdir -p "$DIR" || exit 1
[[ -s "$TMP" ]] || exit 0

write_rows() {
  cat "$TMP" >>"$FILE" || return 1
  sync "$FILE" 2>/dev/null || true
}

# lock_is_stale <dir>: its holder pid is no longer alive, or it has no pid and is
# over a minute old.
lock_is_stale() {
  local holder
  holder="$(cat "$1/pid" 2>/dev/null)"
  if [[ -n "$holder" ]]; then
    ! kill -0 "$holder" 2>/dev/null
  else
    [[ -n "$(find "$1" -maxdepth 0 -mmin +1 2>/dev/null)" ]]
  fi
}

# take_mkdir_lock: mkdir is atomic. The holder writes its pid inside the lock. A
# stale lock is taken over by renaming it aside, which only one taker can do; the
# taker re-checks the moved lock and renames it back if its holder is alive (a
# second taker that moved a lock just retaken), so a killed appender never wedges
# later ones and a live lock is never removed.
take_mkdir_lock() {
  local tries=0 aside="$LOCKDIR.stale.$$"
  until mkdir "$LOCKDIR" 2>/dev/null; do
    if lock_is_stale "$LOCKDIR" && mv "$LOCKDIR" "$aside" 2>/dev/null; then
      if lock_is_stale "$aside"; then
        rm -rf "$aside"
      else
        # Its holder is alive: put it back. When a new lock took the name meanwhile,
        # mv nests it inside that one, whose holder removes both; then retry.
        mv "$aside" "$LOCKDIR" 2>/dev/null
      fi
      continue
    fi
    tries=$((tries + 1))
    if [[ $tries -gt 600 ]]; then
      echo "append.sh: could not take the buffer lock" >&2
      return 1
    fi
    sleep 0.05
  done
  HELD=1
  printf '%s\n' "$$" >"$LOCKDIR/pid"
}

if command -v flock >/dev/null 2>&1; then
  (
    flock -x 9 || exit 1
    write_rows
  ) 9>"$DIR/.lock" || exit 1
else
  take_mkdir_lock || exit 1
  write_rows || exit 1
fi
exit 0
