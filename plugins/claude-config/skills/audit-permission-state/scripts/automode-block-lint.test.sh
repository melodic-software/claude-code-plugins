#!/usr/bin/env bash
# Regression tests for automode-block-lint.sh (self-contained — ships with the plugin).
#
# Every case drives the shipped reader against a CHECKED-IN FIXTURE. No test
# invokes `claude auto-mode` and no test reads the operator's config: the
# invalid-JSON defect is machine-conditional, so a check run against the real CLI
# would pass or fail for reasons unrelated to this code.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/automode-block-lint.sh"
FIXTURES="$SCRIPT_DIR/../evals/fixtures"

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
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: $2, actual: $3"; fi
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
count_matching() { printf '%s\n' "$1" | grep -cE "$2"; }

if ! command -v python3 >/dev/null 2>&1 && ! command -v python >/dev/null 2>&1; then
  echo "SKIP: python3 not installed — this lane is optional by design" >&2
  exit 0
fi

CONFIG="$FIXTURES/automode-config-rawctl.json"
DEFAULTS="$FIXTURES/automode-defaults.json"

run() {
  # Always fixtured, never the real CLI. Cases needing different fixtures build
  # their own `env` invocation rather than threading overrides through here.
  env AUTOMODE_CONFIG_FIXTURE="$CONFIG" AUTOMODE_DEFAULTS_FIXTURE="$DEFAULTS" bash "$SCRIPT"
}

# --- Criterion 8, defect 1: a raw control character inside a string value -----
# The headline defensive-contract case. The shipped reader must return all four
# sections from a payload a strict parser rejects — and the assertion proves the
# fixture really is invalid rather than trusting that it was built correctly.
if command -v jq >/dev/null 2>&1; then
  jq_rc=0
  jq -e . "$CONFIG" >/dev/null 2>&1 || jq_rc=$?
  if [[ "$jq_rc" -ne 0 ]]; then
    pass "the fixture really does carry a raw control character (jq rejects it)"
  else
    fail "the fixture really does carry a raw control character (jq rejects it)" \
      "jq parsed it cleanly, so this suite is not testing the measured defect"
  fi
else
  pass "strict-parser rejection (skipped — jq not installed)"
fi

OUT=$(run)
assert_contains "the non-strict reader parses what jq cannot" "$OUT" "status=read"
assert_contains "all four sections are seen" "$OUT" "sections=4"

# --- Criterion 8, defect 3: a label carrying a bracketed annotation -----------
# "Git Destructive [named+specifics …]: …" splits at the first '[', not the
# first ':'. Splitting at the colon would carry the annotation into the label.
assert_contains "a bracketed label is cut at the bracket" "$OUT" "First missing: Git Destructive"
assert_not_contains "the annotation is not carried into the label" "$OUT" "named+specifics"

# --- Criterion 4: a customized section discards the built-in list -------------
assert_eq "exactly one section is reported as discarding its defaults" 1 "$(count_matching "$OUT" '\[C4-defaults\]')"
assert_contains "the finding names the section" "$OUT" "[C4-defaults] soft_deny"
assert_contains "and states how many entries are gone" "$OUT" "1 of the 2 built-in"
assert_contains "and states the mechanic rather than just the symptom" "$OUT" "REPLACES the built-in list"

# A section that still carries every built-in entry was never customized: the
# CLI expands "$defaults" in its own output, so firing here would report a
# discard that did not happen.
assert_not_contains "an expanded-but-untouched section does not fire" "$OUT" "[C4-defaults] environment"
assert_not_contains "nor does one identical to the built-in list" "$OUT" "[C4-defaults] hard_deny"

# A section carrying "$defaults" explicitly is never a finding.
assert_not_contains "a section carrying \$defaults does not fire" "$OUT" "[C4-defaults] allow"

# --- Candidate 2: the same subject allowed and denied -------------------------
assert_eq "the contradiction fires once" 1 "$(count_matching "$OUT" '\[C2b-contradiction\]')"
assert_contains "it names both sections to reconcile" "$OUT" "appears in both allow and hard_deny"

# --- Candidate 3: an entry an earlier hard_deny forecloses --------------------
assert_eq "the shadowed entry fires once" 1 "$(count_matching "$OUT" '\[C3-shadowed\]')"
assert_contains "it says why the entry can never fire" "$OUT" "cannot be overridden"

# --- Criterion 8, defect 2: a MISSING key, not an empty array ----------------
# `defaults --label <x>` omits a non-matching key entirely. A reader that
# expects an empty array raises instead of reporting "no entries".
MISSING_KEY="$TEST_TMPDIR/defaults-missing-key.json"
printf '{"allow": ["Only Section: one entry."]}\n' >"$MISSING_KEY"
OUT_MISSING=$(env AUTOMODE_CONFIG_FIXTURE="$CONFIG" AUTOMODE_DEFAULTS_FIXTURE="$MISSING_KEY" bash "$SCRIPT")
rc=$?
assert_exit "a defaults payload missing three keys does not crash the reader" 0 "$rc"
assert_contains "and the run still reports its status" "$OUT_MISSING" "status=read"
assert_not_contains "a missing key raises no defaults finding for that section" "$OUT_MISSING" "[C4-defaults] soft_deny"

# The same tolerance on the config side.
EMPTY_CONFIG="$TEST_TMPDIR/config-empty.json"
printf '{}\n' >"$EMPTY_CONFIG"
OUT_EMPTY=$(env AUTOMODE_CONFIG_FIXTURE="$EMPTY_CONFIG" AUTOMODE_DEFAULTS_FIXTURE="$DEFAULTS" bash "$SCRIPT")
assert_contains "a config with no sections is read, not crashed on" "$OUT_EMPTY" "sections=0"
assert_contains "and reports no findings rather than failing" "$OUT_EMPTY" "findings=0"

# --- Criterion 8, defect 4: exit status is never trusted ----------------------
# A command that exits 0 having produced nothing must be reported as unavailable.
# This is the difference between "your block is clean" and "the block was never
# read", and only one of those is true.
EMPTY_OUT="$TEST_TMPDIR/empty.json"
: >"$EMPTY_OUT"
OUT_NOUSE=$(env AUTOMODE_CONFIG_FIXTURE="$EMPTY_OUT" AUTOMODE_DEFAULTS_FIXTURE="$DEFAULTS" bash "$SCRIPT")
rc=$?
assert_exit "an empty capture still exits 0" 0 "$rc"
assert_contains "an empty capture is reported unavailable, not clean" "$OUT_NOUSE" "status=unavailable"
assert_contains "and says explicitly that it is not a clean bill" "$OUT_NOUSE" "NOT a clean bill"
assert_eq "no findings are invented from an unread block" 0 "$(count_matching "$OUT_NOUSE" '^finding ')"

# Unparseable even non-strictly is reported as unread rather than as empty.
GARBAGE="$TEST_TMPDIR/garbage.json"
printf 'this is not json at all\n' >"$GARBAGE"
OUT_GARBAGE=$(env AUTOMODE_CONFIG_FIXTURE="$GARBAGE" AUTOMODE_DEFAULTS_FIXTURE="$DEFAULTS" bash "$SCRIPT")
assert_contains "unparseable output is reported unparseable" "$OUT_GARBAGE" "status=unparseable"
assert_eq "and yields no findings" 0 "$(count_matching "$OUT_GARBAGE" '^finding ')"

# --- The lane is optional: no python, no failure ------------------------------
# With python unreachable the lane must skip visibly and exit 0, so one lane's
# prerequisite never becomes the whole skill's problem.
STUB="$TEST_TMPDIR/stub-path"
mkdir -p "$STUB"
real_bash="$(command -v bash)"
for tool in mktemp rm cat tr tail printf; do
  src="$(command -v "$tool" 2>/dev/null)" || continue
  printf '#!%s\nexec "%s" "$@"\n' "$real_bash" "$src" >"$STUB/$tool"
  chmod +x "$STUB/$tool"
done
rc=0
OUT_NOPY=$(env AUTOMODE_CONFIG_FIXTURE="$CONFIG" AUTOMODE_DEFAULTS_FIXTURE="$DEFAULTS" \
  PATH="$STUB" "$real_bash" "$SCRIPT" 2>&1) || rc=$?
assert_exit "a missing python does not fail the run" 0 "$rc"
assert_contains "the skip notice names the lane" "$OUT_NOPY" "autoMode block lane SKIPPED"
assert_contains "and says why a POSIX fallback is not possible" "$OUT_NOPY" "non-strict JSON parser"
assert_contains "and states the blast radius" "$OUT_NOPY" "Every other stage of this skill is unaffected"
assert_contains "the summary records the skip rather than reporting zero findings" "$OUT_NOPY" "status=skipped"

# --- critique: surfaced, wrapped, never replaced ------------------------------
TRUNCATED="$TEST_TMPDIR/critique-truncated.txt"
printf 'Your rules are mostly fine, but entry four is covered only when the resolving output is visible earlier' >"$TRUNCATED"
OUT_TRUNC=$(env AUTOMODE_CONFIG_FIXTURE="$CONFIG" AUTOMODE_DEFAULTS_FIXTURE="$DEFAULTS" \
  AUTOMODE_CRITIQUE_FIXTURE="$TRUNCATED" bash "$SCRIPT" --critique)
assert_contains "the critique text is surfaced verbatim" "$OUT_TRUNC" "entry four is covered only when"
assert_contains "a mid-sentence cut is called out as truncated" "$OUT_TRUNC" "appears TRUNCATED"
assert_contains "and says truncation is undetectable from exit status" "$OUT_TRUNC" "not detectable from exit status"

COMPLETE="$TEST_TMPDIR/critique-complete.txt"
printf 'Your rules look consistent and every entry states a checkable condition.\n' >"$COMPLETE"
OUT_COMPLETE=$(env AUTOMODE_CONFIG_FIXTURE="$CONFIG" AUTOMODE_DEFAULTS_FIXTURE="$DEFAULTS" \
  AUTOMODE_CRITIQUE_FIXTURE="$COMPLETE" bash "$SCRIPT" --critique)
assert_not_contains "a complete critique is not called truncated" "$OUT_COMPLETE" "appears TRUNCATED"

EMPTY_CRIT="$TEST_TMPDIR/critique-empty.txt"
: >"$EMPTY_CRIT"
OUT_NOCRIT=$(env AUTOMODE_CONFIG_FIXTURE="$CONFIG" AUTOMODE_DEFAULTS_FIXTURE="$DEFAULTS" \
  AUTOMODE_CRITIQUE_FIXTURE="$EMPTY_CRIT" bash "$SCRIPT" --critique)
assert_contains "an empty critique says so plainly" "$OUT_NOCRIT" "critique returned nothing; run it yourself"
assert_contains "and prices the claim with the measurement behind it" "$OUT_NOCRIT" "three consecutive runs"

# Without the flag, critique is never run at all.
assert_not_contains "critique is not surfaced without the flag" "$OUT" "end critique"

# --- A payload that PARSES but has the wrong SHAPE ---------------------------
# Parsing is not enough. A valid JSON array or string parsed cleanly and then
# exploded on the first .get(), exiting 0 with a traceback and NO summary line --
# so a caller grepping status= saw nothing and a success exit. In the one lane
# whose premise is that the CLI's output cannot be trusted, that is the failure
# its own header contract forbids.
for shape in '[1, 2, 3]' '"hello"' '42' 'null'; do
  SHAPE_FILE="$TEST_TMPDIR/shape.json"
  printf '%s
' "$shape" >"$SHAPE_FILE"
  rc=0
  OUT_SHAPE=$(env AUTOMODE_CONFIG_FIXTURE="$SHAPE_FILE" AUTOMODE_DEFAULTS_FIXTURE="$DEFAULTS" bash "$SCRIPT" 2>&1) || rc=$?
  assert_exit "a $shape payload does not crash the lane" 0 "$rc"
  assert_eq "and always emits exactly one summary line" 1 "$(count_matching "$OUT_SHAPE" '^automode summary ')"
  assert_eq "and never reports findings from a payload it could not use" 0 "$(count_matching "$OUT_SHAPE" '^finding ')"
  assert_not_contains "and never leaks a traceback" "$OUT_SHAPE" "Traceback"
done

# --- The critique spawn is priced before it happens --------------------------
# The entry-diff sibling prices its spawn; this one did not, and an unpriced
# spawn is the surprise the opt-in flag exists to prevent.
NOTICE_STUB="$TEST_TMPDIR/notice-stub"
mkdir -p "$NOTICE_STUB"
real_bash_n="$(command -v bash)"
printf '#!%s
printf "stub critique output.\n"
' "$real_bash_n" >"$NOTICE_STUB/claude"
chmod +x "$NOTICE_STUB/claude"
OUT_NOTICE=$(env AUTOMODE_CONFIG_FIXTURE="$CONFIG" AUTOMODE_DEFAULTS_FIXTURE="$DEFAULTS"   PATH="$NOTICE_STUB:$PATH" bash "$SCRIPT" --critique 2>&1)
assert_contains "the critique spawn prints a cost notice" "$OUT_NOTICE" "CRITIQUE COST NOTICE"
assert_contains "the notice says nothing has been spawned yet" "$OUT_NOTICE" "nothing has been spawned yet"

# --- Argument handling --------------------------------------------------------
rc=0
err=$(bash "$SCRIPT" --bogus </dev/null 2>&1) || rc=$?
assert_exit "exit 2 on an unknown argument" 2 "$rc"
assert_contains "the unknown argument is named" "$err" "unknown argument"

rc=0
help=$(bash "$SCRIPT" --help </dev/null 2>&1) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help states the optional-runtime contract" "$help" "exits 0 so the rest of the skill still runs"
assert_contains "--help states that reset is never run" "$help" "it never
runs 'claude auto-mode reset'"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
