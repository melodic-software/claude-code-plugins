#!/usr/bin/env bash
# Self-contained tests for score-golden.sh. The golden set does not exist yet
# (Phase 6 authors it), so this suite builds a synthetic expected/actual pair
# inline and pins the arithmetic against it. Per the shell-test-helpers
# convention, assertion helpers are local.
#
# The load-bearing case here is what the scorer refuses to guess. A golden case
# the run never scored is DECLINED and excluded from the tally, never counted
# as a miss: scoring a case nobody ran would report a recall failure that
# describes the harness rather than the detector.
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCORE="$SCRIPT_DIR/score-golden.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed (this suite reads the script's JSON product)" >&2
  exit 0
fi

export HOME="$TEST_TMPDIR/home"
export CLAUDE_PROJECT_DIR="$TEST_TMPDIR/noconfig"
mkdir -p "$HOME" "$CLAUDE_PROJECT_DIR"

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
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "exit $3" "exit $2"; fi
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$3" "$2"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$2" ;;
  esac
}

# --- Synthetic golden set --------------------------------------------------------
#
# Seven cases, chosen so every confusion-matrix cell and both refusal paths are
# exercised, and so the resulting precision and recall are exact quarters.

GOLDEN="$TEST_TMPDIR/golden"

case_dir() {
  mkdir -p "$GOLDEN/$1"
  printf '%s\n' "# case $1" >"$GOLDEN/$1/case.md"
  printf '%s\n' "$2" >"$GOLDEN/$1/expected.json"
}

case_dir c1-hit '{"findings": [{"class": "verbatim", "tier": "fingerprint-confirmed",
  "span": {"start_line": 10, "end_line": 20}}], "negatives": false, "notes": "clean hit"}'
case_dir c2-missed '{"findings": [{"class": "verbatim", "tier": "fingerprint-confirmed",
  "span": {"start_line": 5, "end_line": 9}}], "negatives": false, "notes": "run found nothing"}'
case_dir c3-negative-clean '{"findings": [], "negatives": true, "notes": "hard negative, not flagged"}'
case_dir c4-negative-flagged '{"findings": [], "negatives": true, "notes": "hard negative, flagged"}'
case_dir c5-wrong-class '{"findings": [{"class": "near-verbatim",
  "span": {"start_line": 1, "end_line": 10}}], "negatives": false, "notes": "class mismatch"}'
case_dir c6-disjoint-span '{"findings": [{"class": "verbatim",
  "span": {"start_line": 100, "end_line": 110}}], "negatives": false, "notes": "span mismatch"}'
case_dir c7-not-run '{"findings": [{"class": "verbatim",
  "span": {"start_line": 1, "end_line": 5}}], "negatives": false, "notes": "never scored"}'

ACTUAL="$TEST_TMPDIR/actual.json"
printf '%s\n' '{
  "cases_run": ["c1-hit", "c2-missed", "c3-negative-clean", "c4-negative-flagged",
                "c5-wrong-class", "c6-disjoint-span"],
  "findings": [
    {"case": "c1-hit", "class": "verbatim", "tier": "fingerprint-confirmed",
     "span": {"start_line": 12, "end_line": 18}},
    {"case": "c4-negative-flagged", "class": "verbatim",
     "span": {"start_line": 1, "end_line": 3}},
    {"case": "c5-wrong-class", "class": "paraphrase",
     "span": {"start_line": 1, "end_line": 10}},
    {"case": "c6-disjoint-span", "class": "verbatim",
     "span": {"start_line": 1, "end_line": 5}}
  ]
}' >"$ACTUAL"

run() { bash "$SCORE" "$@"; }

# --- Usage -----------------------------------------------------------------------

OUT="$(run --help 2>&1)"
assert_exit "--help exits 0" "$?" "0"
assert_contains "--help names the script" "$OUT" "score-golden.sh"

run --nope >/dev/null 2>&1
assert_exit "unknown argument exits 2" "$?" "2"

run --golden "$GOLDEN" >/dev/null 2>&1
assert_exit "a missing --actual exits 2" "$?" "2"

run --actual "$ACTUAL" >/dev/null 2>&1
assert_exit "a missing --golden exits 2" "$?" "2"

run --golden "$TEST_TMPDIR/absent" --actual "$ACTUAL" >/dev/null 2>&1
assert_exit "a nonexistent golden directory exits 2" "$?" "2"

run --golden "$GOLDEN" --actual "$TEST_TMPDIR/absent.json" >/dev/null 2>&1
assert_exit "a nonexistent actual file exits 2" "$?" "2"

mkdir -p "$TEST_TMPDIR/emptygolden"
run --golden "$TEST_TMPDIR/emptygolden" --actual "$ACTUAL" >/dev/null 2>&1
assert_exit "a golden directory with no cases exits 3" "$?" "3"

# --- The tally -------------------------------------------------------------------

OUT="$(run --golden "$GOLDEN" --actual "$ACTUAL" 2>/dev/null)"
assert_exit "a clean run exits 0" "$?" "0"

echo "$OUT" | jq -e . >/dev/null 2>&1
assert_exit "stdout is valid JSON" "$?" "0"

assert_eq "every golden case is accounted for" \
  "$(echo "$OUT" | jq -r '.cases')" "7"
assert_eq "a matching finding is a true positive" \
  "$(echo "$OUT" | jq -r '.overall.tp')" "1"
assert_eq "a positive case with no matching finding is a false negative" \
  "$(echo "$OUT" | jq -r '.overall.fn')" "3"
assert_eq "a finding matching nothing expected is a false positive" \
  "$(echo "$OUT" | jq -r '.overall.fp')" "3"
assert_eq "a clean hard negative is a true negative" \
  "$(echo "$OUT" | jq -r '.overall.tn')" "1"

assert_eq "precision is tp over tp plus fp" \
  "$(echo "$OUT" | jq -r '.overall.precision')" "0.25"
assert_eq "recall is tp over tp plus fn" \
  "$(echo "$OUT" | jq -r '.overall.recall')" "0.25"
assert_eq "the scored total excludes the unscored case" \
  "$(echo "$OUT" | jq -r '.overall.scored')" "6"

# --- Matching rules --------------------------------------------------------------

assert_eq "an overlapping span on the right class matches" \
  "$(echo "$OUT" | jq -r '.by_case[] | select(.case == "c1-hit") | .verdict')" "tp"
assert_eq "a class mismatch does not match" \
  "$(echo "$OUT" | jq -r '.by_case[] | select(.case == "c5-wrong-class") | .verdict')" "fn+fp"
assert_eq "a disjoint span does not match" \
  "$(echo "$OUT" | jq -r '.by_case[] | select(.case == "c6-disjoint-span") | .verdict')" "fn+fp"
assert_eq "a flagged hard negative is a false positive" \
  "$(echo "$OUT" | jq -r '.by_case[] | select(.case == "c4-negative-flagged") | .verdict')" "fp"

# --- Refusals --------------------------------------------------------------------

assert_eq "a case the run never scored is declined" \
  "$(echo "$OUT" | jq -r '[.declined[] | select(.cases[] == "c7-not-run")] | length')" "1"
assert_contains "the decline states why" \
  "$(echo "$OUT" | jq -r '.declined[].reason')" "not scored"
assert_eq "a declined case is not counted as a miss" \
  "$(echo "$OUT" | jq -r '.overall.tp + .overall.fn + .overall.tn')" "5"

NOCOV="$TEST_TMPDIR/nocov.json"
jq 'del(.cases_run)' "$ACTUAL" >"$NOCOV"
NC="$(run --golden "$GOLDEN" --actual "$NOCOV" 2>/dev/null)"
assert_eq "an undeclared coverage list is reported, not assumed away" \
  "$(echo "$NC" | jq -r '.coverage_declared')" "false"
assert_eq "without a coverage list every case is scored" \
  "$(echo "$NC" | jq -r '.overall.scored')" "7"

STRAY="$TEST_TMPDIR/stray.json"
printf '%s\n' '{"cases_run": ["ghost"], "findings": [{"case": "ghost", "class": "verbatim"}]}' >"$STRAY"
ST="$(run --golden "$GOLDEN" --actual "$STRAY" 2>/dev/null)"
assert_contains "a finding for an unknown case is declined with a reason" \
  "$(echo "$ST" | jq -r '.declined[].reason')" "not in the golden set"

# --- Per-class breakdown and gates -----------------------------------------------

assert_eq "cases stratify by their expected class" \
  "$(echo "$OUT" | jq -r '.by_class[] | select(.class == "verbatim") | .n')" "3"
assert_eq "hard negatives stratify as their own class" \
  "$(echo "$OUT" | jq -r '.by_class[] | select(.class == "negative") | .n')" "2"
assert_eq "a class carries its own tally" \
  "$(echo "$OUT" | jq -r '.by_class[] | select(.class == "verbatim") | .tp')" "1"

assert_eq "the gate defaults are the plan's values" \
  "$(echo "$OUT" | jq -r '"\(.gates.fix_precision_bar)/\(.gates.report_recall_floor)/\(.gates.min_n_per_class)"')" \
  "0.95/0.8/10"
assert_contains "a class below min n ships report-only" \
  "$(echo "$OUT" | jq -r '.by_class[] | select(.class == "verbatim") | .gate')" "report-only"

mkdir -p "$CLAUDE_PROJECT_DIR/.claude"
printf '%s\n' '{"gates": {"min_n_per_class": 2, "fix_precision_bar": 0.1, "report_recall_floor": 0.1}}' \
  >"$CLAUDE_PROJECT_DIR/.claude/provenance.json"
CFG="$(run --golden "$GOLDEN" --actual "$ACTUAL" 2>/dev/null)"
assert_eq "config lowers the minimum n" \
  "$(echo "$CFG" | jq -r '.gates.min_n_per_class')" "2"
assert_contains "a class at or above min n binds" \
  "$(echo "$CFG" | jq -r '.by_class[] | select(.class == "verbatim") | .gate')" "binding"
assert_eq "a class is measured against the configured bar" \
  "$(echo "$CFG" | jq -r '.by_class[] | select(.class == "verbatim") | .meets_precision_bar')" "true"
rm -f "$CLAUDE_PROJECT_DIR/.claude/provenance.json"

OUT_SC="$(run --show-config 2>&1)"
assert_exit "--show-config exits 0" "$?" "0"
assert_contains "--show-config prints the gates" "$OUT_SC" "fix_precision_bar"

# --- Division by zero ------------------------------------------------------------

NOFIND="$TEST_TMPDIR/nofind.json"
printf '%s\n' '{"cases_run": ["c3-negative-clean"], "findings": []}' >"$NOFIND"
NF_OUT="$(run --golden "$GOLDEN" --actual "$NOFIND" 2>/dev/null)"
echo "$NF_OUT" | jq -e . >/dev/null 2>&1
assert_exit "a run with no findings at all stays valid JSON" "$?" "0"
assert_eq "precision is null rather than a divide by zero" \
  "$(echo "$NF_OUT" | jq -r '.overall.precision')" "null"

# --- Determinism -----------------------------------------------------------------

RUN_A="$(run --golden "$GOLDEN" --actual "$ACTUAL" 2>/dev/null)"
RUN_B="$(run --golden "$GOLDEN" --actual "$ACTUAL" 2>/dev/null)"
assert_eq "repeat runs produce identical output" "$RUN_A" "$RUN_B"

printf '\nPassed: %s  Failed: %s\n' "$((CASE_NUM - FAILED))" "$FAILED"
[[ "$FAILED" -eq 0 ]]
