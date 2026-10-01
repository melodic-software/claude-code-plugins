#!/usr/bin/env bash
# Known-answer tests for metrics.sh. No expected value here comes from running
# metrics.sh. Each names its source:
#   - Wikipedia "Cohen's kappa", worked example (50 items: 20 yes/yes, 5 yes/no,
#     10 no/yes, 15 no/no; po 0.7, pe 0.5, kappa 0.4).
#   - Newcombe 1998, "Two-sided confidence intervals for the single proportion",
#     Stat Med 17:857-872, Table I: 81/263, Wilson score interval 0.2553-0.3662.
#   - The rest by hand, each cross-checked with python3's standard library
#     (fractions.Fraction for kappa, statistics.NormalDist().inv_cdf(0.975) =
#     1.959964 for z, and the Wilson formula), never with this script.
# Every interval prints to 4 decimals with z = 1.959964.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The judge hooks' fixtures: a temp dir, a `claude` on PATH that records any
# real call, the stub judge behind TEST_JUDGE_CMD, and the ok/fail counters.
# shellcheck source=../../../../hooks/judge-test-helpers.sh
source "$HERE/../../../../hooks/judge-test-helpers.sh"
METRICS="$HERE/metrics.sh"
W="$TMP/cal"
mkdir -p "$W/cases"

header() { printf 'id\tsource\tlanguage\tfile\ttest\tin_scope\thuman_label\tmodel_label\tadjudicated_label\tjudge_verdict\tevidence\tnote\tstratum\tsplit\n'; }
# row <id> <stratum> <split> <human> <model> <adjudicated> <judge> [file] [test] [note]
row() { printf '%s\tsrc\tts\t%s\t%s\tyes\t%s\t%s\t%s\t%s\t\t%s\t%s\t%s\n' "$1" "${8:-}" "${9:-}" "$4" "$5" "$6" "$7" "${10:-}" "$2" "$3"; }
# rows <count> <args for row after the id>: <count> rows with ids <prefix>1..n
rows() {
  local n="$1" p="$2" i
  shift 2
  for ((i = 1; i <= n; i++)); do row "$p$i" "$@"; done
}

# --- Cohen's kappa, two classes (Wikipedia worked example: 0.4) ---------------
{
  header
  rows 20 a s tune FLAG FLAG "" ""
  rows 5 b s tune FLAG PASS "" ""
  rows 10 c s tune PASS FLAG "" ""
  rows 15 d s tune PASS PASS "" ""
} >"$W/wiki.tsv"
out="$(bash "$METRICS" "$W/wiki.tsv")"
assert_contains "kappa, Wikipedia worked example" "$out" $'kappa user-model s 0.4000 (n=50)'
assert_contains "no judge labels gives NA" "$out" $'kappa judge-user s NA (n=0)'

# --- Three classes, one matrix used three ways ----------------------------------
# Rows are the first rater (or the judge), columns the second (or adjudicated):
#             FLAG PASS UNKNOWN
#   FLAG        6    2     1
#   PASS        1    8     1
#   UNKNOWN     0    1     4
# By hand: n 24, po 18/24 = 0.75; row totals 9 10 5, column totals 7 11 6;
# pe (9*7 + 10*11 + 5*6)/576 = 203/576; kappa (0.75 - 203/576)/(1 - 203/576)
# = 229/373 = 0.6139.
# FLAG precision 6/9: Wilson 0.3542-0.8794. FLAG recall 6/7: 0.4869-0.9743.
# Prevalence (adjudicated FLAG) 7/24 = 0.2917. UNKNOWN: judge 5, adjudicated 6.
matrix() { # matrix <stratum> <split>: the 24 rows, judge and human in the row role
  local s="$1" sp="$2"
  rows 6 "$s-ff" "$s" "$sp" FLAG FLAG FLAG FLAG
  rows 2 "$s-fp" "$s" "$sp" FLAG PASS PASS FLAG
  rows 1 "$s-fu" "$s" "$sp" FLAG UNKNOWN UNKNOWN FLAG
  rows 1 "$s-pf" "$s" "$sp" PASS FLAG FLAG PASS
  rows 8 "$s-pp" "$s" "$sp" PASS PASS PASS PASS
  rows 1 "$s-pu" "$s" "$sp" PASS UNKNOWN UNKNOWN PASS
  rows 1 "$s-up" "$s" "$sp" UNKNOWN PASS PASS UNKNOWN
  rows 4 "$s-uu" "$s" "$sp" UNKNOWN UNKNOWN UNKNOWN UNKNOWN
}
{
  header
  matrix seed tune
  # A second stratum where every label agrees on PASS: pe = 1, kappa undefined.
  rows 3 same in-use holdout PASS PASS PASS PASS
} >"$W/three.tsv"
out="$(bash "$METRICS" "$W/three.tsv")"
assert_contains "kappa, three classes" "$out" $'kappa user-model seed 0.6139 (n=24)'
# matrix() gives the judge the user's label on every row: identical labels, kappa 1.
assert_contains "judge vs user, identical labels" "$out" $'kappa judge-user seed 1.0000 (n=24)'
assert_contains "judge vs model rater, same matrix" "$out" $'kappa judge-model seed 0.6139 (n=24)'
assert_contains "confusion row FLAG" "$out" $'confusion seed judge=FLAG FLAG=6 PASS=2 UNKNOWN=1'
assert_contains "confusion row PASS" "$out" $'confusion seed judge=PASS FLAG=1 PASS=8 UNKNOWN=1'
assert_contains "confusion row UNKNOWN" "$out" $'confusion seed judge=UNKNOWN FLAG=0 PASS=1 UNKNOWN=4'
assert_contains "FLAG precision with Wilson" "$out" $'flag-precision seed 0.6667 [0.3542, 0.8794] (6/9)'
assert_contains "FLAG recall with Wilson" "$out" $'flag-recall seed 0.8571 [0.4869, 0.9743] (6/7)'
assert_contains "prevalence" "$out" $'prevalence seed 0.2917 (7/24)'
assert_contains "UNKNOWN counts" "$out" $'unknown seed judge=5 adjudicated=6'
assert_contains "kappa NA when chance agreement is 1" "$out" $'kappa user-model in-use NA (n=3)'
assert_contains "precision NA when the judge never says FLAG" "$out" $'flag-precision in-use NA (0/0)'
assert_contains "recall NA with no adjudicated FLAG" "$out" $'flag-recall in-use NA (0/0)'
assert_contains "strata pooled into all" "$out" $'confusion all judge=PASS FLAG=1 PASS=11 UNKNOWN=1'
assert_contains "stratum header" "$out" $'stratum in-use n=3'

# --- Wilson edge and published cases --------------------------------------------
# Newcombe 1998 Table I: 81/263 gives 0.2553-0.3662. By the formula: 0/5 gives
# 0.0000-0.4345 and 5/5 gives 0.5655-1.0000.
{
  header
  rows 81 t s tune FLAG FLAG FLAG FLAG
  rows 182 f s tune PASS PASS PASS FLAG
} >"$W/newcombe.tsv"
out="$(bash "$METRICS" "$W/newcombe.tsv")"
assert_contains "Wilson, Newcombe 81/263" "$out" $'flag-precision s 0.3080 [0.2553, 0.3662] (81/263)'
{
  header
  rows 5 a s tune PASS PASS PASS FLAG
} >"$W/zero.tsv"
out="$(bash "$METRICS" "$W/zero.tsv")"
assert_contains "Wilson x = 0" "$out" $'flag-precision s 0.0000 [0.0000, 0.4345] (0/5)'
{
  header
  rows 5 a s tune FLAG FLAG FLAG FLAG
} >"$W/all.tsv"
out="$(bash "$METRICS" "$W/all.tsv")"
assert_contains "Wilson x = n" "$out" $'flag-recall s 1.0000 [0.5655, 1.0000] (5/5)'

# --- --check ----------------------------------------------------------------------
# A repository laid out like this one: the prompt, the labels, calibration.md.
CR="$TMP/check-repo"
LBL="$CR/plugins/testing/skills/audit/evals/judge-calibration/labels.tsv"
CAL="$CR/docs/specs/tautological-tests-judge/calibration.md"
mkdir -p "${LBL%/*}" "${CAL%/*}" "$CR/plugins/testing/hooks"
git -C "$CR" init -q -b main
commit() { git -C "$CR" add -A && git -C "$CR" -c user.name=t -c user.email=t@t commit -qm "$1"; }
printf 'prompt v1\n' >"$CR/plugins/testing/hooks/test-judge-prompt.md"
printf '# Calibration\n' >"$CAL"
commit prompt
# Passing set: 2 strata, holdout exactly a third of each, user-model kappa 1.
{
  header
  rows 2 s seed tune FLAG FLAG FLAG ""
  rows 1 h seed holdout PASS PASS PASS ""
  rows 4 u in-use tune PASS PASS PASS ""
  rows 2 v in-use holdout FLAG FLAG FLAG ""
} >"$LBL"
commit labels
out="$(bash "$METRICS" --check "$LBL" 2>&1)"
check "--check exits 0 on a complete, frozen set (output: ${out:0:200})" "[[ $? -eq 0 ]]"

expect_check_fail() { # <name> <message part>
  local o rc
  o="$(bash "$METRICS" --check "$LBL" 2>&1)"
  rc=$?
  check "$1 fails --check" "[[ $rc -ne 0 ]]"
  assert_contains "$1 names the cause" "$o" "$2"
}
cp "$LBL" "$TMP/good.tsv"
sed -i '2s/\tFLAG\tFLAG\tFLAG\t/\tFLAG\t\tFLAG\t/' "$LBL"
expect_check_fail "a missing model label" "s1: model_label"
cp "$TMP/good.tsv" "$LBL"
sed -i '2s/\tseed\ttune$/\t\ttune/' "$LBL"
expect_check_fail "a missing stratum" "s1: stratum"
cp "$TMP/good.tsv" "$LBL"
sed -i 's/\tin-use\tholdout$/\tin-use\ttune/' "$LBL"
expect_check_fail "too small a holdout" "in-use: holdout 0 of 6"
cp "$TMP/good.tsv" "$LBL"
sed -i 's/^u1\(.*\)\tPASS\tPASS\tPASS\t/u1\1\tPASS\tFLAG\tPASS\t/; s/^u2\(.*\)\tPASS\tPASS\tPASS\t/u2\1\tPASS\tFLAG\tPASS\t/' "$LBL"
# By hand: user FLAG 4, PASS 5; model FLAG 6, PASS 3; agree 7 of 9.
# pe (4*6 + 5*3)/81 = 39/81; kappa (63/81 - 39/81)/(42/81) = 24/42 = 0.5714.
expect_check_fail "user-model kappa below 0.6" "kappa user-model 0.5714 is below 0.6"
cp "$TMP/good.tsv" "$LBL"
printf 'prompt v2\n' >"$CR/plugins/testing/hooks/test-judge-prompt.md"
commit "prompt after labels"
late="$(git -C "$CR" rev-parse HEAD)"
expect_check_fail "a prompt change after labeling" "${late:0:12} changed the judge prompt after labels.tsv"
printf 'holdout-only: %s\n' "${late:0:7}" >>"$CAL"
commit "record holdout-only metrics"
bash "$METRICS" --check "$LBL" >/dev/null 2>&1
check "--check accepts a later prompt change with a holdout-only marker" "[[ $? -eq 0 ]]"
rm -rf "$CR/.git"
git -C "$CR" init -q -b main
expect_check_fail "labels outside git history" "labels.tsv has no commit"

# --- --sweep through the judge command function, stub only -----------------------
SW="$TMP/sweep"
mkdir -p "$SW/cases"
printf 'it("adds", () => {\n  expect(add(1, 2)).toBe(3);\n});\n\nit("flag restates", () => {\n  expect(add(1, 2)).toBe(1 + 2);\n});\n' \
  >"$SW/cases/case-1.add.test.ts.fixture"
printf 'export const add = (a, b) => a + b;\n' >"$SW/cases/case-1.add.ts.fixture"
# shellcheck disable=SC2016 # the case file holds a literal $(...)
printf '#!/usr/bin/env bash\nfail() { exit 1; }\n[[ "$(echo a)" == a ]] || fail\n' >"$SW/cases/case-2.flag.test.sh.fixture"
{
  header
  row c1 seed tune "" "" PASS "" cases/case-1.add.test.ts.fixture adds
  row c2 seed holdout "" "" FLAG "" cases/case-1.add.test.ts.fixture "flag restates"
  row c3 in-use holdout "" "" FLAG "" cases/case-2.flag.test.sh.fixture flag.test.sh "changed 2-3"
} >"$SW/labels.tsv"
# Every stub answer costs $0.01.
cat >"$TMP/cost-stub.sh" <<EOF
#!/usr/bin/env bash
ls >"\$STUB_DIR/ls-\$\$-\$RANDOM"
"$TMP/judge-stub.sh" "\$@" | jq -c '. + {total_cost_usd: 0.01}'
EOF
chmod +x "$TMP/cost-stub.sh"
out="$(TEST_JUDGE_CMD="$TMP/cost-stub.sh" bash "$METRICS" --sweep "$SW/labels.tsv" 2>&1)"
rc=$?
check "--sweep exits 0 (output: ${out:0:300})" "[[ $rc -eq 0 ]]"
check "the sweep table has the six rows calibration.md greps for" \
  "[[ \$(grep -cE '^\| (haiku|sonnet|opus) \| (low|medium) \|' <<<\"\$out\") -eq 6 ]]"
check "six distinct arms" "[[ \$(grep -E '^\| (haiku|sonnet|opus) \| (low|medium) \|' <<<\"\$out\" | cut -d'|' -f2,3 | sort -u | wc -l) -eq 6 ]]"
# Holdout rows c2 and c3 are both FLAG, and the stub flags both (names hold
# "flag"): precision 2/2 and recall 2/2, Wilson 0.3424-1.0000 (formula, python3).
# UNKNOWN 0 of 3. Cost: two runs (one per case file) at $0.01 over 3 cases,
# $0.0067 a case.
# shellcheck disable=SC2016 # a literal dollar amount
assert_contains "a row reports holdout precision, recall, UNKNOWN rate and cost" "$out" \
  '| haiku | low | 1.0000 [0.3424, 1.0000] (2/2) | 1.0000 [0.3424, 1.0000] (2/2) | 0.0000 (0/3) | $0.0067 |'
check "the stub ran once per case file per arm" "[[ \$(stub_calls) -eq 12 ]]"
args="$(for i in $(seq 1 "$(stub_calls)"); do stub_args "$i"; done)"
assert_contains "runs through judge::run (its system prompt flag)" "$args" "--system-prompt"
assert_contains "runs through judge::run (its read-only tools)" "$args" $'--tools\nRead,Grep,Glob'
for m in haiku sonnet opus; do
  assert_contains "arm model $m reached the judge" "$args" $'--model\n'"$m"
done
for e in low medium; do
  assert_contains "arm effort $e reached the judge" "$args" $'--effort\n'"$e"
done
assert_not_contains "the judge never sees the labels" "$args" "labels.tsv"
assert_not_contains "the judge never sees a case id" "$args" "case-1"
check "the judge reads the case under its real name" "grep -q 'Judge these test blocks in .*/add.test.ts (block' <<<\"\$args\""
check "the implementation sibling sits beside the case" "grep -qx 'add.ts' \"\$STUB_DIR\"/ls-*"
check "only the case's own files reach the judge's repo" "compgen -G \"\$STUB_DIR/ls-*\" >/dev/null && ! grep -qvx -e add.ts -e add.test.ts -e flag.test.sh \"\$STUB_DIR\"/ls-*"
check "per-arm verdicts are kept" "[[ -f \"\$SW/sweep/opus-medium.tsv\" ]]"
assert_contains "verdicts map back to case ids" "$(cat "$SW/sweep/opus-medium.tsv" 2>/dev/null)" $'c2\tFLAG\topus\tmedium'
check "no real claude was called" "[[ ! -e \"\$TMP/real-claude-called\" ]]"

finish
