#!/usr/bin/env bash
# Black-box contract test for packet-prune.sh.
#
# Self-contained and cwd-independent; mutates only its own mktemp dir.
#
# The cases that matter are the ones where a wrong answer destroys the
# deliverable: an old packet holding `item.md` must survive `--apply`, a bare
# invocation must delete nothing, and a root that is not an evidence tree must
# be refused before anything is walked.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/packet-prune.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

OLD="19990101T000000Z"
NEW="$(date -u +%Y%m%dT%H%M%SZ)"

# fresh_tree — rebuild a known evidence tree, echo its root.
fresh_tree() {
  local root="$WORK/data/evidence"
  rm -rf "$WORK/data"
  mkdir -p "$root/sess-1/plugin-a-skill/$OLD" \
    "$root/sess-1/plugin-a-skill/$NEW" \
    "$root/sess-1/plugin-b-hook/$OLD" \
    "$root/sess-2/plugin-c/not-a-nonce"
  : >"$root/sess-1/plugin-a-skill/$OLD/audit-notes.md"
  : >"$root/sess-1/plugin-a-skill/$NEW/audit-notes.md"
  : >"$root/sess-1/plugin-b-hook/$OLD/audit-notes.md"
  : >"$root/sess-1/plugin-b-hook/$OLD/item.md"
  : >"$root/sess-2/plugin-c/not-a-nonce/audit-notes.md"
  printf '%s' "$root"
}

# run <expected-exit> <label> [args...] — echoes captured output for reuse.
last_out=""
run() {
  local expected="$1" label="$2"
  shift 2
  local actual
  last_out="$(bash "$SUT" "$@" 2>&1)"
  actual=$?
  if [[ "$actual" -eq "$expected" ]]; then
    pass "$label (exit $actual)"
  else
    fail "$label — expected exit $expected, got $actual: $last_out"
  fi
}

has() {
  if [[ "$last_out" == *"$1"* ]]; then
    pass "$2"
  else
    fail "$2 — output was: $last_out"
  fi
}

# --- dry run is the default -------------------------------------------------

root="$(fresh_tree)"
run 0 "bare invocation runs" --root "$root"
has "WOULD-DELETE" "old packet is reported as a would-delete"
has "(dry run" "dry run is announced"
if [[ -e "$root/sess-1/plugin-a-skill/$OLD/audit-notes.md" ]]; then
  pass "dry run deleted nothing"
else
  fail "dry run DELETED a packet — the default must never mutate"
fi

# --- the deliverable safeguard ----------------------------------------------

root="$(fresh_tree)"
run 0 "apply runs" --root "$root" --apply
has "RETAIN-ITEM" "a packet holding item.md is reported as retained"
if [[ -e "$root/sess-1/plugin-b-hook/$OLD/item.md" ]]; then
  pass "an OLD packet holding item.md survives --apply"
else
  fail "--apply DELETED an unemitted item.md — the one thing retention must never destroy"
fi
if [[ ! -e "$root/sess-1/plugin-a-skill/$OLD" ]]; then
  pass "an old packet without item.md is deleted under --apply"
else
  fail "--apply did not delete an expired packet"
fi
if [[ -e "$root/sess-1/plugin-a-skill/$NEW/audit-notes.md" ]]; then
  pass "a packet inside the window survives --apply"
else
  fail "--apply deleted a packet inside the retention window"
fi

# --- fail closed on an ungradable nonce -------------------------------------

if [[ -e "$root/sess-2/plugin-c/not-a-nonce/audit-notes.md" ]]; then
  pass "a directory whose name is not a nonce is never deleted"
else
  fail "--apply deleted a directory it could not grade the age of"
fi
has "UNPARSABLE" "an ungradable directory is reported, not silently kept"

# --- root containment -------------------------------------------------------

mkdir -p "$WORK/not-evidence/sess/slug/$OLD"
run 2 "a root not named 'evidence' is refused" --root "$WORK/not-evidence"
has "refusing to prune" "the refusal names its reason"
if [[ -e "$WORK/not-evidence/sess/slug/$OLD" ]]; then
  pass "the refused root was not walked"
else
  fail "a refused root was still pruned"
fi

run 2 "a missing root is a usage error" --root "$WORK/no-such-dir"
run 2 "--root is required" --days 5
run 2 "a non-numeric --days is refused" --root "$(fresh_tree)" --days thirty
run 2 "an unknown argument is refused" --root "$(fresh_tree)" --wipe
run 0 "--help exits clean" --help

# --- --days 0 expires everything except the protected packet ----------------

root="$(fresh_tree)"
run 0 "--days 0 runs" --root "$root" --days 0 --apply
if [[ -e "$root/sess-1/plugin-b-hook/$OLD/item.md" ]]; then
  pass "item.md survives even at --days 0"
else
  fail "--days 0 destroyed an unemitted item.md"
fi

echo
if [[ $fails -eq 0 ]]; then
  echo "all packet-prune.sh contract tests passed"
  exit 0
fi
echo "$fails packet-prune.sh contract test(s) failed" >&2
exit 1
