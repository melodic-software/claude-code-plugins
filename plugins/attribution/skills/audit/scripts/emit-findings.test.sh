#!/usr/bin/env bash
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

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

# shellcheck source=../../../lib/test-helpers.sh
source "$SCRIPT_DIR/../../../lib/test-helpers.sh"
SKIPPED=0

skip() {
  SKIPPED=$((SKIPPED + 1))
  printf 'SKIP (host: %s): %s\n' "$2" "$1"
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
assert_fails() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    fail "$label" "non-zero exit" "exit 0"
  else
    pass "$label"
  fi
}

REPO="$TEST_TMPDIR/repo"
mkdir -p "$REPO/docs"
printf '%s\n' '# Doc' >"$REPO/docs/page.md"
git -C "$REPO" init -q
git -C "$REPO" config user.email "test@example.com"
git -C "$REPO" config user.name "Test"
git -C "$REPO" add -A
git -C "$REPO" commit -qm "fixture"
git -C "$REPO" checkout -qb feature/attribution-relay

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
      "rule": "attribution/audit/rule-verbatim-copy",
      "file": "docs/page.md",
      "span": {"start_line": 44, "end_line": 51},
      "class": "verbatim",
      "tier": "fingerprint-confirmed",
      "source": {"url": "https://code.claude.com/docs/skills.md", "fetched": "2026-08-27",
                 "identity": {"checked": true}},
      "fingerprint": {"containment": 0.42, "longest_span_words": 27}
    },
    {
      "rule": "attribution/audit/rule-stamp-expired",
      "file": "docs/page.md",
      "line": 12,
      "stamp_date": "2025-01-01",
      "window_days": 180,
      "days_over": 424
    },
    {
      "rule": "attribution/audit/rule-trigger-less-stamp",
      "file": "docs/page.md",
      "line": 20,
      "stamp_date": "2026-05-05"
    },
    {
      "rule": "attribution/audit/rule-verbatim-copy",
      "file": "docs/page.md",
      "span": {"start_line": 70, "end_line": 72},
      "class": "paraphrase",
      "tier": "llm-suspected"
    },
    {
      "rule": "attribution/audit/rule-verbatim-copy",
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

TARGET="$OUTDIR/20260828T120000Z-attribution.md"
run --report "$REPORTS/full.json" --out "$TARGET" >/dev/null 2>&1
assert_exit "a clean run exits 0" "$?" "0"

assert_file "the file is written" "$TARGET"
BODY="$(cat "$TARGET")"

assert_contains "frontmatter declares the consumed type" "$BODY" "type: review-findings"
assert_contains "frontmatter carries the branch" "$BODY" "branch: feature/attribution-relay"
assert_match "date is a full ISO-8601 instant with an explicit Z" \
  "$BODY" 'date: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z'
assert_contains "the Findings section is present" "$BODY" "## Findings"
assert_contains "the table header is the contract's columns" "$BODY" \
  "| Rank | Tier | Confidence | Location | Surface(s) | Finding | Action |"

ROWS="$(grep -c '^| [0-9]' "$TARGET")"
assert_eq "only the three relay-eligible findings become rows" "$ROWS" "3"
assert_contains "the fingerprint-confirmed copy is a row" "$BODY" "rule-verbatim-copy"
assert_contains "the expired stamp is a row" "$BODY" "rule-stamp-expired"
assert_contains "the trigger-less stamp is a row" "$BODY" "rule-trigger-less-stamp"
assert_not_contains "an llm-suspected verdict never reaches the relay" "$BODY" "llm-suspected"
assert_not_contains "a source-fetched-similar verdict never reaches the relay" "$BODY" "source-fetched-similar"
assert_contains "withheld judgment findings are counted, not dropped" "$BODY" "2 judgment"

NF_SEARCHED='["https://code.claude.com/docs/llms.txt","site search: nf-surface.example"]'

write_report notfound-absent.json '{
  "counts": {"files": 3},
  "findings": [
    {
      "rule": "attribution/audit/rule-verbatim-copy",
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
      "rule": "attribution/audit/rule-verbatim-copy",
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
      \"rule\": \"attribution/audit/rule-verbatim-copy\",
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

run --report "$REPORTS/full.json" --out "$OUTDIR/nf-unrelated.md" >/dev/null 2>&1
assert_exit "a sidecar with no not-found finding is unaffected" "$?" "0"

COPY_ROW="$(grep 'rule-verbatim-copy' "$TARGET" | head -1)"
assert_contains "Tier is looked up from the crosswalk" "$COPY_ROW" "| IMPORTANT |"
assert_contains "Confidence is high for a deterministic rule that fired" "$COPY_ROW" "| high |"
assert_contains "Location is repo-relative file:line" "$COPY_ROW" "docs/page.md:44"
assert_contains "the Finding cell leads with the qualified rule id" "$COPY_ROW" \
  "| attribution/audit/rule-verbatim-copy:"
assert_contains "the Finding cell carries the fired values" "$COPY_ROW" "27"
assert_contains "the copy row names its source" "$COPY_ROW" "https://code.claude.com/docs/skills.md"
assert_contains "the Action names the producer-owned remediation" "$COPY_ROW" "attribution:audit fix"

STAMP_ROW="$(grep 'rule-stamp-expired' "$TARGET" | head -1)"
assert_contains "the stamp row carries its fired values" "$STAMP_ROW" "424"
assert_contains "the stamp row names its window" "$STAMP_ROW" "180"
assert_contains "the stamp row is not auto-applicable" "$STAMP_ROW" "re-deriv"

assert_eq "ranks run 1..N in order" \
  "$(grep -o '^| [0-9]* |' "$TARGET" | tr -dc '0-9' | tr -d '\n')" "123"

write_report pipes.json '{
  "findings": [
    {
      "rule": "attribution/audit/rule-verbatim-copy",
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
assert_not_contains "an already-escaped pipe is not double-escaped" "$PIPE_ROW" '\\|'
assert_not_contains "a newline inside a cell is replaced" "$PIPE_ROW" $'\n'

write_report pipe-path.json '{
  "findings": [
    {"rule": "attribution/audit/rule-stamp-expired", "file": "a|b.md", "line": 1,
     "stamp_date": "2025-01-01", "window_days": 180, "days_over": 9}
  ]
}'
PIPE_PATH_OUT="$OUTDIR/pipe-path.md"
run --report "$REPORTS/pipe-path.json" --out "$PIPE_PATH_OUT" >/dev/null 2>&1
PIPE_PATH_ROW="$(grep 'rule-stamp-expired' "$PIPE_PATH_OUT" | head -1)"
assert_eq "a pipe in a path keeps the row at the contract's columns" \
  "$(printf '%s' "$PIPE_PATH_ROW" | sed 's/\\|//g' | tr -cd '|' | wc -c | tr -d ' ')" "8"
assert_contains "and the path is escaped in place" "$PIPE_PATH_ROW" 'a\|b.md:1'

UNP="$OUTDIR/unparsed.md"
run --report "$REPORTS/unparsed.json" --out "$UNP" >/dev/null 2>&1
assert_exit "a finding with no rule id still exits 0" "$?" "0"
assert_contains "an unrecognized finding lands in Unparsed" "$(cat "$UNP")" "## Unparsed"
assert_contains "the unparsed finding keeps its raw text" "$(cat "$UNP")" "no rule id"

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
write_report withheld-vs.json '{
  "counts": {"files": 2},
  "findings": [
    {"tier": "vendored-snapshot", "file": "e.md", "excerpt": "LEAKCANARY-VS"}
  ]
}'

for wcase in "nf:not-found:LEAKCANARY.example" \
  "sfs:source-fetched-similar:LEAKCANARY-SFS" \
  "llm:llm-suspected:LEAKCANARY-LLM" \
  "vs:vendored-snapshot:LEAKCANARY-VS"; do
  IFS=: read -r wname wtier wcanary <<<"$wcase"
  WOUT="$OUTDIR/withheld-$wname.md"
  run --report "$REPORTS/withheld-$wname.json" --out "$WOUT" >/dev/null 2>&1
  assert_exit "a rule-less $wtier finding still exits 0" "$?" "0"
  WBODY="$(cat "$WOUT")"
  assert_not_contains "a rule-less $wtier tier name never reaches the file" "$WBODY" "$wtier"
  assert_not_contains "a rule-less $wtier payload never reaches the file" "$WBODY" "$wcanary"
  assert_not_contains "a rule-less $wtier finding opens no Unparsed section" "$WBODY" "## Unparsed"
  assert_contains "a rule-less $wtier finding is counted, not dropped" "$WBODY" "1 judgment"
done

write_report withheld-vs-rule.json '{
  "counts": {"files": 2},
  "findings": [
    {"rule": "attribution/audit/rule-verbatim-copy", "tier": "vendored-snapshot",
     "file": "e.md", "excerpt": "LEAKCANARY-VSRULE",
     "source": {"route": "vendored-snapshot"}}
  ]
}'
WVSR="$OUTDIR/withheld-vs-rule.md"
run --report "$REPORTS/withheld-vs-rule.json" --out "$WVSR" >/dev/null 2>&1
assert_exit "a rule-paired vendored-snapshot finding exits 0" "$?" "0"
VSR_BODY="$(cat "$WVSR")"
assert_eq "a rule-paired vendored-snapshot finding is no relay row" \
  "$(grep -c '^| [0-9]' "$WVSR")" "0"
assert_not_contains "a rule-paired vendored-snapshot tier name never reaches the file" \
  "$VSR_BODY" "vendored-snapshot"
assert_not_contains "a rule-paired vendored-snapshot payload never reaches the file" \
  "$VSR_BODY" "LEAKCANARY-VSRULE"
assert_contains "a rule-paired vendored-snapshot finding is counted as judgment" \
  "$VSR_BODY" "1 judgment"
assert_not_contains "a rule-paired vendored-snapshot finding is not counted as ineligible" \
  "$VSR_BODY" "Not relay-eligible"

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

write_report withheld-padded.json '{
  "findings": [{"tier": "  not-found  ", "file": "a.md", "note": "PADCANARY",
                "searched": ["https://x.example/"]}]
}'
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
  IFS=: read -r sname sverdict scanary <<<"$scase"
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
assert_not_contains "a capitalized-key searched surface never reaches the file" \
  "$(cat "$OUTDIR/withheld-capkey.md")" "CAPSURFACE.example"

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

write_report withheld-with-rule.json '{
  "counts": {"files": 2},
  "findings": [
    {"rule": "attribution/audit/rule-stamp-expired", "file": "e.md", "line": 7,
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

write_report gate-unrelated.json '{
  "counts": {"files": 2},
  "findings": [{
    "rule": "attribution/audit/rule-stamp-expired", "file": "u.md", "line": 3,
    "stamp_date": "2025-01-01", "window_days": 180, "days_over": 424,
    "xref": {"tier": "prior run said not-found"}
  }]
}'
GUN="$OUTDIR/gate-unrelated.md"
run --report "$REPORTS/gate-unrelated.json" --out "$GUN" >/dev/null 2>&1
assert_exit "a not-found named outside the declared tier is not gated" "$?" "0"

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
write_report verdict-cased.json '{
  "counts": {"files": 2},
  "findings": [{"Verdict": "llm-suspected", "file": "vc.md", "excerpt": "VCASECANARY"}]
}'
write_report verdict-on-stamp.json '{
  "counts": {"files": 2},
  "findings": [{"rule": "attribution/audit/rule-stamp-expired", "file": "vst.md",
                "line": 3, "verdict": "llm-suspected", "stamp_date": "2025-01-01",
                "window_days": 180, "days_over": 9}]
}'

for vc in "string:not-found:VSTRCANARY" "array:llm-suspected:VARRCANARY" \
  "deep:llm-suspected:VDEEPCANARY" "cased:llm-suspected:VCASECANARY" \
  "on-stamp:llm-suspected:none"; do
  IFS=: read -r vn vv vk <<<"$vc"
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

write_report verdict-beside-confirmed.json '{
  "counts": {"files": 2},
  "findings": [{
    "rule": "attribution/audit/rule-verbatim-copy", "file": "vb.md",
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

write_report verdict-superseded.json '{
  "counts": {"files": 2},
  "findings": [{
    "rule": "attribution/audit/rule-verbatim-copy", "file": "vsup.md",
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

write_report tier-unusable-null.json '{
  "counts": {"files": 2},
  "findings": [{"rule": "attribution/audit/rule-future", "tier": null,
                "verdict": {"result": {"tier": "not-found"}}, "excerpt": "UNUSABLENULL",
                "searched": ["https://un.example/u"]}]
}'
write_report tier-unusable-empty.json '{
  "counts": {"files": 2},
  "findings": [{"rule": "attribution/audit/rule-future", "tier": [],
                "verdict": ["source-fetched-similar"], "excerpt": "UNUSABLEEMPTY"}]
}'
write_report tier-unusable-word.json '{
  "counts": {"files": 2},
  "findings": [{"rule": "attribution/audit/rule-future", "tier": "pending",
                "verdict": {"tier": "llm-suspected"}, "excerpt": "UNUSABLEWORD"}]
}'
for uu in "null:not-found:UNUSABLENULL" "empty:source-fetched-similar:UNUSABLEEMPTY" \
  "word:llm-suspected:UNUSABLEWORD"; do
  IFS=: read -r un uv uk <<<"$uu"
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

write_report verdict-tier-unusable-word.json '{
  "counts": {"files": 2},
  "findings": [{"rule": "attribution/audit/rule-nomination", "file": "vu.md",
                "verdict": {"tier": "pending", "result": "not-found", "confidence": "low"},
                "excerpt": "VUWORDCANARY", "searched": ["https://vu.example/u"]}]
}'
write_report verdict-tier-unusable-null.json '{
  "counts": {"files": 2},
  "findings": [{"verdict": {"tier": null, "outcome": "llm-suspected"},
                "file": "vu2.md", "note": "VUNULLCANARY"}]
}'
write_report verdict-tier-unusable-blank.json '{
  "counts": {"files": 2},
  "findings": [{"verdict": {"tier": "", "outcome": "source-fetched-similar",
                            "evidence": "VUBLANKCANARY"}, "file": "vu3.md"}]
}'
write_report verdict-tier-unusable-sni.json '{
  "counts": {"files": 2},
  "findings": [{"verdict": {"tier": "unset", "outcome": "source-not-identified"},
                "file": "vu4.md", "excerpt": "VUSNICANARY",
                "searched": ["https://vu4.example/u"]}]
}'
for vu in "word:not-found:VUWORDCANARY" "null:llm-suspected:VUNULLCANARY" \
  "blank:source-fetched-similar:VUBLANKCANARY" \
  "sni:source-not-identified:VUSNICANARY"; do
  IFS=: read -r vun vuv vuk <<<"$vu"
  VUO="$OUTDIR/verdict-tier-unusable-$vun.md"
  run --report "$REPORTS/verdict-tier-unusable-$vun.json" --out "$VUO" >/dev/null 2>&1
  VUB="$(cat "$VUO")"
  assert_eq "an unusable verdict.tier emits no relay row ($vun)" \
    "$(grep -c '^| [0-9]' "$VUO")" "0"
  assert_not_contains "an unusable verdict.tier does not hide the outcome ($vun)" \
    "$VUB" "$vuv"
  assert_not_contains "an unusable verdict.tier leaks no payload ($vun)" "$VUB" "$vuk"
  assert_not_contains "an unusable verdict.tier opens no Unparsed section ($vun)" \
    "$VUB" "## Unparsed"
  assert_contains "an unusable verdict.tier is counted ($vun)" "$VUB" "1 judgment"
done

write_report verdict-tier-unusable-gate.json '{
  "counts": {"files": 2},
  "findings": [{"verdict": {"tier": "pending", "result": "not-found"}, "file": "vg.md"}]
}'
run --report "$REPORTS/verdict-tier-unusable-gate.json" \
  --out "$OUTDIR/verdict-tier-unusable-gate.md" >/dev/null 2>&1
assert_exit "an unusable verdict.tier does not let a not-found skip the gate" "$?" "3"

write_report verdict-tier-unusable-stamp.json '{
  "counts": {"files": 2},
  "findings": [{"rule": "attribution/audit/rule-stamp-expired", "file": "vs2.md",
                "line": 1, "stamp_date": "2020-01-01", "window_days": 9, "days_over": 2,
                "verdict": {"tier": "pending", "result": "not-found"},
                "searched": ["https://vs2.example/u"]}]
}'
VUS="$OUTDIR/verdict-tier-unusable-stamp.md"
run --report "$REPORTS/verdict-tier-unusable-stamp.json" --out "$VUS" >/dev/null 2>&1
assert_eq "a stamp rule carrying a smuggled outcome emits no relay row" \
  "$(grep -c '^| [0-9]' "$VUS")" "0"
assert_contains "and it is counted as withheld" "$(cat "$VUS")" "1 judgment"

write_report tier-unusable-ungated.json '{
  "counts": {"files": 2},
  "findings": [{"rule": "attribution/audit/rule-future", "tier": "pending",
                "verdict": "not-found", "excerpt": "UNUSABLEGATE"}]
}'
run --report "$REPORTS/tier-unusable-ungated.json" \
  --out "$OUTDIR/tier-unusable-ungated.md" >/dev/null 2>&1
assert_exit "an unusable tier does not let a not-found skip the searched gate" "$?" "3"

write_report verdict-child-confirmed.json '{
  "counts": {"files": 2},
  "findings": [{
    "rule": "attribution/audit/rule-verbatim-copy", "file": "vch.md",
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
  IFS=: read -r rn rv rk <<<"$rw"
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

write_report record-wrapped-benign.json '{
  "counts": {"files": 2},
  "findings": [
    [{"note": "BENIGNWRAPCANARY"}],
    {"rule": "attribution/audit/rule-stamp-expired", "file": "ok.md", "line": 4,
     "stamp_date": "2025-01-01", "window_days": 180, "days_over": 9}
  ]
}'
RWB="$OUTDIR/record-wrapped-benign.md"
run --report "$REPORTS/record-wrapped-benign.json" --out "$RWB" >/dev/null 2>&1
RWB_BODY="$(cat "$RWB")"
assert_contains "a benign wrapped record still lands in Unparsed" \
  "$RWB_BODY" "BENIGNWRAPCANARY"
assert_contains "and the well-formed finding beside it still relays" "$RWB_BODY" "ok.md:4"

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

write_report neutral-published-name.json '{
  "counts": {"files": 2},
  "findings": [{"rule": "attribution/audit/rule-stamp-expired", "file": "sn.md",
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

write_report truncated.json '{"findings": [{"rule": "x"'
TRUNC_ERR="$(run --report "$REPORTS/truncated.json" --out "$OUTDIR/truncated.md" 2>&1)"
assert_exit "a truncated sidecar exits 3" "$?" "3"
assert_contains "and says it is not a JSON object" "$TRUNC_ERR" "not a JSON object"
assert_not_contains "and does not blame a missing findings key" \
  "$TRUNC_ERR" "no findings key"
GARB_ERR="$(run --report "$REPORTS/garbage.json" --out "$OUTDIR/garbage2.md" 2>&1)"
assert_contains "non-JSON input says it is not a JSON object" \
  "$GARB_ERR" "not a JSON object"

write_report findings-scalar.json '{"findings": "none"}'
FSC="$OUTDIR/findings-scalar.md"
FSC_ERR="$(run --report "$REPORTS/findings-scalar.json" --out "$FSC" 2>&1)"
assert_exit "a non-list findings key exits 3" "$?" "3"
assert_contains "and says the findings key is not a list" "$FSC_ERR" "not a list"
assert_not_contains "and does not blame the not-found check" "$FSC_ERR" "not-found finding"

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
write_report tier-invisible-interior.json '{
  "findings": [{"tier": "not-‍found", "file": "x.md", "note": "INVIS-INTERIOR",
                "searched": ["https://z.example/u"]}]
}'
write_report tier-invisible-interior2.json '{
  "findings": [{"verdict": {"tier": "source-fetched-​similar"}, "file": "x.md",
                "note": "INVIS-INTERIOR2"}]
}'
write_report tier-invisible-vs16.json '{
  "findings": [{"tier": "not-found️", "file": "x.md", "note": "INVIS-VS16",
                "searched": ["https://z.example/u"]}]
}'
write_report tier-invisible-cgj.json '{
  "findings": [{"tier": "not-͏found", "file": "x.md", "note": "INVIS-CGJ",
                "searched": ["https://z.example/u"]}]
}'
for iv in "zwsp:not-found:INVIS-ZWSP" "zwnj:not-found:INVIS-ZWNJ" \
  "wj:llm-suspected:INVIS-WJ" "lrm:llm-suspected:INVIS-LRM" \
  "shy:not-found:INVIS-SHY" "mixed:not-found:INVIS-MIXED" \
  "nbsp:not-found:INVIS-NBSP" "interior:not-found:INVIS-INTERIOR" \
  "interior2:source-fetched-similar:INVIS-INTERIOR2" \
  "vs16:not-found:INVIS-VS16" "cgj:not-found:INVIS-CGJ"; do
  IFS=: read -r ivn ivv ivk <<<"$iv"
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

write_report tier-dash-u2010.json '{
  "findings": [{"tier": "not‐found", "file": "x.md", "note": "DASH2010CANARY",
                "searched": ["https://z.example/u"]}]
}'
write_report tier-dash-u2011.json '{
  "findings": [{"verdict": "llm‑suspected", "file": "x.md", "note": "DASH2011CANARY"}]
}'
write_report tier-dash-minus.json '{
  "findings": [{"tier": "not−found", "file": "x.md", "note": "DASHMINUSCANARY",
                "searched": ["https://z.example/u"]}]
}'
for dc in "u2010:not-found:DASH2010CANARY" "u2011:llm-suspected:DASH2011CANARY" \
  "minus:not-found:DASHMINUSCANARY"; do
  IFS=: read -r dcn dcv dck <<<"$dc"
  DCO="$OUTDIR/tier-dash-$dcn.md"
  run --report "$REPORTS/tier-dash-$dcn.json" --out "$DCO" >/dev/null 2>&1
  DCB="$(cat "$DCO")"
  assert_not_contains "a hyphen homoglyph is still the verdict it renders as ($dcn)" \
    "$DCB" "$dcv"
  assert_not_contains "a hyphen homoglyph leaks no payload ($dcn)" "$DCB" "$dck"
  assert_contains "a hyphen homoglyph is counted ($dcn)" "$DCB" "1 judgment"
done

write_report tier-key-name.json '{
  "counts": {"files": 2},
  "findings": [{"rule": "attribution/audit/rule-unknown", "file": "k.md", "line": 1,
                "tier": {"not-found": true}, "note": "KEYNAMECANARY",
                "searched": ["https://k.example/u"]}]
}'
write_report tier-key-wrapped.json '{
  "counts": {"files": 2},
  "findings": [{"rule": "attribution/audit/rule-unknown", "file": "k2.md",
                "tier": [{"llm-suspected": 1}], "note": "KEYWRAPCANARY"}]
}'
write_report record-key-name.json '{
  "counts": {"files": 2},
  "findings": [[{"not-found": {"excerpt": "RECORDKEYCANARY"}}]]
}'
for kc in "tier-key-name:not-found:KEYNAMECANARY" \
  "tier-key-wrapped:llm-suspected:KEYWRAPCANARY" \
  "record-key-name:not-found:RECORDKEYCANARY"; do
  IFS=: read -r kcn kcv kck <<<"$kc"
  KCO="$OUTDIR/$kcn.md"
  run --report "$REPORTS/$kcn.json" --out "$KCO" >/dev/null 2>&1
  KCB="$(cat "$KCO")"
  assert_not_contains "a verdict spelled as a key is still a verdict ($kcn)" \
    "$KCB" "$kcv"
  assert_not_contains "a verdict spelled as a key leaks no payload ($kcn)" "$KCB" "$kck"
  assert_not_contains "a verdict spelled as a key opens no Unparsed section ($kcn)" \
    "$KCB" "## Unparsed"
  assert_contains "a verdict spelled as a key is counted ($kcn)" "$KCB" "1 judgment"
done

write_report record-invisible-wrapped.json '{
  "counts": {"files": 2},
  "findings": [["llm-suspected️", "WRAPINVISCANARY"]]
}'
RIW="$OUTDIR/record-invisible-wrapped.md"
run --report "$REPORTS/record-invisible-wrapped.json" --out "$RIW" >/dev/null 2>&1
RIW_BODY="$(cat "$RIW")"
assert_not_contains "an invisibly spelled verdict in a wrapped record is withheld" \
  "$RIW_BODY" "## Unparsed"
assert_not_contains "and it leaks no payload" "$RIW_BODY" "WRAPINVISCANARY"
assert_contains "and it is counted" "$RIW_BODY" "1 judgment"

write_report tier-visible-space.json '{
  "counts": {"files": 2},
  "findings": [{"tier": "not found", "file": "x.md", "note": "VISIBLESPACECANARY"}]
}'
write_report tier-visible-accent.json '{
  "counts": {"files": 2},
  "findings": [{"tier": "not-fóund", "file": "x.md", "note": "VISIBLEACCENTCANARY"}]
}'
for vz in "space:VISIBLESPACECANARY" "accent:VISIBLEACCENTCANARY"; do
  IFS=: read -r vzn vzk <<<"$vz"
  VZO="$OUTDIR/tier-visible-$vzn.md"
  run --report "$REPORTS/tier-visible-$vzn.json" --out "$VZO" >/dev/null 2>&1
  assert_exit "a rendering character inside the name is not stripped ($vzn)" "$?" "0"
  assert_contains "and the record keeps the unknown-tier appendix path ($vzn)" \
    "$(cat "$VZO")" "$vzk"
done

write_report tier-freetext.json '{
  "counts": {"files": 2},
  "findings": [{
    "rule": "attribution/audit/rule-verbatim-copy", "file": "ft.md",
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

write_report tier-freetext-nf.json '{
  "counts": {"files": 2},
  "findings": [{
    "rule": "attribution/audit/rule-verbatim-copy", "file": "ftn.md",
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

write_report eligible-capkey.json '{
  "counts": {"files": 2},
  "findings": [{
    "rule": "attribution/audit/rule-verbatim-copy", "file": "ec.md",
    "span": {"start_line": 41}, "TIER": "fingerprint-confirmed",
    "source": {"url": "https://ec.example/s"},
    "fingerprint": {"containment": 0.9, "longest_span_words": 46}
  }]
}'
write_report eligible-verdict.json '{
  "counts": {"files": 2},
  "findings": [{
    "rule": "attribution/audit/rule-verbatim-copy", "file": "ev.md",
    "span": {"start_line": 42}, "verdict": {"tier": "Fingerprint-Confirmed"},
    "source": {"url": "https://ev.example/s"},
    "fingerprint": {"containment": 0.9, "longest_span_words": 47}
  }]
}'
for ecase in "capkey:ec.md:41" "verdict:ev.md:42"; do
  IFS=: read -r ename efile eline <<<"$ecase"
  EOUT="$OUTDIR/eligible-$ename.md"
  run --report "$REPORTS/eligible-$ename.json" --out "$EOUT" >/dev/null 2>&1
  EBODY="$(cat "$EOUT")"
  assert_eq "fingerprint-confirmed declared at an allowlisted position relays ($ename)" \
    "$(grep -c '^| [0-9]' "$EOUT")" "1"
  assert_contains "the relayed row keeps its location ($ename)" "$EBODY" "$efile:$eline"
  assert_not_contains "it is not counted as declaring no confirmed tier ($ename)" \
    "$EBODY" "Not relay-eligible"
done

write_report malformed-mixed.json '{
  "counts": {"files": 2},
  "findings": [
    {"rule": "attribution/audit/rule-stamp-expired", "file": "good.md", "line": 7,
     "stamp_date": "2025-01-01", "window_days": 180, "days_over": 424},
    [{"tier": "MALFORMEDARRAY"}],
    "MALFORMEDSTRING",
    {"rule": "attribution/audit/rule-verbatim-copy", "file": "s.md",
     "span": "lines 4-9", "tier": "fingerprint-confirmed",
     "source": "https://bad.example/s", "fingerprint": "0.9",
     "note": "MALFORMEDSPAN"},
    {"rule": ["attribution/audit/rule-stamp-expired"], "file": "r.md",
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

write_report survive-nested-history.json '{
  "counts": {"files": 2},
  "findings": [{
    "rule": "attribution/audit/rule-verbatim-copy", "file": "s1.md",
    "span": {"start_line": 11}, "tier": "fingerprint-confirmed",
    "source": {"url": "https://s1.example/s"},
    "fingerprint": {"containment": 0.9, "longest_span_words": 40},
    "provenance": {"tier": {"current": "fingerprint-confirmed", "superseded": "not-found"}}
  }]
}'
write_report survive-related.json '{
  "counts": {"files": 2},
  "findings": [{
    "rule": "attribution/audit/rule-verbatim-copy", "file": "s2.md",
    "span": {"start_line": 12}, "tier": "fingerprint-confirmed",
    "source": {"url": "https://s2.example/s"},
    "fingerprint": {"containment": 0.9, "longest_span_words": 41},
    "related": [{"rule": "attribution/audit/rule-other", "tier": "not-found"},
                {"note": "see also"}]
  }]
}'
write_report survive-notes.json '{
  "counts": {"files": 2},
  "findings": [{
    "rule": "attribution/audit/rule-verbatim-copy", "file": "s3.md",
    "span": {"start_line": 13}, "tier": "fingerprint-confirmed",
    "source": {"url": "https://s3.example/s"},
    "fingerprint": {"containment": 0.9, "longest_span_words": 42},
    "notes": {"tier": "was source-fetched-similar last run; now confirmed"}
  }]
}'
write_report survive-review.json '{
  "counts": {"files": 2},
  "findings": [{
    "rule": "attribution/audit/rule-verbatim-copy", "file": "s4.md",
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
    "rule": "attribution/audit/rule-stamp-expired", "file": "s5.md", "line": 15,
    "stamp_date": "2025-01-01", "window_days": 180, "days_over": 424,
    "review": {"tier": "escalate when the prior run said not-found"}
  }]
}'
write_report survive-xref.json '{
  "counts": {"files": 2},
  "findings": [{
    "rule": "attribution/audit/rule-trigger-less-stamp", "file": "s6.md", "line": 16,
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
  IFS=: read -r vname vrule vfile vline <<<"$vcase"
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

write_report survive-ambiguous.json '{
  "counts": {"files": 2},
  "findings": [{
    "rule": "attribution/audit/rule-stamp-expired", "file": "s7.md", "line": 17,
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

write_report ineligible-copy.json '{
  "counts": {"files": 2},
  "findings": [{
    "rule": "attribution/audit/rule-verbatim-copy", "file": "i.md",
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

write_report stamp-unreadable-tier.json '{
  "counts": {"files": 2},
  "findings": [{"rule": "attribution/audit/rule-stamp-expired", "file": "su.md",
                "line": 3, "tier": "nоt-found", "stamp_date": "2020-01-01",
                "window_days": 90, "days_over": 5}]
}'
SUT="$OUTDIR/stamp-unreadable-tier.md"
run --report "$REPORTS/stamp-unreadable-tier.json" --out "$SUT" >/dev/null 2>&1
SUT_BODY="$(cat "$SUT")"
assert_eq "a stamp rule declaring an unreadable tier emits no relay row" \
  "$(grep -c '^| [0-9]' "$SUT")" "0"
assert_contains "and it is counted as not relay-eligible" \
  "$SUT_BODY" "Not relay-eligible: 1"

write_report stamp-benign-verdict.json '{
  "counts": {"files": 2},
  "findings": [{"rule": "attribution/audit/rule-stamp-expired", "file": "sb.md",
                "line": 4, "verdict": {"reviewed_by": "alice", "agents": 2},
                "stamp_date": "2020-01-01", "window_days": 90, "days_over": 5}]
}'
SBV="$OUTDIR/stamp-benign-verdict.md"
run --report "$REPORTS/stamp-benign-verdict.json" --out "$SBV" >/dev/null 2>&1
assert_eq "a stamp rule with a benign verdict still relays" \
  "$(grep -c '^| [0-9]' "$SBV")" "1"
assert_not_contains "and is not counted as ineligible" \
  "$(cat "$SBV")" "Not relay-eligible"

write_report stamp-verdict-names-judgment.json '{
  "counts": {"files": 2},
  "findings": [{"rule": "attribution/audit/rule-stamp-expired", "file": "svj.md",
                "line": 1, "verdict": "not-found", "excerpt": "SVJCANARY",
                "stamp_date": "2020-01-01", "window_days": 90, "days_over": 5,
                "searched": ["https://svj.example/u"]}]
}'
SVJ="$OUTDIR/stamp-verdict-names-judgment.md"
run --report "$REPORTS/stamp-verdict-names-judgment.json" --out "$SVJ" >/dev/null 2>&1
SVJ_BODY="$(cat "$SVJ")"
assert_eq "a stamp rule whose verdict names a judgment verdict emits no relay row" \
  "$(grep -c '^| [0-9]' "$SVJ")" "0"
assert_contains "and it is counted as withheld, not as ineligible" \
  "$SVJ_BODY" "Withheld from the relay: 1 judgment"
assert_not_contains "and it takes the withheld path, not the unreadable-tier path" \
  "$SVJ_BODY" "Not relay-eligible"
assert_not_contains "and it leaks no payload" "$SVJ_BODY" "SVJCANARY"

write_report stamp-no-tier.json '{
  "counts": {"files": 2},
  "findings": [{"rule": "attribution/audit/rule-trigger-less-stamp", "file": "sn3.md",
                "line": 5, "stamp_date": "2026-05-05"}]
}'
run --report "$REPORTS/stamp-no-tier.json" --out "$OUTDIR/stamp-no-tier.md" >/dev/null 2>&1
assert_eq "a stamp rule declaring no tier relays" \
  "$(grep -c '^| [0-9]' "$OUTDIR/stamp-no-tier.md")" "1"

write_report gate-searched-cased.json '{
  "counts": {"files": 2},
  "findings": [
    {"rule": "attribution/audit/rule-verbatim-copy", "file": "gsc.md",
     "span": {"start_line": 4}, "tier": "fingerprint-confirmed",
     "fingerprint": {"longest_span_words": 30, "containment": 0.9},
     "source": {"url": "https://gsc.example/s"}},
    {"tier": "not-found", "Searched": ["docs", "web"], "note": "GSCCANARY"}
  ]
}'
GSC="$OUTDIR/gate-searched-cased.md"
run --report "$REPORTS/gate-searched-cased.json" --out "$GSC" >/dev/null 2>&1
assert_exit "a differently-cased searched key still names its surfaces" "$?" "0"
assert_eq "and the relay-eligible finding beside it survives" \
  "$(grep -c '^| [0-9]' "$GSC")" "1"
assert_contains "and the not-found finding is withheld and counted" \
  "$(cat "$GSC")" "1 judgment"
assert_not_contains "and its payload never reaches the file" "$(cat "$GSC")" "GSCCANARY"
assert_not_contains "it is not miscounted as a judgment finding" \
  "$INEL_BODY" "judgment findings"
assert_not_contains "an ineligible copy still leaks no payload" \
  "$INEL_BODY" "INELIGIBLECANARY"

write_report unparsed-unknown-rule.json '{
  "counts": {"files": 2},
  "findings": [
    {"rule": "attribution/audit/rule-future-thing", "file": "f.md", "line": 9,
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

RS_BASE='{
  "rule": "attribution/audit/rule-restated-upstream-fact",
  "file": "rs.md", "line": 7, "class": "restated-fact", "tier": "llm-suspected",
  "excerpt": "RSEXCERPT a|b",
  "rubric": {"samples": 3, "unanimous": true, "verdict": "STANDS",
             "grades": {"R1-external-owner": {"pass": true, "evidence": "RSGRADECANARY"}}},
  "review": {"agents": 1, "verdict": "SURVIVES", "evidence": "RSREVIEWCANARY"}
}'

rs_case() {
  jq -c "$2" <<<"$RS_BASE" | jq -s '{counts: {files: 2}, findings: .}' >"$REPORTS/$1.json"
  RS_OUT="$OUTDIR/$1.md"
  run --report "$REPORTS/$1.json" --out "$RS_OUT" >/dev/null 2>&1
  RS_EXIT=$?
  RS_BODY="$(cat "$RS_OUT" 2>/dev/null)"
  RS_ROWS="$(grep -c '^| [0-9]' "$RS_OUT" 2>/dev/null)"
}
rs_withheld() {
  rs_case "$2" "$3"
  assert_exit "$1: the run still exits 0" "$RS_EXIT" "0"
  assert_eq "$1: no row" "$RS_ROWS" "0"
  assert_contains "$1: counted as withheld" "$RS_BODY" "Withheld from the relay: 1 judgment"
  assert_not_contains "$1: not sent to Unparsed" "$RS_BODY" "## Unparsed"
  assert_not_contains "$1: no grade leaks" "$RS_BODY" "RSGRADECANARY"
  assert_not_contains "$1: no review leaks" "$RS_BODY" "RSREVIEWCANARY"
}

rs_case rs-relay '.'
assert_eq "a unanimous survived restated fact is one row" "$RS_ROWS" "1"
assert_contains "the row leads with the qualified rule id" "$RS_BODY" \
  "attribution/audit/rule-restated-upstream-fact: restates a fact"
assert_contains "the fired values are the panel size and the refutation outcome" "$RS_BODY" \
  "unanimous panel of 3 samples, refutation survived"
assert_contains "the tier is IMPORTANT and Confidence is omitted" "$RS_BODY" \
  "| 1 | IMPORTANT |  | rs.md:7 | attribution:audit |"
assert_contains "the excerpt pipe is escaped" "$RS_BODY" 'RSEXCERPT a\|b'
assert_contains "the relayed count is one" "$RS_BODY" "Relay-eligible findings: 1."
assert_not_contains "no withheld count on a clean relay" "$RS_BODY" "Withheld from the relay"
for leaked in llm-suspected source-fetched-similar not-found fingerprint-confirmed \
  STANDS SURVIVES RSGRADECANARY RSREVIEWCANARY; do
  assert_not_contains "the relayed file never carries $leaked" "$RS_BODY" "$leaked"
done

rs_case rs-relay-fetched '.tier = "source-fetched-similar" | .source = {"url": "https://rs.example/page"}'
assert_eq "a survived restated fact at the fetched-source tier relays" "$RS_ROWS" "1"
assert_contains "the source it was compared with is named" "$RS_BODY" "; source https://rs.example/page"
assert_not_contains "and the tier name still does not appear" "$RS_BODY" "source-fetched-similar"

rs_case rs-relay-notfound '.tier = "not-found" | .searched = ["RSSEARCHED-1", "RSSEARCHED-2"]'
assert_eq "a survived restated fact whose source search ended not-found relays" "$RS_ROWS" "1"
assert_not_contains "and the searched surfaces stay out of the file" "$RS_BODY" "RSSEARCHED"

rs_case rs-notfound-unlisted '.tier = "not-found"'
assert_exit "a not-found restated fact naming no surfaces is still refused" "$RS_EXIT" "3"

rs_case rs-relay-no-tier 'del(.tier)'
assert_eq "the declared tier plays no part: a record declaring none relays" "$RS_ROWS" "1"
rs_case rs-relay-folded '.rubric.verdict = "  stands " | .review.verdict = "Survives"'
assert_eq "a verdict spelled in another case still reads as the name it shows" "$RS_ROWS" "1"

rs_case rs-relay-odd-values \
  '.rubric.samples = {"x": "llm-suspected"} | .source = {"url": {"tier": "not-found"}} | .excerpt = {"tier": "source-fetched-similar"}'
assert_eq "a record whose cell values are the wrong type still relays" "$RS_ROWS" "1"
assert_contains "the panel size falls back to a question mark" "$RS_BODY" "unanimous panel of ? samples"
for leaked in llm-suspected source-fetched-similar not-found; do
  assert_not_contains "a wrong-typed value never carries $leaked into the file" "$RS_BODY" "$leaked"
done

rs_withheld "a split panel" rs-split '.rubric.unanimous = false'
rs_withheld "a panel verdict other than STANDS" rs-not-stands '.rubric.verdict = "MIXED"'
rs_withheld "a refuted finding" rs-vetoed '.review.verdict = "REFUTED"'
rs_withheld "a refutation outcome that is neither" rs-review-open '.review.verdict = "INCONCLUSIVE"'
rs_withheld "a judgment tier with no declared outcome" rs-no-outcome 'del(.rubric, .review)'
rs_withheld "a missing refutation block" rs-no-review 'del(.review)'
rs_withheld "a missing panel block" rs-no-rubric 'del(.rubric)'
rs_withheld "the rule id and class with no tier and no outcome" rs-bare 'del(.tier, .rubric, .review)'
rs_withheld "a unanimity that is a string" rs-string-unanimous '.rubric.unanimous = "true"'
rs_withheld "a unanimity that is a number" rs-number-unanimous '.rubric.unanimous = 1'
rs_withheld "a panel block that is not an object" rs-rubric-string '.rubric = "STANDS"'
rs_withheld "a refutation block that is a list" rs-review-list '.review = ["SURVIVES"]'
rs_withheld "a verdict that is a list" rs-verdict-list '.review.verdict = ["SURVIVES"]'
rs_withheld "a differently cased block key" rs-cased-key '.Rubric = .rubric | del(.rubric)'
rs_withheld "a class other than restated-fact" rs-wrong-class '.class = "paraphrase"'
rs_withheld "a missing class" rs-no-class 'del(.class)'
rs_withheld "a foreign plugin's rule id" rs-foreign-rule '.rule = "other/audit/rule-restated-upstream-fact"'
rs_withheld "a foreign plugin's rule id, another class and no tier" rs-foreign-rule-class \
  '.rule = "other/audit/rule-restated-upstream-fact" | .class = "paraphrase" | del(.tier)'

rs_withheld "the copy rule id under a fingerprint-confirmed tier" rs-copy-confirmed \
  '.rule = "attribution/audit/rule-verbatim-copy" | .tier = "fingerprint-confirmed"'
rs_withheld "the copy rule id and no tier" rs-copy-untiered \
  '.rule = "attribution/audit/rule-verbatim-copy" | del(.tier)'

write_report rs-copy-with-outcome.json "{
  \"counts\": {\"files\": 2},
  \"findings\": [{
    \"rule\": \"attribution/audit/rule-verbatim-copy\", \"file\": \"rc.md\",
    \"span\": {\"start_line\": 5}, \"class\": \"paraphrase\", \"tier\": \"llm-suspected\",
    \"rubric\": {\"samples\": 3, \"unanimous\": true, \"verdict\": \"STANDS\"},
    \"review\": {\"agents\": 1, \"verdict\": \"SURVIVES\"}
  }]
}"
run --report "$REPORTS/rs-copy-with-outcome.json" --out "$OUTDIR/rs-copy-with-outcome.md" >/dev/null 2>&1
assert_eq "a copy finding carrying a survived outcome is still withheld" \
  "$(grep -c '^| [0-9]' "$OUTDIR/rs-copy-with-outcome.md")" "0"
assert_contains "and is counted as withheld" "$(cat "$OUTDIR/rs-copy-with-outcome.md")" \
  "Withheld from the relay: 1 judgment"

jq --argjson rs "$RS_BASE" '.findings += [$rs]' "$REPORTS/full.json" >"$REPORTS/rs-mixed.json"
run --report "$REPORTS/rs-mixed.json" --out "$OUTDIR/rs-mixed.md" >/dev/null 2>&1
RS_MIXED="$(cat "$OUTDIR/rs-mixed.md")"
assert_eq "the four relay rules give four rows" "$(grep -c '^| [0-9]' "$OUTDIR/rs-mixed.md")" "4"
assert_contains "the withheld count is unchanged by the new rule" "$RS_MIXED" \
  "Withheld from the relay: 2 judgment"
RS_ROW="$(grep '^| [0-9].*rule-restated-upstream-fact' "$OUTDIR/rs-mixed.md")"
RS_COPY_ROW="$(grep '^| [0-9].*rule-verbatim-copy' "$OUTDIR/rs-mixed.md")"
assert_match "the restated row ranks last" "$RS_ROW" '^\| 4 \|'
assert_contains "the copy row keeps Confidence high" "$RS_COPY_ROW" "| high |"
assert_contains "the copy row still names the fix flow" "$RS_COPY_ROW" '/attribution:audit fix'
assert_contains "the restated remedy is a pointer" "$RS_ROW" "a pointer at the point of use"
assert_contains "or a stamped record" "$RS_ROW" "stamped record (the decision in its own words, a pointer, an as-of date, an observable recheck trigger)"
assert_contains "and it says the row is report-only" "$RS_ROW" "Not auto-applicable: report-only"
assert_not_contains "the restated remedy never names the fix flow" "$RS_ROW" '/attribution:audit fix'
assert_not_contains "nor the sweep flow" "$RS_ROW" '/attribution:audit sweep'
assert_not_contains "nor a remediating invocation of any kind" "$RS_ROW" "remediated by"
assert_not_contains "and the stamp rows do not carry the restated remedy" \
  "$(grep '^| [0-9].*rule-stamp-expired' "$OUTDIR/rs-mixed.md")" "pointer at the point of use"

DUP="$OUTDIR/dup.md"
run --report "$REPORTS/full.json" --out "$DUP" >/dev/null 2>&1
run --report "$REPORTS/full.json" --out "$DUP" >/dev/null 2>&1
assert_file "a second write takes the -2 suffix" "$OUTDIR/dup-2.md"
run --report "$REPORTS/full.json" --out "$DUP" >/dev/null 2>&1
assert_file "a third write takes the -3 suffix" "$OUTDIR/dup-3.md"

BR="$OUTDIR/branch.md"
run --report "$REPORTS/full.json" --out "$BR" --branch 'no' >/dev/null 2>&1
assert_contains "a YAML-implicit-typed branch name is quoted" "$(cat "$BR")" 'branch: "no"'

BR2="$OUTDIR/branch2.md"
run --report "$REPORTS/full.json" --out "$BR2" --branch '#hash' >/dev/null 2>&1
assert_contains "a branch starting with a YAML indicator is quoted" "$(cat "$BR2")" 'branch: "#hash"'

write_report abs.json "{
  \"findings\": [
    {
      \"rule\": \"attribution/audit/rule-stamp-expired\",
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

attribution_root_spelling_reaches_an_anchor() {
  local top alt
  top="$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "$top" ]] || return 1
  [[ "$top" == "$REPO" ]] && return 0
  alt="$(cd "$top" 2>/dev/null && pwd)" || return 1
  [[ "$alt" == "$REPO" ]]
}

# silent-skip-ok: routed to skip(), a visible SKIP line counted apart from PASS
if attribution_root_spelling_reaches_an_anchor; then
  assert_contains "an absolute path is relativized" "$(cat "$ABS")" "| docs/page.md:7 |"
  assert_not_contains "the repo root does not survive into Location" "$(cat "$ABS")" "$REPO/docs"
else
  skip "an absolute path is relativized" \
    'the fixture root has a third spelling git never reports, so no anchor names it'
  skip "the repo root does not survive into Location" \
    'the fixture root has a third spelling git never reports, so no anchor names it'
fi

assert_fails "an uncreatable destination directory exits non-zero" \
  bash "$EMIT" --report "$REPORTS/full.json" --out /proc/nope/deeper/x.md

OUT="$(run --report "$REPORTS/full.json" --out /proc/nope/deeper/x.md 2>&1)"
assert_not_contains "a failed write never claims it wrote" "$OUT" "wrote"

UNWRITABLE="$TEST_TMPDIR/unwritable"
mkdir -p "$UNWRITABLE"
chmod a-w "$UNWRITABLE"
# silent-skip-ok: routed to skip(), a visible SKIP line counted apart from PASS
if [[ ! -w "$UNWRITABLE" ]]; then
  assert_fails "an unwritable destination exits non-zero" \
    bash "$EMIT" --report "$REPORTS/full.json" --out "$UNWRITABLE/x.md"
else
  skip "an unwritable destination exits non-zero" \
    'this user ignores mode bits, so the destination stays writable'
fi
chmod u+w "$UNWRITABLE"

D1="$OUTDIR/det1.md"
D2="$OUTDIR/det2.md"
run --report "$REPORTS/full.json" --out "$D1" >/dev/null 2>&1
run --report "$REPORTS/full.json" --out "$D2" >/dev/null 2>&1
assert_eq "repeat runs differ only in their date line" \
  "$(diff <(grep -v '^date:' "$D1") <(grep -v '^date:' "$D2") >/dev/null && echo same)" "same"

printf '\nPassed: %s  Failed: %s  Host skips: %s\n' "$((CASE_NUM - FAILED))" "$FAILED" "$SKIPPED"
[[ "$FAILED" -eq 0 ]]
