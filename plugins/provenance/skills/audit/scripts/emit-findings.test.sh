#!/usr/bin/env bash
# Self-contained tests for emit-findings.sh. Fixtures are built inline in a
# tmpdir. Per the shell-test-helpers convention, assertion helpers are local.
#
# Two load-bearing groups here. First, the relay boundary: only
# fingerprint-confirmed copies and the two deterministic stamp rules may reach
# the findings file, and a judgment verdict that leaks into it would break the
# boundary the Brief draws. Second, cell escaping: the fix action parses the
# table, so a pipe in a quoted excerpt splits a row into phantom columns.
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMIT="$SCRIPT_DIR/emit-findings.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed (the script reads a JSON sidecar)" >&2
  exit 0
fi
if ! command -v git >/dev/null 2>&1; then
  echo "SKIP: git not installed (branch and relativization need it)" >&2
  exit 0
fi

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
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "absent: $3" "present" ;;
  *) pass "$1" ;;
  esac
}
assert_match() {
  if [[ "$2" =~ $3 ]]; then pass "$1"; else fail "$1" "matches: $3" "$2"; fi
}
assert_file() {
  if [[ -f "$2" ]]; then pass "$1"; else fail "$1" "exists: $2" "absent"; fi
}
assert_no_file() {
  if [[ -e "$2" ]]; then fail "$1" "absent: $2" "exists"; else pass "$1"; fi
}
# assert_fails <label> <command...>: the command must exit non-zero.
assert_fails() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    fail "$label" "non-zero exit" "exit 0"
  else
    pass "$label"
  fi
}

# --- Fixture repository ----------------------------------------------------------

REPO="$TEST_TMPDIR/repo"
mkdir -p "$REPO/docs"
printf '%s\n' '# Doc' >"$REPO/docs/page.md"
git -C "$REPO" init -q
git -C "$REPO" config user.email "test@example.com"
git -C "$REPO" config user.name "Test"
git -C "$REPO" add -A
git -C "$REPO" commit -qm "fixture"
git -C "$REPO" checkout -qb feature/provenance-relay

REPORTS="$TEST_TMPDIR/reports"
OUTDIR="$TEST_TMPDIR/out"
mkdir -p "$REPORTS" "$OUTDIR"

write_report() {
  printf '%s\n' "$2" >"$REPORTS/$1"
}

write_report full.json '{
  "counts": {"files": 1347},
  "findings": [
    {
      "id": "f-0001",
      "rule": "provenance/audit/rule-verbatim-copy",
      "file": "docs/page.md",
      "span": {"start_line": 44, "end_line": 51},
      "class": "verbatim",
      "tier": "fingerprint-confirmed",
      "source": {"url": "https://code.claude.com/docs/skills.md", "fetched": "2026-08-27",
                 "identity": {"checked": true}},
      "fingerprint": {"containment": 0.42, "longest_span_words": 27}
    },
    {
      "rule": "provenance/audit/rule-stamp-expired",
      "file": "docs/page.md",
      "line": 12,
      "stamp_date": "2025-01-01",
      "window_days": 180,
      "days_over": 424
    },
    {
      "rule": "provenance/audit/rule-trigger-less-stamp",
      "file": "docs/page.md",
      "line": 20,
      "stamp_date": "2026-05-05"
    },
    {
      "rule": "provenance/audit/rule-verbatim-copy",
      "file": "docs/page.md",
      "span": {"start_line": 70, "end_line": 72},
      "class": "paraphrase",
      "tier": "llm-suspected"
    },
    {
      "rule": "provenance/audit/rule-verbatim-copy",
      "file": "docs/page.md",
      "span": {"start_line": 80, "end_line": 82},
      "tier": "source-fetched-similar"
    }
  ]
}'

write_report empty.json '{"counts": {"files": 10}, "findings": []}'
write_report notdetector.json '{"summary": "nothing to do here"}'
write_report garbage.json 'this is not json at all'
write_report unparsed.json '{"findings": [{"file": "docs/page.md", "line": 3, "note": "no rule id"}]}'

run() { (cd "$REPO" && bash "$EMIT" "$@"); }

# --- Usage -----------------------------------------------------------------------

OUT="$(bash "$EMIT" --help 2>&1)"
assert_exit "--help exits 0" "$?" "0"
assert_contains "--help names the script" "$OUT" "emit-findings.sh"

run --report "$REPORTS/full.json" >/dev/null 2>&1
assert_exit "a missing --out exits 2" "$?" "2"

run --out "$OUTDIR/x.md" >/dev/null 2>&1
assert_exit "a missing --report exits 2" "$?" "2"

run --report "$REPORTS/absent.json" --out "$OUTDIR/x.md" >/dev/null 2>&1
assert_exit "a nonexistent report exits 2" "$?" "2"

run --report "$REPORTS/notdetector.json" --out "$OUTDIR/x.md" >/dev/null 2>&1
assert_exit "a report with no findings key exits 3" "$?" "3"

run --report "$REPORTS/garbage.json" --out "$OUTDIR/x.md" >/dev/null 2>&1
assert_exit "an unparsable report exits 3" "$?" "3"

run --nope --report "$REPORTS/full.json" --out "$OUTDIR/x.md" >/dev/null 2>&1
assert_exit "an unknown argument exits 2" "$?" "2"

# --- The composed file -----------------------------------------------------------

TARGET="$OUTDIR/20260828T120000Z-provenance.md"
run --report "$REPORTS/full.json" --out "$TARGET" >/dev/null 2>&1
assert_exit "a clean run exits 0" "$?" "0"

assert_file "the file is written" "$TARGET"
BODY="$(cat "$TARGET")"

assert_contains "frontmatter declares the consumed type" "$BODY" "type: review-findings"
assert_contains "frontmatter carries the branch" "$BODY" "branch: feature/provenance-relay"
assert_match "date is a full ISO-8601 instant with an explicit Z" \
  "$BODY" 'date: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z'
assert_contains "the Findings section is present" "$BODY" "## Findings"
assert_contains "the table header is the contract's columns" "$BODY" \
  "| Rank | Tier | Confidence | Location | Surface(s) | Finding | Action |"

# --- Relay eligibility -----------------------------------------------------------

ROWS="$(grep -c '^| [0-9]' "$TARGET")"
assert_eq "only the three relay-eligible findings become rows" "$ROWS" "3"
assert_contains "the fingerprint-confirmed copy is a row" "$BODY" "rule-verbatim-copy"
assert_contains "the expired stamp is a row" "$BODY" "rule-stamp-expired"
assert_contains "the trigger-less stamp is a row" "$BODY" "rule-trigger-less-stamp"
assert_not_contains "an llm-suspected verdict never reaches the relay" "$BODY" "llm-suspected"
assert_not_contains "a source-fetched-similar verdict never reaches the relay" "$BODY" "source-fetched-similar"
assert_contains "withheld judgment findings are counted, not dropped" "$BODY" "2 judgment"

# --- The not-found searched-surfaces schema check --------------------------------
#
# A `not-found` outcome names every surface it checked, and that listing used to be
# prose-only. The sidecar now carries it as a `searched` array and this producer
# refuses input without one, on the same input-refusal exit code as a sidecar with
# no findings key: refusing beats composing from a sidecar whose neutral outcome
# concludes nothing about anything.
#
# The refusal validates the SIDECAR, never an emitted row. `not-found` is a
# judgment verdict the relay boundary withholds, so a well-formed one is accepted
# and still emits nothing — and the `searched` surfaces it named must not reach the
# findings file either. A schema check that relaxed the boundary to see its own
# field would be a worse defect than the one it fixed.

NF_SEARCHED='["https://code.claude.com/docs/llms.txt","site search: nf-surface.example"]'

write_report notfound-absent.json '{
  "counts": {"files": 3},
  "findings": [
    {
      "rule": "provenance/audit/rule-verbatim-copy",
      "file": "docs/page.md",
      "span": {"start_line": 90, "end_line": 93},
      "tier": "not-found"
    }
  ]
}'

write_report notfound-empty.json '{
  "counts": {"files": 3},
  "findings": [
    {
      "rule": "provenance/audit/rule-verbatim-copy",
      "file": "docs/page.md",
      "span": {"start_line": 90, "end_line": 93},
      "tier": "not-found",
      "searched": []
    }
  ]
}'

write_report notfound-listed.json "{
  \"counts\": {\"files\": 3},
  \"findings\": [
    {
      \"rule\": \"provenance/audit/rule-verbatim-copy\",
      \"file\": \"docs/page.md\",
      \"span\": {\"start_line\": 90, \"end_line\": 93},
      \"tier\": \"not-found\",
      \"searched\": $NF_SEARCHED
    }
  ]
}"

NF_ABSENT="$OUTDIR/notfound-absent.md"
run --report "$REPORTS/notfound-absent.json" --out "$NF_ABSENT" >/dev/null 2>&1
assert_exit "a not-found finding with no searched array exits 3" "$?" "3"
assert_no_file "the refused sidecar writes nothing" "$NF_ABSENT"

NF_EMPTY="$OUTDIR/notfound-empty.md"
run --report "$REPORTS/notfound-empty.json" --out "$NF_EMPTY" >/dev/null 2>&1
assert_exit "a not-found finding with an empty searched array exits 3" "$?" "3"
assert_no_file "the empty-listing sidecar writes nothing" "$NF_EMPTY"

NF_OK="$OUTDIR/notfound-listed.md"
run --report "$REPORTS/notfound-listed.json" --out "$NF_OK" >/dev/null 2>&1
assert_exit "a not-found finding naming its surfaces is accepted" "$?" "0"
assert_file "the accepted sidecar still writes the file" "$NF_OK"
NF_BODY="$(cat "$NF_OK")"
assert_eq "an accepted not-found finding still emits no relay row" \
  "$(grep -c '^| [0-9]' "$NF_OK")" "0"
assert_not_contains "the not-found tier name never reaches the relay" "$NF_BODY" "not-found"
assert_not_contains "the searched array never reaches the relay" "$NF_BODY" "searched"
assert_not_contains "a searched surface never reaches the relay" "$NF_BODY" \
  "nf-surface.example"
assert_contains "the withheld not-found finding is counted" "$NF_BODY" "1 judgment"

# The check is scoped to not-found. A relay-eligible finding carries no searched
# array and must not be refused for the lack of one.
run --report "$REPORTS/full.json" --out "$OUTDIR/nf-unrelated.md" >/dev/null 2>&1
assert_exit "a sidecar with no not-found finding is unaffected" "$?" "0"

# --- Producer-owned fields -------------------------------------------------------

COPY_ROW="$(grep 'rule-verbatim-copy' "$TARGET" | head -1)"
assert_contains "Tier is looked up from the crosswalk" "$COPY_ROW" "| IMPORTANT |"
assert_contains "Confidence is high for a deterministic rule that fired" "$COPY_ROW" "| high |"
assert_contains "Location is repo-relative file:line" "$COPY_ROW" "docs/page.md:44"
assert_contains "the Finding cell leads with the qualified rule id" "$COPY_ROW" \
  "| provenance/audit/rule-verbatim-copy:"
assert_contains "the Finding cell carries the fired values" "$COPY_ROW" "27"
assert_contains "the copy row names its source" "$COPY_ROW" "https://code.claude.com/docs/skills.md"
assert_contains "the Action names the producer-owned remediation" "$COPY_ROW" "provenance:audit fix"

STAMP_ROW="$(grep 'rule-stamp-expired' "$TARGET" | head -1)"
assert_contains "the stamp row carries its fired values" "$STAMP_ROW" "424"
assert_contains "the stamp row names its window" "$STAMP_ROW" "180"
assert_contains "the stamp row is not auto-applicable" "$STAMP_ROW" "re-deriv"

assert_eq "ranks run 1..N in order" \
  "$(grep -o '^| [0-9]* |' "$TARGET" | tr -dc '0-9' | tr -d '\n')" "123"

# --- Cell escaping ---------------------------------------------------------------

write_report pipes.json '{
  "findings": [
    {
      "rule": "provenance/audit/rule-verbatim-copy",
      "file": "docs/page.md",
      "span": {"start_line": 5, "end_line": 6},
      "tier": "fingerprint-confirmed",
      "source": {"url": "https://example.com/a"},
      "fingerprint": {"containment": 0.5, "longest_span_words": 20},
      "excerpt": "a | b and an already \\| escaped pipe\nplus a newline"
    }
  ]
}'
PIPE_OUT="$OUTDIR/pipes.md"
run --report "$REPORTS/pipes.json" --out "$PIPE_OUT" >/dev/null 2>&1
PIPE_ROW="$(grep 'rule-verbatim-copy' "$PIPE_OUT" | head -1)"
assert_eq "the escaped row still has exactly the contract's columns" \
  "$(printf '%s' "$PIPE_ROW" | sed 's/\\|//g' | tr -cd '|' | wc -c | tr -d ' ')" "8"
assert_contains "a bare pipe is escaped" "$PIPE_ROW" '\|'
# The needle is the DOUBLE-ESCAPED form a naive gsub produces: three characters,
# backslash backslash pipe. It read `\\\|` — four characters, which the broken
# output does not contain either, so the assertion could not fail on the regression
# it names.
assert_not_contains "an already-escaped pipe is not double-escaped" "$PIPE_ROW" '\\|'
assert_not_contains "a newline inside a cell is replaced" "$PIPE_ROW" $'\n'

# --- Unparsed and coverage -------------------------------------------------------

UNP="$OUTDIR/unparsed.md"
run --report "$REPORTS/unparsed.json" --out "$UNP" >/dev/null 2>&1
assert_exit "a finding with no rule id still exits 0" "$?" "0"
assert_contains "an unrecognized finding lands in Unparsed" "$(cat "$UNP")" "## Unparsed"
assert_contains "the unparsed finding keeps its raw text" "$(cat "$UNP")" "no rule id"

# --- The relay boundary holds without a rule id ----------------------------------
#
# A judgment verdict used to escape the boundary whenever it carried no rule id:
# nothing classified it, so it fell through to `## Unparsed` and was dumped
# verbatim — tier name and payload included — into the very file the boundary
# keeps it out of. Withholding is decided by the DECLARED TIER, ahead of any rule
# lookup, so no verdict re-enters through the appendix. The finding is still
# counted in `## Surfaces`: counting is not a silent drop.

write_report withheld-nf.json '{
  "counts": {"files": 2},
  "findings": [
    {"tier": "not-found", "file": "a.md", "searched": ["https://LEAKCANARY.example/u"]}
  ]
}'
write_report withheld-sfs.json '{
  "counts": {"files": 2},
  "findings": [
    {"tier": "source-fetched-similar", "file": "b.md", "excerpt": "LEAKCANARY-SFS"}
  ]
}'
write_report withheld-llm.json '{
  "counts": {"files": 2},
  "findings": [
    {"tier": "llm-suspected", "file": "c.md", "excerpt": "LEAKCANARY-LLM"}
  ]
}'

for wcase in "nf:not-found:LEAKCANARY.example" \
  "sfs:source-fetched-similar:LEAKCANARY-SFS" \
  "llm:llm-suspected:LEAKCANARY-LLM"; do
  wname="${wcase%%:*}"
  wrest="${wcase#*:}"
  wtier="${wrest%%:*}"
  wcanary="${wrest#*:}"
  WOUT="$OUTDIR/withheld-$wname.md"
  run --report "$REPORTS/withheld-$wname.json" --out "$WOUT" >/dev/null 2>&1
  assert_exit "a rule-less $wtier finding still exits 0" "$?" "0"
  WBODY="$(cat "$WOUT")"
  assert_not_contains "a rule-less $wtier tier name never reaches the file" "$WBODY" "$wtier"
  assert_not_contains "a rule-less $wtier payload never reaches the file" "$WBODY" "$wcanary"
  assert_not_contains "a rule-less $wtier finding opens no Unparsed section" "$WBODY" "## Unparsed"
  assert_contains "a rule-less $wtier finding is counted, not dropped" "$WBODY" "1 judgment"
done

# Casing is not a way around the boundary: the tier is matched case-folded.
write_report withheld-cased.json '{
  "counts": {"files": 2},
  "findings": [
    {"tier": "LLM-Suspected", "file": "c.md", "excerpt": "LEAKCANARY-CASED"}
  ]
}'
WCASED="$OUTDIR/withheld-cased.md"
run --report "$REPORTS/withheld-cased.json" --out "$WCASED" >/dev/null 2>&1
CASED_BODY="$(cat "$WCASED")"
assert_not_contains "a differently-cased judgment tier is still withheld" \
  "$CASED_BODY" "LLM-Suspected"
assert_not_contains "a differently-cased judgment payload is still withheld" \
  "$CASED_BODY" "LEAKCANARY-CASED"
assert_contains "a differently-cased judgment finding is counted" "$CASED_BODY" "1 judgment"

# A tier declared below the top level is still a declared tier.
write_report withheld-nested.json '{
  "counts": {"files": 2},
  "findings": [
    {"file": "d.md", "line": 4, "verdict": {"tier": "llm-suspected"},
     "excerpt": "LEAKCANARY-NEST"}
  ]
}'
WNEST="$OUTDIR/withheld-nested.md"
run --report "$REPORTS/withheld-nested.json" --out "$WNEST" >/dev/null 2>&1
NEST_BODY="$(cat "$WNEST")"
assert_not_contains "a nested judgment tier is still withheld" "$NEST_BODY" "llm-suspected"
assert_not_contains "a nested judgment payload is still withheld" "$NEST_BODY" "LEAKCANARY-NEST"
assert_contains "a nested judgment finding is counted" "$NEST_BODY" "1 judgment"

# A tier field is read generously, because every sloppiness here is a leak and
# none is a false relay row. Each of these declares a withheld verdict in a shape
# an exact top-level string match would have missed.
write_report withheld-padded.json '{
  "findings": [{"tier": "  not-found  ", "file": "a.md", "note": "PADCANARY",
                "searched": ["https://x.example/"]}]
}'
# These two declare `not-found` and so must name their searched surfaces like any
# other not-found finding — the gate reads the same declared tier the boundary
# does, so an evasive spelling no longer buys a pass through it. The listing is
# input the gate consumes and never emits, so it gets a canary of its own.
write_report withheld-arraytier.json '{
  "findings": [{"tier": ["not-found"], "file": "a.md", "note": "ARRCANARY",
                "searched": ["https://ARRSURFACE.example/u"]}]
}'
write_report withheld-objtier.json '{
  "findings": [{"tier": {"name": "llm-suspected"}, "file": "a.md", "note": "OBJCANARY"}]
}'
write_report withheld-capkey.json '{
  "findings": [{"Tier": "not-found", "file": "a.md", "note": "CAPCANARY",
                "searched": ["https://CAPSURFACE.example/u"]}]
}'

for scase in "padded:not-found:PADCANARY" "arraytier:not-found:ARRCANARY" \
  "objtier:llm-suspected:OBJCANARY" "capkey:not-found:CAPCANARY"; do
  sname="${scase%%:*}"
  srest="${scase#*:}"
  sverdict="${srest%%:*}"
  scanary="${srest#*:}"
  SOUT="$OUTDIR/withheld-$sname.md"
  run --report "$REPORTS/withheld-$sname.json" --out "$SOUT" >/dev/null 2>&1
  SBODY="$(cat "$SOUT")"
  assert_not_contains "a $sname tier declaration names no verdict in the file" \
    "$SBODY" "$sverdict"
  assert_not_contains "a $sname tier declaration leaks no payload" "$SBODY" "$scanary"
  assert_contains "a $sname tier declaration is counted" "$SBODY" "1 judgment"
done

assert_not_contains "an array-tier searched surface never reaches the file" \
  "$(cat "$OUTDIR/withheld-arraytier.md")" "ARRSURFACE.example"
assert_not_contains "a capitalised-key searched surface never reaches the file" \
  "$(cat "$OUTDIR/withheld-capkey.md")" "CAPSURFACE.example"

# The scope is the DECLARED tier. A verdict name spelled in some other field is
# opaque payload, not a verdict, and does not withhold the record — asserted so
# the limit stays a stated one rather than an accident.
write_report unparsed-prose-tier.json '{
  "findings": [{"file": "a.md", "note": "PROSECANARY mentions llm-suspected in prose"}]
}'
PROSE="$OUTDIR/unparsed-prose-tier.md"
run --report "$REPORTS/unparsed-prose-tier.json" --out "$PROSE" >/dev/null 2>&1
PROSE_BODY="$(cat "$PROSE")"
assert_contains "a verdict name in free text is not a tier declaration" \
  "$PROSE_BODY" "PROSECANARY"
assert_contains "such a record is reported as unmapped, not withheld" \
  "$PROSE_BODY" "Unmapped: 1"

# A valid rule id does not readmit a withheld verdict: the tier decides first.
write_report withheld-with-rule.json '{
  "counts": {"files": 2},
  "findings": [
    {"rule": "provenance/audit/rule-stamp-expired", "file": "e.md", "line": 7,
     "tier": "llm-suspected", "stamp_date": "2025-01-01", "window_days": 180,
     "days_over": 424}
  ]
}'
WRULE="$OUTDIR/withheld-with-rule.md"
run --report "$REPORTS/withheld-with-rule.json" --out "$WRULE" >/dev/null 2>&1
RULE_BODY="$(cat "$WRULE")"
assert_not_contains "a judgment tier on a stamp rule is still withheld" \
  "$RULE_BODY" "llm-suspected"
assert_eq "a judgment tier on a stamp rule emits no relay row" \
  "$(grep -c '^| [0-9]' "$WRULE")" "0"
assert_contains "a judgment tier on a stamp rule is counted" "$RULE_BODY" "1 judgment"

# --- The gate and the boundary read ONE declared tier ------------------------------
#
# The searched-surfaces gate used to compare `.tier` to "not-found" exactly, at the
# top level, while the boundary recognized four more shapes. A sidecar declaring the
# verdict in any of those shapes therefore skipped the refusal and was counted as
# withheld instead — the schema check silently not running is worse than it failing.
# Both now read the same declared tier, so every shape the boundary withholds is a
# shape the gate demands a `searched` listing for.

write_report gate-capkey.json '{
  "findings": [{"Tier": "not-found", "file": "a.md", "note": "GATECAP"}]
}'
write_report gate-arraytier.json '{
  "findings": [{"tier": ["not-found"], "file": "a.md", "note": "GATEARR"}]
}'
write_report gate-padded.json '{
  "findings": [{"tier": "  NOT-FOUND  ", "file": "a.md", "note": "GATEPAD"}]
}'
write_report gate-verdict.json '{
  "findings": [{"verdict": {"tier": "not-found"}, "file": "a.md", "note": "GATEVERDICT"}]
}'

for gname in capkey arraytier padded verdict; do
  GOUT="$OUTDIR/gate-$gname.md"
  run --report "$REPORTS/gate-$gname.json" --out "$GOUT" >/dev/null 2>&1
  assert_exit "an evasively spelled not-found with no searched array exits 3 ($gname)" \
    "$?" "3"
  assert_no_file "the refused $gname sidecar writes nothing" "$GOUT"
done

# The gate is scoped to not-found, like the boundary is scoped to three names. A
# nested tier that is NOT a declaration must not start demanding a searched array.
write_report gate-unrelated.json '{
  "counts": {"files": 2},
  "findings": [{
    "rule": "provenance/audit/rule-stamp-expired", "file": "u.md", "line": 3,
    "stamp_date": "2025-01-01", "window_days": 180, "days_over": 424,
    "xref": {"tier": "prior run said not-found"}
  }]
}'
GUN="$OUTDIR/gate-unrelated.md"
run --report "$REPORTS/gate-unrelated.json" --out "$GUN" >/dev/null 2>&1
assert_exit "a not-found named outside the declared tier is not gated" "$?" "0"

# --- A `verdict` key is a declaration WHOLE, not only its `tier` child -------------
#
# Reading `verdict.tier` alone left three shapes saying the same thing outside the
# boundary: a bare string, a list, and a `tier` one level further down. Each reached
# the file — a stamp rule carrying one was RELAYED, and one with no rule id printed
# verbatim into `## Unparsed`. The whole `verdict` value is the declared tier.

write_report verdict-string.json '{
  "counts": {"files": 2},
  "findings": [{"verdict": "not-found", "file": "vs.md", "excerpt": "VSTRCANARY",
                "searched": ["https://vs.example/u"]}]
}'
write_report verdict-array.json '{
  "counts": {"files": 2},
  "findings": [{"verdict": ["llm-suspected"], "file": "va.md", "excerpt": "VARRCANARY"}]
}'
write_report verdict-deep.json '{
  "counts": {"files": 2},
  "findings": [{"verdict": {"result": {"tier": "llm-suspected"}}, "file": "vd.md",
                "excerpt": "VDEEPCANARY"}]
}'
# The KEY casing is what this case tests, so the VALUE is spelled the way the needle
# below is. It read `"LLM-Suspected"` against a lowercase needle through a
# case-sensitive glob, so reverting the whole-verdict read left this iteration
# passing while its three siblings failed: an assertion that cannot fail on the
# regression it names.
write_report verdict-cased.json '{
  "counts": {"files": 2},
  "findings": [{"Verdict": "llm-suspected", "file": "vc.md", "excerpt": "VCASECANARY"}]
}'
write_report verdict-on-stamp.json '{
  "counts": {"files": 2},
  "findings": [{"rule": "provenance/audit/rule-stamp-expired", "file": "vst.md",
                "line": 3, "verdict": "llm-suspected", "stamp_date": "2025-01-01",
                "window_days": 180, "days_over": 9}]
}'

for vc in "string:not-found:VSTRCANARY" "array:llm-suspected:VARRCANARY" \
  "deep:llm-suspected:VDEEPCANARY" "cased:llm-suspected:VCASECANARY" \
  "on-stamp:llm-suspected:none"; do
  vn="${vc%%:*}"
  vr="${vc#*:}"
  vv="${vr%%:*}"
  vk="${vr#*:}"
  VO="$OUTDIR/verdict-$vn.md"
  run --report "$REPORTS/verdict-$vn.json" --out "$VO" >/dev/null 2>&1
  VB="$(cat "$VO")"
  assert_eq "a whole-verdict declaration emits no relay row ($vn)" \
    "$(grep -c '^| [0-9]' "$VO")" "0"
  assert_not_contains "a whole-verdict declaration names no verdict in the file ($vn)" \
    "$VB" "$vv"
  assert_not_contains "a whole-verdict declaration opens no Unparsed section ($vn)" \
    "$VB" "## Unparsed"
  assert_contains "a whole-verdict declaration is counted as judgment ($vn)" \
    "$VB" "1 judgment"
  if [[ "$vk" != "none" ]]; then
    assert_not_contains "a whole-verdict declaration leaks no payload ($vn)" "$VB" "$vk"
  fi
done

# --- The drop direction of the whole-`verdict` read --------------------------------
#
# The `verdict` fallback applies ONLY to a record that declares no `tier`. A record
# that declares one has declared its tier: the tier is set by fixed rule from the
# evidence and a `verdict` is the judges output, different fields by design, so
# reading the verdict beside a declared tier is the over-capture drop one container
# in. Taking the WHOLE verdict makes that worse, because every sibling key inside it
# becomes a tier declaration.
write_report verdict-beside-confirmed.json '{
  "counts": {"files": 2},
  "findings": [{
    "rule": "provenance/audit/rule-verbatim-copy", "file": "vb.md",
    "span": {"start_line": 9}, "tier": "fingerprint-confirmed",
    "source": {"url": "https://vb.example/s"},
    "fingerprint": {"containment": 0.9, "longest_span_words": 30},
    "verdict": {"prior": "llm-suspected", "agents": 2}
  }]
}'
VBC="$OUTDIR/verdict-beside-confirmed.md"
run --report "$REPORTS/verdict-beside-confirmed.json" --out "$VBC" >/dev/null 2>&1
assert_exit "a declared tier beside a judges verdict exits 0" "$?" "0"
assert_eq "a declared fingerprint-confirmed tier wins over a verdict beside it" \
  "$(grep -c '^| [0-9]' "$VBC")" "1"
assert_not_contains "and the copy is not counted as a judgment finding" \
  "$(cat "$VBC")" "judgment findings"

# The same rule keeps a confirmed copy out of the whole-sidecar refusal: a `verdict`
# is not consulted at all when a `tier` is declared, so a superseded outcome named
# beside it demands no searched listing.
write_report verdict-superseded.json '{
  "counts": {"files": 2},
  "findings": [{
    "rule": "provenance/audit/rule-verbatim-copy", "file": "vsup.md",
    "span": {"start_line": 10}, "tier": "fingerprint-confirmed",
    "source": {"url": "https://vsup.example/s"},
    "fingerprint": {"containment": 0.9, "longest_span_words": 31},
    "verdict": {"superseded_by": "not-found"}
  }]
}'
VSUP="$OUTDIR/verdict-superseded.md"
run --report "$REPORTS/verdict-superseded.json" --out "$VSUP" >/dev/null 2>&1
assert_exit "a superseded outcome beside a declared tier refuses nothing" "$?" "0"
assert_eq "and the confirmed copy still reaches the relay" \
  "$(grep -c '^| [0-9]' "$VSUP")" "1"

# The fallback turns on a tier NAMED, not on a `tier` key present. Keying off the key
# let one unusable value disarm the whole boundary: the verdict was never consulted,
# so the record printed verbatim into `## Unparsed` and skipped the searched gate.
write_report tier-unusable-null.json '{
  "counts": {"files": 2},
  "findings": [{"rule": "provenance/audit/rule-future", "tier": null,
                "verdict": {"result": {"tier": "not-found"}}, "excerpt": "UNUSABLENULL",
                "searched": ["https://un.example/u"]}]
}'
write_report tier-unusable-empty.json '{
  "counts": {"files": 2},
  "findings": [{"rule": "provenance/audit/rule-future", "tier": [],
                "verdict": ["source-fetched-similar"], "excerpt": "UNUSABLEEMPTY"}]
}'
write_report tier-unusable-word.json '{
  "counts": {"files": 2},
  "findings": [{"rule": "provenance/audit/rule-future", "tier": "pending",
                "verdict": {"tier": "llm-suspected"}, "excerpt": "UNUSABLEWORD"}]
}'
for uu in "null:not-found:UNUSABLENULL" "empty:source-fetched-similar:UNUSABLEEMPTY" \
  "word:llm-suspected:UNUSABLEWORD"; do
  un="${uu%%:*}"
  ur="${uu#*:}"
  uv="${ur%%:*}"
  uk="${ur#*:}"
  UO="$OUTDIR/tier-unusable-$un.md"
  run --report "$REPORTS/tier-unusable-$un.json" --out "$UO" >/dev/null 2>&1
  UB="$(cat "$UO")"
  assert_not_contains "an unusable tier does not disarm the verdict read ($un)" \
    "$UB" "$uv"
  assert_not_contains "an unusable tier leaks no payload ($un)" "$UB" "$uk"
  assert_not_contains "an unusable tier opens no Unparsed section ($un)" \
    "$UB" "## Unparsed"
  assert_contains "an unusable tier is counted, not dropped ($un)" "$UB" "1 judgment"
done

# And the same shape without a searched listing is refused, not quietly appended.
write_report tier-unusable-ungated.json '{
  "counts": {"files": 2},
  "findings": [{"rule": "provenance/audit/rule-future", "tier": "pending",
                "verdict": "not-found", "excerpt": "UNUSABLEGATE"}]
}'
run --report "$REPORTS/tier-unusable-ungated.json" \
  --out "$OUTDIR/tier-unusable-ungated.md" >/dev/null 2>&1
assert_exit "an unusable tier does not let a not-found skip the searched gate" "$?" "3"

# With no top-level tier, the verdict IS the declaration, and its `tier` child is the
# tier when it has one — a sibling key inside the verdict is not.
write_report verdict-child-confirmed.json '{
  "counts": {"files": 2},
  "findings": [{
    "rule": "provenance/audit/rule-verbatim-copy", "file": "vch.md",
    "span": {"start_line": 11},
    "verdict": {"tier": "fingerprint-confirmed", "superseded_by": "not-found"},
    "source": {"url": "https://vch.example/s"},
    "fingerprint": {"containment": 0.9, "longest_span_words": 32}
  }]
}'
VCH="$OUTDIR/verdict-child-confirmed.md"
run --report "$REPORTS/verdict-child-confirmed.json" --out "$VCH" >/dev/null 2>&1
assert_exit "a verdict declaring a confirmed tier child refuses nothing" "$?" "0"
assert_eq "and its copy reaches the relay" "$(grep -c '^| [0-9]' "$VCH")" "1"
assert_not_contains "and it is not counted as withheld" \
  "$(cat "$VCH")" "judgment findings"

# --- A record that is not an object carries no verdict into the appendix -----------
#
# The malformed-record route runs BEFORE any tier is read, so one array layer around
# a verdict declaration used to bypass the boundary and the searched gate alike, and
# print the tier name and the payload verbatim into `## Unparsed`. A record with no
# declared tier to respect is withheld when a verdict name appears anywhere inside
# it: `[{"tier": "not-found", "excerpt": "..."}]` is a verdict in the wrong wrapper.
write_report record-wrapped-object.json '{
  "counts": {"files": 2},
  "findings": [[{"tier": "not-found", "excerpt": "WRAPOBJCANARY"}]]
}'
write_report record-bare-string.json '{
  "counts": {"files": 2}, "findings": ["not-found"]
}'
write_report record-nested-array.json '{
  "counts": {"files": 2}, "findings": [[["llm-suspected"]]]
}'
for rw in "wrapped-object:not-found:WRAPOBJCANARY" "bare-string:not-found:none" \
  "nested-array:llm-suspected:none"; do
  rn="${rw%%:*}"
  rr="${rw#*:}"
  rv="${rr%%:*}"
  rk="${rr#*:}"
  RO="$OUTDIR/record-$rn.md"
  run --report "$REPORTS/record-$rn.json" --out "$RO" >/dev/null 2>&1
  RB="$(cat "$RO")"
  assert_not_contains "a wrapped verdict record names no verdict in the file ($rn)" \
    "$RB" "$rv"
  assert_not_contains "a wrapped verdict record opens no Unparsed section ($rn)" \
    "$RB" "## Unparsed"
  assert_contains "a wrapped verdict record is counted ($rn)" "$RB" "1 judgment"
  if [[ "$rk" != "none" ]]; then
    assert_not_contains "a wrapped verdict record leaks no payload ($rn)" "$RB" "$rk"
  fi
done

# A malformed record naming no verdict keeps the appendix path, and never costs the
# well-formed findings beside it.
write_report record-wrapped-benign.json '{
  "counts": {"files": 2},
  "findings": [
    [{"note": "BENIGNWRAPCANARY"}],
    {"rule": "provenance/audit/rule-stamp-expired", "file": "ok.md", "line": 4,
     "stamp_date": "2025-01-01", "window_days": 180, "days_over": 9}
  ]
}'
RWB="$OUTDIR/record-wrapped-benign.md"
run --report "$REPORTS/record-wrapped-benign.json" --out "$RWB" >/dev/null 2>&1
RWB_BODY="$(cat "$RWB")"
assert_contains "a benign wrapped record still lands in Unparsed" \
  "$RWB_BODY" "BENIGNWRAPCANARY"
assert_contains "and the well-formed finding beside it still relays" "$RWB_BODY" "ok.md:4"

# --- The searched listing is read wherever the outcome is declared ----------------
#
# The gate reads the declared tier through slots that are case-folded and generous
# about wrappers; it must read `searched` through the same ones, or it refuses a
# sidecar that satisfies the very requirement it enforces.
write_report gate-verdict-searched.json '{
  "counts": {"files": 2},
  "findings": [{"verdict": {"tier": "not-found", "searched": ["https://gv.example/u"]},
                "file": "gv.md", "note": "GATEVSCANARY"}]
}'
write_report gate-verdict-cased-searched.json '{
  "counts": {"files": 2},
  "findings": [{"Verdict": {"tier": "not-found", "searched": ["https://gvc.example/u"]},
                "file": "gvc.md", "note": "GATEVCCANARY"}]
}'
write_report gate-tier-object-searched.json '{
  "counts": {"files": 2},
  "findings": [{"tier": {"name": "not-found", "searched": ["https://gt.example/u"]},
                "file": "gt.md", "note": "GATETOCANARY"}]
}'
write_report gate-verdict-list-searched.json '{
  "counts": {"files": 2},
  "findings": [{"verdict": [{"tier": "not-found", "searched": ["https://gl.example/u"]}],
                "file": "gl.md", "note": "GATEGLCANARY"}]
}'
for gs in verdict-searched verdict-cased-searched tier-object-searched \
  verdict-list-searched; do
  GO="$OUTDIR/gate-$gs.md"
  run --report "$REPORTS/gate-$gs.json" --out "$GO" >/dev/null 2>&1
  assert_exit "a not-found naming its surfaces where it declared the outcome ($gs)" \
    "$?" "0"
  assert_file "and the accepted sidecar still writes the file ($gs)" "$GO"
  assert_contains "and the finding is still withheld and counted ($gs)" \
    "$(cat "$GO")" "1 judgment"
done

# --- The neutral outcome under the name SKILL.md publishes ------------------------
#
# `SKILL.md` publishes the neutral tier as `source-not-identified` while this file
# elsewhere calls it `not-found`. The sidecar is model-authored against that
# description, so a reader that knows one spelling relays the other. Recognizing one
# name too many can only withhold a record; one too few walks a judgment verdict
# onto a relay row.
write_report neutral-published-name.json '{
  "counts": {"files": 2},
  "findings": [{"rule": "provenance/audit/rule-stamp-expired", "file": "sn.md",
                "line": 5, "tier": "source-not-identified", "excerpt": "SNICANARY",
                "stamp_date": "2025-01-01", "window_days": 180, "days_over": 9,
                "searched": ["https://sn.example/u"]}]
}'
SNI="$OUTDIR/neutral-published-name.md"
run --report "$REPORTS/neutral-published-name.json" --out "$SNI" >/dev/null 2>&1
SNI_BODY="$(cat "$SNI")"
assert_eq "the published neutral tier emits no relay row" \
  "$(grep -c '^| [0-9]' "$SNI")" "0"
assert_not_contains "the published neutral tier names no verdict in the file" \
  "$SNI_BODY" "source-not-identified"
assert_not_contains "the published neutral tier leaks no payload" "$SNI_BODY" "SNICANARY"
assert_contains "the published neutral tier is counted" "$SNI_BODY" "1 judgment"

write_report neutral-published-ungated.json '{
  "counts": {"files": 2},
  "findings": [{"tier": "source-not-identified", "file": "sn2.md", "note": "SNI2"}]
}'
run --report "$REPORTS/neutral-published-ungated.json" \
  --out "$OUTDIR/neutral-published-ungated.md" >/dev/null 2>&1
assert_exit "the published neutral tier names its surfaces like the other spelling" \
  "$?" "3"

# --- A sidecar that does not parse says so ----------------------------------------
#
# `has("findings")` fails on unparsable input too, so every truncated or non-JSON
# sidecar was refused for having no findings key — a cause the input does not have.
write_report truncated.json '{"findings": [{"rule": "x"'
TRUNC_ERR="$(run --report "$REPORTS/truncated.json" --out "$OUTDIR/truncated.md" 2>&1)"
assert_exit "a truncated sidecar exits 3" "$?" "3"
assert_contains "and says it is not a JSON object" "$TRUNC_ERR" "not a JSON object"
assert_not_contains "and does not blame a missing findings key" \
  "$TRUNC_ERR" "no findings key"
GARB_ERR="$(run --report "$REPORTS/garbage.json" --out "$OUTDIR/garbage2.md" 2>&1)"
assert_contains "non-JSON input says it is not a JSON object" \
  "$GARB_ERR" "not a JSON object"

# --- A findings key that is not a list is named for what it is --------------------
#
# It used to fail inside the not-found gate and be refused under that gate's message,
# reporting a cause the input does not have.
write_report findings-scalar.json '{"findings": "none"}'
FSC="$OUTDIR/findings-scalar.md"
FSC_ERR="$(run --report "$REPORTS/findings-scalar.json" --out "$FSC" 2>&1)"
assert_exit "a non-list findings key exits 3" "$?" "3"
assert_contains "and says the findings key is not a list" "$FSC_ERR" "not a list"
assert_not_contains "and does not blame the not-found check" "$FSC_ERR" "not-found finding"

# --- A verdict name is matched EXACTLY, never as a prefix -------------------------
#
# `test()` searched for a substring, so an extended name such as `not-found-v2`
# matched the verdict it merely starts with: the record was classified as withheld,
# its payload erased, and no `## Unparsed` entry emitted — the exact silent drop the
# appendix exists to prevent for a future record. A candidate name now has to EQUAL a
# verdict after trimming and case-folding, which leaves every accepted wrapper shape
# intact because the wrapper is walked before the names are compared.

write_report tier-extended.json '{
  "counts": {"files": 2},
  "findings": [{"tier": "not-found-v2", "file": "x.md", "note": "EXTENDEDCANARY"}]
}'
EXT="$OUTDIR/tier-extended.md"
run --report "$REPORTS/tier-extended.json" --out "$EXT" >/dev/null 2>&1
assert_exit "an extended tier name is not a not-found finding to gate" "$?" "0"
EXT_BODY="$(cat "$EXT")"
assert_contains "an extended tier name still opens Unparsed" "$EXT_BODY" "## Unparsed"
assert_contains "an extended tier name keeps its raw text" "$EXT_BODY" "EXTENDEDCANARY"
assert_contains "an extended tier name is reported as unmapped" "$EXT_BODY" "Unmapped: 1"
assert_not_contains "an extended tier name is not counted as withheld" \
  "$EXT_BODY" "judgment findings"

write_report tier-extended-llm.json '{
  "counts": {"files": 2},
  "findings": [{"tier": "llm-suspected-review", "file": "x.md", "note": "EXTLLMCANARY"}]
}'
EXTL="$OUTDIR/tier-extended-llm.md"
run --report "$REPORTS/tier-extended-llm.json" --out "$EXTL" >/dev/null 2>&1
EXTL_BODY="$(cat "$EXTL")"
assert_contains "a suffixed llm tier name stays visible in Unparsed" \
  "$EXTL_BODY" "EXTLLMCANARY"
assert_contains "a suffixed llm tier name is reported as unmapped" \
  "$EXTL_BODY" "Unmapped: 1"

# Exact naming does not readmit the wrapper shapes: the WRAPPER is read generously
# and the NAME exactly, so a verdict buried two containers deep is still a verdict.
write_report tier-deep-wrapper.json '{
  "findings": [{"tier": {"history": [{"name": "  LLM-Suspected  "}]}, "file": "x.md",
                "note": "DEEPWRAPCANARY"}]
}'
DW="$OUTDIR/tier-deep-wrapper.md"
run --report "$REPORTS/tier-deep-wrapper.json" --out "$DW" >/dev/null 2>&1
DW_BODY="$(cat "$DW")"
assert_not_contains "a verdict wrapped two containers deep is still withheld" \
  "$DW_BODY" "llm-suspected"
assert_not_contains "a deeply wrapped verdict leaks no payload" "$DW_BODY" "DEEPWRAPCANARY"
assert_contains "a deeply wrapped verdict is counted" "$DW_BODY" "1 judgment"

# Trimming covers every invisible character, by Unicode CLASS rather than by a list
# of the ones someone thought of: a tier that RENDERS as a verdict name in the
# written file is a verdict name in the written file. An enumeration of two code
# points left six others leaking, and a trailing unhandled one anchored the
# end-of-string trim so it neutralized a leading code point that WAS handled.
write_report tier-invisible-zwsp.json '{
  "findings": [{"tier": "​not-found﻿", "file": "x.md", "note": "INVIS-ZWSP",
                "searched": ["https://z.example/u"]}]
}'
write_report tier-invisible-zwnj.json '{
  "findings": [{"tier": "‌not-found", "file": "x.md", "note": "INVIS-ZWNJ",
                "searched": ["https://z.example/u"]}]
}'
write_report tier-invisible-wj.json '{
  "findings": [{"tier": "⁠llm-suspected", "file": "x.md", "note": "INVIS-WJ"}]
}'
write_report tier-invisible-lrm.json '{
  "findings": [{"tier": "‎llm-suspected‏", "file": "x.md", "note": "INVIS-LRM"}]
}'
write_report tier-invisible-shy.json '{
  "findings": [{"tier": "­not-found", "file": "x.md", "note": "INVIS-SHY",
                "searched": ["https://z.example/u"]}]
}'
write_report tier-invisible-mixed.json '{
  "findings": [{"tier": "​not-found⁠", "file": "x.md", "note": "INVIS-MIXED",
                "searched": ["https://z.example/u"]}]
}'
write_report tier-invisible-nbsp.json '{
  "findings": [{"tier": " not-found ", "file": "x.md", "note": "INVIS-NBSP",
                "searched": ["https://z.example/u"]}]
}'
for iv in "zwsp:not-found:INVIS-ZWSP" "zwnj:not-found:INVIS-ZWNJ" \
  "wj:llm-suspected:INVIS-WJ" "lrm:llm-suspected:INVIS-LRM" \
  "shy:not-found:INVIS-SHY" "mixed:not-found:INVIS-MIXED" \
  "nbsp:not-found:INVIS-NBSP"; do
  ivn="${iv%%:*}"
  ivr="${iv#*:}"
  ivv="${ivr%%:*}"
  ivk="${ivr#*:}"
  IVO="$OUTDIR/tier-invisible-$ivn.md"
  run --report "$REPORTS/tier-invisible-$ivn.json" --out "$IVO" >/dev/null 2>&1
  IVB="$(cat "$IVO")"
  assert_eq "an invisibly padded verdict emits no relay row ($ivn)" \
    "$(grep -c '^| [0-9]' "$IVO")" "0"
  assert_not_contains "an invisibly padded verdict is still withheld ($ivn)" \
    "$IVB" "$ivv"
  assert_not_contains "an invisibly padded verdict leaks no payload ($ivn)" "$IVB" "$ivk"
  assert_contains "an invisibly padded verdict is counted ($ivn)" "$IVB" "1 judgment"
done

# FREE TEXT in a tier field names no tier, which is the same answer this producer
# already gives a verdict name spelled in a `note`. It has to be: withholding a
# fingerprint-confirmed copy because a `verdict.tier` review note mentions a verdict
# is the over-capture drop wearing an allowlisted key.
write_report tier-freetext.json '{
  "counts": {"files": 2},
  "findings": [{
    "rule": "provenance/audit/rule-verbatim-copy", "file": "ft.md",
    "span": {"start_line": 31}, "tier": "fingerprint-confirmed",
    "source": {"url": "https://ft.example/s"},
    "fingerprint": {"containment": 0.9, "longest_span_words": 44},
    "verdict": {"tier": "the llm-suspected nomination was overruled by review"}
  }]
}'
FT="$OUTDIR/tier-freetext.md"
run --report "$REPORTS/tier-freetext.json" --out "$FT" >/dev/null 2>&1
assert_exit "a review note in an allowlisted tier field exits 0" "$?" "0"
FT_BODY="$(cat "$FT")"
assert_eq "a review note in verdict.tier does not withhold the copy" \
  "$(grep -c '^| [0-9]' "$FT")" "1"
assert_contains "the surviving copy is counted as relay-eligible" \
  "$FT_BODY" "Relay-eligible findings: 1."
assert_not_contains "the surviving copy is not counted as a judgment finding" \
  "$FT_BODY" "judgment findings"

# The same shape naming `not-found` must not escalate into a whole-sidecar refusal:
# a review note is not a not-found outcome, so there are no searched surfaces to
# demand and nothing to refuse.
write_report tier-freetext-nf.json '{
  "counts": {"files": 2},
  "findings": [{
    "rule": "provenance/audit/rule-verbatim-copy", "file": "ftn.md",
    "span": {"start_line": 32}, "tier": "fingerprint-confirmed",
    "source": {"url": "https://ftn.example/s"},
    "fingerprint": {"containment": 0.9, "longest_span_words": 45},
    "verdict": {"tier": "human review: the not-found nomination was withdrawn"}
  }]
}'
FTN="$OUTDIR/tier-freetext-nf.md"
run --report "$REPORTS/tier-freetext-nf.json" --out "$FTN" >/dev/null 2>&1
assert_exit "a review note naming not-found is not a not-found finding" "$?" "0"
assert_eq "and the copy it annotates still reaches the relay" \
  "$(grep -c '^| [0-9]' "$FTN")" "1"

# --- One reader answers the eligibility question too -------------------------------
#
# The allowlist decided WHERE a tier is declared when withholding, while eligibility
# compared `.tier` to the string exactly. So a copy declaring fingerprint-confirmed
# at either allowlisted position was dropped — no row, no appendix entry — and the
# `## Surfaces` count called it a copy declaring no fingerprint-confirmed tier, which
# the reader beside it disagrees with. Casing was closed as an evasion route in the
# withholding direction only.
write_report eligible-capkey.json '{
  "counts": {"files": 2},
  "findings": [{
    "rule": "provenance/audit/rule-verbatim-copy", "file": "ec.md",
    "span": {"start_line": 41}, "TIER": "fingerprint-confirmed",
    "source": {"url": "https://ec.example/s"},
    "fingerprint": {"containment": 0.9, "longest_span_words": 46}
  }]
}'
write_report eligible-verdict.json '{
  "counts": {"files": 2},
  "findings": [{
    "rule": "provenance/audit/rule-verbatim-copy", "file": "ev.md",
    "span": {"start_line": 42}, "verdict": {"tier": "Fingerprint-Confirmed"},
    "source": {"url": "https://ev.example/s"},
    "fingerprint": {"containment": 0.9, "longest_span_words": 47}
  }]
}'
for ecase in "capkey:ec.md:41" "verdict:ev.md:42"; do
  ename="${ecase%%:*}"
  erest="${ecase#*:}"
  efile="${erest%%:*}"
  eline="${erest#*:}"
  EOUT="$OUTDIR/eligible-$ename.md"
  run --report "$REPORTS/eligible-$ename.json" --out "$EOUT" >/dev/null 2>&1
  EBODY="$(cat "$EOUT")"
  assert_eq "fingerprint-confirmed declared at an allowlisted position relays ($ename)" \
    "$(grep -c '^| [0-9]' "$EOUT")" "1"
  assert_contains "the relayed row keeps its location ($ename)" "$EBODY" "$efile:$eline"
  assert_not_contains "it is not counted as declaring no confirmed tier ($ename)" \
    "$EBODY" "Not relay-eligible"
done

# --- One malformed record never takes the run with it ------------------------------
#
# jq aborts the whole program on a type error, so a record that is not an object, or
# whose `span` or `rule` is the wrong type, ended the run at exit 3 under a message
# blaming the JSON — and every well-formed finding beside it was lost. Refusing a
# sidecar is for what the input-refusal gates examine deliberately; a single bad
# record is what `## Unparsed` is for.
write_report malformed-mixed.json '{
  "counts": {"files": 2},
  "findings": [
    {"rule": "provenance/audit/rule-stamp-expired", "file": "good.md", "line": 7,
     "stamp_date": "2025-01-01", "window_days": 180, "days_over": 424},
    [{"tier": "MALFORMEDARRAY"}],
    "MALFORMEDSTRING",
    {"rule": "provenance/audit/rule-verbatim-copy", "file": "s.md",
     "span": "lines 4-9", "tier": "fingerprint-confirmed",
     "source": "https://bad.example/s", "fingerprint": "0.9",
     "note": "MALFORMEDSPAN"},
    {"rule": ["provenance/audit/rule-stamp-expired"], "file": "r.md",
     "note": "MALFORMEDRULE"}
  ]
}'
MAL="$OUTDIR/malformed-mixed.md"
run --report "$REPORTS/malformed-mixed.json" --out "$MAL" >/dev/null 2>&1
assert_exit "a malformed record does not refuse the sidecar" "$?" "0"
assert_file "the well-formed findings are still written" "$MAL"
MAL_BODY="$(cat "$MAL")"
assert_contains "the well-formed stamp finding still reaches the relay" \
  "$MAL_BODY" "good.md:7"
assert_contains "a non-object record lands in Unparsed" "$MAL_BODY" "MALFORMEDARRAY"
assert_contains "a scalar record lands in Unparsed" "$MAL_BODY" "MALFORMEDSTRING"
assert_contains "a mistyped rule id lands in Unparsed" "$MAL_BODY" "MALFORMEDRULE"
assert_contains "a mistyped span still emits its copy row" "$MAL_BODY" "| s.md |"

# --- The other direction: relay-eligible findings SURVIVE --------------------------
#
# Every assertion above is a withhold assertion, and a boundary asserted only in one
# direction is satisfied by withholding everything. Reading `tier` at any depth did
# exactly that: these records declare `fingerprint-confirmed` or a stamp rule at the
# top level and carry an unrelated nested `tier`, and each was dropped — no relay
# row, no `## Unparsed` entry, counted as a judgment finding it is not. The sidecar
# is model-authored against no schema and `tier` is already overloaded here, so none
# of these shapes is contrived.

write_report survive-nested-history.json '{
  "counts": {"files": 2},
  "findings": [{
    "rule": "provenance/audit/rule-verbatim-copy", "file": "s1.md",
    "span": {"start_line": 11}, "tier": "fingerprint-confirmed",
    "source": {"url": "https://s1.example/s"},
    "fingerprint": {"containment": 0.9, "longest_span_words": 40},
    "provenance": {"tier": {"current": "fingerprint-confirmed", "superseded": "not-found"}}
  }]
}'
write_report survive-related.json '{
  "counts": {"files": 2},
  "findings": [{
    "rule": "provenance/audit/rule-verbatim-copy", "file": "s2.md",
    "span": {"start_line": 12}, "tier": "fingerprint-confirmed",
    "source": {"url": "https://s2.example/s"},
    "fingerprint": {"containment": 0.9, "longest_span_words": 41},
    "related": [{"rule": "provenance/audit/rule-other", "tier": "not-found"},
                {"note": "see also"}]
  }]
}'
write_report survive-notes.json '{
  "counts": {"files": 2},
  "findings": [{
    "rule": "provenance/audit/rule-verbatim-copy", "file": "s3.md",
    "span": {"start_line": 13}, "tier": "fingerprint-confirmed",
    "source": {"url": "https://s3.example/s"},
    "fingerprint": {"containment": 0.9, "longest_span_words": 42},
    "notes": {"tier": "was source-fetched-similar last run; now confirmed"}
  }]
}'
write_report survive-review.json '{
  "counts": {"files": 2},
  "findings": [{
    "rule": "provenance/audit/rule-verbatim-copy", "file": "s4.md",
    "span": {"start_line": 14}, "tier": "fingerprint-confirmed",
    "source": {"url": "https://s4.example/s"},
    "fingerprint": {"containment": 0.9, "longest_span_words": 43},
    "review": {"agents": 2,
               "tier": "unchanged; one agent argued llm-suspected and was vetoed"}
  }]
}'
write_report survive-stamp-review.json '{
  "counts": {"files": 2},
  "findings": [{
    "rule": "provenance/audit/rule-stamp-expired", "file": "s5.md", "line": 15,
    "stamp_date": "2025-01-01", "window_days": 180, "days_over": 424,
    "review": {"tier": "escalate when the prior run said not-found"}
  }]
}'
write_report survive-xref.json '{
  "counts": {"files": 2},
  "findings": [{
    "rule": "provenance/audit/rule-trigger-less-stamp", "file": "s6.md", "line": 16,
    "stamp_date": "2026-05-05",
    "xref": {"TIER": "prior: not-found"}
  }]
}'

for vcase in "nested-history:rule-verbatim-copy:s1.md:11" \
  "related:rule-verbatim-copy:s2.md:12" \
  "notes:rule-verbatim-copy:s3.md:13" \
  "review:rule-verbatim-copy:s4.md:14" \
  "stamp-review:rule-stamp-expired:s5.md:15" \
  "xref:rule-trigger-less-stamp:s6.md:16"; do
  vname="${vcase%%:*}"
  vrest="${vcase#*:}"
  vrule="${vrest%%:*}"
  vrest="${vrest#*:}"
  vfile="${vrest%%:*}"
  vline="${vrest#*:}"
  VOUT="$OUTDIR/survive-$vname.md"
  run --report "$REPORTS/survive-$vname.json" --out "$VOUT" >/dev/null 2>&1
  assert_exit "a relay-eligible finding with an unrelated nested tier exits 0 ($vname)" \
    "$?" "0"
  VBODY="$(cat "$VOUT")"
  assert_eq "an unrelated nested tier still emits its relay row ($vname)" \
    "$(grep -c '^| [0-9]' "$VOUT")" "1"
  assert_contains "the surviving row names its rule ($vname)" "$VBODY" "$vrule"
  assert_contains "the surviving row keeps its location ($vname)" \
    "$VBODY" "$vfile:$vline"
  assert_contains "the surviving finding is counted as relay-eligible ($vname)" \
    "$VBODY" "Relay-eligible findings: 1."
  assert_not_contains "a survivor is never counted as a withheld judgment ($vname)" \
    "$VBODY" "judgment findings"
  assert_not_contains "a survivor opens no Unparsed section ($vname)" \
    "$VBODY" "## Unparsed"
done

# The stated limit of the value half, asserted so it stays a stated one. A DECLARED
# tier whose value names a judgment verdict is withheld even when it names
# fingerprint-confirmed too: nothing here can tell that history array from the
# `["not-found"]` evasion above, and withholding is the side that stays visible.
write_report survive-ambiguous.json '{
  "counts": {"files": 2},
  "findings": [{
    "rule": "provenance/audit/rule-stamp-expired", "file": "s7.md", "line": 17,
    "stamp_date": "2025-01-01", "window_days": 180, "days_over": 424,
    "tier": ["fingerprint-confirmed", "not-found"],
    "searched": ["https://s7.example/u"]
  }]
}'
AMB="$OUTDIR/survive-ambiguous.md"
run --report "$REPORTS/survive-ambiguous.json" --out "$AMB" >/dev/null 2>&1
AMB_BODY="$(cat "$AMB")"
assert_eq "a tier naming both a verdict and a relay tier emits no row" \
  "$(grep -c '^| [0-9]' "$AMB")" "0"
assert_contains "such a record is counted, never dropped" "$AMB_BODY" "1 judgment"

# --- Each Surfaces count says what its records ARE --------------------------------
#
# A copy rule declaring neither fingerprint-confirmed nor a judgment verdict is not
# relay-eligible, but it is not a judgment finding on the human report either.
# Counting it as one sends a reader looking for it where it is not.
write_report ineligible-copy.json '{
  "counts": {"files": 2},
  "findings": [{
    "rule": "provenance/audit/rule-verbatim-copy", "file": "i.md",
    "span": {"start_line": 21}, "tier": "some-future-verdict",
    "note": "INELIGIBLECANARY"
  }]
}'
INEL="$OUTDIR/ineligible-copy.md"
run --report "$REPORTS/ineligible-copy.json" --out "$INEL" >/dev/null 2>&1
INEL_BODY="$(cat "$INEL")"
assert_eq "a copy declaring no fingerprint-confirmed tier emits no row" \
  "$(grep -c '^| [0-9]' "$INEL")" "0"
assert_contains "it is counted as not relay-eligible" "$INEL_BODY" "Not relay-eligible: 1"
assert_not_contains "it is not miscounted as a judgment finding" \
  "$INEL_BODY" "judgment findings"
assert_not_contains "an ineligible copy still leaks no payload" \
  "$INEL_BODY" "INELIGIBLECANARY"

# The genuine `## Unparsed` path is untouched. Unmappable for any reason OTHER than
# a withheld verdict — an unknown rule id, an unknown tier — still lands verbatim.
write_report unparsed-unknown-rule.json '{
  "counts": {"files": 2},
  "findings": [
    {"rule": "provenance/audit/rule-future-thing", "file": "f.md", "line": 9,
     "note": "UNPARSEDCANARY"}
  ]
}'
UNK_RULE="$OUTDIR/unparsed-unknown-rule.md"
run --report "$REPORTS/unparsed-unknown-rule.json" --out "$UNK_RULE" >/dev/null 2>&1
UNK_RULE_BODY="$(cat "$UNK_RULE")"
assert_contains "an unknown rule id still opens Unparsed" "$UNK_RULE_BODY" "## Unparsed"
assert_contains "an unknown rule id keeps its raw text" "$UNK_RULE_BODY" "UNPARSEDCANARY"
assert_contains "an unknown rule id is reported as unmapped" "$UNK_RULE_BODY" "Unmapped: 1"

write_report unparsed-unknown-tier.json '{
  "counts": {"files": 2},
  "findings": [
    {"tier": "some-future-verdict", "file": "g.md", "note": "UNKNOWNTIERCANARY"}
  ]
}'
UNK_TIER="$OUTDIR/unparsed-unknown-tier.md"
run --report "$REPORTS/unparsed-unknown-tier.json" --out "$UNK_TIER" >/dev/null 2>&1
UNK_TIER_BODY="$(cat "$UNK_TIER")"
assert_contains "an unknown tier still opens Unparsed" "$UNK_TIER_BODY" "## Unparsed"
assert_contains "an unknown tier keeps its raw text" "$UNK_TIER_BODY" "UNKNOWNTIERCANARY"
assert_contains "an unknown tier is reported as unmapped" "$UNK_TIER_BODY" "Unmapped: 1"

EMPTY="$OUTDIR/empty.md"
run --report "$REPORTS/empty.json" --out "$EMPTY" >/dev/null 2>&1
assert_exit "a zero-finding run still exits 0" "$?" "0"
assert_file "a zero-finding run still writes the file" "$EMPTY"
assert_contains "coverage is reported even with no findings" "$(cat "$EMPTY")" "## Surfaces"
assert_contains "the surfaces line names the corpus size" "$(cat "$EMPTY")" "10"

# --- Non-overwrite naming --------------------------------------------------------

DUP="$OUTDIR/dup.md"
run --report "$REPORTS/full.json" --out "$DUP" >/dev/null 2>&1
run --report "$REPORTS/full.json" --out "$DUP" >/dev/null 2>&1
assert_file "a second write takes the -2 suffix" "$OUTDIR/dup-2.md"
run --report "$REPORTS/full.json" --out "$DUP" >/dev/null 2>&1
assert_file "a third write takes the -3 suffix" "$OUTDIR/dup-3.md"

# --- Branch handling -------------------------------------------------------------

BR="$OUTDIR/branch.md"
run --report "$REPORTS/full.json" --out "$BR" --branch 'no' >/dev/null 2>&1
assert_contains "a YAML-implicit-typed branch name is quoted" "$(cat "$BR")" 'branch: "no"'

BR2="$OUTDIR/branch2.md"
run --report "$REPORTS/full.json" --out "$BR2" --branch '#hash' >/dev/null 2>&1
assert_contains "a branch starting with a YAML indicator is quoted" "$(cat "$BR2")" 'branch: "#hash"'

# --- Absolute paths --------------------------------------------------------------

write_report abs.json "{
  \"findings\": [
    {
      \"rule\": \"provenance/audit/rule-stamp-expired\",
      \"file\": \"$REPO/docs/page.md\",
      \"line\": 7,
      \"stamp_date\": \"2025-01-01\",
      \"window_days\": 180,
      \"days_over\": 100
    }
  ]
}"
ABS="$OUTDIR/abs.md"
run --report "$REPORTS/abs.json" --out "$ABS" >/dev/null 2>&1
assert_contains "an absolute path is relativized" "$(cat "$ABS")" "| docs/page.md:7 |"
assert_not_contains "the repo root does not survive into Location" "$(cat "$ABS")" "$REPO/docs"

# --- Write failures --------------------------------------------------------------
#
# The worst outcome for a persistence step is reporting success having written
# nothing: the audit says the findings are relayed, and the consumer never scans
# a file that does not exist. `set -e` is deliberately not on in this script, so
# the two writing commands are checked explicitly.

assert_fails "an uncreatable destination directory exits non-zero" \
  bash "$EMIT" --report "$REPORTS/full.json" --out /proc/nope/deeper/x.md

OUT="$(run --report "$REPORTS/full.json" --out /proc/nope/deeper/x.md 2>&1)"
assert_not_contains "a failed write never claims it wrote" "$OUT" "wrote"

UNWRITABLE="$TEST_TMPDIR/unwritable"
mkdir -p "$UNWRITABLE"
chmod a-w "$UNWRITABLE"
if [[ ! -w "$UNWRITABLE" ]]; then
  assert_fails "an unwritable destination exits non-zero" \
    bash "$EMIT" --report "$REPORTS/full.json" --out "$UNWRITABLE/x.md"
else
  pass "an unwritable destination exits non-zero (SKIP: this user ignores mode bits)"
fi
chmod u+w "$UNWRITABLE"

# --- Determinism -----------------------------------------------------------------

D1="$OUTDIR/det1.md"
D2="$OUTDIR/det2.md"
run --report "$REPORTS/full.json" --out "$D1" >/dev/null 2>&1
run --report "$REPORTS/full.json" --out "$D2" >/dev/null 2>&1
assert_eq "repeat runs differ only in their date line" \
  "$(diff <(grep -v '^date:' "$D1") <(grep -v '^date:' "$D2") >/dev/null && echo same)" "same"

printf '\nPassed: %s  Failed: %s\n' "$((CASE_NUM - FAILED))" "$FAILED"
[[ "$FAILED" -eq 0 ]]
