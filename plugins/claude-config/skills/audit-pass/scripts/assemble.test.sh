#!/usr/bin/env bash
# Regression tests for assemble.sh (self-contained — ships with the plugin).
#
# The fixture partial is built to be HOSTILE to the selection rules: it carries
# an abandoned attempt with a complete-looking prefix, a superseded lower epoch,
# and an `open` terminator. A test over a well-behaved partial would pass under
# a selection rule that simply concatenated every row.
#
# Two are NEGATIVE tests in the sense this repo means it: they mutate a copy of
# the script to delete exactly one selection rule and assert the mutated copy
# produces the output the real one refuses.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/assemble.sh"

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
  *"$3"*) fail "$1" "expected NOT to contain: $3" ;;
  *) pass "$1" ;;
  esac
}
assert_file() {
  if [[ -f "$2" ]]; then pass "$1"; else fail "$1" "no such file: $2"; fi
}

run() { bash "$SCRIPT" "$@"; }

if ! command -v python3 >/dev/null 2>&1; then
  printf 'SKIP: python3 absent; assemble.sh refuses without it and there is nothing to test\n'
  rc=0
  run assemble --run-dir "$TEST_TMPDIR" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -eq 2 ]]; then
    printf 'PASS: without python3 assembly exits 2 naming the prerequisite\n'
    exit 0
  fi
  printf 'FAIL: without python3 assembly should exit 2, got %s\n' "$rc" >&2
  exit 1
fi

RUN_DIR="$TEST_TMPDIR/run"
mkdir -p "$RUN_DIR"

# A SUPERSEDED epoch. A writer that a stale-lease adoption fenced appends to its
# own file; assembly must read only the highest epoch present, and the lower
# files are retained as the evidence that an adoption happened.
cat >"$RUN_DIR/findings.partial.1.jsonl" <<'EOF'
{"record":"start","attempt":{"lane":"skills","ordinal":1}}
{"record":"finding","attempt":{"lane":"skills","ordinal":1},"lane":"skills","tier":"derived","severity":"warn","finding_id/v1":"fencedfencedfenc","identity":{"check":"p/s/fenced","claim":"claim.fenced","sites":[{"surface":"fenced.md","anchor":"s:"}]}}
{"record":"terminator","attempt":{"lane":"skills","ordinal":1},"state":"complete","verification":"verified"}
EOF

# The winning epoch. Lane `skills` has an ABANDONED attempt 1 that appended a
# finding and never terminated, plus a terminated attempt 2. Lane `conflicts`
# terminates normally. Lane `doctor` terminates `open`, which renders but leaves
# the lane INCOMPLETE so --resume re-runs it.
cat >"$RUN_DIR/findings.partial.2.jsonl" <<'EOF'
{"record":"start","attempt":{"lane":"skills","ordinal":1}}
{"record":"finding","attempt":{"lane":"skills","ordinal":1},"lane":"skills","tier":"derived","severity":"error","finding_id/v1":"abandonedabandon","identity":{"check":"p/s/abandoned","claim":"claim.abandoned","sites":[{"surface":"abandoned.md","anchor":"s:"}]}}
{"record":"supersession","lane":"skills","retires":1}
{"record":"start","attempt":{"lane":"skills","ordinal":2}}
{"record":"finding","attempt":{"lane":"skills","ordinal":2},"lane":"skills","tier":"derived","severity":"warn","group":"g:1111111111111111","finding_id/v1":"aaaaaaaaaaaaaaaa","identity":{"check":"p/s/one","claim":"claim.one","sites":[{"surface":"a.md","anchor":"e:aaaaaaaaaaaa:bbbbbbbb"}]}}
{"record":"finding","attempt":{"lane":"skills","ordinal":2},"lane":"skills","tier":"judged","severity":"info","group":"g:1111111111111111","finding_id/v1":"bbbbbbbbbbbbbbbb","identity":{"check":"p/s/one","claim":"claim.one","sites":[{"surface":"b.md","anchor":"e:cccccccccccc:dddddddd"}]}}
{"record":"note","attempt":{"lane":"skills","ordinal":2},"lane":"skills","tier":"note","note_id":"n1","names":["aaaaaaaaaaaaaaaa","bbbbbbbbbbbbbbbb"]}
{"record":"terminator","attempt":{"lane":"skills","ordinal":2},"state":"complete","verification":"inline","skipped":[{"surface":"vendor/x.md","reason":"class 2 exclusion"}]}
{"record":"start","attempt":{"lane":"conflicts","ordinal":1}}
{"record":"terminator","attempt":{"lane":"conflicts","ordinal":1},"state":"complete","verification":"verified"}
{"record":"start","attempt":{"lane":"doctor","ordinal":1}}
{"record":"terminator","attempt":{"lane":"doctor","ordinal":1},"state":"open","verification":"skipped"}
EOF

cat >"$TEST_TMPDIR/meta.json" <<'EOF'
{
  "run": {"id": "20260913T000000Z-abcdef", "headBaseline": "abcdef", "headEndpoint": "abcdef",
          "harness": "2.1.268", "arguments": "--lanes skills,conflicts"},
  "target": "/repo",
  "partialScope": true,
  "gate": {"verdict": "indeterminate", "reason": "no comparable predecessor",
           "properties": {"P1": "not evaluated", "P4": "satisfied"}},
  "comparability": {"verdict": "non-comparable", "movedInput": "--lanes"}
}
EOF

# --- Case 1: epoch selection ------------------------------------------------

assert_eq "epoch reports the highest partial present" "2" "$(run epoch --run-dir "$RUN_DIR")"

# --- Case 2: assembly ------------------------------------------------------

OUT=$(run assemble --run-dir "$RUN_DIR" --meta "$TEST_TMPDIR/meta.json")
assert_file "assembly writes findings.json" "$RUN_DIR/findings.json"
assert_file "assembly writes report.md beside it" "$RUN_DIR/report.md"
assert_contains "and names both artifacts on stdout" "$OUT" "report.md"

JSON=$(cat "$RUN_DIR/findings.json")
assert_contains "the assembled document carries its ownership header" "$JSON" "audit-pass/report/v1"

# The superseded epoch is not read.
assert_not_contains "a lower epoch's rows are not assembled" "$JSON" "fencedfencedfenc"
assert_file "and the superseded partial is retained, not deleted" "$RUN_DIR/findings.partial.1.jsonl"

# The abandoned attempt's rows are discarded outright, including its
# complete-looking prefix.
assert_not_contains "an abandoned attempt's findings are discarded" "$JSON" "abandonedabandon"
assert_contains "the winning attempt's derived finding is assembled" "$JSON" "aaaaaaaaaaaaaaaa"
assert_contains "the winning attempt's judged finding is assembled" "$JSON" "bbbbbbbbbbbbbbbb"

# Tier routes the row to its section: derived to mechanical, judged to
# behavioral, note to notes. They stay separate because their guarantees differ.
MECH=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print([r["finding_id/v1"] for r in d["sections"]["mechanical"]])' "$RUN_DIR/findings.json")
BEHAV=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print([r["finding_id/v1"] for r in d["sections"]["behavioral"]])' "$RUN_DIR/findings.json")
NOTES=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print([r["note_id"] for r in d["sections"]["notes"]])' "$RUN_DIR/findings.json")
assert_contains "a derived row lands in the mechanical section" "$MECH" "aaaaaaaaaaaaaaaa"
assert_contains "a judged row lands in the behavioral section" "$BEHAV" "bbbbbbbbbbbbbbbb"
assert_contains "a note lands in the notes section, not among the findings" "$NOTES" "n1"
assert_not_contains "and a note is not in the mechanical section" "$MECH" "n1"

# `open` is an assembly terminator, not a completion.
DOCTOR_COMPLETE=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print([l["complete"] for l in d["lanes"] if l["lane"]=="doctor"][0])' "$RUN_DIR/findings.json")
assert_eq "an open terminator renders the lane but leaves it incomplete" "False" "$DOCTOR_COMPLETE"
SKILLS_COMPLETE=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print([l["complete"] for l in d["lanes"] if l["lane"]=="skills"][0])' "$RUN_DIR/findings.json")
assert_eq "an ordinary completion marks the lane complete" "True" "$SKILLS_COMPLETE"

assert_contains "the supersession record is carried into the document" "$JSON" "supersession"

# --- Case 3: report.md ------------------------------------------------------

REPORT=$(cat "$RUN_DIR/report.md")
assert_eq "the ownership line is the first line of report.md" \
  "<!-- audit-pass/report/v1 -->" "$(head -1 "$RUN_DIR/report.md")"
assert_contains "the header names the run" "$REPORT" "20260913T000000Z-abcdef"
assert_contains "the header marks a narrowed run partial-scope" "$REPORT" "partial-scope"
assert_contains "the verdict block carries the gate" "$REPORT" "indeterminate"
assert_contains "and names the comparability input that moved" "$REPORT" "--lanes"
assert_contains "a property with no verdict renders as not evaluated" "$REPORT" "not evaluated"
assert_contains "the headline counts the tiers" "$REPORT" "## Headline"
assert_contains "a finding renders its group" "$REPORT" "g:1111111111111111"

# Every section renders, including the empty ones: an absent section and an
# empty one look identical on the page and mean opposite things.
for section in Notes Suppressed Delegated Skipped Verification Inventory; do
  assert_contains "the $section section is rendered" "$REPORT" "## $section"
done
assert_contains "an empty section says none rather than vanishing" "$REPORT" "none"
assert_contains "a lane's skipped surface is carried with its reason" "$REPORT" "class 2 exclusion"
assert_contains "verification mode is reported per lane" "$REPORT" "mode: \`inline\`"

# --- Case 4: render re-renders from findings.json ---------------------------

cp "$RUN_DIR/report.md" "$TEST_TMPDIR/report-from-assembly.md"
rm -f "$RUN_DIR/report.md"
run render --findings "$RUN_DIR/findings.json" >/dev/null
assert_file "render rebuilds report.md from the assembled document" "$RUN_DIR/report.md"
if cmp -s "$TEST_TMPDIR/report-from-assembly.md" "$RUN_DIR/report.md"; then
  pass "and produces byte-identical output to the one assembly wrote"
else
  fail "and produces byte-identical output to the one assembly wrote" "the two renderings differ"
fi

# --- Case 5: a malformed row is refused, never silently dropped -------------

BAD_DIR="$TEST_TMPDIR/bad"
mkdir -p "$BAD_DIR"
cat >"$BAD_DIR/findings.partial.1.jsonl" <<'EOF'
{"record":"start","attempt":{"lane":"skills","ordinal":1}}
{bad json}
EOF
rc=0
run assemble --run-dir "$BAD_DIR" >/dev/null 2>&1 || rc=$?
assert_exit "a malformed partial row fails assembly rather than being skipped" 2 "$rc"

# --- Case 6: NEGATIVE tests on the selection rules --------------------------

# Delete the highest-epoch selection and the fenced writer's rows come back.
COPY="$TEST_TMPDIR/no-epoch-select.sh"
# shellcheck disable=SC2016  # the $ sequences are literal script text, not expansions
sed 's/^    if \[\[ -z "\$best" || "\$ep" -gt "\$best" \]\]; then$/    if [[ -z "$best" ]]; then/' "$SCRIPT" >"$COPY"
MUT_DIR="$TEST_TMPDIR/mut"
mkdir -p "$MUT_DIR"
cp "$RUN_DIR/findings.partial.1.jsonl" "$RUN_DIR/findings.partial.2.jsonl" "$MUT_DIR/"
bash "$COPY" assemble --run-dir "$MUT_DIR" >/dev/null 2>&1
MUT_JSON=$(cat "$MUT_DIR/findings.json" 2>/dev/null || printf '')
assert_contains "without highest-epoch selection a fenced writer's rows are assembled" \
  "$MUT_JSON" "fencedfencedfenc"

# Delete the attempt-ordinal filter and the abandoned attempt's findings come back.
COPY2="$TEST_TMPDIR/no-attempt-filter.sh"
sed '/if (ordinal if isinstance(ordinal, int) else 0) != winner\[0\]:/,+1d' "$SCRIPT" >"$COPY2"
MUT2_DIR="$TEST_TMPDIR/mut2"
mkdir -p "$MUT2_DIR"
cp "$RUN_DIR/findings.partial.2.jsonl" "$MUT2_DIR/"
bash "$COPY2" assemble --run-dir "$MUT2_DIR" >/dev/null 2>&1
MUT2_JSON=$(cat "$MUT2_DIR/findings.json" 2>/dev/null || printf '')
assert_contains "without the attempt filter an abandoned attempt's findings are assembled" \
  "$MUT2_JSON" "abandonedabandon"

# --- Case 7: usage ----------------------------------------------------------

rc=0
run >/dev/null 2>&1 || rc=$?
assert_exit "no command exits 2" 2 "$rc"
rc=0
run nonsense >/dev/null 2>&1 || rc=$?
assert_exit "an unknown command exits 2" 2 "$rc"
rc=0
run assemble >/dev/null 2>&1 || rc=$?
assert_exit "assemble without --run-dir exits 2" 2 "$rc"
rc=0
EMPTY_DIR="$TEST_TMPDIR/empty"
mkdir -p "$EMPTY_DIR"
run assemble --run-dir "$EMPTY_DIR" >/dev/null 2>&1 || rc=$?
assert_exit "assemble with no partial exits 2" 2 "$rc"
rc=0
run --help >/dev/null 2>&1 || rc=$?
assert_exit "--help exits 0" 0 "$rc"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
