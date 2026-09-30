#!/usr/bin/env bash
# Regression tests for clean.sh's prune of the hook log root's shared files.
#
# Coverage:
#   - hook-events.jsonl.1 (the file the telemetry sink rotates the shared log
#     to) is pruned to the --keep-days window like hook-events.jsonl
#   - --dry-run reports what it would prune for both files and changes nothing
#   - a rotated file with a line that is not valid JSON is left intact and the
#     run exits 1
#   - a missing rotated file is skipped and the run exits 0
#
# CC_OTEL_STORE points at an empty directory so the OTEL delegate never sees a
# real store.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/clean.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed"
  exit 0
fi

FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: [%d] %s\n' "$CASE_NUM" "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s: expected %q got %q\n' "$CASE_NUM" "$1" "$2" "$3" >&2
  FAILED=$((FAILED + 1))
}
assert_eq() { if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }
assert_contains() { if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1" "contains: $3" "$2"; fi; }

ROOT_REL=".observability/claude"
OLD='{"ts":"2020-01-01T00:00:00Z","n":1}'
NEW='{"ts":"2999-01-01T00:00:00Z","n":2}'

# A project directory holding the shared file and its rotated .1, each with one
# row outside the window and one inside it.
make_project() { # <name>
  local dir="$TEST_TMPDIR/$1"
  mkdir -p "$dir/$ROOT_REL" "$dir/otel"
  printf '%s\n%s\n' "$OLD" "$NEW" >"$dir/$ROOT_REL/hook-events.jsonl"
  printf '%s\n%s\n' "$OLD" "$NEW" >"$dir/$ROOT_REL/hook-events.jsonl.1"
  printf '%s' "$dir"
}

run_clean() { # <project> [args...] ; sets OUT and RC
  local dir="$1"
  shift
  OUT=$(env CLAUDE_PROJECT_DIR="$dir" CC_OTEL_STORE="$dir/otel" bash "$SCRIPT" --keep-days 30 "$@" 2>&1)
  RC=$?
}

# --- dry run reports both files and changes nothing ---------------------------
P1="$(make_project p1)"
run_clean "$P1" --dry-run
assert_eq "dry run exits 0" 0 "$RC"
assert_contains "dry run reports the rotated file" "$OUT" "hook-events.jsonl.1: 2 lines"
assert_contains "dry run says it would prune one row" "$OUT" "would keep 1, prune 1"
assert_eq "dry run leaves the rotated file untouched" 2 "$(wc -l <"$P1/$ROOT_REL/hook-events.jsonl.1" | tr -d ' ')"

# --- a real run prunes the rotated file to the window -------------------------
run_clean "$P1" --quiet
assert_eq "real run exits 0" 0 "$RC"
assert_eq "rotated file keeps only the in-window row" "$NEW" "$(cat "$P1/$ROOT_REL/hook-events.jsonl.1")"
assert_eq "live file is pruned the same way" "$NEW" "$(cat "$P1/$ROOT_REL/hook-events.jsonl")"

# --- an unparsable line leaves the rotated file intact and fails the run ------
P2="$(make_project p2)"
printf '%s\nnot json\n' "$OLD" >"$P2/$ROOT_REL/hook-events.jsonl.1"
run_clean "$P2" --quiet
assert_eq "an unparsable rotated file exits 1" 1 "$RC"
assert_eq "an unparsable rotated file is left intact" 2 "$(wc -l <"$P2/$ROOT_REL/hook-events.jsonl.1" | tr -d ' ')"

# --- no rotated file is not an error ------------------------------------------
P3="$(make_project p3)"
rm -f "$P3/$ROOT_REL/hook-events.jsonl.1"
run_clean "$P3"
assert_eq "a missing rotated file exits 0" 0 "$RC"
assert_contains "a missing rotated file is skipped" "$OUT" "hook-events.jsonl.1: missing"

if ((FAILED > 0)); then
  printf '%d of %d checks failed\n' "$FAILED" "$CASE_NUM" >&2
  exit 1
fi
printf 'all %d checks passed\n' "$CASE_NUM"
