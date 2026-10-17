#!/usr/bin/env bash
# Tests for lib/source-bookmarks.sh: a bookmark moves only after a full,
# readable read of its source. Self-contained and cwd-independent.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SB="$SCRIPT_DIR/source-bookmarks.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILED=0
check() { # name expected actual
  if [[ "$2" == "$3" ]]; then
    echo "ok - $1"
  else
    echo "not ok - $1: expected '$2', got '$3'" >&2
    FAILED=1
  fi
}
sb() { bash "$SB" "$1" --data-dir "$TMP" --profile default "${@:2}"; }

check "no bookmark reads as none" none "$(sb get --source vendor-a)"
check "full data read advances" advanced "$(sb advance --source vendor-a --state data --read full --at 2026-10-10)"
check "bookmark is stored" 2026-10-10 "$(sb get --source vendor-a)"
check "partial read leaves the bookmark" unchanged "$(sb advance --source vendor-a --state data --read partial --at 2026-10-17)"
check "partial read keeps the date" 2026-10-10 "$(sb get --source vendor-a)"
check "unreadable source leaves the bookmark" unchanged "$(sb advance --source vendor-a --state unreadable --read full --at 2026-10-17)"
check "unreadable keeps the date" 2026-10-10 "$(sb get --source vendor-a)"
check "unreadable first read creates nothing" unchanged "$(sb advance --source vendor-b --state unreadable --read partial --at 2026-10-17)"
check "no file for the failed source" none "$(sb get --source vendor-b)"
check "full empty read advances" advanced "$(sb advance --source vendor-a --state empty --read full --at 2026-10-17)"
check "empty read moved the date" 2026-10-17 "$(sb get --source vendor-a)"
check "sources are independent" none "$(sb get --source vendor-b)"

printf 'garbage\n' >"$TMP/default/bookmarks/vendor-c"
check "unparsable bookmark reads as none" none "$(sb get --source vendor-c)"

ln -s "$TMP/elsewhere" "$TMP/default/bookmarks/vendor-d"
sb advance --source vendor-d --state data --read full --at 2026-10-17 >/dev/null 2>&1
check "symlinked bookmark refused (exit 1)" 1 "$?"
[[ ! -e "$TMP/elsewhere" ]]
check "symlink target untouched" 0 "$?"

sb get --source '../x' >/dev/null 2>&1
check "path traversal source refused (exit 2)" 2 "$?"
sb advance --source vendor-a --state data --read full --at tomorrow >/dev/null 2>&1
check "bad date refused (exit 2)" 2 "$?"

sb advance --source vendor-a --state data --read full --at 2026-13-45 >/dev/null 2>&1
check "impossible date refused (exit 2)" 2 "$?"
sb advance --source vendor-a --state data --read full --at 2026-02-29 >/dev/null 2>&1
check "February 29 of a common year refused (exit 2)" 2 "$?"
check "February 29 of a leap year advances" advanced "$(sb advance --source vendor-a --state data --read full --at 2028-02-29)"

exit "$FAILED"
