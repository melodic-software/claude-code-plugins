#!/usr/bin/env bash
# Regression tests for check-all.sh.
#
# Coverage:
#   - reads check-all-output/registry-snapshot.tsv (header
#     written to OUT regardless of input rows)
#   - per-row gh failure → FETCH_FAILED transition
#   - per-row gh JSON success → OPEN/CLOSED transition computed correctly
#   - empty snapshot → header-only results, exit 0
#   - missing snapshot → exit 1
#
# Uses a per-case fake check-all-output tree and a PATH-stub `gh`.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/check-all.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# Inline test helpers — self-contained, no external test lib (ships with the plugin).
FAILED=0
CASE_NUM=0
pass() { CASE_NUM=$((CASE_NUM + 1)); printf 'PASS: [%d] %s\n' "$CASE_NUM" "$1"; }
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s — expected %q got %q\n' "$CASE_NUM" "$1" "$2" "$3" >&2
  FAILED=$((FAILED + 1))
}
skip_case() { printf 'SKIP: %s\n' "$1" >&2; }
assert_eq() { if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }
assert_exit() { if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1" "exit $2" "exit $3"; fi; }
assert_contains() { if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1" "contains: $3" "$2"; fi; }
assert_not_contains() { if [[ "$2" != *"$3"* ]]; then pass "$1"; else fail "$1" "absent: $3" "$2"; fi; }
assert_file_exists() { if [[ -f "$2" ]]; then pass "$1"; else fail "$1" "file exists: $2" "absent"; fi; }

# Build per-case CWD with snapshot.tsv + PATH-stub gh.
make_case() {
  local case_dir="$1" snapshot_content="$2" gh_mode="$3"
  mkdir -p "$case_dir/check-all-output" "$case_dir/path-stub"
  printf '%s' "$snapshot_content" >"$case_dir/check-all-output/registry-snapshot.tsv"

  case "$gh_mode" in
    fail)
      cat >"$case_dir/path-stub/gh" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
      ;;
    closed)
      cat >"$case_dir/path-stub/gh" <<'STUB'
#!/usr/bin/env bash
echo '{"state":"CLOSED","stateReason":"completed","closedAt":"2026-01-01T00:00:00Z"}'
STUB
      ;;
    open)
      cat >"$case_dir/path-stub/gh" <<'STUB'
#!/usr/bin/env bash
echo '{"state":"OPEN","stateReason":"","closedAt":""}'
STUB
      ;;
  *) ;;
  esac
  chmod +x "$case_dir/path-stub/gh" 2>/dev/null || true
}

# --- Case 1: gh always fails → FETCH_FAILED transition ---
CASE_A="$TEST_TMPDIR/case-a"
make_case "$CASE_A" $'1\texample-org/example-repo\topen\n' fail
(cd "$CASE_A" && CHECK_ALL_OUTPUT_DIR="$CASE_A/check-all-output" PATH="$CASE_A/path-stub:$PATH" bash "$SCRIPT") >/dev/null 2>&1
RC=$?
assert_exit "gh-fail → exit 0" 0 "$RC"
OUT_FILE="$CASE_A/check-all-output/check-all-results.tsv"
assert_file_exists "results.tsv written" "$OUT_FILE"
RESULTS=$(cat "$OUT_FILE")
assert_contains "FETCH_FAILED transition recorded" "$RESULTS" "FETCH_FAILED"

# --- Case 2: tracked=open + state=CLOSED → OPEN->CLOSED transition ---
CASE_B="$TEST_TMPDIR/case-b"
make_case "$CASE_B" $'42\texample-org/example-repo\topen\n' closed
(cd "$CASE_B" && CHECK_ALL_OUTPUT_DIR="$CASE_B/check-all-output" PATH="$CASE_B/path-stub:$PATH" bash "$SCRIPT") >/dev/null 2>&1
RC=$?
assert_exit "open→closed → exit 0" 0 "$RC"
RESULTS=$(cat "$CASE_B/check-all-output/check-all-results.tsv")
assert_contains "OPEN->CLOSED transition" "$RESULTS" "OPEN->CLOSED"

# --- Case 3: tracked=closed + state=OPEN → CLOSED->OPEN transition ---
CASE_C="$TEST_TMPDIR/case-c"
make_case "$CASE_C" $'7\texample-org/example-repo\tclosed\n' open
(cd "$CASE_C" && CHECK_ALL_OUTPUT_DIR="$CASE_C/check-all-output" PATH="$CASE_C/path-stub:$PATH" bash "$SCRIPT") >/dev/null 2>&1
RC=$?
assert_exit "closed→open → exit 0" 0 "$RC"
RESULTS=$(cat "$CASE_C/check-all-output/check-all-results.tsv")
assert_contains "CLOSED->OPEN transition" "$RESULTS" "CLOSED->OPEN"

# --- Case 4: tracked=open + state=OPEN → UNCHANGED ---
CASE_D="$TEST_TMPDIR/case-d"
make_case "$CASE_D" $'5\texample-org/example-repo\topen\n' open
(cd "$CASE_D" && CHECK_ALL_OUTPUT_DIR="$CASE_D/check-all-output" PATH="$CASE_D/path-stub:$PATH" bash "$SCRIPT") >/dev/null 2>&1
RC=$?
assert_exit "unchanged → exit 0" 0 "$RC"
RESULTS=$(cat "$CASE_D/check-all-output/check-all-results.tsv")
assert_contains "UNCHANGED transition" "$RESULTS" "UNCHANGED"

# --- Case 5: empty snapshot → header only, exit 0 ---
CASE_E="$TEST_TMPDIR/case-e"
mkdir -p "$CASE_E/check-all-output"
printf '' >"$CASE_E/check-all-output/registry-snapshot.tsv"
(cd "$CASE_E" && CHECK_ALL_OUTPUT_DIR="$CASE_E/check-all-output" PATH="$CASE_E/path-stub:$PATH" bash "$SCRIPT") >/dev/null 2>&1
RC=$?
assert_exit "empty snapshot → exit 0" 0 "$RC"
RESULTS=$(cat "$CASE_E/check-all-output/check-all-results.tsv")
assert_contains "header present" "$RESULTS" "transition"
assert_not_contains "no FETCH_FAILED on empty input" "$RESULTS" "FETCH_FAILED"
LOG_CONTENT=$(cat "$CASE_E/check-all-output/check-all.log")
assert_contains "log ends DONE" "$LOG_CONTENT" "DONE"

# --- Case 6: missing snapshot → exit 1 ---
CASE_F="$TEST_TMPDIR/case-f"
mkdir -p "$CASE_F/check-all-output"
(cd "$CASE_F" && CHECK_ALL_OUTPUT_DIR="$CASE_F/check-all-output" bash "$SCRIPT") >/dev/null 2>&1
RC=$?
assert_exit "missing snapshot → exit 1" 1 "$RC"

[[ $FAILED -eq 0 ]] || exit 1
echo "All cases passed ($CASE_NUM)."
