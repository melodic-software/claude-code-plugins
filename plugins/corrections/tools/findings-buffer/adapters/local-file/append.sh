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
# Remove the lock only while its pid file still holds this process's pid.
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

[[ -s "$TMP" ]] || exit 0

# refuse_links: the buffer stays a plain directory inside the repository, so a
# symlink can never redirect rows (or the lock file) elsewhere.
refuse_links() {
  local p
  for p in "$ROOT/.work" "$DIR" "$DIR/.lock" "$LOCKDIR" "$FILE"; do
    if [[ -L "$p" ]]; then
      echo "append.sh: $p is a symlink; the buffer must be a plain directory in the repository" >&2
      return 1
    fi
  done
}
refuse_links || exit 2
if [[ ! -d "$DIR" ]]; then
  mkdir -p "$DIR" || exit 1
  # Rows never leave the machine: keep the buffer out of git.
  printf '*\n' >"$DIR/.gitignore" || exit 1
fi
REAL_DIR="$(cd "$DIR" && pwd -P)" && REAL_ROOT="$(cd "$ROOT" && pwd -P)" || exit 1
if [[ "$REAL_DIR" != "$REAL_ROOT/.work/buffer" ]]; then
  echo "append.sh: $DIR resolves outside the repository" >&2
  exit 2
fi

write_rows() {
  refuse_links || return 1
  cat "$TMP" >>"$FILE" || return 1
  sync "$FILE" 2>/dev/null || true
}

# take_mkdir_lock: mkdir is atomic, and the holder writes its pid inside the lock.
# There is no automatic takeover: a lock whose holder pid is dead fails at once, and
# a live holder that keeps it past the wait fails too, each naming the lock dir.
take_mkdir_lock() {
  local tries=0 holder
  until mkdir "$LOCKDIR" 2>/dev/null; do
    holder="$(cat "$LOCKDIR/pid" 2>/dev/null)"
    if [[ -n "$holder" ]] && ! kill -0 "$holder" 2>/dev/null; then
      echo "append.sh: buffer lock $LOCKDIR is stale (holder pid $holder is not running); remove it and retry" >&2
      return 1
    fi
    tries=$((tries + 1))
    if [[ $tries -gt 600 ]]; then
      echo "append.sh: could not take the buffer lock $LOCKDIR (holder pid ${holder:-unknown}); if no append is running, remove it and retry" >&2
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
  ) 9>>"$DIR/.lock" || exit 1
else
  take_mkdir_lock || exit 1
  write_rows || exit 1
fi
exit 0
