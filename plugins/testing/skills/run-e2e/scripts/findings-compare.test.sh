#!/usr/bin/env bash
# Tests for findings-compare.sh: each label, the not-checked rule, the no-baseline
# case, the order, the input checks, and the fields findings.schema.json requires;
# then finding-id.sh, the id a map pass gives each finding.
# Every expected value is written by hand from the rules the script states.
# test-scope: plugins/testing/skills/run-e2e/schemas/findings.schema.json
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMP="$HERE/findings-compare.sh"
SCHEMA="$HERE/../schemas/findings.schema.json"
FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
same() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected '$3', got '$2'"; fi; }

command -v jq >/dev/null 2>&1 || {
  echo "FAIL: jq is required to run these tests" >&2
  exit 1
}

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

entry() {
  jq -cn --arg f "$1" --arg p "$2" --arg e "$3" --arg o "$4" --arg r "${5:-}" '{
    feature: $f, part: (if $p == "null" then null else $p end), entry_point: $e, outcome: $o,
    reason: (if $r == "" then null else $r end), wall_time_seconds: 12.5, tokens: 3400,
    unmeasured_reason: null}'
}
finding() {
  local id="$1" f="$2" p="$3" s="$4"
  shift 4
  jq -cn --arg id "$id" --arg f "$f" --arg p "$p" --arg s "$s" '{
    id: $id, feature: $f, part: (if $p == "null" then null else $p end), kind: "error",
    where: "2", entry_points: $ARGS.positional, severity: $s, label: "unstated",
    evidence: ["\($f)/report.md"]}' --args "$@"
}
pass_file() {
  jq -n --arg b "$2" --slurpfile e "$3" --slurpfile f "$4" \
    '{pass: {build: $b, entries: $e}, findings: $f}' >"$1"
}
labels() { jq -r '[.findings[] | "\(.id)=\(.compare)"] | join(" ")' <<<"$1"; }

{
  entry billing export /billing:export passed
  entry cart null /cart failed
  entry search query /search passed
  entry auth login /auth:login passed
  entry auth login /auth:sso passed
  entry docs null /docs passed
} >"$TMP/base-entries"
{
  finding aaaa0001 cart null high /cart
  finding aaaa0002 billing export medium /billing:export
  finding aaaa0003 search query low /search
  finding aaaa0004 auth login critical /auth:login /auth:sso
  finding aaaa0005 docs null high /docs
  finding aaaa0006 search query medium /search
} >"$TMP/base-findings"
pass_file "$TMP/base.json" build-1 "$TMP/base-entries" "$TMP/base-findings"

{
  entry billing export /billing:export passed
  entry cart null /cart failed
  entry search query /search "not checked" cap
  entry auth login /auth:login passed
  entry auth login /auth:sso "not checked" "blocked: no Ready"
  entry search other /search passed
} >"$TMP/new-entries"
{
  finding aaaa0001 cart null critical /cart
  finding aaaa0007 cart null low /cart
  finding aaaa0008 cart null high /cart
} >"$TMP/new-findings"
pass_file "$TMP/new.json" build-2 "$TMP/new-entries" "$TMP/new-findings"

out="$(bash "$CMP" "$TMP/new.json")"
same "no baseline: exit 0" "$?" 0
same "no baseline: every finding is NEW, by severity" "$(labels "$out")" \
  "aaaa0001=NEW aaaa0008=NEW aaaa0007=NEW"
same "no baseline: the baseline build is null" "$(jq -c .builds <<<"$out")" \
  '{"baseline":null,"newer":"build-2"}'
same "no baseline: counts" "$(jq -c .counts <<<"$out")" \
  '{"NEW":3,"PRE-EXISTING":0,"GONE":0,"not checked":0}'

out="$(bash "$CMP" --baseline "$TMP/base.json" "$TMP/new.json")"
same "baseline: exit 0" "$?" 0
same "baseline: each id's label, in report order" "$(labels "$out")" \
  "aaaa0008=NEW aaaa0007=NEW aaaa0001=PRE-EXISTING aaaa0002=GONE aaaa0004=not checked aaaa0005=not checked aaaa0006=not checked aaaa0003=not checked"
same "baseline: both builds" "$(jq -c .builds <<<"$out")" \
  '{"baseline":"build-1","newer":"build-2"}'
same "baseline: counts" "$(jq -c .counts <<<"$out")" \
  '{"NEW":2,"PRE-EXISTING":1,"GONE":1,"not checked":4}'
same "a PRE-EXISTING finding carries the newer pass's record" \
  "$(jq -r '.findings[] | select(.id == "aaaa0001") | .severity' <<<"$out")" critical
same "a GONE finding carries the baseline's record" \
  "$(jq -r '.findings[] | select(.id == "aaaa0002") | "\(.feature)/\(.part) \(.severity)"' <<<"$out")" \
  "billing/export medium"
same "a GONE finding has no not_driven list" \
  "$(jq -r '.findings[] | select(.id == "aaaa0002") | has("not_driven")' <<<"$out")" false

not_driven() { jq -c --arg id "$1" '.findings[] | select(.id == $id) | .not_driven' <<<"$out"; }
same "an entry the cap left out is not checked, with the entry's reason" "$(not_driven aaaa0003)" \
  '[{"entry_point":"/search","reason":"cap"}]'
same "one undriven entry point of two keeps the finding not checked" "$(not_driven aaaa0004)" \
  '[{"entry_point":"/auth:sso","reason":"blocked: no Ready"}]'
same "an entry missing from the newer pass is not checked" "$(not_driven aaaa0005)" \
  '[{"entry_point":"/docs","reason":"not in the newer pass"}]'
same "the same entry point under another part does not count as driven" "$(not_driven aaaa0006)" \
  '[{"entry_point":"/search","reason":"cap"}]'

gone_undriven="$(jq -r '[.findings[] | select(.compare == "GONE") | .entry_points[]] | join(" ")' <<<"$out")"
same "only a finding whose every entry point was driven is GONE" "$gone_undriven" "/billing:export"

{ finding aaaa0009 cart null medium /cart; } >"$TMP/old-cart"
pass_file "$TMP/old-cart.json" build-0 "$TMP/base-entries" "$TMP/old-cart"
out="$(bash "$CMP" --baseline "$TMP/old-cart.json" "$TMP/new.json")"
same "a missing id on an entry that failed again is GONE" \
  "$(jq -r '.findings[] | select(.id == "aaaa0009") | .compare' <<<"$out")" GONE

: >"$TMP/none"
pass_file "$TMP/empty.json" build-3 "$TMP/none" "$TMP/none"
out="$(bash "$CMP" --baseline "$TMP/empty.json" "$TMP/empty.json")"
same "two passes with no findings: an empty list" "$(jq -c .findings <<<"$out")" '[]'

bash "$CMP" 2>/dev/null
same "no file is a usage error" "$?" 2
bash "$CMP" --baseline 2>/dev/null
same "--baseline with no file is a usage error" "$?" 2
bash "$CMP" --verbose "$TMP/new.json" 2>/dev/null
same "an unknown option is a usage error" "$?" 2
bash "$CMP" "$TMP/new.json" "$TMP/base.json" 2>/dev/null
same "two positional files is a usage error" "$?" 2
bash "$CMP" "$TMP/missing.json" 2>/dev/null
same "a missing file exits 2" "$?" 2
printf '{not json' >"$TMP/bad.json"
bash "$CMP" --baseline "$TMP/bad.json" "$TMP/new.json" 2>/dev/null
same "a baseline that is not JSON exits 2" "$?" 2
jq 'del(.pass.build)' "$TMP/new.json" >"$TMP/nobuild.json"
err="$(bash "$CMP" "$TMP/nobuild.json" 2>&1 >/dev/null)"
same "a pass with no build exits 2" "$?" 2
same "the error names the missing field" "$err" \
  "findings-compare.sh: $TMP/nobuild.json: pass.build is not a non-empty string"
jq '.findings += [.findings[0]]' "$TMP/new.json" >"$TMP/dup.json"
bash "$CMP" "$TMP/dup.json" 2>/dev/null
same "two findings with one id exit 2" "$?" 2
jq '.pass.entries[0].outcome = "skipped"' "$TMP/new.json" >"$TMP/outcome.json"
bash "$CMP" "$TMP/outcome.json" 2>/dev/null
same "an unknown entry outcome exits 2" "$?" 2
jq '.findings[0].entry_points = "/cart"' "$TMP/new.json" >"$TMP/eps.json"
bash "$CMP" "$TMP/eps.json" 2>/dev/null
same "entry_points that is not a list exits 2" "$?" 2
jq '.findings[0].entry_points = []' "$TMP/base.json" >"$TMP/noeps.json"
bash "$CMP" --baseline "$TMP/noeps.json" "$TMP/new.json" 2>/dev/null
same "a baseline finding with no entry points exits 2, never GONE" "$?" 2
: >"$TMP/blank.json"
bash "$CMP" --baseline "$TMP/blank.json" "$TMP/new.json" 2>/dev/null
same "an empty baseline file exits 2, not a run with no baseline" "$?" 2
bash "$CMP" "$TMP/blank.json" 2>/dev/null
same "an empty newer file exits 2" "$?" 2
cat "$TMP/new.json" "$TMP/new.json" >"$TMP/twice.json"
bash "$CMP" "$TMP/twice.json" 2>/dev/null
same "a file with two JSON values exits 2" "$?" 2

req() { jq -r --arg d "$1" '.["$defs"][$d].required | sort | join(" ")' "$SCHEMA"; }
same "a finding requires its fields" "$(req Finding)" \
  "entry_points evidence feature id kind label part severity where"
same "an entry requires its outcome and measures" "$(req Entry)" \
  "entry_point feature outcome part reason tokens unmeasured_reason wall_time_seconds"
same "a pass requires its build and entries" \
  "$(jq -r '.properties.pass.required | sort | join(" ")' "$SCHEMA")" "build entries"
same "label is stated or unstated" "$(jq -c '.["$defs"].Finding.properties.label.enum' "$SCHEMA")" \
  '["stated","unstated"]'
same "the entry outcomes are the ones the script reads" \
  "$(jq -c '.["$defs"].Entry.properties.outcome.enum' "$SCHEMA")" '["passed","failed","not checked"]'

ID="$HERE/finding-id.sh"
fid() {
  rc=0
  out="$(bash "$ID" "$@" 2>/dev/null)" || rc=$?
}
fid billing export error 2
base_id="$out"
same "finding-id: a valid finding exits 0" "$rc" 0
same "finding-id: the id fits the schema's id pattern" \
  "$(jq -r --arg id "$base_id" '.["$defs"].Finding.properties.id.pattern as $p | $id | test($p)' "$SCHEMA")" true
same "finding-id: the id is 16 hex digits" "${#base_id}" 16
fid billing export error 2
same "finding-id: the same fields give the same id" "$out" "$base_id"
for args in "billing import error 2" "billing _ error 2" "billing export crash 2" "billing export error proof"; do
  read -r f p k w <<<"$args"
  [[ "$p" == _ ]] && p=""
  fid "$f" "$p" "$k" "$w"
  if [[ "$rc" == 0 && "$out" != "$base_id" ]]; then pass "finding-id: '$args' gives another id"; else
    fail "finding-id: '$args' gives another id" "rc $rc, id '$out'"
  fi
done
same "finding-id: the kinds are the schema's" \
  "$(jq -r '.["$defs"].Finding.properties.kind.enum | join(" ")' "$SCHEMA")" \
  "result-not-met error crash refusal no-output garbled-output"
fid billing export timeout 2
same "finding-id: a kind outside the schema's list exits 2" "$rc" 2
for bad in 0 02 step ""; do
  fid billing export error "$bad"
  same "finding-id: where '$bad' exits 2" "$rc" 2
done
fid "billing"$'\n'"x" export error 2
same "finding-id: a feature with a newline exits 2" "$rc" 2
fid billing "export"$'\n'"x" error 2
same "finding-id: a part with a newline exits 2" "$rc" 2
fid billing export error
same "finding-id: three arguments exit 2" "$rc" 2

echo
if ((FAILED == 0)); then echo "all passed"; else echo "$FAILED failed"; fi
((FAILED == 0))
