#!/usr/bin/env bash
# Tests for discriminate.py, the does-this-check-actually-fail harness.
#
# This is the harness consolidated from five source-run variants, four of which
# returned a confident wrong answer. Every one of those defects has a case here,
# and each asserts the FIXED behavior:
#
#   * both arms exiting 127 must report HARNESS BROKEN, not a verdict;
#   * a signal absent from both arms must report HARNESS BROKEN, not a verdict;
#   * a check that cannot even be launched must report HARNESS BROKEN, not a
#     traceback and not a verdict;
#   * a patch that changed nothing must be refused before either arm runs;
#   * an UNCOMMITTED change to the target must survive the run, because the
#     restore comes from saved bytes and never from `git checkout --`.
#
# The last one is a BEHAVIORAL proof rather than an inspection of the source:
# the target is committed WITHOUT the fix, the fix is applied and left
# uncommitted, and the case asserts the fix is still there afterwards. A
# `git checkout --` restore would have destroyed it, which is exactly what
# source failure 5 did.
#
# The fixtures are Python rather than shell so that `check.argv` needs no path
# spelling at all: the check is named RELATIVE to `check.cwd`, which the harness
# resolves. That is deliberate, not incidental. argv is handed straight to the
# operating system with no MSYS rewriting, so a bash check needs MSYS paths in
# its arguments while a native check needs native ones, and a fixture that
# hardcoded either spelling would test the host rather than the harness.
set -uo pipefail

# This suite BUILDS a git fixture. `git -C` changes directory, it does not
# isolate: an inherited absolute GIT_DIR overrides repository discovery, and
# GIT_CONFIG replaces the file `git config` writes, so the fixture's identity
# would land in the CALLER's repository. Clear the environment.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=harness-lib.sh
source "$SCRIPT_DIR/harness-lib.sh"
harness_require_python
DISCRIMINATE="$SCRIPT_DIR/discriminate.py"
readonly DISCRIMINATE

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

# Not under the system temporary root. /tmp is an MSYS MOUNT with no drive
# letter, so a native Windows interpreter reaches it only through cygpath, and
# threading that through every fixture would test the mount table rather than
# the harness.
WORK="${PERF_HARNESS_TEST_ROOT:-$HOME/.cache/performance-harness-tests}/discriminate.$$"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

RUN_OUT=""
RUN_RC=0
run_discriminate() {
  RUN_OUT="$("$HARNESS_PYTHON" "$DISCRIMINATE" "$@" 2>&1)"
  RUN_RC=$?
}

# Single-quoted in Python so the anchor embeds into a JSON config verbatim. A
# double quote here would need JSON escaping, and getting that wrong is a
# fixture bug that reads as a harness bug.
FIX_LINE="value = value.removesuffix('-suffix')"

write_subject() {
  cat >"$1/subject.py" <<SUBJECT
import sys

value = sys.argv[1]
$FIX_LINE
print(value)
SUBJECT
}

write_check() {
  cat >"$1/check.py" <<'CHECK'
import pathlib
import subprocess
import sys

here = pathlib.Path(__file__).resolve().parent
done = subprocess.run(
    [sys.executable, str(here / "subject.py"), "abc-suffix"],
    capture_output=True,
    text=True,
    check=False,
)
out = done.stdout.strip()
if out == "abc":
    print("PASS: the suffix is stripped")
    sys.exit(0)
print(f"FAIL: the suffix is not stripped (got {out!r})")
sys.exit(1)
CHECK
}

write_config() {
  local dir="$1" name="$2" argv="$3"
  cat >"$dir/$name" <<CONFIG
{
  "target": "$dir/subject.py",
  "anchor": "$FIX_LINE",
  "replacement": "pass  # fix disabled for the discrimination check",
  "check": {"argv": $argv, "cwd": "$dir", "timeout": 120},
  "signal": {"regex": "^(PASS|FAIL): the suffix.*$"},
  "expect": {"negative_contains": "FAIL:", "positive_contains": "PASS:"}
}
CONFIG
}

CHECK_ARGV="[\"$HARNESS_PYTHON\", \"check.py\"]"

# --- 1. the happy path: red without the fix, green with it, arms differ ---
mkdir -p "$WORK/ok"
write_subject "$WORK/ok"
write_check "$WORK/ok"
write_config "$WORK/ok" config.json "$CHECK_ARGV"
before_bytes="$(cat "$WORK/ok/subject.py")"

run_discriminate --config "$WORK/ok/config.json"
assert_eq "a discriminating check exits 0" "0" "$RUN_RC"
assert_contains "the verdict is stated" "VERDICT: DISCRIMINATING" "$RUN_OUT"
assert_contains "the negative arm's signal is shown" "FAIL: the suffix is not stripped" "$RUN_OUT"
assert_contains "the positive arm's signal is shown" "PASS: the suffix is stripped" "$RUN_OUT"
assert_contains "the restore is verified, not assumed" "restore verified byte-identical: True" "$RUN_OUT"
assert_eq "the target is byte-identical afterwards" "$before_bytes" "$(cat "$WORK/ok/subject.py")"
if [[ ! -e "$WORK/ok/subject.py.discriminate-backup" ]]; then
  pass "the sidecar is removed once the restore verifies"
else
  fail "the sidecar is removed once the restore verifies" "absent" "present"
fi

# --- 2. an UNCOMMITTED fix survives: the restore never uses git ---
# discriminating-skip-required: this case is the only behavioral proof that
# `git checkout --` is not the restore path, which is source failure 5.
mkdir -p "$WORK/git"
git init --quiet "$WORK/git" >/dev/null 2>&1
git -C "$WORK/git" config user.email harness@example.invalid
git -C "$WORK/git" config user.name "Harness Test"
write_check "$WORK/git"
# Commit the subject WITHOUT the fix, so the committed blob is the broken one.
cat >"$WORK/git/subject.py" <<'BROKEN'
import sys

value = sys.argv[1]
print(value)
BROKEN
git -C "$WORK/git" add -A >/dev/null 2>&1
git -C "$WORK/git" commit --quiet -m "subject without the fix" >/dev/null 2>&1
# Now apply the fix and leave it UNCOMMITTED. This is the exact situation that
# destroyed the work in the source run.
write_subject "$WORK/git"
write_config "$WORK/git" config.json "$CHECK_ARGV"

run_discriminate --config "$WORK/git/config.json"
assert_eq "the run over an uncommitted fix exits 0" "0" "$RUN_RC"
assert_contains "the uncommitted target is warned about" "has uncommitted changes" "$RUN_OUT"
if grep -q 'removesuffix' "$WORK/git/subject.py"; then
  pass "the UNCOMMITTED fix survived the run"
else
  fail "the UNCOMMITTED fix survived the run" "the fix line still present" "$(cat "$WORK/git/subject.py")"
fi

# --- 3. both arms exiting 127 report HARNESS BROKEN, not a verdict ---
# This is source failures 3 and 4 verbatim: a path that resolved nowhere made
# both arms exit 127, and the harness reported a confident "NOT DISCRIMINATING".
# discriminating-skip-required: without this case nothing proves the harness
# distinguishes "the check never ran" from "the check does not discriminate".
mkdir -p "$WORK/dead127"
write_subject "$WORK/dead127"
cat >"$WORK/dead127/check.py" <<'DEAD127'
import sys

sys.exit(127)
DEAD127
write_config "$WORK/dead127" config.json "$CHECK_ARGV"
run_discriminate --config "$WORK/dead127/config.json"
assert_eq "two arms exiting 127 are refused" "2" "$RUN_RC"
assert_contains "the refusal says the harness is broken" "HARNESS BROKEN" "$RUN_OUT"
assert_contains "the refusal names the 127 shape" "exited 127" "$RUN_OUT"
assert_not_contains "it does not report a discrimination verdict" "VERDICT: NOT DISCRIMINATING" "$RUN_OUT"
assert_not_contains "it does not report success" "VERDICT: DISCRIMINATING" "$RUN_OUT"

# --- 4. a check that cannot be LAUNCHED reports HARNESS BROKEN, not a traceback ---
mkdir -p "$WORK/unlaunchable"
write_subject "$WORK/unlaunchable"
write_config "$WORK/unlaunchable" config.json '["definitely-not-a-real-binary-xyz"]'
run_discriminate --config "$WORK/unlaunchable/config.json"
assert_eq "an unlaunchable check is refused" "2" "$RUN_RC"
assert_contains "the refusal states nothing was measured" "Nothing was measured" "$RUN_OUT"
assert_not_contains "no traceback reaches the operator" "Traceback (most recent call last)" "$RUN_OUT"
assert_eq "the target survives an unlaunchable check" \
  "$(cat "$WORK/ok/subject.py")" "$(cat "$WORK/unlaunchable/subject.py")"

# --- 5. a signal absent from BOTH arms reports HARNESS BROKEN ---
mkdir -p "$WORK/nosignal"
write_subject "$WORK/nosignal"
write_check "$WORK/nosignal"
cat >"$WORK/nosignal/config.json" <<CONFIG
{
  "target": "$WORK/nosignal/subject.py",
  "anchor": "$FIX_LINE",
  "replacement": "pass  # fix disabled",
  "check": {"argv": $CHECK_ARGV, "cwd": "$WORK/nosignal", "timeout": 120},
  "signal": {"regex": "^NEVER MATCHES ANYTHING.*$"},
  "expect": {"negative_contains": "FAIL:", "positive_contains": "PASS:"}
}
CONFIG
run_discriminate --config "$WORK/nosignal/config.json"
assert_eq "a signal absent from both arms is refused" "2" "$RUN_RC"
assert_contains "the refusal names the never-ran shape" "matched in NEITHER arm" "$RUN_OUT"
assert_contains "the refusal denies it is a negative result" "not a negative result" "$RUN_OUT"

# --- 6. identical FAILING arms with NO signal config report HARNESS BROKEN ---
# With `signal` omitted the signal is the exit code, which is a documented and
# supported shape. Any shared NON-ZERO code then lands on the identical-arms
# branch, and 127 is only the most visible spelling of "never ran": a check that
# cannot open its own script exits 2 in both arms just as symmetrically. Scoring
# that as a discrimination verdict would be a confident claim about a check that
# may never have executed.
# discriminating-skip-required: this case is the only cover for the no-signal
# path into the identical-arms branch.
mkdir -p "$WORK/rcsignal"
write_subject "$WORK/rcsignal"
cat >"$WORK/rcsignal/config.json" <<CONFIG
{
  "target": "$WORK/rcsignal/subject.py",
  "anchor": "$FIX_LINE",
  "replacement": "pass  # fix disabled",
  "check": {"argv": ["$HARNESS_PYTHON", "no-such-check.py"], "cwd": "$WORK/rcsignal"}
}
CONFIG
run_discriminate --config "$WORK/rcsignal/config.json"
assert_eq "identical failing arms with no signal config are refused" "2" "$RUN_RC"
assert_contains "the refusal says the harness is broken" "HARNESS BROKEN" "$RUN_OUT"
assert_contains "the refusal names the identical failing signal" "IDENTICAL FAILING signal" "$RUN_OUT"
assert_contains "the refusal admits it cannot tell the two cases apart" \
  "cannot tell a check that fails the same way" "$RUN_OUT"
assert_not_contains "it does not score a discrimination verdict" \
  "VERDICT: NOT DISCRIMINATING" "$RUN_OUT"
assert_not_contains "it does not claim the check ran" "exercises the patched code path, or" "$RUN_OUT"

# --- 7. a check that passes with the fix disabled does not discriminate ---
mkdir -p "$WORK/weak"
write_subject "$WORK/weak"
cat >"$WORK/weak/check.py" <<'WEAK'
print("PASS: the suffix is ignored by this check")
WEAK
write_config "$WORK/weak" config.json "$CHECK_ARGV"
run_discriminate --config "$WORK/weak/config.json"
assert_eq "a check that cannot fail exits 1" "1" "$RUN_RC"
assert_contains "the identical PASSING arms are named" "IDENTICAL PASSING signal" "$RUN_OUT"
assert_contains "the report rules out a patch that failed to land" "verified applied on disk" "$RUN_OUT"

# --- 8. patch preconditions ---
mkdir -p "$WORK/anchor"
write_subject "$WORK/anchor"
write_check "$WORK/anchor"

cat >"$WORK/anchor/missing.json" <<CONFIG
{
  "target": "$WORK/anchor/subject.py",
  "anchor": "this text is not in the file at all",
  "replacement": "something else",
  "check": {"argv": $CHECK_ARGV, "cwd": "$WORK/anchor"}
}
CONFIG
run_discriminate --config "$WORK/anchor/missing.json"
assert_eq "an absent anchor is refused" "2" "$RUN_RC"
assert_contains "the absent anchor reports its count" "occurs 0 times" "$RUN_OUT"

cat >"$WORK/anchor/noop.json" <<CONFIG
{
  "target": "$WORK/anchor/subject.py",
  "anchor": "import sys",
  "replacement": "import sys",
  "check": {"argv": $CHECK_ARGV, "cwd": "$WORK/anchor"}
}
CONFIG
run_discriminate --config "$WORK/anchor/noop.json"
assert_eq "a no-op patch is refused" "2" "$RUN_RC"
assert_contains "the refusal names the unvaried-arms consequence" "never varied" "$RUN_OUT"

printf 'value = 1\nvalue = 1\n' >"$WORK/anchor/twice.py"
cat >"$WORK/anchor/twice.json" <<CONFIG
{
  "target": "$WORK/anchor/twice.py",
  "anchor": "value = 1",
  "replacement": "value = 2",
  "check": {"argv": $CHECK_ARGV, "cwd": "$WORK/anchor"}
}
CONFIG
run_discriminate --config "$WORK/anchor/twice.json"
assert_eq "an ambiguous anchor is refused" "2" "$RUN_RC"
assert_contains "the ambiguous anchor reports its count" "occurs 2 times" "$RUN_OUT"
assert_eq "a refused run leaves the target alone" \
  "$(printf 'value = 1\nvalue = 1')" "$(cat "$WORK/anchor/twice.py")"

[[ "${FAILED:-0}" -eq 0 ]] || exit 1
echo "OK: discriminate arms, restore and preconditions"
exit 0
