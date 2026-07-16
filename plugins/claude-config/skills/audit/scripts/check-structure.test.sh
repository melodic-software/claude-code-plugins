#!/usr/bin/env bash
# Self-contained tests for check-structure.sh (no external test lib — ships with the plugin).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/check-structure.sh"
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
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}
assert_contains() {
  case "$2" in
    *"$3"*) pass "$1" ;;
    *) fail "$1" "expected to contain: $3" ;;
  esac
}
assert_not_contains() {
  case "$2" in
    *"$3"*) fail "$1" "unexpected substring: $3" ;;
    *) pass "$1" ;;
  esac
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed" >&2
  exit 0
fi

# --- Case 1: happy path on a valid fixture project ----------------------------
fixture_dir="$TEST_TMPDIR/valid"
mkdir -p "$fixture_dir/.claude"
printf '{"permissions":{"deny":["Read(./.env)"],"ask":[],"allow":["Bash(git status)"]},"enabledPlugins":{"a@m":true}}\n' >"$fixture_dir/.claude/settings.json"
rc=0
out=$(
  SETTINGS_AUDIT_STRUCTURE_FIXTURE_DIR="$fixture_dir" \
    bash "$SCRIPT" 2>/dev/null
) || rc=$?
assert_exit "case 1: exit 0 on valid settings" 0 "$rc"
assert_contains "case 1: settings.json facts" "$out" "File: .claude/settings.json"
assert_contains "case 1: valid json" "$out" "Valid JSON: yes"
assert_contains "case 1: deny count" "$out" "Deny count: 1"
assert_contains "case 1: absent local reported" "$out" "Present: no"
assert_not_contains "case 1: no env dump" "$out" "sk-"

# --- Case 2: invalid JSON exits 1 ---------------------------------------------
fixture_dir="$TEST_TMPDIR/invalid-json"
mkdir -p "$fixture_dir/.claude"
printf '{invalid\n' >"$fixture_dir/.claude/settings.json"
rc=0
out=$(
  SETTINGS_AUDIT_STRUCTURE_FIXTURE_DIR="$fixture_dir" \
    bash "$SCRIPT" 2>/dev/null
) || rc=$?
assert_exit "case 2: exit 1 on invalid JSON" 1 "$rc"
assert_contains "case 2: invalid json reported" "$out" "Valid JSON: no"

# --- Case 3: missing jq exits 2 -------------------------------------------------
# Run the script under an EMPTY PATH so its `command -v jq` resolves nothing. The
# script exits at the jq gate before invoking any external tool, so an empty PATH
# suffices — and invoking via bash's absolute path keeps the empty PATH from hiding
# bash itself.
real_bash=$(command -v bash)
empty_path_dir="$TEST_TMPDIR/empty-path"
mkdir -p "$empty_path_dir"
rc=0
err_out=$(
  PATH="$empty_path_dir" "$real_bash" "$SCRIPT" 2>&1
) || rc=$?
assert_exit "case 3: exit 2 when jq missing" 2 "$rc"
assert_contains "case 3: jq required message" "$err_out" "jq required"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
