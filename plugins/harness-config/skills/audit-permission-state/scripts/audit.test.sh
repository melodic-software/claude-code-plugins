#!/usr/bin/env bash
# Regression tests for audit.sh (self-contained — ships with the plugin).
#
# audit.sh composes the stage scripts; it owns no checks of its own. These tests
# cover what composition can get wrong: running the inventory more than once,
# widening the default past read-only, firing a priced lane nobody asked for, and
# swallowing a stage's readability record on the way through.
#
# Stage behavior itself belongs to each stage's own suite. Nothing here asserts a
# finding.
# test-scope: .claude/settings.json
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/audit.sh"

# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help names the read-only default" "$OUT" "every read-only stage"
assert_contains "--help prices the oracle" "$OUT" "SPAWNS A REAL"
assert_contains "--help warns about critique" "$OUT" "truncate or return nothing"

rc=0
ERR=$(bash "$SCRIPT" --not-a-flag 2>&1) || rc=$?
assert_exit "an unknown argument exits 2" 2 "$rc"
assert_contains "and names the argument" "$ERR" "--not-a-flag"

rc=0
OUT=$(bash "$SCRIPT") || rc=$?
assert_exit "a bare run exits 0" 0 "$rc"
assert_contains "the default runs the inventory" "$OUT" "===== Scopes and surfaces ====="
assert_contains "the default runs the merge" "$OUT" "===== Effective set ====="
assert_contains "the default runs the entry diff" "$OUT" "===== Auto-mode entry diff ====="
assert_contains "the default runs the plane lint" "$OUT" "===== Permission-plane lint ====="
assert_contains "the default runs managed conformance" "$OUT" "===== Managed conformance ====="
assert_contains "the default runs the block lint" "$OUT" "===== autoMode block lint ====="

assert_contains "the merge summarized" "$OUT" "merge summary"
assert_contains "the entry diff summarized" "$OUT" "entry-diff summary"
assert_contains "the plane lint summarized" "$OUT" "lint summary"
assert_contains "managed conformance summarized" "$OUT" "managed conformance summary"
assert_contains "the block lint summarized" "$OUT" "automode summary"

assert_eq "the inventory ran exactly once" 1 "$(count_matching "$OUT" 'NOTE: local scope anchored')"

OUT_SCOPES=$(bash "$SCRIPT" --scopes)
assert_contains "--scopes runs the inventory" "$OUT_SCOPES" "===== Scopes and surfaces ====="
assert_not_contains "--scopes stops before the merge" "$OUT_SCOPES" "===== Effective set ====="
assert_not_contains "--scopes stops before the lint" "$OUT_SCOPES" "===== Permission-plane lint ====="

OUT_LINT=$(bash "$SCRIPT" --lint)
assert_contains "--lint runs the lint" "$OUT_LINT" "lint summary"
assert_not_contains "--lint does not run the entry diff" "$OUT_LINT" "entry-diff summary"
assert_not_contains "--lint does not run managed conformance" "$OUT_LINT" "managed conformance summary"

OUT_MANAGED=$(bash "$SCRIPT" --managed)
assert_contains "--managed runs managed conformance" "$OUT_MANAGED" "managed conformance summary"
assert_not_contains "--managed does not run the lint" "$OUT_MANAGED" "lint summary"

OUT_BLOCK=$(bash "$SCRIPT" --block)
assert_contains "--block runs the block lint" "$OUT_BLOCK" "automode summary"
assert_not_contains "--block skips the inventory entirely" "$OUT_BLOCK" "===== Scopes and surfaces ====="

assert_not_contains "the default names no oracle section" "$OUT" "oracle"
assert_not_contains "the default names no critique section" "$OUT" "critique"

assert_contains "the entry diff keeps its status token" "$OUT" "entry-diff summary allow_before="
assert_contains "the plane lint keeps its status token" "$OUT" "checks_run=12 status="
assert_contains "the diff keeps its own DIFF-NOTE records" "$OUT" "DIFF-NOTE:"

STUB_DIR="$(mktemp -d)"
trap 'rm -rf "$STUB_DIR"' EXIT
for real in "$SCRIPT_DIR"/*.sh; do
  case "$(basename "$real")" in
  *.test.sh) continue ;;
  *) cp "$real" "$STUB_DIR/" ;;
  esac
done
cat >"$STUB_DIR/permission-state.sh" <<'STUB'
#!/usr/bin/env bash
echo "ERROR: jq required" >&2
exit 2
STUB

rc=0
OUT_FAIL=$(bash "$STUB_DIR/audit.sh" 2>/dev/null) || rc=$?
assert_exit "a failed inventory propagates its exit status" 2 "$rc"
assert_not_contains "and no stage output is printed" "$OUT_FAIL" "====="

rc=0
ERR_FAIL=$(bash "$STUB_DIR/audit.sh" 2>&1 >/dev/null) || rc=$?
assert_contains "the error names the real status, not 0" "$ERR_FAIL" "failed (exit 2)"

report_and_exit
