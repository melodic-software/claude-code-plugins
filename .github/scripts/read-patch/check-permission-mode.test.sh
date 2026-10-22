#!/usr/bin/env bash
# Tests for check-permission-mode.sh: the requested mode against the mode a
# leg's init message reports.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/check-permission-mode.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILED=0

ok() { printf 'ok - %s\n' "$1"; }
not_ok() {
  printf 'not ok - %s\n' "$1"
  FAILED=1
}
check() {
  if [[ $2 == "$3" ]]; then ok "$1"; else not_ok "$1: expected [$2], got [$3]"; fi
}

init() {
  local path="$TMP/$RANDOM$RANDOM.json"
  printf '[{"type":"system","subtype":"init","permissionMode":"%s"},{"type":"result","subtype":"success"}]' "$1" >"$path"
  printf '%s' "$path"
}
# run REQUESTED EXECUTION_FILE: sets RC and OUT.
run() {
  RC=0
  OUT=$(MODE="$1" EXECUTION_FILE="$2" bash "$CHECK" 2>&1) || RC=$?
}

run dontAsk "$(init dontAsk)"
check 'dontAsk asked, dontAsk reported: passes' 0 "$RC"
run auto "$(init auto)"
check 'auto asked, auto reported: passes' 0 "$RC"
run dontAsk "$(init default)"
check 'dontAsk asked, default reported: passes' 0 "$RC"
run auto "$(init default)"
check 'auto asked, default reported: fails' 1 "$RC"
check 'auto asked, default reported: the error is unchanged' \
  "::error::permission-mode: the leg's init message does not report the mode asked for (auto)" "$OUT"
for reported in bypassPermissions acceptEdits plan auto; do
  run dontAsk "$(init "$reported")"
  check "dontAsk asked, $reported reported: fails" 1 "$RC"
done
run default "$(init dontAsk)"
check 'default asked, dontAsk reported: fails' 1 "$RC"
run dontAsk "$(init '')"
check 'dontAsk asked, empty init mode: fails' 1 "$RC"
printf '[{"type":"system","subtype":"init"}]' >"$TMP/nomode.json"
run dontAsk "$TMP/nomode.json"
check 'dontAsk asked, init without a mode: fails' 1 "$RC"
printf '[{"type":"result","subtype":"success"}]' >"$TMP/noinit.json"
run dontAsk "$TMP/noinit.json"
check 'dontAsk asked, no init message: fails' 1 "$RC"
run dontAsk "$TMP/missing.json"
check 'dontAsk asked, no execution file: fails' 1 "$RC"
printf '{not json' >"$TMP/bad.json"
run dontAsk "$TMP/bad.json"
check 'dontAsk asked, an unreadable file: fails' 1 "$RC"
run '' "$(init '')"
check 'nothing asked, empty init mode: fails' 1 "$RC"

if ((FAILED)); then
  echo 'FAILED' >&2
  exit 1
fi
echo 'all check-permission-mode.sh tests passed'
