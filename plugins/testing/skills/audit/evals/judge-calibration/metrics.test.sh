#!/usr/bin/env bash
# Known-answer tests for metrics.sh, raters.sh and sample.sh's label guard. No
# expected value here comes from running those scripts. Each names its source:
#   - Wikipedia "Cohen's kappa", worked example (50 items: 20 yes/yes, 5 yes/no,
#     10 no/yes, 15 no/no; po 0.7, pe 0.5, kappa 0.4).
#   - Newcombe 1998, "Two-sided confidence intervals for the single proportion",
#     Stat Med 17:857-872, Table I: 81/263, Wilson score interval 0.2553-0.3662.
#   - The rest by hand, each cross-checked with python3's standard library
#     (fractions.Fraction for kappa, statistics.NormalDist().inv_cdf(0.975) =
#     1.959964 for z, the Wilson formula, and math.comb for the exact McNemar
#     p = min(1, 2 * sum(comb(n, k) for k <= min(b, c)) / 2^n)), never with
#     these scripts.
# Every interval prints to 4 decimals with z = 1.959964.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The judge hooks' fixtures: a temp dir, a `claude` on PATH that records any
# real call, the stub judge behind TEST_JUDGE_CMD, and the ok/fail counters.
# shellcheck source=../../../../hooks/judge-test-helpers.sh
source "$HERE/../../../../hooks/judge-test-helpers.sh"
METRICS="$HERE/metrics.sh"
RATERS="$HERE/raters.sh"
W="$TMP/cal"
mkdir -p "$W/cases"
# A real codex is often on PATH: a recording fake shadows it, like `claude`.
cat >"$TMP/bin/codex" <<EOF
#!/usr/bin/env bash
echo "a real codex was called" >>"$TMP/real-codex-called"
exit 97
EOF
chmod +x "$TMP/bin/codex"

COLS=(id source language file test in_scope reference_label opus_label codex_label judge_verdict evidence note stratum split)
header() { (IFS=$'\t' && echo "${COLS[*]}"); }
# row <id> <stratum> <split> <human> <opus> <codex> <judge> [file] [test] [note]
row() { printf '%s\tsrc\tts\t%s\t%s\tyes\t%s\t%s\t%s\t%s\t\t%s\t%s\t%s\n' "$1" "${8:-}" "${9:-}" "$4" "$5" "$6" "$7" "${10:-}" "$2" "$3"; }
# rows <count> <args for row after the id>: <count> rows with ids <prefix>1..n
rows() {
  local n="$1" p="$2" i
  shift 2
  for ((i = 1; i <= n; i++)); do row "$p$i" "$@"; done
}
# setcol <file> <id> <column> <value>: set one cell, found by header name.
setcol() {
  awk -F'\t' -v OFS='\t' -v id="$2" -v k="$3" -v v="$4" \
    'NR == 1 { for (i = 1; i <= NF; i++) c[$i] = i } NR > 1 && $c["id"] == id { $c[k] = v } 1' "$1" >"$1.new" && mv "$1.new" "$1"
}
# col <file> <column>: one column's values, by header name, without the header.
col() { awk -F'\t' -v k="$2" 'NR == 1 { for (i = 1; i <= NF; i++) c[$i] = i; next } { print $c[k] }' "$1"; }

# --- Cohen's kappa, two classes (Wikipedia worked example: 0.4) ---------------
{
  header
  rows 20 a s tune FLAG FLAG "" ""
  rows 5 b s tune FLAG PASS "" ""
  rows 10 c s tune PASS FLAG "" ""
  rows 15 d s tune PASS PASS "" ""
} >"$W/wiki.tsv"
out="$(bash "$METRICS" "$W/wiki.tsv")"
assert_contains "kappa, Wikipedia worked example, with coverage and raw agreement" "$out" \
  'kappa user-opus in s 0.4000 (n=50) coverage 1.0000 (50/50) agreement 0.7000 (35/50)'
assert_contains "no judge labels gives NA" "$out" 'kappa judge-user in s NA (n=0) coverage NA (0/0) agreement NA (0/0)'
assert_not_contains "a rater with no label on any row gets no line" "$out" 'kappa user-codex'

# --- Three classes and the UNKNOWN rule, one matrix used three ways ------------
# Rows are the judge (and the opus rater), columns the user's label:
#             FLAG PASS UNKNOWN
#   FLAG        6    2     1
#   PASS        1    8     1
#   UNKNOWN     1    1     3
# By hand: n 24. The two UNKNOWN verdicts on a user FLAG or PASS row abstain,
# so kappa runs over 22 rows: agree 6 + 8 + 3 = 17, po 17/22; judge totals
# 9 10 3, user totals 7 10 5; pe (63 + 100 + 15)/484 = 178/484; kappa
# (374 - 178)/(484 - 178) = 98/153 = 0.6405. Coverage: 19 user FLAG or PASS
# rows, 17 not abstained: 0.8947. FLAG precision 6/9 (the FLAG on a user
# UNKNOWN row counts against it): Wilson 0.3542-0.8794. FLAG recall 6/7 (the
# abstention on a user FLAG row is left out): 0.4869-0.9743. Prevalence 8/24.
# On the 5 user UNKNOWN rows: 3 judge UNKNOWN (correct), 2 over-reach.
matrix() { # matrix <stratum> <split>: the 24 rows; codex agrees with the user
  local s="$1" sp="$2"
  rows 6 "$s-ff" "$s" "$sp" FLAG FLAG FLAG FLAG
  rows 2 "$s-fp" "$s" "$sp" PASS FLAG PASS FLAG
  rows 1 "$s-fu" "$s" "$sp" UNKNOWN FLAG UNKNOWN FLAG
  rows 1 "$s-pf" "$s" "$sp" FLAG PASS FLAG PASS
  rows 8 "$s-pp" "$s" "$sp" PASS PASS PASS PASS
  rows 1 "$s-pu" "$s" "$sp" UNKNOWN PASS UNKNOWN PASS
  rows 1 "$s-uf" "$s" "$sp" FLAG UNKNOWN FLAG UNKNOWN
  rows 1 "$s-up" "$s" "$sp" PASS UNKNOWN PASS UNKNOWN
  rows 3 "$s-uu" "$s" "$sp" UNKNOWN UNKNOWN UNKNOWN UNKNOWN
}
{
  header
  matrix seed tune
  # A second stratum where every label agrees on PASS: pe = 1, kappa undefined.
  rows 3 same in-use holdout PASS PASS PASS PASS
} >"$W/three.tsv"
out="$(bash "$METRICS" "$W/three.tsv")"
assert_contains "kappa, three classes, abstentions left out" "$out" \
  'kappa user-opus in seed 0.6405 (n=22) coverage 0.8947 (17/19) agreement 0.7727 (17/22)'
assert_contains "judge vs user, same matrix" "$out" \
  'kappa judge-user in seed 0.6405 (n=22) coverage 0.8947 (17/19) agreement 0.7727 (17/22)'
assert_contains "codex read by its column name: identical to the user" "$out" \
  'kappa user-codex in seed 1.0000 (n=24) coverage 1.0000 (19/19) agreement 1.0000 (24/24)'
assert_contains "confusion row FLAG" "$out" $'confusion seed judge=FLAG FLAG=6 PASS=2 UNKNOWN=1'
assert_contains "confusion row PASS" "$out" $'confusion seed judge=PASS FLAG=1 PASS=8 UNKNOWN=1'
assert_contains "confusion row UNKNOWN" "$out" $'confusion seed judge=UNKNOWN FLAG=1 PASS=1 UNKNOWN=3'
assert_contains "FLAG precision counts a FLAG on a user UNKNOWN" "$out" $'flag-precision seed 0.6667 [0.3542, 0.8794] (6/9)'
assert_contains "FLAG recall leaves the abstention out" "$out" $'flag-recall seed 0.8571 [0.4869, 0.9743] (6/7)'
assert_contains "prevalence" "$out" $'prevalence seed 0.3333 (8/24)'
assert_contains "achieved FLAG n" "$out" $'flag-n seed 8'
assert_contains "achieved FLAG n is 0 in a stratum with no user FLAG" "$out" $'flag-n in-use 0'
assert_contains "the judge on user UNKNOWN rows" "$out" $'unknown seed user=5 correct=3 over-reach=2'
assert_contains "kappa NA when chance agreement is 1" "$out" 'kappa user-opus in in-use NA (n=3)'
assert_contains "precision NA when the judge never says FLAG" "$out" $'flag-precision in-use NA (0/0)'
assert_contains "recall NA with no user FLAG" "$out" $'flag-recall in-use NA (0/0)'
assert_contains "strata pooled into all" "$out" $'confusion all judge=PASS FLAG=1 PASS=11 UNKNOWN=1'
assert_contains "stratum header" "$out" $'stratum in-use n=3'
# The plan's Sanity Check greps, over a report with two strata and the pool.
check "the user-opus grep finds exactly the pooled line" "[[ \$(grep -cE '^kappa user-opus .* all ' <<<\"\$out\") -eq 1 ]]"
check "the user-codex grep finds exactly the pooled line" "[[ \$(grep -cE '^kappa user-codex .* all ' <<<\"\$out\") -eq 1 ]]"
check "the judge-user grep finds the pooled line" "[[ \$(grep -cE '^kappa judge-user .* all ' <<<\"\$out\") -ge 1 ]]"

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

# --- columns by header name ----------------------------------------------------------
awk -F'\t' -v OFS='\t' '{ print $14, $13, $12, $11, $10, $9, $8, $7, $6, $5, $4, $3, $2, $1 }' "$W/wiki.tsv" >"$W/reversed.tsv"
out="$(bash "$METRICS" "$W/reversed.tsv")"
assert_contains "columns in any order give the same kappa" "$out" 'kappa user-opus in s 0.4000 (n=50)'
cut -f1-12 "$W/wiki.tsv" >"$W/nostratum.tsv"
out="$(bash "$METRICS" "$W/nostratum.tsv" 2>&1)"
check "a missing column exits 2" "[[ $? -eq 2 ]]"
assert_contains "a missing column is named" "$out" "no stratum column"

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
# Passing set: 2 strata, holdout exactly a third of each, opus rated every
# row, codex none (so codex is not configured).
{
  header
  rows 2 s seed tune FLAG FLAG "" ""
  rows 1 h seed holdout PASS PASS "" ""
  rows 4 u in-use tune PASS PASS "" ""
  rows 2 v in-use holdout FLAG FLAG "" ""
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
setcol "$LBL" s1 opus_label ""
expect_check_fail "a missing opus label" "s1: opus_label"
cp "$TMP/good.tsv" "$LBL"
setcol "$LBL" s1 reference_label ""
expect_check_fail "a missing user label" "s1: reference_label"
cp "$TMP/good.tsv" "$LBL"
setcol "$LBL" u1 codex_label PASS
expect_check_fail "codex configured by one label, missing elsewhere" "s1: codex_label"
cp "$TMP/good.tsv" "$LBL"
setcol "$LBL" s1 stratum ""
expect_check_fail "a missing stratum" "s1: stratum"
cp "$TMP/good.tsv" "$LBL"
for i in 1 2; do setcol "$LBL" "v$i" split tune; done
expect_check_fail "too small a holdout" "in-use: holdout 0 of 6"
cp "$TMP/good.tsv" "$LBL"
setcol "$LBL" u1 opus_label FLAG
setcol "$LBL" u2 opus_label FLAG
# By hand: user FLAG 4, PASS 5; opus FLAG 6, PASS 3; agree 7 of 9.
# pe (4*6 + 5*3)/81 = 39/81; kappa (63/81 - 39/81)/(42/81) = 24/42 = 0.5714.
# The user's labels are the ground truth, so a weak rater does not block.
out="$(bash "$METRICS" --check "$LBL" 2>&1)"
check "a rater under 0.6 does not fail --check (output: ${out:0:200})" "[[ $? -eq 0 ]]"
assert_contains "a rater under 0.6 is reported as failed" "$(bash "$METRICS" "$LBL")" \
  'kappa user-opus in all 0.5714 (n=9) coverage 1.0000 (9/9) agreement 0.7778 (7/9) failed'
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

# --- --table: selection over kept sweep files, known answers ----------------------
# 12 rows: r1-r4 the user labeled FLAG, r5-r12 PASS. Each arm answers the
# user's label except where listed; "wrong" rows flip FLAG and PASS.
#   opus high:     r12 FLAG                  11/12, the most accurate
#   opus medium:   r10 FLAG, r11 UNKNOWN     10/12; vs best b=1 c=2: p 1
#   opus low:      r1-r9 wrong               3/12;  b=1 c=9: p 22/1024 = 0.0215
#   sonnet low:    r1-r6 wrong               6/12;  b=1 c=6: p 16/128 = 0.1250
#   sonnet medium: r1-r2 wrong               10/12; b=1 c=2: p 1
#   sonnet high:   r1-r2 wrong               10/12; p 1
#   sonnet xhigh:  r1-r9 wrong               3/12;  p 0.0215
# Tied with opus high (p >= 0.05): opus medium and sonnet low, medium and
# high. Sonnet wins; p95 wall (nearest rank) is 30 for low and 20 for medium
# and high; cost per row 0.03/12 = 0.0025 for medium beats 0.06/12 for high:
# chosen sonnet medium. Fallback, opus by the same rule: opus high is its most
# accurate, opus medium ties with it (p 1) and has the lower p95 (40 vs 50).
TB="$TMP/table"
mkdir -p "$TB/sweep"
{
  header
  for i in 1 2 3 4; do row "r$i" s tune FLAG "" "" ""; done
  for i in 5 6 7 8 9 10 11 12; do row "r$i" s tune PASS "" "" ""; done
} >"$TB/labels.tsv"
arm_file() { # arm_file <model> <effort> <wrong rows "a-b"> [row=verdict...]
  local m="$1" e="$2" lo="${3%-*}" hi="${3#*-}" i v
  shift 3
  for i in $(seq 1 12); do
    v=PASS && ((i <= 4)) && v=FLAG
    ((lo > 0 && i >= lo && i <= hi)) && { [[ "$v" == FLAG ]] && v=PASS || v=FLAG; }
    for o in "$@"; do [[ "${o%=*}" == "r$i" ]] && v="${o#*=}"; done
    printf 'r%d\t%s\t%s\t%s\treason\n' "$i" "$v" "$m" "$e"
  done >"$TB/sweep/$m-$e.tsv"
}
arm_file opus high 0-0 r12=FLAG
arm_file opus medium 0-0 r10=FLAG r11=UNKNOWN
arm_file opus low 1-9
arm_file sonnet low 1-6
arm_file sonnet medium 1-2
arm_file sonnet high 1-2
arm_file sonnet xhigh 1-9
printf '0.05\t40\n0.05\t50\n' >"$TB/sweep/opus-high.runs.tsv"
printf '0.05\t30\n0.05\t40\n' >"$TB/sweep/opus-medium.runs.tsv"
printf '0.05\t20\n0.05\t30\n' >"$TB/sweep/opus-low.runs.tsv"
printf '0.01\t10\n0.01\t30\n' >"$TB/sweep/sonnet-low.runs.tsv"
printf '0.01\t10\n0.02\t20\n' >"$TB/sweep/sonnet-medium.runs.tsv"
printf '0.03\t10\n0.03\t20\n' >"$TB/sweep/sonnet-high.runs.tsv"
printf '0.1\t5\n0.1\t6\n' >"$TB/sweep/sonnet-xhigh.runs.tsv"
out="$(bash "$METRICS" --table "$TB/labels.tsv" 2>&1)"
check "--table exits 0 (output: ${out:0:300})" "[[ $? -eq 0 ]]"
# opus high: FLAG on r1-r4 and r12, so precision 4/5 (Wilson 0.3755-0.9638)
# and recall 4/4 (0.5101-1.0000); cost 0.10/12; wall median 45, p95 50, total 90.
# shellcheck disable=SC2016 # literal dollar amounts
assert_contains "the most accurate arm's row" "$out" \
  '| opus | high | 0.9167 (11/12) | 0.8000 [0.3755, 0.9638] (4/5) | 1.0000 [0.5101, 1.0000] (4/4) | 1.0000 (12/12) | $0.0083 | 45.0 s | 50.0 s | 90.0 s | 1.0000 |'
# sonnet medium: precision 2/2, recall 2/4 (Wilson 0.1500-0.8500).
# shellcheck disable=SC2016
assert_contains "a tied arm's row" "$out" \
  '| sonnet | medium | 0.8333 (10/12) | 1.0000 [0.3424, 1.0000] (2/2) | 0.5000 [0.1500, 0.8500] (2/4) | 1.0000 (12/12) | $0.0025 | 15.0 s | 20.0 s | 30.0 s | 1.0000 |'
assert_contains "an UNKNOWN on a PASS row costs coverage" "$out" '| opus | medium | 0.8333 (10/12) |'
# shellcheck disable=SC2016
assert_contains "opus medium's coverage" "$out" '| 0.9167 (11/12) | $0.0083 | 35.0 s | 40.0 s | 70.0 s | 1.0000 |'
check "exact McNemar, b=1 c=9" "grep -qE '^\\| opus \\| low \\|.*\\| 0\\.0215 \\|\$' <<<\"\$out\""
check "exact McNemar, b=1 c=6" "grep -qE '^\\| sonnet \\| low \\|.*\\| 0\\.1250 \\|\$' <<<\"\$out\""
assert_contains "chosen: sonnet, then p95 wall, then cost" "$out" $'\nchosen: sonnet medium'
assert_contains "fallback: the other class by the same rule" "$out" $'\nfallback: opus medium'
check "the table has the seven rows the Sanity Check greps for" \
  "[[ \$(grep -cE '^\\| (sonnet \\| (low|medium|high|xhigh)|opus \\| (low|medium|high)) \\|' <<<\"\$out\") -eq 7 ]]"
# The most accurate arm tied on accuracy: sonnet wins it.
arm_file sonnet medium 0-0 r12=FLAG
out="$(bash "$METRICS" --table "$TB/labels.tsv" 2>&1)"
assert_contains "an accuracy tie at the top goes to sonnet" "$out" '| sonnet | medium | 0.9167 (11/12) |'
assert_contains "and sonnet medium is chosen" "$out" $'\nchosen: sonnet medium'

# --- --sweep through the judge command function, stub only -----------------------
SW="$TMP/sweep"
mkdir -p "$SW/cases/case-1/test" "$SW/cases/case-1/src" "$SW/cases/case-2"
printf 'it("adds", () => {\n  expect(add(1, 2)).toBe(3);\n});\n\nit("flag restates", () => {\n  expect(add(1, 2)).toBe(1 + 2);\n});\n' \
  >"$SW/cases/case-1/test/add.test.ts.fixture"
printf 'export const add = (a, b) => a + b;\n' >"$SW/cases/case-1/src/add.ts.fixture"
# shellcheck disable=SC2016 # the case file holds a literal $(...)
printf '#!/usr/bin/env bash\nfail() { exit 1; }\n[[ "$(echo a)" == a ]] || fail\n' >"$SW/cases/case-2/flag.test.sh.fixture"
{
  header
  row c1 seed tune PASS "" "" "" cases/case-1/test/add.test.ts.fixture adds
  row c2 seed holdout FLAG "" "" "" cases/case-1/test/add.test.ts.fixture "flag restates"
  row c3 in-use holdout FLAG "" "" "" cases/case-2/flag.test.sh.fixture flag.test.sh "changed 2-3"
} >"$SW/labels.tsv"
# Every stub answer costs $0.01.
cat >"$TMP/cost-stub.sh" <<EOF
#!/usr/bin/env bash
find . -type f -not -path "./.git/*" >"\$STUB_DIR/ls-\$\$-\$RANDOM"
"$TMP/judge-stub.sh" "\$@" | jq -c '. + {total_cost_usd: 0.01}'
EOF
chmod +x "$TMP/cost-stub.sh"
out="$(bash "$METRICS" --rerun sonnet medium "$SW/labels.tsv" 2>&1)"
check "--rerun before a sweep exits 2" "[[ $? -eq 2 ]]"
assert_contains "--rerun before a sweep says why" "$out" "no sweep/sonnet-medium.tsv"
out="$(TEST_JUDGE_CMD="$TMP/cost-stub.sh" bash "$METRICS" --sweep "$SW/labels.tsv" 2>&1)"
rc=$?
check "--sweep exits 0 (output: ${out:0:300})" "[[ $rc -eq 0 ]]"
check "the sweep table has the seven rows calibration.md greps for" \
  "[[ \$(grep -cE '^\\| (sonnet \\| (low|medium|high|xhigh)|opus \\| (low|medium|high)) \\|' <<<\"\$out\") -eq 7 ]]"
check "seven distinct arms" "[[ \$(grep -E '^\\| (sonnet|opus) \\| (low|medium|high|xhigh) \\|' <<<\"\$out\" | cut -d'|' -f2,3 | sort -u | wc -l) -eq 7 ]]"
# c2 and c3 are user FLAG and the stub flags both (names hold "flag"); c1 is
# PASS and passes: accuracy 3/3, precision 2/2 and recall 2/2 (Wilson
# 0.3424-1.0000), coverage 3/3. Cost: two runs (one per case file) at $0.01
# over 3 rows, $0.0067 a row.
# shellcheck disable=SC2016 # a literal dollar amount
assert_contains "a row reports accuracy, precision, recall, coverage and cost" "$out" \
  '| sonnet | low | 1.0000 (3/3) | 1.0000 [0.3424, 1.0000] (2/2) | 1.0000 [0.3424, 1.0000] (2/2) | 1.0000 (3/3) | $0.0067 |'
check "every arm ties, so sonnet is chosen" "grep -q '^chosen: sonnet ' <<<\"\$out\""
check "and the fallback is opus" "grep -q '^fallback: opus ' <<<\"\$out\""
check "the stub ran once per case file per arm" "[[ \$(stub_calls) -eq 14 ]]"
args="$(for i in $(seq 1 "$(stub_calls)"); do stub_args "$i"; done)"
assert_contains "runs through judge::run (its system prompt flag)" "$args" "--system-prompt"
assert_contains "runs through judge::run (its read-only tools)" "$args" $'--tools\nRead,Grep,Glob'
for m in sonnet opus; do
  assert_contains "arm model $m reached the judge" "$args" $'--model\n'"$m"
done
for e in low medium high xhigh; do
  assert_contains "arm effort $e reached the judge" "$args" $'--effort\n'"$e"
done
assert_not_contains "no haiku arm" "$args" $'--model\nhaiku'
assert_not_contains "the judge never sees the labels" "$args" "labels.tsv"
assert_not_contains "the judge never sees a case id" "$args" "case-1"
check "the judge reads the case under its real name" "grep -q 'Judge these test blocks in .*/add.test.ts (block' <<<\"\$args\""
check "the code under test keeps its repository path" "grep -qx './src/add.ts' \"\$STUB_DIR\"/ls-*"
check "only the case's own files reach the judge's repo" "compgen -G \"\$STUB_DIR/ls-*\" >/dev/null && ! grep -qvx -e ./src/add.ts -e ./test/add.test.ts -e ./flag.test.sh \"\$STUB_DIR\"/ls-*"
check "per-arm verdicts are kept" "[[ -f \"\$SW/sweep/opus-medium.tsv\" ]]"
assert_contains "verdicts map back to case ids" "$(cat "$SW/sweep/opus-medium.tsv" 2>/dev/null)" $'c2\tFLAG\topus\tmedium'
check "each arm keeps one cost and wall time per run" \
  "[[ \$(awk -F'\t' 'NF == 2 && \$1 == 0.01 && \$2 ~ /^[0-9]+(\\.[0-9]+)?\$/' \"\$SW/sweep/sonnet-xhigh.runs.tsv\" | wc -l) -eq 2 ]]"

# --- --rerun: run-to-run variance of one arm ---------------------------------------
# The re-runs pass every block: c2 and c3 change, c1 does not: 2/3.
cat >"$TMP/pass-stub.sh" <<EOF
#!/usr/bin/env bash
"$TMP/cost-stub.sh" "\$@" | jq -c '.result |= ("Here you go: " + (sub("^Here you go: "; "") | fromjson | .verdicts |= map(.verdict = "PASS" | .diff = "") | tojson))'
EOF
chmod +x "$TMP/pass-stub.sh"
stub_reset
out="$(TEST_JUDGE_CMD="$TMP/pass-stub.sh" bash "$METRICS" --rerun sonnet medium "$SW/labels.tsv" 2>&1)"
check "--rerun exits 0 (output: ${out:0:300})" "[[ $? -eq 0 ]]"
assert_contains "--rerun reports the share of rows whose verdict changed" "$out" '| rerun | sonnet | medium | 0.6667 (2/3) |'
check "two more runs per case file" "[[ \$(stub_calls) -eq 4 ]]"
check "the re-run rows do not match the sweep grep" \
  "[[ \$(grep -cE '^\\| (sonnet \\| (low|medium|high|xhigh)|opus \\| (low|medium|high)) \\|' <<<\"\$out\") -eq 0 ]]"
check "the re-runs' verdicts are kept" "[[ -f \"\$SW/sweep/sonnet-medium.rerun2.tsv\" ]]"
check "no real claude was called" "[[ ! -e \"\$TMP/real-claude-called\" ]]"

# --- raters.sh: blind model raters, stub only ---------------------------------------
RW="$TMP/raters"
mkdir -p "$RW"
cp -R "$SW/cases" "$RW/cases"
{
  header
  row c1 seed tune "" "" "" "" cases/case-1/test/add.test.ts.fixture adds
  row c2 seed holdout "" "" "" "" cases/case-1/test/add.test.ts.fixture "flag restates #2"
  row c3 in-use holdout "" "" "" "" cases/case-2/flag.test.sh.fixture flag.test.sh "changed 2-3"
  row c4 in-use holdout "" "" "" "" cases/case-2/flag.test.sh.fixture "leaky one"
} >"$RW/labels.tsv"
# The claude stub: logs its arguments, cwd listing and prompt; FLAG when the
# test name holds "flag", else PASS; a "leaky" test's transcript reads the
# labels, which the guard must catch.
cat >"$TMP/rater-claude.sh" <<'EOF'
#!/usr/bin/env bash
n="$(date +%s)-$$-$RANDOM"
printf '%s\0' "$@" >"$STUB_DIR/rater-$n.args"
find . -type f -not -path './.git/*' | sort >"$STUB_DIR/rater-$n.ls"
prompt="${!#}"
label=PASS
grep -q '^Test: .*flag' <<<"$prompt" && label=FLAG
grep -q '^Test: leaky' <<<"$prompt" &&
  echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"../judge-calibration/labels.tsv"}}]}}'
reason="stub\\treason"
[[ $label == FLAG ]] && reason+=" {x: 1}" # a reason quoting code braces
jq -cn --arg r "Label: {\"label\": \"$label\", \"reason\": \"$reason\"}" '{type: "result", subtype: "success", is_error: false, result: $r}'
EOF
# The codex stub: `login status` per STUB_CODEX_LOGIN; exec writes UNKNOWN to -o.
cat >"$TMP/rater-codex.sh" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == login ]] && { [[ "${STUB_CODEX_LOGIN:-ok}" == ok ]]; exit; }
printf '%s\0' "$@" >"$STUB_DIR/codex-$(date +%s)-$$-$RANDOM.args"
out=""
while (($#)); do [[ "$1" == -o ]] && out="$2"; shift; done
echo '{"type":"turn.completed"}'
printf '{"label": "UNKNOWN", "reason": "codex stub"}\n' >"$out"
EOF
chmod +x "$TMP/rater-claude.sh" "$TMP/rater-codex.sh"
export RATER_CLAUDE_CMD="$TMP/rater-claude.sh" RATER_CODEX_CMD="$TMP/rater-codex.sh"
out="$(bash "$RATERS" "$RW/labels.tsv" 2>&1)"
check "raters.sh exits 1 when a row failed the guard (output: ${out:0:300})" "[[ $? -eq 1 ]]"
assert_contains "opus labels by id, reason on one line" "$(cat "$RW/raters/opus.tsv" 2>/dev/null)" \
  $'c1\tPASS\tstub reason\nc2\tFLAG\tstub reason {x: 1}\nc3\tFLAG\tstub reason {x: 1}\nc4\t\t'
assert_contains "the guard names its cause" "$(cat "$RW/raters/opus.tsv" 2>/dev/null)" "labels.tsv"
assert_contains "codex rates every row" "$(cut -f1,2 "$RW/raters/codex.tsv" 2>/dev/null)" $'c1\tUNKNOWN\nc2\tUNKNOWN\nc3\tUNKNOWN\nc4\tUNKNOWN'
rargs="$(for f in "$STUB_DIR"/rater-*.args; do tr '\0' '\n' <"$f"; done)"
assert_contains "opus runs as opus" "$rargs" $'-p\n--model\nopus'
assert_contains "opus has read-only tools" "$rargs" $'--tools\nRead,Grep,Glob'
check "opus reads only inside its case repository" "grep -qE '^Read\\(/.+/\\*\\*\\)\$' <<<\"\$rargs\""
assert_contains "no hooks" "$rargs" '{"disableAllHooks":true}'
assert_contains "no settings sources" "$rargs" $'--setting-sources\n\n'
assert_contains "no MCP servers" "$rargs" "--strict-mcp-config"
assert_contains "no slash commands" "$rargs" "--disable-slash-commands"
assert_contains "a transcript to guard" "$rargs" $'--output-format\nstream-json'
assert_contains "the prompt names the test file at its repository path" "$rargs" "Test file: test/add.test.ts"
assert_contains "the prompt names an ordinal past the first" "$rargs" "Test: flag restates (block 2 of the blocks with this name)"
assert_contains "the prompt gives the changed lines" "$rargs" "Changed lines: 2-3"
assert_contains "the prompt carries the judge's labels" "$rargs" "- FLAG: the expected value restates the implementation."
assert_contains "the prompt asks for one JSON object" "$rargs" '{"label"'
assert_not_contains "the rater never sees a case id" "$rargs" "case-1"
assert_not_contains "the rater never sees the labels file" "$rargs" "labels.tsv"
assert_not_contains "the rater never sees the calibration directory" "$rargs" "judge-calibration"
check "the rater's repository holds the case's files" "grep -qx './src/add.ts' \"\$STUB_DIR\"/rater-*.ls"
check "and nothing else" "! grep -qvx -e ./src/add.ts -e ./test/add.test.ts -e ./flag.test.sh \"\$STUB_DIR\"/rater-*.ls"
cargs="$(for f in "$STUB_DIR"/codex-*.args; do tr '\0' '\n' <"$f"; done)"
assert_contains "codex runs read-only in the case repository" "$cargs" $'exec\n-s\nread-only\n-C\n/'
for f in --ephemeral --skip-git-repo-check --json -o --ignore-user-config; do assert_contains "codex gets $f" "$cargs" $'\n'"$f"$'\n'; done
assert_contains "codex runs without web search" "$cargs" $'\n-c\nweb_search=disabled\n'
assert_contains "codex runs without connected apps" "$cargs" $'\n-c\nfeatures.apps=false\n'
assert_empty "labels.tsv is untouched until --merge" "$(col "$RW/labels.tsv" opus_label | tr -d '\n')"

out="$(bash "$RATERS" --merge "$RW/labels.tsv" 2>&1)"
check "--merge exits 0 (output: ${out:0:300})" "[[ $? -eq 0 ]]"
check "--merge copies opus labels by id, a failed row's stays empty" "[[ \$(col \"\$RW/labels.tsv\" opus_label | paste -sd, -) == PASS,FLAG,FLAG, ]]"
assert_contains "--merge copies codex labels by id" "$(col "$RW/labels.tsv" codex_label)" $'UNKNOWN\nUNKNOWN\nUNKNOWN\nUNKNOWN'
assert_empty "--merge leaves the user's column alone" "$(col "$RW/labels.tsv" reference_label | tr -d '\n')"
out="$(bash "$RATERS" "$RW/labels.tsv" 2>&1)"
check "raters.sh refuses once labels.tsv holds a label" "[[ $? -eq 1 ]]"
assert_contains "and says why" "$out" "already holds labels"

for col in opus_label codex_label; do
  for id in c1 c2 c3 c4; do setcol "$RW/labels.tsv" "$id" "$col" ""; done
done
rm -rf "$RW/raters" "$STUB_DIR"/codex-* "$STUB_DIR"/rater-*
out="$(STUB_CODEX_LOGIN=fail bash "$RATERS" "$RW/labels.tsv" 2>&1)"
assert_contains "codex logged out: opus rates alone" "$out" "codex"
check "no codex file when codex is logged out" "[[ -f \"\$RW/raters/opus.tsv\" && ! -e \"\$RW/raters/codex.tsv\" ]]"
check "codex exec never ran" "! compgen -G \"\$STUB_DIR/codex-*\" >/dev/null"
rm -rf "$RW/raters"
RATER_CODEX_CMD="$TMP/no-such-codex" bash "$RATERS" "$RW/labels.tsv" >/dev/null 2>&1
check "no codex on PATH: opus rates alone" "[[ -f \"\$RW/raters/opus.tsv\" && ! -e \"\$RW/raters/codex.tsv\" ]]"
check "no real codex was called" "[[ ! -e \"\$TMP/real-codex-called\" ]]"
check "no real claude was called by the raters" "[[ ! -e \"\$TMP/real-claude-called\" ]]"

# --- sample.sh refuses to redraw over any label, read by header name --------------
SP="$TMP/sample"
mkdir -p "$SP"
cp "$HERE/sample.sh" "$SP/"
awk -F'\t' -v OFS='\t' '{ print $14, $13, $12, $11, $10, $9, $8, $7, $6, $5, $4, $3, $2, $1 }' "$RW/labels.tsv" >"$SP/labels.tsv"
cp "$SP/labels.tsv" "$SP/before.tsv"
out="$(bash "$SP/sample.sh" "$TMP/no-repos" 2>&1)"
check "sample.sh passes an unlabeled set in any column order to the repository check" "[[ $? -eq 2 ]]"
assert_contains "it then looks for the repositories" "$out" "lacks"
check "a missing repository leaves labels.tsv as it was" "cmp -s \"\$SP/before.tsv\" \"\$SP/labels.tsv\""
setcol "$SP/labels.tsv" c2 codex_label PASS
out="$(bash "$SP/sample.sh" "$TMP/no-repos" 2>&1)"
check "sample.sh refuses a set with a codex label" "[[ $? -eq 1 ]]"
assert_contains "and says why" "$out" "already holds labels"

# --- the shipped set: labels.tsv and cases/ agree ---------------------------------
SHIP="$HERE/labels.tsv"
assert_contains "the shipped header names the raters' columns" "$(head -n 1 "$SHIP")" $'\treference_label\topus_label\tcodex_label\tjudge_verdict\t'
assert_not_contains "no single model rater column" "$(head -n 1 "$SHIP")" "model_label"
assert_not_contains "no adjudicated column" "$(head -n 1 "$SHIP")" "adjudicated_label"
assert_empty "every filled label cell is FLAG, PASS or UNKNOWN" \
  "$(for c in reference_label opus_label codex_label judge_verdict; do col "$SHIP" "$c"; done | grep -vxE 'FLAG|PASS|UNKNOWN|')"
missing="$(col "$SHIP" file | sort -u | while read -r f; do [[ -f "$HERE/$f" ]] || echo "$f"; done)"
assert_empty "every row's case file exists" "$missing"
unlabeled="$(for d in "$HERE"/cases/*/; do
  d="${d%/}"
  col "$SHIP" file | awk -v p="cases/${d##*/}/" 'index($0, p) == 1 { f = 1 } END { exit !f }' || echo "${d##*/}"
done)"
assert_empty "every case directory has a row" "$unlabeled"
fss="$(paste <(col "$SHIP" file) <(col "$SHIP" stratum) <(col "$SHIP" split))"
straddle="$(awk -F'\t' '{ s[$1] = s[$1] " " $3 } END { for (f in s) if (s[f] ~ /tune/ && s[f] ~ /holdout/) print f }' <<<"$fss")"
assert_empty "no case file has rows in both tune and holdout" "$straddle"
short="$(awk -F'\t' '{ n[$2]++; h[$2] += $3 == "holdout" } END { for (s in n) if (3 * h[s] < n[s]) print s }' <<<"$fss")"
assert_empty "each stratum holds out at least a third" "$short"

finish
