#!/usr/bin/env bash
# Black-box contract test for measure-invocation.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/measure-invocation.sh"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

if ! command -v jq >/dev/null 2>&1; then
  printf 'FAIL - jq is required\n' >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export MEASURE_INVOCATION_REPO_ROOT="$TMP"

run() { bash "$SUT" "$@"; }

make_skill() {
  local dir="$1" desc="$2"
  mkdir -p "$dir"
  printf '%s\n' "---
description: \"$desc\"
disable-model-invocation: false
---

# Fixture
" >"$dir/SKILL.md"
}

# A probe set of 20 queries, both splits, both polarities.
write_probes() {
  local skill_dir="$1"
  local competitor_dir="$2"
  mkdir -p "$TMP/probes"
  cat >"$TMP/probes/target.json" <<EOF
{
  "skill": "fixture:target",
  "plugin": "fixture",
  "skill_dir": "$skill_dir",
  "competitors": ["fixture:rival"],
  "competitor_dirs": {"fixture:rival": "$competitor_dir"},
  "queries": [
    {"id": "pos-train-01", "split": "train", "expect_trigger": true, "request": "lint my skill frontmatter"},
    {"id": "pos-train-02", "split": "train", "expect_trigger": true, "request": "check this skill"},
    {"id": "pos-train-03", "split": "train", "expect_trigger": true, "request": "is this SKILL.md valid"},
    {"id": "pos-train-04", "split": "train", "expect_trigger": true, "request": "validate skill quality"},
    {"id": "pos-train-05", "split": "train", "expect_trigger": true, "request": "check skill before publishing"},
    {"id": "pos-train-06", "split": "train", "expect_trigger": true, "request": "lint the skill contract"},
    {"id": "pos-val-01", "split": "validation", "expect_trigger": true, "request": "validate skill frontmatter"},
    {"id": "pos-val-02", "split": "validation", "expect_trigger": true, "request": "skill quality gate"},
    {"id": "pos-val-03", "split": "validation", "expect_trigger": true, "request": "check this skill please"},
    {"id": "pos-val-04", "split": "validation", "expect_trigger": true, "request": "is this SKILL.md valid today"},
    {"id": "neg-train-01", "split": "train", "expect_trigger": false, "request": "write a brand-new skill for CSV parsing"},
    {"id": "neg-train-02", "split": "train", "expect_trigger": false, "request": "how to write SKILL.md from the authoring playbook"},
    {"id": "neg-train-03", "split": "train", "expect_trigger": false, "request": "create a skill with progressive disclosure"},
    {"id": "neg-train-04", "split": "train", "expect_trigger": false, "request": "authoring best practices for a new skill"},
    {"id": "neg-train-05", "split": "train", "expect_trigger": false, "request": "structure a SKILL.md hub and spokes"},
    {"id": "neg-train-06", "split": "train", "expect_trigger": false, "request": "skill-authoring playbook for descriptions"},
    {"id": "neg-val-01", "split": "validation", "expect_trigger": false, "request": "write me a skill from scratch"},
    {"id": "neg-val-02", "split": "validation", "expect_trigger": false, "request": "create a skill using the authoring playbook"},
    {"id": "neg-val-03", "split": "validation", "expect_trigger": false, "request": "progressive disclosure in a new SKILL.md"},
    {"id": "neg-val-04", "split": "validation", "expect_trigger": false, "request": "authoring a skill body"}
  ]
}
EOF
}

make_skill "$TMP/skills/target" \
  "Skill-authoring QA. Use when: 'check this skill', 'lint my skill', 'is this SKILL.md valid', 'validate skill quality', 'check skill before publishing'."
make_skill "$TMP/skills/rival" \
  "Anthropic skill-authoring playbook. Use when: 'create a skill', 'how to write SKILL.md', 'skill best practices', 'authoring playbook', 'progressive disclosure'."
write_probes "skills/target" "skills/rival"

out="$(run --help 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'listing-overlap is a FLOOR' <<<"$out" && ! grep -q 'set -uo pipefail' <<<"$out"; then
  pass "--help prints the header and stops before code"
else
  fail "--help should print the header (rc=$rc): $out"
fi

out="$(run 2>&1)"
rc=$?
if [[ $rc -eq 2 ]]; then
  pass "no args is usage error (exit 2)"
else
  fail "no args should exit 2 (rc=$rc): $out"
fi

out="$(run validate "$TMP/probes" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'validate: PASS' <<<"$out"; then
  pass "validate accepts a 20-query both-split set"
else
  fail "validate should pass the fixture (rc=$rc): $out"
fi

mkdir -p "$TMP/thin/probes"
jq '.queries = .queries[0:3]' "$TMP/probes/target.json" >"$TMP/thin/probes/target.json"
out="$(run validate "$TMP/thin/probes" 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'FAIL:' <<<"$out"; then
  pass "validate FAILs a set under 8 queries"
else
  fail "thin set should FAIL (rc=$rc): $out"
fi

mkdir -p "$TMP/nosplit/probes"
jq '.queries[].split = "holdout"' "$TMP/probes/target.json" >"$TMP/nosplit/probes/target.json"
out="$(run validate "$TMP/nosplit/probes" 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'split must be train or validation' <<<"$out"; then
  pass "validate FAILs an unknown split"
else
  fail "unknown split should FAIL (rc=$rc): $out"
fi

mkdir -p "$TMP/strexpect/probes"
jq '.queries[0].expect_trigger = "true"' "$TMP/probes/target.json" >"$TMP/strexpect/probes/target.json"
out="$(run validate "$TMP/strexpect/probes" 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'expect_trigger must be a boolean' <<<"$out"; then
  pass "validate FAILs a string expect_trigger"
else
  fail "string expect_trigger should FAIL (rc=$rc): $out"
fi

score_json="$(run score "$TMP/probes" 2>"$TMP/score.err")"
rc=$?
printf '%s\n' "$score_json" >"$TMP/score.json"
if [[ $rc -eq 0 ]] && jq -e '.method == "listing-overlap" and (.skills | length == 1)' "$TMP/score.json" >/dev/null; then
  pass "score emits a listing-overlap report"
else
  fail "score should emit a report (rc=$rc): $(cat "$TMP/score.err") $score_json"
fi

train_tr="$(jq -r '.skills[0].splits.train.trigger_rate' "$TMP/score.json")"
val_tr="$(jq -r '.skills[0].splits.validation.trigger_rate' "$TMP/score.json")"
train_ft="$(jq -r '.skills[0].splits.train.false_trigger_rate' "$TMP/score.json")"
val_ft="$(jq -r '.skills[0].splits.validation.false_trigger_rate' "$TMP/score.json")"
# Fixture descriptions are built so positives quote the target triggers and
# negatives quote the rival's. Expect a strong floor, not a perfect 1.0 on
# every token-overlap quirk.
awk -v t="$train_tr" -v v="$val_tr" 'BEGIN { exit !((t+0) >= 0.5 && (v+0) >= 0.5) }'
tr_ok=$?
awk -v t="$train_ft" -v v="$val_ft" 'BEGIN { exit !((t+0) <= 0.5 && (v+0) <= 0.5) }'
ft_ok=$?
if [[ $tr_ok -eq 0 && $ft_ok -eq 0 ]]; then
  pass "score reports train and validation trigger_rate >= 0.5 and false_trigger_rate <= 0.5 (train=$train_tr/$train_ft val=$val_tr/$val_ft)"
else
  fail "rates off the fixture floor (train=$train_tr/$train_ft val=$val_tr/$val_ft) stderr=$(cat "$TMP/score.err")"
fi

n_train="$(jq '.skills[0].splits.train.n' "$TMP/score.json")"
n_val="$(jq '.skills[0].splits.validation.n' "$TMP/score.json")"
if [[ "$n_train" == "12" && "$n_val" == "8" ]]; then
  pass "score keeps the 12/8 train/validation split"
else
  fail "expected 12/8 split, got $n_train/$n_val"
fi

cmp_json="$(run compare "$TMP/score.json" "$TMP/score.json")"
delta="$(jq -r '.skills[0].validation.trigger_rate_delta' <<<"$cmp_json")"
if awk -v d="$delta" 'BEGIN { exit !(d+0 == 0) }'; then
  pass "compare against self is a zero validation delta"
else
  fail "self-compare delta should be 0, got $delta ($cmp_json)"
fi

# Treatment: flip one validation miss into a hit by copying baseline and
# forcing predicted=true on a false-trigger-negative if any, else bump rates
# via jq so compare shows a non-zero delta.
jq '
  .skills[0].splits.validation.trigger_rate = ((.skills[0].splits.validation.trigger_rate // 0) + 0.25)
  | .skills[0].splits.validation.false_trigger_rate = ((.skills[0].splits.validation.false_trigger_rate // 0) * 0.5)
' "$TMP/score.json" >"$TMP/treatment.json"
cmp_json="$(run compare "$TMP/score.json" "$TMP/treatment.json")"
tdelta="$(jq -r '.skills[0].validation.trigger_rate_delta' <<<"$cmp_json")"
if awk -v d="$tdelta" 'BEGIN { exit !(d+0 > 0) }'; then
  pass "compare reports a positive validation trigger_rate delta after a rewrite-shaped bump"
else
  fail "expected positive delta, got $tdelta ($cmp_json)"
fi

printf 'not json\n' >"$TMP/malformed.json"
if run compare "$TMP/score.json" "$TMP/malformed.json" >/dev/null 2>&1; then
  fail "compare on a malformed report should exit non-zero"
else
  pass "compare on a malformed report exits non-zero"
fi

emit_dir="$TMP/eval-out"
run emit-plugin-eval "$TMP/probes" "$emit_dir" >/dev/null
n_cases="$(find "$emit_dir" -mindepth 1 -maxdepth 1 -type d | wc -l)"
if [[ "$n_cases" -eq 20 ]] && [[ -f "$emit_dir/fixture-target-pos-train-01/prompt.md" ]] &&
  [[ -f "$emit_dir/fixture-target-pos-train-01/graders/skill-fired.md" ]] &&
  [[ -f "$emit_dir/fixture-target-neg-train-01/graders/skill-quiet.md" ]]; then
  pass "emit-plugin-eval writes 20 cases with fire and quiet graders"
else
  fail "emit-plugin-eval layout wrong (n=$n_cases)"
fi

if run emit-plugin-eval "$TMP/probes" "$emit_dir" >/dev/null 2>&1; then
  fail "emit-plugin-eval into a non-empty dir should refuse"
else
  pass "emit-plugin-eval refuses a non-empty out dir"
fi

jq '.skills = []' "$TMP/score.json" >"$TMP/empty.json"
if run compare "$TMP/score.json" "$TMP/empty.json" >/dev/null 2>&1; then
  fail "compare over mismatched skill sets should exit non-zero"
else
  pass "compare refuses mismatched skill sets"
fi

mkdir -p "$TMP/badrival/probes"
jq '.competitor_dirs = {}' "$TMP/probes/target.json" >"$TMP/badrival/probes/target.json"
if run score "$TMP/badrival/probes" >/dev/null 2>&1; then
  fail "score with an unloadable competitor should exit non-zero"
else
  pass "score refuses an unloadable competitor"
fi

mkdir -p "$TMP/gone/probes"
jq '.skill_dir = "skills/absent" | .competitor_dirs = {} | .competitors = []' "$TMP/probes/target.json" >"$TMP/gone/probes/target.json"
out="$(run score "$TMP/gone/probes" 2>&1)"
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'none of the 1 probe file(s)' <<<"$out" && grep -q 'MEASURE_INVOCATION_REPO_ROOT' <<<"$out"; then
  pass "score exits 2 with guidance when every skill_dir is unresolved"
else
  fail "all-unresolved score should exit 2 with the message (rc=$rc): $out"
fi

out="$(run validate "$TMP/gone/probes" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q "WARN:.*skill_dir 'skills/absent' does not resolve" <<<"$out" &&
  grep -q 'INFO: 1 of 1 probe file(s) have a skill_dir that does not resolve' <<<"$out"; then
  pass "validate keeps the WARN, exits 0, and reports the unresolved count"
else
  fail "validate over unresolved skill_dir should exit 0 with WARN and INFO (rc=$rc): $out"
fi

mkdir -p "$TMP/mixed/probes"
cp "$TMP/gone/probes/target.json" "$TMP/mixed/probes/a-gone.json"
sed 's/"fixture:target"/"fixture:target2"/' "$TMP/probes/target.json" >"$TMP/mixed/probes/b-here.json"
out="$(run score "$TMP/mixed/probes" 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q "cannot resolve skill_dir 'skills/absent'" <<<"$out"; then
  pass "score keeps the per-skill error and exit 1 when only some skill_dirs resolve"
else
  fail "partial-unresolved score should exit 1 (rc=$rc): $out"
fi

out="$(run compare "$TMP/score.json" "$TMP/malformed.json" 2>&1)"
rc=$?
if [[ $rc -eq 2 ]]; then
  pass "compare on a malformed report exits 2"
else
  fail "compare on a malformed report should exit 2 (rc=$rc): $out"
fi
run compare "$TMP/score.json" "$TMP/empty.json" >/dev/null 2>&1
rc=$?
if [[ $rc -eq 2 ]]; then
  pass "compare over mismatched skill sets exits 2"
else
  fail "compare over mismatched skill sets should exit 2 (rc=$rc)"
fi

run emit-plugin-eval "$TMP/probes" /dev/null/x >/dev/null 2>&1
rc=$?
if [[ $rc -eq 2 ]]; then
  pass "emit-plugin-eval exits 2 when the out dir cannot be created"
else
  fail "emit-plugin-eval into an uncreatable dir should exit 2 (rc=$rc)"
fi

out="$(run score --method 2>&1)"
rc=$?
if [[ $rc -eq 2 ]] && grep -q -- '--method needs a value' <<<"$out"; then
  pass "score --method without a value says so"
else
  fail "score --method without a value should be named (rc=$rc): $out"
fi

mkdir -p "$TMP/empty-probes" "$TMP/tmpfix"
TMPDIR="$TMP/tmpfix" run score "$TMP/empty-probes" >/dev/null 2>&1
if [[ -z "$(ls -A "$TMP/tmpfix")" ]]; then
  pass "score removes its temp dir on an early exit"
else
  fail "score left a temp dir behind: $(ls "$TMP/tmpfix")"
fi

mkdir -p "$TMP/it's"
out="$(TMPDIR="$TMP/it's" run score "$TMP/empty-probes" 2>&1)"
if [[ -z "$(ls -A "$TMP/it's")" ]] && ! grep -q 'unexpected EOF' <<<"$out"; then
  pass "score cleans up when TMPDIR contains a quote"
else
  fail "score mishandled a quote in TMPDIR: $out"
fi

if [[ $fails -gt 0 ]]; then
  printf 'measure-invocation.test.sh: %s failed\n' "$fails" >&2
  exit 1
fi
printf 'measure-invocation.test.sh: all passed\n'
exit 0
