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
if declare -F local_metadata_field >/dev/null; then
  pass "source-guard: helpers exposed after source"
else
  fail "source-guard: helpers exposed after source" "function defined" "undefined"
fi

# --- 4. Nested metadata parsing on fixture ----------------------------------------

FIXTURE_SKILL="$TEST_TMPDIR/SKILL.md"
cat >"$FIXTURE_SKILL" <<'EOF'
---
name: thariq-skills
description: "test fixture"
user-invocable: true
metadata:
  upstream-version: 1.0.0
  synced: 2026-03-17
---

# Body
EOF

FRONTMATTER_FILE="$FIXTURE_SKILL"

parsed_ver=$(local_metadata_field "upstream-version")
assert_eq "parses metadata.upstream-version (nested)" "1.0.0" "$parsed_ver"

parsed_synced=$(local_metadata_field "synced")
assert_eq "parses metadata.synced (nested)" "2026-03-17" "$parsed_synced"

# --- 5. Upstream frontmatter version extraction -----------------------------------

FIXTURE_UP="$TEST_TMPDIR/upstream.md"
cat >"$FIXTURE_UP" <<'EOF'
---
name: thariq-skills
description: >
  Guide for designing and authoring Claude Code skills.
version: 1.2.0
date: 2026-08-01
---

# Upstream body
EOF

up_ver=$(upstream_version_from_file "$FIXTURE_UP")
assert_eq "extracts top-level version from upstream frontmatter" "1.2.0" "$up_ver"

# Body-only file (no frontmatter) yields empty.
FIXTURE_NOFM="$TEST_TMPDIR/nofm.md"
printf '# Just a body\nversion: 9.9.9 in prose should not match\n' >"$FIXTURE_NOFM"
nofm_ver=$(upstream_version_from_file "$FIXTURE_NOFM")
assert_eq "no frontmatter returns empty version" "" "$nofm_ver"

# --- 6. replace_metadata_field mutates indented key --------------------------------

FIXTURE_MUT="$TEST_TMPDIR/SKILL-mut.md"
cat >"$FIXTURE_MUT" <<'EOF'
---
name: thariq-skills
metadata:
  upstream-version: 1.0.0
  synced: 2026-03-17
---
EOF

TMPDIR_RUN="$TEST_TMPDIR"
FRONTMATTER_FILE="$FIXTURE_MUT"
replace_metadata_field "upstream-version" "2.0.0"
replace_metadata_field "synced" "2030-01-01"

mutated=$(cat "$FIXTURE_MUT")
assert_contains "upstream-version bumped" "$mutated" "upstream-version: 2.0.0"
assert_contains "synced bumped" "$mutated" "synced: 2030-01-01"
assert_not_contains "old synced removed" "$mutated" "2026-03-17"

# --- 7. file_sha returns empty for missing file -------------------------------------

missing_sha=$(file_sha "$TEST_TMPDIR/does-not-exist.txt")
assert_eq "file_sha returns empty for missing path" "" "$missing_sha"

# --- Final report --------------------------------------------------------------------

rm -rf "$TEST_TMPDIR" "$SOURCED_TMPDIR"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
