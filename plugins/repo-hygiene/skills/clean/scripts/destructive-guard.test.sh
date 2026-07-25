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
  "git stash drop" \
  "git stash drop stash@{0}" \
  "git stash clear" \
  "git -C /tmp/x stash drop" \
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
assert_exit "ack prefix allows stash drop" 0 "$(guard_exit "CLEAN_GUARD_ACK=1 git stash drop stash@{1}")"

# --- 5. Benign commands pass -----------------------------------------------------

for cmd in "git status" "rm file.txt" "git clean -n" "git clean -nx" "git clean -x" "ls -rf" "dotnet build" "git stash list" "git stash show stash@{0}"; do
  assert_exit "allows: $cmd" 0 "$(guard_exit "$cmd")"
done

# --- 6. Kill switch --------------------------------------------------------------

killed=$(
  jq -n '{tool_input:{command:"git clean -fdx"}}' | CLAUDE_PLUGIN_OPTION_CLEAN_DESTRUCTIVE_GUARD_ENABLED=false bash "$SCRIPT" >/dev/null 2>&1
  echo $?
)
assert_exit "kill switch allows everything" 0 "$killed"

# --- 7. Non-Bash / empty input tolerated ------------------------------------------

empty=$(
  printf '{}' | bash "$SCRIPT" >/dev/null 2>&1
  echo $?
)
assert_exit "empty tool_input exits 0" 0 "$empty"

# --- 8. Degraded mode without jq: fail-closed -------------------------------------
# Sandbox PATH containing everything the guard needs except jq. Symlinking works
# on Linux CI; on Windows/MSYS the linked bash cannot load its DLLs, so the
# sandbox is verified functional first and the cases are skipped when it isn't.

NOJQ_DIR="$(mktemp -d)"
trap 'rm -rf "$NOJQ_DIR"' EXIT
for bin in bash cat grep sed; do
  ln -s "$(command -v "$bin")" "$NOJQ_DIR/$bin" 2>/dev/null || true
done

nojq_exit() {
  printf '{"tool_input":{"command":"%s"}}' "$1" | PATH="$NOJQ_DIR" "$NOJQ_DIR/bash" "$SCRIPT" >/dev/null 2>&1
  echo $?
}

if [[ "$(PATH="$NOJQ_DIR" "$NOJQ_DIR/bash" -c 'command -v jq >/dev/null 2>&1 && echo have-jq; echo ok' 2>/dev/null)" == "ok" ]]; then
  assert_exit "no jq: blocks raw destructive payload" 2 "$(nojq_exit "git clean -fdx")"
  assert_exit "no jq: blocks rm -rf payload" 2 "$(nojq_exit "rm -rf build/")"
  assert_exit "no jq: benign payload passes" 0 "$(nojq_exit "git status")"
  assert_exit "no jq: ack prefix does NOT bypass (unverifiable)" 2 "$(nojq_exit "CLEAN_GUARD_ACK=1 git clean -fdx")"
  reason=$(printf '{"tool_input":{"command":"git clean -fdx"}}' | PATH="$NOJQ_DIR" "$NOJQ_DIR/bash" "$SCRIPT" 2>&1 >/dev/null)
  assert_contains "no jq: block reason names degraded mode" "$reason" "degraded mode: jq not found"
else
  skip_case "degraded-mode cases: PATH sandbox not functional on this platform"
fi

# --- Final report -----------------------------------------------------------------

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
