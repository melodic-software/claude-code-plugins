#!/usr/bin/env bash
# Regression tests for destructive-guard.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/destructive-guard.sh"

FAILED=0
CASE_NUM=0

# shellcheck source=lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"

guard_exit() {
  jq -n --arg c "$1" '{tool_input:{command:$c}}' | bash "$SCRIPT" >/dev/null 2>&1
  echo $?
}

# --- 1. --help contract --------------------------------------------------------

help_out=$(bash "$SCRIPT" --help 2>&1)
assert_exit "--help exits 0" 0 $?
assert_contains "--help names the ack prefix" "$help_out" "CLEAN_GUARD_ACK"

# --- 2. Destructive commands blocked (exit 2) -----------------------------------

for cmd in \
  "rm -rf build/" \
  "rm -Rf build/" \
  "rm -r -f build/" \
  "rm -f -r build/" \
  "rm --recursive --force build/" \
  "git clean -fdx" \
  "git clean --force -d" \
  "git -C /tmp/x clean -fdx" \
  "git --git-dir=/tmp/x/.git clean -f" \
  "git -c gc.auto=0 clean -f" \
  "git -C /tmp/x reset --hard origin/main" \
  "git reset --hard origin/main" \
  "git checkout -- ." \
  "git -C /tmp/x checkout -- ." \
  "Remove-Item -Recurse -Force obj"; do
  assert_exit "blocks: $cmd" 2 "$(guard_exit "$cmd")"
done

# --- 3. Block reason reaches stderr ----------------------------------------------

reason=$(jq -n '{tool_input:{command:"git clean -fdx"}}' | bash "$SCRIPT" 2>&1 >/dev/null)
assert_contains "block reason names the guard" "$reason" "destructive guard"
assert_contains "block reason names the ack path" "$reason" "CLEAN_GUARD_ACK=1"

# --- 4. Acknowledged commands allowed --------------------------------------------

assert_exit "ack prefix allows git clean" 0 "$(guard_exit "CLEAN_GUARD_ACK=1 git clean -fdx -e node_modules/")"
assert_exit "ack prefix allows reset --hard" 0 "$(guard_exit "CLEAN_GUARD_ACK=1 git reset --hard origin/main")"

# --- 5. Benign commands pass -----------------------------------------------------

for cmd in "git status" "rm file.txt" "git clean -n" "git clean -nx" "git clean -x" "ls -rf" "dotnet build"; do
  assert_exit "allows: $cmd" 0 "$(guard_exit "$cmd")"
done

# --- 6. Kill switch --------------------------------------------------------------

killed=$(
  jq -n '{tool_input:{command:"git clean -fdx"}}' | HOOK_CLEAN_DESTRUCTIVE_GUARD_ENABLED=false bash "$SCRIPT" >/dev/null 2>&1
  echo $?
)
assert_exit "kill switch allows everything" 0 "$killed"

# --- 7. Non-Bash / empty input tolerated ------------------------------------------

empty=$(
  printf '{}' | bash "$SCRIPT" >/dev/null 2>&1
  echo $?
)
assert_exit "empty tool_input exits 0" 0 "$empty"

# --- Final report -----------------------------------------------------------------

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
