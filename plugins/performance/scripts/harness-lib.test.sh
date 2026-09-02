#!/usr/bin/env bash
# Tests for harness-lib.sh, the shared precondition helpers.
#
# Every case here asserts that a precondition FAILS when it is unmet. That is
# the point of the library: harness-integrity.md rule 2 forbids degrading into a
# weaker check that passes, so "it refused" is the behavior under test, not an
# error path to tolerate.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=harness-lib.sh
source "$SCRIPT_DIR/harness-lib.sh"

# Inline test helpers: self-contained, no external test lib (ships with the plugin).
FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: [%d] %s\n' "$CASE_NUM" "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s - expected %q got %q\n' "$CASE_NUM" "$1" "$2" "$3" >&2
  FAILED=$((FAILED + 1))
}
assert_eq() { if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }
assert_contains() {
  if [[ "$3" == *"$2"* ]]; then pass "$1"; else fail "$1" "*$2*" "$3"; fi
}

RUN_OUT=""
RUN_RC=0
# Run a library function in a subshell so its `exit` terminates only that
# subshell, and capture what it said along with how it exited.
capture() {
  RUN_OUT="$("$@" 2>&1)"
  RUN_RC=$?
}

WORK="${PERF_HARNESS_TEST_ROOT:-$HOME/.cache/performance-harness-tests}/harness-lib.$$"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT
export PERF_HARNESS_LEDGER_DIR="$WORK/ledger"

# --- harness_posix_form ---
# portability-ok: 'D:\a\b' is literal Windows path DATA under test, not a regex; the
# backslash pairs are the input this conversion exists to fold, not GNU escapes.
assert_eq "backslash drive path folds to POSIX" "/d/a/b" "$(harness_posix_form 'D:\a\b')"
assert_eq "forward-slash drive path folds to POSIX" "/d/a/b" "$(harness_posix_form 'D:/a/b')"
assert_eq "drive root folds to POSIX" "/c/" "$(harness_posix_form 'C:/')"
assert_eq "an already-POSIX path is unchanged" "/d/a/b" "$(harness_posix_form '/d/a/b')"
assert_eq "a non-path string is unchanged" "before" "$(harness_posix_form 'before')"

# --- harness_require_posix_path ---
capture harness_require_posix_path "the subject" 'D:/worktrees/repo/hook.sh'
assert_eq "a drive-letter path is refused" "2" "$RUN_RC"
assert_contains "the refusal names the POSIX spelling" "/d/... rather than D:/..." "$RUN_OUT"

capture harness_require_posix_path "the subject" 'bash /d/ok/x.sh && cat C:/leaked/y'
assert_eq "an EMBEDDED drive-letter path is refused" "2" "$RUN_RC"

capture harness_require_posix_path "the subject" '/d/worktrees/repo/hook.sh'
assert_eq "a POSIX path is accepted" "0" "$RUN_RC"

capture harness_require_posix_path "the subject" 'bash -c "printf %s hello"'
assert_eq "an ordinary command string is accepted" "0" "$RUN_RC"

# --- harness_resolve_shim_dir ---
capture harness_resolve_shim_dir ""
assert_eq "an empty shim directory is refused" "2" "$RUN_RC"
assert_contains "the refusal explains why there is no default" "must be the SAME directory" "$RUN_OUT"

capture harness_resolve_shim_dir "${TMPDIR:-/tmp}/performance-harness-shim-probe"
assert_eq "a shim directory under the temporary root is refused" "2" "$RUN_RC"
assert_contains "the refusal names the mktemp defect" "temporary root" "$RUN_OUT"

# The same physical directory reached by a DIFFERENT SPELLING must still be
# refused. On Windows, TEMP is often the 8.3 short form
# (C:\Users\<SHORT~1>\...) while /tmp resolves to the long form, and a string
# prefix test between the two finds nothing: the rejection would silently stop
# working on exactly the platform the source failures came from.
# discriminating-skip-required: the spelling-independence of the temp-root
# rejection is the only thing this case proves.
TMPDIR_ALIAS="$(cd /tmp && pwd -P)"
capture env TMPDIR=/tmp bash -c \
  "source '$SCRIPT_DIR/harness-lib.sh'; harness_resolve_shim_dir '$TMPDIR_ALIAS/perf-shim-probe'"
assert_eq "a temp root reached by another spelling is refused" "2" "$RUN_RC"

# A directory whose NAME merely contains "tmp" is not under the temporary root
# and must be accepted; a substring match here would misfire on real paths.
mkdir -p "$WORK/tmp-but-not-temp"
harness_resolve_shim_dir "$WORK/tmp-but-not-temp"
assert_contains "a stable directory named tmp-* is accepted" "tmp-but-not-temp" "$HARNESS_SHIM_DIR"

# --- harness_ledger_check ---
harness_ledger_check "case-ledger" "/d/stable/shim"
capture harness_ledger_check "case-ledger" "/d/stable/shim"
assert_eq "an unchanged injected PATH entry passes" "0" "$RUN_RC"

capture harness_ledger_check "case-ledger" "/d/moved/shim"
assert_eq "a CHANGED injected PATH entry is refused" "2" "$RUN_RC"
assert_contains "the refusal names both values" "/d/stable/shim" "$RUN_OUT"
assert_contains "the refusal cites rule 1" "rule 1" "$RUN_OUT"

harness_ledger_reset "case-ledger"
capture harness_ledger_check "case-ledger" "/d/moved/shim"
assert_eq "a reset ledger accepts a new entry" "0" "$RUN_RC"

capture env -u PERF_HARNESS_LEDGER_DIR -u XDG_CACHE_HOME -u HOME \
  bash -c "source '$SCRIPT_DIR/harness-lib.sh'; harness_ledger_path k"
assert_eq "no writable ledger location is refused, not skipped" "2" "$RUN_RC"

[[ "${FAILED:-0}" -eq 0 ]] || exit 1
echo "OK: harness-lib preconditions"
exit 0
