#!/usr/bin/env bash
# Self-contained regression tests for update.sh (no external test lib — ships
# with the plugin; network-free: exercises help, arg handling, and the sourced
# helper functions against local fixtures only).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/update.sh"
TEST_TMPDIR="$(mktemp -d)"

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "exit $2" "exit $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$2" ;;
  esac
}

# --- 1. --help contract --------------------------------------------------------

help_out=$(bash "$SCRIPT" --help 2>&1)
help_exit=$?
assert_exit "--help exits 0" 0 "$help_exit"
if [[ -n "$help_out" ]]; then
  pass "--help emits non-empty stdout"
else
  fail "--help emits non-empty stdout" "non-empty" "empty"
fi
assert_contains "--help mentions --check" "$help_out" "--check"
assert_contains "--help mentions --apply" "$help_out" "--apply"
assert_contains "--help mentions UPSTREAM" "$help_out" "UPSTREAM"

help_out_short=$(bash "$SCRIPT" -h 2>&1)
short_exit=$?
assert_exit "-h exits 0" 0 "$short_exit"
assert_contains "-h mentions --check" "$help_out_short" "--check"

# --- 2. Unknown flag handling ----------------------------------------------------

unknown_out=$(bash "$SCRIPT" --bogus-flag 2>&1)
unknown_exit=$?
assert_exit "unknown flag exits 2" 2 "$unknown_exit"
assert_contains "unknown flag mentions expected modes" "$unknown_out" "expected"

# --- 3. Source-guard: helpers callable when sourced ------------------------------

# Sourcing installs the script's own EXIT trap (cleanup of its TMPDIR_RUN); the
# test tmpdir is removed explicitly at the end instead of via trap.
# shellcheck source=update.sh
source "$SCRIPT" 2>/dev/null
SOURCED_TMPDIR="$TMPDIR_RUN"
if declare -F recorded_field >/dev/null; then
  pass "source-guard: helpers exposed after source"
else
  fail "source-guard: helpers exposed after source" "function defined" "undefined"
fi

# --- 4. recorded_field parses UPSTREAM.md fixture ----------------------------------

FIXTURE_UP="$TEST_TMPDIR/UPSTREAM.md"
cat >"$FIXTURE_UP" <<'EOF'
# Firecrawl skill upstream sync state

- Last sync: 2026-05-22
- Upstream SHA256: abc123def456
- CLI version at sync: 1.18.0
- Previous CLI version (rollback target): 1.16.0
EOF

UPSTREAM_MD="$FIXTURE_UP"
parsed_sha=$(recorded_upstream_sha)
assert_eq "parses recorded Upstream SHA256" "abc123def456" "$parsed_sha"
parsed_ver=$(recorded_cli_version)
assert_eq "parses recorded CLI version" "1.18.0" "$parsed_ver"

# Missing file yields empty, not an error.
UPSTREAM_MD="$TEST_TMPDIR/does-not-exist.md"
missing=$(recorded_upstream_sha)
assert_eq "missing UPSTREAM.md returns empty" "" "$missing"

# --- 5. rewrite_upstream_md writes the full record ----------------------------------

UPSTREAM_MD="$TEST_TMPDIR/UPSTREAM-out.md"
rewrite_upstream_md "deadbeef" "2.0.0" "1.18.0"
written=$(cat "$UPSTREAM_MD")
assert_contains "record has SHA" "$written" "Upstream SHA256: deadbeef"
assert_contains "record has version" "$written" "CLI version at sync: 2.0.0"
assert_contains "record has rollback target" "$written" "rollback target): 1.18.0"

# --- 6. sha256 helper matches a direct call ------------------------------------------

echo "firecrawl test" >"$TEST_TMPDIR/sha-fixture.txt"
sha_via_helper=$(sha256 "$TEST_TMPDIR/sha-fixture.txt" | awk '{print $1}' | tr -d '\r')
if command -v sha256sum >/dev/null 2>&1; then
  sha_direct=$(sha256sum "$TEST_TMPDIR/sha-fixture.txt" | awk '{print $1}' | tr -d '\r')
else
  sha_direct=$(shasum -a 256 "$TEST_TMPDIR/sha-fixture.txt" | awk '{print $1}' | tr -d '\r')
fi
assert_eq "sha256 helper matches direct call" "$sha_direct" "$sha_via_helper"

# --- Final report ---------------------------------------------------------------------

rm -rf "$TEST_TMPDIR" "$SOURCED_TMPDIR"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
