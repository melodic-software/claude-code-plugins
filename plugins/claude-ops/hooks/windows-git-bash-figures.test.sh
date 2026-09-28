#!/usr/bin/env bash
# The figures script must refuse a non-Windows host. A Linux timing is not
# the evidence #3757 asks for.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HOOK_DIR/windows-git-bash-figures.sh"
pass=0
fail=0
ok() { echo "ok: $*"; pass=$((pass + 1)); }
bad() { echo "FAIL: $*" >&2; fail=$((fail + 1)); }

uname_s="$(uname -s 2>/dev/null || true)"
case "$uname_s" in
MINGW* | MSYS* | CYGWIN*)
  out="$(bash "$SCRIPT")"
  status=$?
  if [[ "$status" -eq 0 ]] && printf '%s\n' "$out" | grep -q '^FIGURE kill_switch_ms='; then
    ok "Windows Git Bash run printed figures"
  else
    bad "Windows run status=$status output=$out"
  fi
  ;;
*)
  out="$(bash "$SCRIPT" 2>&1)"
  status=$?
  if [[ "$status" -eq 2 ]] && ! printf '%s\n' "$out" | grep -q '^FIGURE '; then
    ok "non-Windows host exits 2 and prints no figure"
  else
    bad "expected exit 2 and no FIGURE line, got status=$status output=$out"
  fi
  ;;
esac

echo "PASS=$pass FAIL=$fail"
[[ "$fail" -eq 0 ]]
