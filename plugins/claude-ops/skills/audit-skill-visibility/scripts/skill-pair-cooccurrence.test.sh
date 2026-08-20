#!/usr/bin/env bash
# Regression tests for skill-pair-cooccurrence.sh.
#
# The defect this script exists to prevent is a proxy reported as a measurement,
# so the cases that matter are the ones where a number WOULD be available and is
# withheld anyway, and the ones where the caveat must survive into the output.
#
# Coverage:
#   - a store over both floors yields a rate, with the ordering split
#   - an EMPTY denominator withholds rather than reporting 0% (the specific
#     inversion: "caller never ran" is not "callee never followed caller")
#   - a span under the exposure floor withholds even with a full denominator
#   - a denominator under the group floor withholds even with a long span
#   - the proxy caveat appears in BOTH renderers (prose and --json), because a
#     machine consumer stripping it is the same defect as a human not seeing it
#   - grouping is (project_id, branch): the same branch name under two projects
#     does not merge, and one project across two branches does not merge
#   - a malformed row is skipped, not fatal
#   - a record with no project_id/branch still groups instead of vanishing
#   - argument validation exits 3; an absent store exits 2 and says so
#
# Every case runs in THIS shell, never a `( … )` subshell: an assertion inside a
# subshell increments a copy of the failure counter, and the run would report
# green with a failing case in it.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/skill-pair-cooccurrence.sh"

FAILED=0
CASE_NUM=0
TMP=""

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'ok %d - %s\n' "$CASE_NUM" "$1"
}

fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'not ok %d - %s\n' "$CASE_NUM" "$1"
  [[ $# -ge 2 ]] && printf '    %s\n' "$2"
}

assert_contains() {
  if [[ "$2" == *"$3"* ]]; then
    pass "$1"
  else
    fail "$1" "expected to contain: $3"
    printf '    actual: %s\n' "$2"
  fi
}

assert_not_contains() {
  if [[ "$2" != *"$3"* ]]; then
    pass "$1"
  else
    fail "$1" "expected NOT to contain: $3"
    printf '    actual: %s\n' "$2"
  fi
}

assert_status() {
  if [[ "$2" == "$3" ]]; then
    pass "$1"
  else
    fail "$1" "expected exit $3, got $2"
  fi
}

cleanup() { [[ -n "$TMP" ]] && rm -rf "$TMP"; }
trap cleanup EXIT

TMP="$(mktemp -d)"

# Emit one SkillUse row. Kept as a helper so a fixture reads as data, not jq.
row() {
  printf '{"ts":"%s","event":"SkillUse","skill":"%s","branch":"%s","project":"p","project_id":"%s","hook":"skill-usage-audit","source":"tool"}\n' \
    "$1" "$2" "$3" "$4"
}

# --- fixture: six groups, five carrying the caller, spanning > 30 days -------
# g1..g4 carry both skills; g5 carries the caller alone; g6 carries neither.
# Within the carrying groups the ordering is deliberately mixed so the split is
# asserted rather than assumed.
FULL="$TMP/full.jsonl"
{
  row 2026-01-01T00:00:00Z implementation:implement b1 proj
  row 2026-01-01T00:05:00Z tdd:principles b1 proj # caller-first
  row 2026-01-05T00:00:00Z implementation:implement b2 proj
  row 2026-01-05T00:05:00Z tdd:principles b2 proj # caller-first
  row 2026-01-10T00:05:00Z implementation:implement b3 proj
  row 2026-01-10T00:00:00Z tdd:principles b3 proj # callee-first
  row 2026-01-15T00:00:00Z implementation:implement b4 proj
  row 2026-01-15T00:00:00Z tdd:principles b4 proj # same-timestamp
  row 2026-01-20T00:00:00Z implementation:implement b5 proj
  row 2026-02-20T00:00:00Z session-flow:handoff b6 proj
} >"$FULL"

out="$(bash "$SUT" --store "$FULL")"
st=$?
assert_status "a store over both floors exits 0" "$st" 0
assert_contains "reports a rate over the caller-bearing denominator" "$out" "VERDICT: 80% — 4 of 5"
assert_contains "splits the ordering: callee-first" "$out" "1 with tdd:principles first"
assert_contains "splits the ordering: caller-first" "$out" "2 with implementation:implement first"
assert_contains "splits the ordering: same-timestamp" "$out" "1 at the same timestamp"
assert_contains "the denominator excludes groups without the caller" "$out" "Denominator:       5 group(s)"
assert_contains "the prose renderer carries the proxy caveat" "$out" "PROXY LIMIT"
assert_contains "the caveat names what it is not" "$out" "co-occurrence, not attribution"

# The caveat must survive the machine-readable renderer too.
jout="$(bash "$SUT" --store "$FULL" --json)"
assert_contains "--json emits the rate" "$jout" '"rate":80'
assert_contains "--json carries proxy_limit" "$jout" '"proxy_limit"'
assert_contains "--json caveat denies attribution" "$jout" "NOT caller attribution"

# --- the inversion this script exists to refuse ------------------------------
# The caller never ran. A naive reading reports "0% of implement sessions also
# used tdd:principles", which is a claim about a population that was never
# observed. It must withhold instead, and must NOT print a percentage.
EMPTY_DENOM="$TMP/empty-denominator.jsonl"
{
  row 2026-01-01T00:00:00Z session-flow:handoff b1 proj
  row 2026-01-10T00:00:00Z tdd:principles b1 proj
  row 2026-02-20T00:00:00Z session-flow:handoff b2 proj
} >"$EMPTY_DENOM"

out="$(bash "$SUT" --store "$EMPTY_DENOM")"
assert_status "an empty denominator still exits 0 (a withheld reading is a reading)" "$?" 0
assert_contains "an empty denominator withholds" "$out" "WITHHELD"
assert_contains "and says why, in the terms that matter" "$out" "no denominator to take a fraction of"
assert_not_contains "an empty denominator never renders a percentage" "$out" "VERDICT:"

# --- span under the exposure floor -------------------------------------------
# Denominator is comfortably over its floor; only the span is short. The rate is
# arithmetically available and must still be withheld.
SHORT="$TMP/short-span.jsonl"
{
  for i in 1 2 3 4 5 6; do
    row "2026-01-0${i}T00:00:00Z" implementation:implement "b$i" proj
    row "2026-01-0${i}T00:05:00Z" tdd:principles "b$i" proj
  done
} >"$SHORT"

out="$(bash "$SUT" --store "$SHORT")"
assert_contains "a span under the exposure floor withholds" "$out" "below the 30d exposure floor"
assert_not_contains "…and renders no percentage despite a full denominator" "$out" "VERDICT:"
# Lowering the floor is what makes the same store readable — proving the floor,
# not the data, is what withheld it.
out="$(bash "$SUT" --store "$SHORT" --floor-days 1)"
assert_contains "the same store reads once the floor is lowered" "$out" "VERDICT: 100% — 6 of 6"

# --- denominator under the group floor ---------------------------------------
THIN="$TMP/thin-denominator.jsonl"
{
  row 2026-01-01T00:00:00Z implementation:implement b1 proj
  row 2026-01-01T00:05:00Z tdd:principles b1 proj
  row 2026-03-01T00:00:00Z implementation:implement b2 proj
} >"$THIN"

out="$(bash "$SUT" --store "$THIN")"
assert_contains "a denominator under the group floor withholds" "$out" "below the floor of 5"
assert_not_contains "…and renders no percentage despite a long span" "$out" "VERDICT:"

# --- grouping is (project_id, branch), not either alone ----------------------
# Same branch name, two projects: these must NOT merge into one group. If they
# merged, the caller in one project would be credited with the callee from the
# other — cross-project contamination reported as a co-occurrence.
CROSS="$TMP/cross-project.jsonl"
{
  row 2026-01-01T00:00:00Z implementation:implement main projA
  row 2026-01-01T00:05:00Z tdd:principles main projB
  row 2026-03-01T00:00:00Z session-flow:handoff main projA
} >"$CROSS"

out="$(bash "$SUT" --store "$CROSS" --floor-groups 1)"
assert_contains "same branch under two projects does not merge" "$out" "VERDICT: 0% — 0 of 1"
assert_not_contains "…so no cross-project co-occurrence is credited" "$out" "VERDICT: 100%"

# One project, two branches: must not merge either.
SPLIT="$TMP/split-branch.jsonl"
{
  row 2026-01-01T00:00:00Z implementation:implement b1 proj
  row 2026-01-01T00:05:00Z tdd:principles b2 proj
  row 2026-03-01T00:00:00Z session-flow:handoff b1 proj
} >"$SPLIT"

out="$(bash "$SUT" --store "$SPLIT" --floor-groups 1)"
assert_contains "one project across two branches does not merge" "$out" "VERDICT: 0% — 0 of 1"

# --- tolerant reading --------------------------------------------------------
# A malformed row must cost that row, not the report.
DIRTY="$TMP/dirty.jsonl"
cp "$FULL" "$DIRTY"
{
  printf 'this is not json\n'
  printf '{"ts":"2026-01-02T00:00:00Z"}\n'                             # no skill
  printf '{"skill":"tdd:principles","event":"SkillUse"}\n'             # no ts
  printf '{"ts":"2026-01-02T00:00:00Z","event":"Other","skill":"x"}\n' # not SkillUse
} >>"$DIRTY"

out="$(bash "$SUT" --store "$DIRTY")"
assert_status "a malformed row is not fatal" "$?" 0
assert_contains "…and the surviving rows still read identically" "$out" "VERDICT: 80% — 4 of 5"

# A record predating project_id/branch must still group rather than vanish.
LEGACY="$TMP/legacy.jsonl"
{
  printf '{"ts":"2026-01-01T00:00:00Z","event":"SkillUse","skill":"implementation:implement"}\n'
  printf '{"ts":"2026-03-01T00:00:00Z","event":"SkillUse","skill":"tdd:principles"}\n'
} >"$LEGACY"

out="$(bash "$SUT" --store "$LEGACY" --floor-groups 1)"
assert_contains "field-less records group into one bucket rather than vanishing" "$out" "VERDICT: 100% — 1 of 1"

# --- argument and store handling ---------------------------------------------
bash "$SUT" --store "$FULL" --pair "nocomma" >/dev/null 2>&1
assert_status "a pair without a comma exits 3" "$?" 3
bash "$SUT" --store "$FULL" --pair "a,b,c" >/dev/null 2>&1
assert_status "a three-name pair exits 3" "$?" 3
bash "$SUT" --store "$FULL" --pair ",b" >/dev/null 2>&1
assert_status "an empty caller exits 3" "$?" 3
bash "$SUT" --store "$FULL" --floor-days "x" >/dev/null 2>&1
assert_status "a non-numeric floor exits 3" "$?" 3
bash "$SUT" --store "$FULL" --bogus >/dev/null 2>&1
assert_status "an unknown flag exits 3" "$?" 3

err="$(bash "$SUT" --store "$TMP/does-not-exist.jsonl" 2>&1)"
assert_status "an absent store exits 2" "$?" 2
assert_contains "…and says nothing was observed rather than implying a zero" "$err" "Nothing has been observed"

printf '\n%d case(s), %d failure(s)\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]]
