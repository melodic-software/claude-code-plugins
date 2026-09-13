#!/usr/bin/env bash
# Self-contained tests for inventory.sh, driven against the committed fixture
# tree in fixtures/tree via fixtures/build-fixture.sh.
#
# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/inventory.sh"
BUILD="$SCRIPT_DIR/fixtures/build-fixture.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASES=0

pass() {
  CASES=$((CASES + 1))
  printf 'PASS: %s\n' "$1"
}

fail() {
  CASES=$((CASES + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}

assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}

assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$2" ;;
  esac
}

assert_lacks() {
  case "$2" in
  *"$3"*) fail "$1" "does not contain: $3" "$2" ;;
  *) pass "$1" ;;
  esac
}

new_fixture() {
  d="$TEST_TMPDIR/fx-$CASES-$RANDOM"
  bash "$BUILD" "$d" ${1:+--variant "$1"} >/dev/null
  printf '%s' "$d"
}

# --- the clean fixture -------------------------------------------------------

root="$(new_fixture)"
out="$(bash "$SUT" --root "$root")"

assert_eq "three offenders are found" "3" "$(printf '%s\n' "$out" | grep -c '^OFFENDER')"
assert_contains "an UPPER-KEBAB name is proposed in lower kebab" "$out" "OFFENDER	docs/Alpha-One.md	docs/alpha-one.md"
assert_contains "an all-caps name is proposed in lower kebab" "$out" "OFFENDER	docs/BETA.md	docs/beta.md"
assert_contains "an underscore becomes a hyphen" "$out" "OFFENDER	docs/Gamma_Three.md	docs/gamma-three.md"

assert_contains "a conventional uppercase basename is exempt" "$out" "EXEMPT	docs/README.md	exempt_basenames"
assert_contains "the contract slice is exempt by path" "$out" "EXEMPT	docs/topics/t/PLAN.md	exempt_paths"
assert_contains "a code file is exempt by extension" "$out" "EXEMPT	docs/tool.py	exempt_extensions"

assert_lacks "an already-legal dotted stem is not an offender" "$out" "docs/v1.2.schema.json	docs/"
assert_lacks "a legal historical record is not an offender" "$out" "OFFENDER	docs/adr/0001-historical.md"
assert_eq "no collision is reported on the clean tree" "0" "$(printf '%s\n' "$out" | grep -c '^COLLISION')"
assert_contains "the scanned count and roots are reported" "$out" "SCANNED	8	docs"

# --- read-only ---------------------------------------------------------------

assert_eq "the tree is byte-identical after an inventory" "" "$(git -C "$root" status --porcelain)"

# --- the collision variant ---------------------------------------------------

root="$(new_fixture collision)"
out="$(bash "$SUT" --root "$root")"
assert_contains "a proposal colliding with an existing path is reported" "$out" "COLLISION	docs/beta.md	docs/beta.md"
assert_eq "no offender is proposed while a collision stands" "0" "$(printf '%s\n' "$out" | grep -c '^OFFENDER')"
assert_eq "a collision still exits 0: it is a finding, not a crash" "0" "$(
  bash "$SUT" --root "$root" >/dev/null 2>&1
  printf '%s' "$?"
)"

# --- configuration is read, never assumed ------------------------------------

root="$(new_fixture)"
jq '.file_names.exempt_basenames = ["README.md"] | .file_names.exempt_extensions = []' \
  "$root/.claude/docs-hygiene.json" >"$root/.claude/t.json"
mv "$root/.claude/t.json" "$root/.claude/docs-hygiene.json"
out="$(bash "$SUT" --root "$root")"
assert_lacks "an extension dropped from the config is no longer exempt" "$out" "EXEMPT	docs/tool.py"

root="$(new_fixture)"
jq '.file_names.roots = ["build"]' "$root/.claude/docs-hygiene.json" >"$root/.claude/t.json"
mv "$root/.claude/t.json" "$root/.claude/docs-hygiene.json"
out="$(bash "$SUT" --root "$root")"
assert_eq "a different root inventories a different tree" "0" "$(printf '%s\n' "$out" | grep -c '^OFFENDER')"
assert_contains "the reported roots follow the configuration" "$out" "SCANNED	1	build"

# --- an explicit --config file -----------------------------------------------

root="$(new_fixture)"
out="$(bash "$SUT" --root "$root" --config "$SCRIPT_DIR/fixtures/config.json")"
assert_eq "an explicit --config resolves the same three offenders" "3" "$(printf '%s\n' "$out" | grep -c '^OFFENDER')"

# --- usage and environment ---------------------------------------------------

assert_eq "--help exits 0" "0" "$(
  bash "$SUT" --help >/dev/null 2>&1
  printf '%s' "$?"
)"
assert_eq "an unknown argument exits 2" "2" "$(
  bash "$SUT" --frobnicate >/dev/null 2>&1
  printf '%s' "$?"
)"
assert_eq "a root that is not a git repository exits 2" "2" "$(
  bash "$SUT" --root "$TEST_TMPDIR" >/dev/null 2>&1
  printf '%s' "$?"
)"

root="$(new_fixture)"
jq '.file_names.rule = "SCREAMING_SNAKE"' "$root/.claude/docs-hygiene.json" >"$root/.claude/t.json"
mv "$root/.claude/t.json" "$root/.claude/docs-hygiene.json"
assert_eq "an unimplemented rule exits 2 rather than guessing" "2" "$(
  bash "$SUT" --root "$root" >/dev/null 2>&1
  printf '%s' "$?"
)"

printf '\nPASS=%d FAIL=%d\n' "$((CASES - FAILED))" "$FAILED"
[[ "$FAILED" -eq 0 ]] || exit 1
