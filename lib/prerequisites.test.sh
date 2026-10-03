#!/usr/bin/env bash
# Owns lib/prerequisites.test.mjs for the plugin test lane, then tests the sh and
# pwsh stubs: with node absent each prints one fixed line and exits 1; with node
# present each hands its arguments and exit code to prerequisites.mjs.
# scripts/run-outside-node-suites.sh treats a sibling .test.sh as the runner.
set -uo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
node --test "$LIB/prerequisites.test.mjs" || exit 1

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n' "$1" >&2
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
EMPTY="$WORK/empty-path"
mkdir -p "$EMPTY"
EXPECTED='prerequisites: node was not found on PATH, so no prerequisite was checked. Install Node.js from https://nodejs.org/en/download, then run this check again.'
SH="$(command -v sh)"

out="$(PATH="$EMPTY" "$SH" "$LIB/prerequisites.sh" check "$WORK")"
rc=$?
if [[ "$rc" -eq 1 && "$out" == "$EXPECTED" ]]; then
  pass "sh stub: node absent prints the fixed line and exits 1"
else
  fail "sh stub: node absent gave rc=$rc out=$out"
fi

"$SH" "$LIB/prerequisites.sh" >/dev/null 2>&1
rc=$?
if [[ "$rc" -eq 2 ]]; then
  pass "sh stub: node present passes the checker's usage exit through"
else
  fail "sh stub: node present gave rc=$rc, want 2"
fi

out="$("$SH" "$LIB/prerequisites.sh" check "$WORK")"
rc=$?
if [[ "$rc" -eq 0 && "$out" == *"declares no external dependency"* ]]; then
  pass "sh stub: node present passes the arguments through"
else
  fail "sh stub: node present gave rc=$rc out=$out"
fi

if PWSH="$(command -v pwsh)"; then
  out="$(PATH="$EMPTY" "$PWSH" -NoProfile -NonInteractive -File "$LIB/prerequisites.ps1" check "$WORK")"
  rc=$?
  out="${out%$'\r'}"
  if [[ "$rc" -eq 1 && "$out" == "$EXPECTED" ]]; then
    pass "pwsh stub: node absent prints the fixed line and exits 1"
  else
    fail "pwsh stub: node absent gave rc=$rc out=$out"
  fi
  out="$("$PWSH" -NoProfile -NonInteractive -File "$LIB/prerequisites.ps1" check "$WORK")"
  rc=$?
  if [[ "$rc" -eq 0 && "$out" == *"declares no external dependency"* ]]; then
    pass "pwsh stub: node present passes the arguments and exit code through"
  else
    fail "pwsh stub: node present gave rc=$rc out=$out"
  fi
else
  printf 'NOTE: pwsh is not on PATH; the pwsh stub cases did not run.\n'
fi

if [[ "$FAILED" -gt 0 ]]; then
  printf '%d stub case(s) failed\n' "$FAILED" >&2
  exit 1
fi
