#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/assemble.sh"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../../../lib/test-helpers.sh
source "$SCRIPT_DIR/../../../lib/test-helpers.sh"

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

cat >"$RUN_DIR/findings.partial.1.jsonl" <<'EOF'
{"record":"start","attempt":{"lane":"skills","ordinal":1}}
{"record":"finding","attempt":{"lane":"skills","ordinal":1},"lane":"skills","tier":"derived","severity":"warn","finding_id/v1":"fencedfencedfenc","identity":{"check":"p/s/fenced","claim":"claim.fenced","sites":[{"surface":"fenced.md","anchor":"s:"}]}}
{"record":"terminator","attempt":{"lane":"skills","ordinal":1},"state":"complete","verification":"verified"}
EOF

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


assert_eq "epoch reports the highest partial present" "2" "$(run epoch --run-dir "$RUN_DIR")"


OUT=$(run assemble --run-dir "$RUN_DIR" --meta "$TEST_TMPDIR/meta.json")
assert_file "assembly writes findings.json" "$RUN_DIR/findings.json"
assert_file "assembly writes report.md beside it" "$RUN_DIR/report.md"
assert_contains "and names both artifacts on stdout" "$OUT" "report.md"

JSON=$(cat "$RUN_DIR/findings.json")
assert_contains "the assembled document carries its ownership header" "$JSON" "audit-pass/report/v1"

assert_not_contains "a lower epoch's rows are not assembled" "$JSON" "fencedfencedfenc"
assert_file "and the superseded partial is retained, not deleted" "$RUN_DIR/findings.partial.1.jsonl"

assert_not_contains "an abandoned attempt's findings are discarded" "$JSON" "abandonedabandon"
assert_contains "the winning attempt's derived finding is assembled" "$JSON" "aaaaaaaaaaaaaaaa"
assert_contains "the winning attempt's judged finding is assembled" "$JSON" "bbbbbbbbbbbbbbbb"

MECH=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print([r["finding_id/v1"] for r in d["sections"]["mechanical"]])' "$RUN_DIR/findings.json")
BEHAV=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print([r["finding_id/v1"] for r in d["sections"]["behavioral"]])' "$RUN_DIR/findings.json")
NOTES=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print([r["note_id"] for r in d["sections"]["notes"]])' "$RUN_DIR/findings.json")
assert_contains "a derived row lands in the mechanical section" "$MECH" "aaaaaaaaaaaaaaaa"
assert_contains "a judged row lands in the behavioral section" "$BEHAV" "bbbbbbbbbbbbbbbb"
assert_contains "a note lands in the notes section, not among the findings" "$NOTES" "n1"
assert_not_contains "and a note is not in the mechanical section" "$MECH" "n1"

DOCTOR_COMPLETE=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print([l["complete"] for l in d["lanes"] if l["lane"]=="doctor"][0])' "$RUN_DIR/findings.json")
assert_eq "an open terminator renders the lane but leaves it incomplete" "False" "$DOCTOR_COMPLETE"
SKILLS_COMPLETE=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print([l["complete"] for l in d["lanes"] if l["lane"]=="skills"][0])' "$RUN_DIR/findings.json")
assert_eq "an ordinary completion marks the lane complete" "True" "$SKILLS_COMPLETE"

assert_contains "the supersession record is carried into the document" "$JSON" "supersession"


REPORT=$(cat "$RUN_DIR/report.md")
assert_eq "the ownership line is the first line of report.md" \
  "<!-- audit-pass/report/v1 -->" "$(head -1 "$RUN_DIR/report.md")"
assert_contains "the header names the run" "$REPORT" "20260913T000000Z-abcdef"
assert_contains "the header marks a narrowed run partial-scope" "$REPORT" "partial-scope"
assert_contains "the verdict block carries the gate" "$REPORT" "indeterminate"
assert_contains "and names the comparability input that moved" "$REPORT" "--lanes"
assert_contains "a property with no verdict renders as not evaluated" "$REPORT" "not evaluated"
assert_contains "the headline counts the tiers" "$REPORT" "## Headline"

assert_contains "the headline carries the per-severity counts, not just the tiers" \
  "$REPORT" "1 derived, 1 judged (by severity: 1 warn, 1 info), 1 notes, 0 suppressed, 1 skipped, across 3 lanes"

SEV_DIR="$TEST_TMPDIR/sev"
mkdir -p "$SEV_DIR"
cat >"$SEV_DIR/findings.partial.1.jsonl" <<'EOF'
{"record":"start","attempt":{"lane":"skills","ordinal":1}}
{"record":"finding","attempt":{"lane":"skills","ordinal":1},"lane":"skills","tier":"derived","severity":"info","finding_id/v1":"s000000000000001","identity":{"check":"p/s/c","claim":"claim.a","sites":[{"surface":"a.md","anchor":"s:"}]}}
{"record":"finding","attempt":{"lane":"skills","ordinal":1},"lane":"skills","tier":"derived","severity":"blocker","finding_id/v1":"s000000000000002","identity":{"check":"p/s/c","claim":"claim.b","sites":[{"surface":"b.md","anchor":"s:"}]}}
{"record":"finding","attempt":{"lane":"skills","ordinal":1},"lane":"skills","tier":"derived","severity":"zebra","finding_id/v1":"s000000000000003","identity":{"check":"p/s/c","claim":"claim.c","sites":[{"surface":"c.md","anchor":"s:"}]}}
{"record":"finding","attempt":{"lane":"skills","ordinal":1},"lane":"skills","tier":"judged","severity":"aardvark","finding_id/v1":"s000000000000004","identity":{"check":"p/s/c","claim":"claim.d","sites":[{"surface":"d.md","anchor":"s:"}]}}
{"record":"finding","attempt":{"lane":"skills","ordinal":1},"lane":"skills","tier":"judged","severity":"error","finding_id/v1":"s000000000000005","identity":{"check":"p/s/c","claim":"claim.e","sites":[{"surface":"e.md","anchor":"s:"}]}}
{"record":"finding","attempt":{"lane":"skills","ordinal":1},"lane":"skills","tier":"judged","finding_id/v1":"s000000000000006","identity":{"check":"p/s/c","claim":"claim.f","sites":[{"surface":"f.md","anchor":"s:"}]}}
{"record":"terminator","attempt":{"lane":"skills","ordinal":1},"state":"complete","verification":"verified"}
EOF
run assemble --run-dir "$SEV_DIR" >/dev/null 2>&1
SEV_REPORT=$(cat "$SEV_DIR/report.md")
assert_contains "the ladder orders the known severities and sorts unknown ones in after it" \
  "$SEV_REPORT" \
  "3 derived, 3 judged (by severity: 1 blocker, 1 error, 1 info, 1 unspecified, 1 aardvark, 1 zebra), 0 notes, 0 suppressed, 0 skipped, across 1 lanes"

COPY_SEV="$TEST_TMPDIR/no-severity-headline.sh"
sed 's/ (by severity: %s)//; /^        severity_part,$/d' "$SCRIPT" >"$COPY_SEV"
rc=0
bash "$COPY_SEV" render --findings "$SEV_DIR/findings.json" --out "$TEST_TMPDIR/no-sev.md" \
  >/dev/null 2>&1 || rc=$?
NO_SEV=$(cat "$TEST_TMPDIR/no-sev.md" 2>/dev/null || printf '')
assert_exit "the mutated copy still renders" 0 "$rc"
assert_contains "and still counts the tiers" "$NO_SEV" "3 derived, 3 judged, 0 notes"
assert_not_contains "but without the severity half the headline names no severity" \
  "$NO_SEV" "by severity"
assert_contains "a finding renders its group" "$REPORT" "g:1111111111111111"

for section in Notes Suppressed Delegated Skipped Verification Inventory; do
  assert_contains "the $section section is rendered" "$REPORT" "## $section"
done
assert_contains "an empty section says none rather than vanishing" "$REPORT" "none"
assert_contains "a lane's skipped surface is carried with its reason" "$REPORT" "class 2 exclusion"
assert_contains "verification mode is reported per lane" "$REPORT" "mode: \`inline\`"


cp "$RUN_DIR/report.md" "$TEST_TMPDIR/report-from-assembly.md"
rm -f "$RUN_DIR/report.md"
run render --findings "$RUN_DIR/findings.json" >/dev/null
assert_file "render rebuilds report.md from the assembled document" "$RUN_DIR/report.md"
if cmp -s "$TEST_TMPDIR/report-from-assembly.md" "$RUN_DIR/report.md"; then
  pass "and produces byte-identical output to the one assembly wrote"
else
  fail "and produces byte-identical output to the one assembly wrote" "the two renderings differ"
fi


BAD_DIR="$TEST_TMPDIR/bad"
mkdir -p "$BAD_DIR"
cat >"$BAD_DIR/findings.partial.1.jsonl" <<'EOF'
{"record":"start","attempt":{"lane":"skills","ordinal":1}}
{bad json}
EOF
rc=0
run assemble --run-dir "$BAD_DIR" >/dev/null 2>&1 || rc=$?
assert_exit "a malformed partial row fails assembly rather than being skipped" 2 "$rc"


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

COPY2="$TEST_TMPDIR/no-attempt-filter.sh"
sed '/if (ordinal if isinstance(ordinal, int) else 0) != winner\[0\]:/,+1d' "$SCRIPT" >"$COPY2"
MUT2_DIR="$TEST_TMPDIR/mut2"
mkdir -p "$MUT2_DIR"
cp "$RUN_DIR/findings.partial.2.jsonl" "$MUT2_DIR/"
bash "$COPY2" assemble --run-dir "$MUT2_DIR" >/dev/null 2>&1
MUT2_JSON=$(cat "$MUT2_DIR/findings.json" 2>/dev/null || printf '')
assert_contains "without the attempt filter an abandoned attempt's findings are assembled" \
  "$MUT2_JSON" "abandonedabandon"


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

report_and_exit
