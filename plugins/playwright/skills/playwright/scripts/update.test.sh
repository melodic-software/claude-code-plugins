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
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "absent: $3" "present" ;;
  *) pass "$1" ;;
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
assert_contains "--help mentions vendor" "$help_out" "vendor"

help_out_short=$(bash "$SCRIPT" -h 2>&1)
short_exit=$?
assert_exit "-h exits 0" 0 "$short_exit"
if [[ -n "$help_out_short" ]]; then
  pass "-h emits non-empty stdout"
else
  fail "-h emits non-empty stdout" "non-empty" "empty"
fi

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
if declare -F read_metadata_field >/dev/null; then
  pass "source-guard: helpers exposed after source"
else
  fail "source-guard: helpers exposed after source" "function defined" "undefined"
fi

# --- 4. Frontmatter parsing on fixture --------------------------------------------

FIXTURE_SKILL="$TEST_TMPDIR/SKILL.md"
cat >"$FIXTURE_SKILL" <<'EOF'
---
name: playwright
description: "test fixture"
user-invocable: true
metadata:
  source: https://example.com/repo
  upstream-package: "@playwright/cli"
  upstream-version: 0.1.13
  upstream-sha: abc123def456
  synced: 2026-05-22
---

# Body
EOF

FRONTMATTER_FILE="$FIXTURE_SKILL"

parsed_ver=$(read_metadata_field "upstream-version")
assert_eq "parses metadata.upstream-version (nested)" "0.1.13" "$parsed_ver"

parsed_sha=$(read_metadata_field "upstream-sha")
assert_eq "parses metadata.upstream-sha (nested)" "abc123def456" "$parsed_sha"

parsed_synced=$(read_metadata_field "synced")
assert_eq "parses metadata.synced (nested)" "2026-05-22" "$parsed_synced"

# --- 5. Negative parse: missing metadata block -------------------------------------

FIXTURE_BARE="$TEST_TMPDIR/SKILL-bare.md"
cat >"$FIXTURE_BARE" <<'EOF'
---
name: bare
description: "no metadata block"
---

# Body
EOF

FRONTMATTER_FILE="$FIXTURE_BARE"
empty_ver=$(read_metadata_field "upstream-version")
assert_eq "missing metadata block returns empty" "" "$empty_ver"

# --- 6. Key-anchored parse: similar key names don't collide -------------------------

FIXTURE_KEYS="$TEST_TMPDIR/SKILL-keys.md"
cat >"$FIXTURE_KEYS" <<'EOF'
---
name: playwright
metadata:
  upstream-sha: sha-value
  upstream-version: 2.0.0
---
EOF

FRONTMATTER_FILE="$FIXTURE_KEYS"
keyed_ver=$(read_metadata_field "upstream-version")
assert_eq "upstream-version does not match upstream-sha row" "2.0.0" "$keyed_ver"

# --- 7. replace_metadata_field mutates indented key ---------------------------------

FIXTURE_MUT="$TEST_TMPDIR/SKILL-mut.md"
cat >"$FIXTURE_MUT" <<'EOF'
---
name: playwright
metadata:
  upstream-version: 1.0.0
  upstream-sha: oldsha
  synced: 2025-01-01
---
EOF

TMPDIR_RUN="$TEST_TMPDIR"
FRONTMATTER_FILE="$FIXTURE_MUT"
replace_metadata_field "upstream-version" "9.9.9"
replace_metadata_field "upstream-sha" "newsha"
replace_metadata_field "synced" "2030-12-31"

mutated=$(cat "$FIXTURE_MUT")
assert_contains "upstream-version bumped" "$mutated" "upstream-version: 9.9.9"
assert_contains "upstream-sha bumped" "$mutated" "upstream-sha: newsha"
assert_contains "synced bumped" "$mutated" "synced: 2030-12-31"
assert_not_contains "old upstream-version removed" "$mutated" "1.0.0"
assert_not_contains "old upstream-sha removed" "$mutated" "oldsha"
assert_not_contains "old synced removed" "$mutated" "2025-01-01"

# --- 8. Live SKILL.md parses (guards frontmatter/script contract drift) -------------

FRONTMATTER_FILE="$(cd "$SCRIPT_DIR/.." && pwd)/SKILL.md"
live_ver=$(read_metadata_field "upstream-version")
if [[ -n "$live_ver" ]]; then
  pass "live SKILL.md exposes metadata.upstream-version ($live_ver)"
else
  fail "live SKILL.md exposes metadata.upstream-version" "non-empty" "empty"
fi

# --- Final report ---------------------------------------------------------------------

rm -rf "$TEST_TMPDIR" "$SOURCED_TMPDIR"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
