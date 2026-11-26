#!/usr/bin/env bash
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

COMMON="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" && [[ -d "$COMMON" ]] || {
  echo "append.sh: not inside a git repository" >&2
  exit 3
}

DIR="$COMMON/findings-buffer"
FILE="$DIR/findings.jsonl"
LOCKDIR="$DIR/.lockdir"
HELD=0
TMP="$(mktemp)" || exit 1
trap 'rm -f "$TMP"; if [[ $HELD -eq 1 ]]; then rm -rf "$LOCKDIR"; fi' EXIT
trap 'exit 1' HUP INT TERM

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

refuse_links() {
  local p
  for p in "$DIR" "$DIR/.lock" "$LOCKDIR" "$FILE"; do
    if [[ -L "$p" ]]; then
      echo "append.sh: $p is a symlink; the buffer must be a plain directory in the git common directory" >&2
      return 1
    fi
  done
}
refuse_links || exit 2
mkdir -p "$DIR" || exit 1
REAL_DIR="$(cd "$DIR" && pwd -P)" && REAL_COMMON="$(cd "$COMMON" && pwd -P)" || exit 1
if [[ "$REAL_DIR" != "$REAL_COMMON/findings-buffer" ]]; then
  echo "append.sh: $DIR resolves outside the git common directory" >&2
  exit 2
fi

write_rows() {
  refuse_links || return 1
  cat "$TMP" >>"$FILE" || return 1
  sync "$FILE" 2>/dev/null || true
}

take_mkdir_lock() {
  local tries=0 holder pending=0
  trap 'pending=1' HUP INT TERM
  until mkdir "$LOCKDIR" 2>/dev/null; do
    if [[ $pending -eq 1 ]]; then
      exit 1
    fi
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
  trap 'exit 1' HUP INT TERM
  if [[ $pending -eq 1 ]]; then
    exit 1
  fi
}

LOCK_WITH="mkdir"
if command -v flock >/dev/null 2>&1; then
  LOCK_WITH="flock"
elif perl -MConfig -MFcntl=:flock -e 'exit !$Config{d_flock}' >/dev/null 2>&1; then
  LOCK_WITH="perl"
fi

lock_fd9() {
  if [[ $LOCK_WITH == flock ]]; then
    flock -x 9
  else
    perl -MFcntl=:flock -e 'open(my $fh, ">>&=", 9) or exit 1; flock($fh, LOCK_EX) or exit 1'
  fi
}

if [[ $LOCK_WITH == mkdir ]]; then
  take_mkdir_lock || exit 1
  write_rows || exit 1
else
  (
    lock_fd9 || {
      echo "append.sh: could not lock $DIR/.lock" >&2
      exit 1
    }
    write_rows
  ) 9>>"$DIR/.lock" || exit 1
fi
exit 0
