#!/usr/bin/env bash
# Self-contained contract tests for open-pr-count.sh (network-free: gh is
# stubbed via a PATH shim so no real GitHub calls happen).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/open-pr-count.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

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
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "exit $2" "exit $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$2" ;;
  esac
}

# PATH shim: a fake `gh` whose behavior is driven by GH_STUB_MODE.
mkdir -p "$TEST_TMPDIR/bin"
cat >"$TEST_TMPDIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "${GH_STUB_MODE:-}" in
  count0) echo "0" ;;
  count3) echo "3" ;;
  fail) exit 4 ;;
  *) exit 4 ;;
esac
EOF
chmod +x "$TEST_TMPDIR/bin/gh"
STUB_PATH="$TEST_TMPDIR/bin:$PATH"

# --- 1. --help contract ---------------------------------------------------------

help_out=$(bash "$SCRIPT" --help 2>&1)
help_exit=$?
assert_exit "--help exits 0" 0 "$help_exit"
assert_contains "--help mentions throttle" "$help_out" "Throttle"

# --- 2. Below-throttle count ----------------------------------------------------

out=$(PATH="$STUB_PATH" GH_STUB_MODE=count0 bash "$SCRIPT" 2>&1)
rc=$?
assert_exit "count 0 exits 0" 0 "$rc"
assert_contains "count 0 reported" "$out" "Open tidy PR count: 0"
assert_contains "count 0 throttle inactive" "$out" "Throttle active: no"

# --- 3. At-throttle count -------------------------------------------------------

out=$(PATH="$STUB_PATH" GH_STUB_MODE=count3 bash "$SCRIPT" 2>&1)
rc=$?
assert_exit "count 3 exits 0" 0 "$rc"
assert_contains "count 3 throttle active" "$out" "Throttle active: yes"

# --- 4. gh failure → unknown ----------------------------------------------------

out=$(PATH="$STUB_PATH" GH_STUB_MODE=fail bash "$SCRIPT" 2>&1)
rc=$?
assert_exit "gh failure exits 1" 1 "$rc"
assert_contains "gh failure reports unknown" "$out" "Open tidy PR count: unknown"

# --- Final report ---------------------------------------------------------------

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
