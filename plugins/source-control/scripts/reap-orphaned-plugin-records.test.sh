#!/usr/bin/env bash
# Regression tests for reap-orphaned-plugin-records.sh. Black-box: a stubbed
# `claude` on PATH reproduces the measured CLI contract (`plugin list --json`
# reports every project-scope record, `plugin uninstall <id> -s project` acts
# only on a record whose projectPath is the current directory). The cases pin
# the properties the Step 2b remedy rests on: paths are reaped in order, an
# existing path is refused without reaping, the run stops at the first failing
# path, and only the directory the script created is removed.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMEDY="$SCRIPT_DIR/reap-orphaned-plugin-records.sh"

FAILED=0
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

command -v jq >/dev/null 2>&1 || skip_suite "jq not available"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

STUB_DIR="$TEST_TMPDIR/stub"
mkdir -p "$STUB_DIR"
STATE="$TEST_TMPDIR/state.json"
LOG="$TEST_TMPDIR/calls.log"

cat >"$STUB_DIR/claude" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
here="$(pwd -W 2>/dev/null || pwd -P)"
if [[ "${1:-}" == "plugin" && "${2:-}" == "list" ]]; then
  jq -c '{installed: .}' "$STUB_STATE"
  exit 0
fi
if [[ "${1:-}" == "plugin" && "${2:-}" == "uninstall" ]]; then
  id="${3:-}"
  printf 'uninstall %s in %s (args: %s)\n' "$id" "$here" "$*" >>"$STUB_CALL_LOG"
  # STUB_FAIL_ID simulates a record the CLI will not remove.
  if [[ "${STUB_FAIL_ID:-}" == "$id" ]]; then
    printf 'Failed to uninstall plugin "%s"\n' "$id" >&2
    exit 1
  fi
  tmp="$(mktemp)"
  jq --arg id "$id" --arg here "$here" \
    'map(select((.id == $id and .projectPath == $here) | not))' "$STUB_STATE" >"$tmp" &&
    mv "$tmp" "$STUB_STATE"
  printf 'Successfully uninstalled plugin: %s (scope: project)\n' "$id"
  exit 0
fi
exit 64
STUB
chmod +x "$STUB_DIR/claude"

RC=0
OUT=""
# run [args...] — one remedy invocation with the stub on PATH.
run() {
  OUT="$(cd "$TEST_TMPDIR" && PATH="$STUB_DIR:$PATH" STUB_STATE="$STATE" \
    STUB_CALL_LOG="$LOG" bash "$REMEDY" "$@" 2>&1)"
  RC=$?
}

native_of() { (cd "$1" && { pwd -W 2>/dev/null || pwd -P; }); }
seed_state() { printf '%s\n' "$1" >"$STATE"; }
reset_log() { : >"$LOG"; }

ROOT="$TEST_TMPDIR/root"
mkdir -p "$ROOT"
ROOT_NATIVE="$(native_of "$ROOT")"

# --- CLI contract ---------------------------------------------------------------

help_out="$(bash "$REMEDY" --help 2>&1)"
assert_exit "--help exits 0" 0 "$?"
assert_contains "--help reaches the end of the header" "$help_out" "later paths are not touched"

run
assert_exit "no path is a usage error" 2 "$RC"

run --bogus
assert_exit "an unknown flag is a usage error" 2 "$RC"

# --- two dead paths reaped in order ---------------------------------------------

A="$ROOT_NATIVE/dead-a"
B="$ROOT_NATIVE/dead-b"
seed_state "$(jq -n --arg a "$A" --arg b "$B" '[
  {id:"p@m",scope:"project",projectPath:$a},
  {id:"q@m",scope:"project",projectPath:$a},
  {id:"p@m",scope:"project",projectPath:$b}
]')"
reset_log
run "$A" "$B"
assert_exit "two dead paths reap cleanly" 0 "$RC"
assert_eq "every record for both paths is gone" "0" "$(jq 'length' "$STATE")"
assert_eq "both paths are removed afterwards" "no" "$([[ -e "$A" || -e "$B" ]] && echo yes || echo no)"
assert_contains "the first path is reported reaped" "$OUT" "[1/2] $A reaped"
assert_contains "the second path is reported reaped" "$OUT" "[2/2] $B reaped"
log="$(cat "$LOG")"
assert_contains "the reap ran from inside the first path" "$log" "uninstall p@m in $A"
assert_contains "the reap ran from inside the second path" "$log" "uninstall p@m in $B"
before_a="${log%%in $B*}"
assert_contains "the first path was reaped before the second" "$before_a" "in $A"
assert_contains "the uninstall is scoped to the project" "$log" "-s project"
assert_not_contains "never escalates to user scope" "$log" "-s user"

# --- an existing path is refused without reaping --------------------------------

LIVE="$ROOT_NATIVE/live"
mkdir -p "$LIVE"
: >"$LIVE/work.txt"
seed_state "$(jq -n --arg l "$LIVE" '[{id:"p@m",scope:"project",projectPath:$l}]')"
reset_log
run "$LIVE"
assert_exit "an existing path fails" 1 "$RC"
assert_contains "the failure names the path" "$OUT" "$LIVE"
assert_contains "the failure names the mkdir step" "$OUT" "failed at mkdir"
assert_eq "no reap ran against the existing path" "" "$(cat "$LOG")"
assert_eq "the record for the existing path is untouched" "1" "$(jq 'length' "$STATE")"
assert_file_exists "the existing directory's contents survive" "$LIVE/work.txt"

# --- stop after the first failing path ------------------------------------------

C="$ROOT_NATIVE/dead-c"
D="$ROOT_NATIVE/dead-d"
E="$ROOT_NATIVE/dead-e"
seed_state "$(jq -n --arg c "$C" --arg d "$D" --arg e "$E" '[
  {id:"p@m",scope:"project",projectPath:$c},
  {id:"bad@m",scope:"project",projectPath:$d},
  {id:"p@m",scope:"project",projectPath:$e}
]')"
reset_log
OUT="$(cd "$TEST_TMPDIR" && PATH="$STUB_DIR:$PATH" STUB_STATE="$STATE" STUB_CALL_LOG="$LOG" \
  STUB_FAIL_ID="bad@m" bash "$REMEDY" "$C" "$D" "$E" 2>&1)"
RC=$?
assert_exit "a failing path exits 1" 1 "$RC"
assert_contains "the failing path is named" "$OUT" "$D"
assert_contains "the failing step is named" "$OUT" "failed at reap"
assert_contains "the stop is reported" "$OUT" "1 later path(s) were not touched"
assert_eq "the path before the failure was reaped and removed" "no" "$([[ -e "$C" ]] && echo yes || echo no)"
assert_eq "the failing path's directory is left in place" "yes" "$([[ -d "$D" ]] && echo yes || echo no)"
assert_eq "the path after the failure was never created" "no" "$([[ -e "$E" ]] && echo yes || echo no)"
assert_not_contains "no uninstall ran for the path after the failure" "$(cat "$LOG")" "in $E"

# --- a missing parent fails at mkdir, pointing at #7461 -------------------------

reset_log
run "$ROOT_NATIVE/no-such-parent/child"
assert_exit "a missing parent fails" 1 "$RC"
assert_contains "the missing parent fails at mkdir" "$OUT" "failed at mkdir"
assert_contains "the message points at #7461" "$OUT" "#7461"
assert_eq "no reap ran for a missing parent" "" "$(cat "$LOG")"
assert_eq "mkdir did not create the parent" "no" "$([[ -e "$ROOT_NATIVE/no-such-parent" ]] && echo yes || echo no)"

# --- a trailing separator names the same path -----------------------------------

F="$ROOT_NATIVE/dead-f"
seed_state "$(jq -n --arg f "$F" '[{id:"p@m",scope:"project",projectPath:$f}]')"
reset_log
run "$F/"
assert_exit "a path with a trailing slash reaps" 0 "$RC"
assert_eq "the trailing-slash record is gone" "0" "$(jq 'length' "$STATE")"

[[ $FAILED -eq 0 ]] || exit 1
printf '\nAll %d cases passed.\n' "$CASE_NUM"
