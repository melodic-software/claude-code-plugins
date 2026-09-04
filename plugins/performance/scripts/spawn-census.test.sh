#!/usr/bin/env bash
# Tests for spawn-census.sh, the drift-immune process-spawn counter.
#
# The counting cases prove the instrument reads correctly. The refusal cases are
# the more important half: every one of them reproduces a way the source-run
# census reported a confident wrong number, and each asserts the script now
# FAILS instead of quietly producing one.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
CENSUS="$SCRIPT_DIR/spawn-census.sh"
readonly CENSUS

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
assert_not_contains() {
  if [[ "$3" != *"$2"* ]]; then pass "$1"; else fail "$1" "no *$2*" "$3"; fi
}

RUN_OUT=""
RUN_RC=0
run_census() {
  RUN_OUT="$(bash "$CENSUS" "$@" 2>&1)"
  RUN_RC=$?
}

# The workspace must NOT sit under the system temporary root: the script rejects
# a temp-rooted shim directory by design, so a mktemp workspace here would make
# every counting case unrunnable.
WORK="${PERF_HARNESS_TEST_ROOT:-$HOME/.cache/performance-harness-tests}/spawn-census.$$"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT
export PERF_HARNESS_LEDGER_DIR="$WORK/ledger"
SHIM="$WORK/shim"

cat >"$WORK/subject.sh" <<'SUBJECT'
#!/usr/bin/env bash
# Two sed spawns and one cat spawn. printf is a builtin and never reaches a
# shim, which is exactly the distinction the census measures.
printf 'x\n' | sed 's/x/y/' >/dev/null
printf 'z\n' | sed 's/z/w/' >/dev/null
cat /dev/null
SUBJECT

# --- 1. the instrument reads correctly ---
run_census --shim-dir "$SHIM" --label counted --tool sed --tool cat -- bash "$WORK/subject.sh"
assert_eq "a well-formed census exits 0" "0" "$RUN_RC"
assert_contains "two sed spawns and one cat spawn are counted" "spawns=3" "$RUN_OUT"
assert_contains "the breakdown names the tools" "2 sed" "$RUN_OUT"

# --- 2. rule 1, empirically: two runs against an unchanged subject agree ---
first="$RUN_OUT"
run_census --shim-dir "$SHIM" --label counted --tool sed --tool cat -- bash "$WORK/subject.sh"
assert_eq "a second run against the unchanged subject agrees" \
  "${first#*spawns=}" "${RUN_OUT#*spawns=}"

# --- 3. stdin reaches the subject, and its exit code is not fabricated ---
# A `printf | subject` pipeline under pipefail reports 141 whenever the subject
# exits without draining stdin, because printf takes EPIPE. That is an exit code
# the subject never returned, and it appears only on a pipe-buffer race, so it
# would show up as an intermittent, unreproducible rc in the census.
# discriminating-skip-required: the rc assertion here is the only thing standing
# between a fabricated exit code and the report.
# shellcheck disable=SC2016  # $line belongs to the inner `bash -c`, not to this shell
run_census --shim-dir "$SHIM" --label stdin-drained --tool cat --no-ledger \
  --stdin 'payload text' -- bash -c 'read -r line; [[ "$line" == "payload text" ]]'
assert_eq "stdin reaches a subject that reads it" "0" "$RUN_RC"
assert_contains "a draining subject reports its own exit code" "rc=0" "$RUN_OUT"

run_census --shim-dir "$SHIM" --label stdin-ignored --tool cat --no-ledger \
  --stdin 'payload the subject never reads' -- bash -c 'exit 0'
assert_eq "an undrained stdin does not fail the census" "0" "$RUN_RC"
assert_contains "an undrained stdin does not fabricate rc=141" "rc=0" "$RUN_OUT"

printf 'from a file\n' >"$WORK/payload.txt"
# shellcheck disable=SC2016  # $line belongs to the inner `bash -c`, not to this shell
run_census --shim-dir "$SHIM" --label stdin-file --tool cat --no-ledger \
  --stdin-file "$WORK/payload.txt" -- bash -c 'read -r line; [[ "$line" == "from a file" ]]'
assert_contains "--stdin-file reaches the subject" "rc=0" "$RUN_OUT"

run_census --shim-dir "$SHIM" --label stdin-missing --tool cat --no-ledger \
  --stdin-file "$WORK/no-such-payload.txt" -- bash -c 'exit 0'
assert_eq "a missing --stdin-file is refused" "2" "$RUN_RC"

# --- 4. a builtin-only subject counts zero, and does not miscount its shims ---
run_census --shim-dir "$SHIM" --label builtins --tool sed --tool cat -- bash -c 'printf ok'
assert_contains "a builtins-only subject counts zero spawns" "spawns=0" "$RUN_OUT"

# --- 5. the shim directory is required, and a temporary one is refused ---
run_census --label nodir --tool sed -- bash -c 'printf ok'
assert_eq "a missing shim directory is refused" "2" "$RUN_RC"
assert_contains "the refusal explains the fixed-PATH requirement" "SAME directory" "$RUN_OUT"

run_census --shim-dir "${TMPDIR:-/tmp}/perf-census-probe" --label tempdir --tool sed -- bash -c 'printf ok'
assert_eq "a temp-rooted shim directory is refused" "2" "$RUN_RC"
assert_contains "the refusal names the mktemp defect" "temporary root" "$RUN_OUT"

# --- 6. an unresolvable tool FAILS rather than being skipped ---
# The source harness wrote `|| continue` here. A silently dropped tool
# undercounts every run and reports a confident wrong number, which
# harness-integrity.md rule 2 forbids: assert the precondition, never degrade.
# discriminating-skip-required: this case is the entire proof that an
# unresolvable tool is refused rather than dropped.
run_census --shim-dir "$SHIM" --label badtool \
  --tool definitely-not-a-real-binary-xyz -- bash -c 'printf ok'
assert_eq "an unresolvable tool is refused" "2" "$RUN_RC"
assert_contains "the refusal explains the undercount" "undercounts" "$RUN_OUT"

# --- 7. a Windows drive-letter subject path is refused ---
run_census --shim-dir "$SHIM" --label winpath --tool sed -- bash 'D:/worktrees/repo/hook.sh'
assert_eq "a drive-letter subject path is refused" "2" "$RUN_RC"
assert_contains "the refusal names the MSYS trap" "resolves nowhere" "$RUN_OUT"

run_census --shim-dir "$SHIM" --label winpathok --tool sed --allow-windows-paths \
  -- bash -c 'printf %s "D:/native/tool.exe"'
assert_eq "--allow-windows-paths is the documented escape hatch" "0" "$RUN_RC"

# --- 8. the ledger catches a shim directory that moved between runs ---
# This is the standalone-invocation half of rule 1. The driver's two-runs-agree
# proof cannot cover it, because a census is run on its own far more often than
# through a driver.
mkdir -p "$WORK/shim-moved"
run_census --shim-dir "$WORK/shim-moved" --label counted --tool sed --tool cat \
  -- bash "$WORK/subject.sh"
assert_eq "a moved shim directory is refused under the same label" "2" "$RUN_RC"
assert_contains "the refusal names the previous entry" "$SHIM" "$RUN_OUT"

run_census --shim-dir "$WORK/shim-moved" --label counted --ledger-reset --tool sed --tool cat \
  -- bash "$WORK/subject.sh"
assert_eq "--ledger-reset accepts a deliberate move" "0" "$RUN_RC"

run_census --shim-dir "$SHIM" --label counted --no-ledger --tool sed --tool cat \
  -- bash "$WORK/subject.sh"
assert_eq "--no-ledger skips the recorded-entry check" "0" "$RUN_RC"

# --- 9. a subject that never ran is refused, not counted as zero ---
run_census --shim-dir "$SHIM" --label missing --tool sed --no-ledger \
  -- /nonexistent/definitely-not-here.sh
assert_eq "a subject exiting 127 is refused" "2" "$RUN_RC"
assert_contains "the refusal names the false-green shape" "never ran" "$RUN_OUT"
assert_not_contains "no spawn count is printed for a subject that never ran" "spawns=" "$RUN_OUT"

# 126 is the other spelling of "never ran": found, but not executable, or a
# directory, or refused by permissions. It produces the same tidy spawns=0 line,
# so guarding only the more famous 127 leaves the identical false green reachable.
# discriminating-skip-required: this case is the only cover for the 126 arm.
run_census --shim-dir "$SHIM" --label notexec --tool sed --no-ledger -- "$WORK"
assert_eq "a subject exiting 126 is refused" "2" "$RUN_RC"
assert_contains "the 126 refusal explains the cause" "not executable" "$RUN_OUT"
assert_not_contains "no spawn count is printed for a 126 subject" "spawns=" "$RUN_OUT"

[[ "${FAILED:-0}" -eq 0 ]] || exit 1
echo "OK: spawn-census"
exit 0
