#!/usr/bin/env bash
# Black-box tests for skill-rewrite-measure.sh. Each case points the script at a
# throwaway fixture tree (SKILL_REWRITE_MEASURE_ROOT) with stub check and score
# binaries, so the suite exercises the snapshot and compare logic, not
# check-skill.sh itself. Expected values are hand-counted from the fixture text.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/skill-rewrite-measure.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
fx="" # set by mk_fixture through a nameref

# Stub checker: exit code and optional WARN lines come from files in the fixture.
STUB_CHECK="$TMP_ROOT/stub-check.sh"
cat >"$STUB_CHECK" <<'EOF'
#!/usr/bin/env bash
[[ -f "$FIXTURE_ROOT/check.warns" ]] && cat "$FIXTURE_ROOT/check.warns"
exit "$(cat "$FIXTURE_ROOT/check.rc")"
EOF
# Stub scorer: prints the fixture's canned score JSON (the real scorer's shape).
STUB_SCORE="$TMP_ROOT/stub-score.sh"
cat >"$STUB_SCORE" <<'EOF'
#!/usr/bin/env bash
cat "$FIXTURE_ROOT/score.json"
EOF

# mk_fixture <out-var>: plugin "pl" with skills alpha (quoted description, 3-line
# body) and beta (folded description, 1-line body), a probes dir, check rc 0.
mk_fixture() {
  local -n _out="$1"
  _out="$(mktemp -d "$TMP_ROOT/fx.XXXXXX")"
  mkdir -p "$_out/plugins/pl/skills/alpha" "$_out/plugins/pl/skills/beta" "$_out/plugins/pl/probes"
  printf -- '---\nname: alpha\ndescription: '"'"'Hello world.'"'"'\n---\n# A\n\nbody\n' >"$_out/plugins/pl/skills/alpha/SKILL.md"
  printf -- '---\nname: beta\ndescription: >\n  Use when a\n  b\n---\nonly\n' >"$_out/plugins/pl/skills/beta/SKILL.md"
  printf '0' >"$_out/check.rc"
  set_score "$_out" 20 20
}

# set_score <root> <n> <ok>: alpha has n probe cases, ok of them correct.
set_score() {
  local root="$1" n="$2" okc="$3" i cases=""
  for ((i = 0; i < n; i++)); do
    [[ -n "$cases" ]] && cases+=","
    if ((i < okc)); then cases+='{"correct":true}'; else cases+='{"correct":false}'; fi
  done
  printf '{"skills":[{"skill":"pl:alpha","listing_file":"plugins/pl/skills/alpha/SKILL.md","cases":[%s]}]}\n' "$cases" >"$root/score.json"
}

# run <root> <args...>: sets OUT and RC.
run() {
  local root="$1"
  shift
  OUT="$(FIXTURE_ROOT="$root" SKILL_REWRITE_MEASURE_ROOT="$root" \
    SKILL_REWRITE_MEASURE_CHECK_BIN="$STUB_CHECK" SKILL_REWRITE_MEASURE_SCORE_BIN="$STUB_SCORE" \
    bash "$SCRIPT" --plugin pl "$@" 2>&1)"
  RC=$?
}

expect_rc() { # <want> <name>
  if [[ "$RC" == "$1" ]]; then ok "$2"; else bad "$2" "exit $RC, want $1; output: $OUT"; fi
}
expect_has() { # <needle> <name>
  if [[ "$OUT" == *"$1"* ]]; then ok "$2"; else bad "$2" "missing '$1' in: $OUT"; fi
}

# --- dry-run lists skills and writes nothing ---------------------------------
mk_fixture fx
run "$fx" --phase before --dry-run
expect_rc 0 "dry-run exits 0"
expect_has "- alpha" "dry-run lists alpha"
expect_has "- beta" "dry-run lists beta"
expect_has "check-skill.sh" "dry-run names the check command"
if [[ -e "$fx/.work" ]]; then bad "dry-run writes nothing" ".work exists"; else ok "dry-run writes nothing"; fi

# --- snapshot values ----------------------------------------------------------
mk_fixture fx
run "$fx" --phase before
expect_rc 0 "before snapshot exits 0"
tsv="$fx/.work/skill-rewrite/pl/before.tsv"
# "Hello world." is 12 characters; the folded "Use when a" + "b" joins to "Use when a b" (12).
alpha_row="$(awk -F'\t' '$1=="skill" && $2=="alpha" { print $3 "|" $4 "|" $5 }' "$tsv")"
beta_row="$(awk -F'\t' '$1=="skill" && $2=="beta" { print $3 "|" $4 "|" $5 }' "$tsv")"
if [[ "$alpha_row" == "12|3|1" ]]; then ok "alpha: quoted description 12 chars, 3 body lines, lexical 1"; else bad "alpha row" "$alpha_row"; fi
if [[ "$beta_row" == "12|1|n/a" ]]; then ok "beta: folded description 12 chars, 1 body line, no probe n/a"; else bad "beta row" "$beta_row"; fi

printf 'WARN: one\nWARN: two\nINFO: x\n' >"$fx/check.warns"
run "$fx" --phase after
root_row="$(awk -F'\t' '$1=="root" { print $4 "|" $5 }' "$fx/.work/skill-rewrite/pl/after.tsv")"
if [[ "$root_row" == "0|2" ]]; then ok "root row records check exit code and WARN count"; else bad "root row" "$root_row"; fi

# --- happy path: unchanged tree compares clean --------------------------------
mk_fixture fx
run "$fx" --phase before
run "$fx" --phase after
run "$fx" --compare
expect_rc 0 "compare of an unchanged tree exits 0"
expect_has "| alpha |" "compare prints a per-skill row"

# --- negative: check root turns non-zero --------------------------------------
mk_fixture fx
run "$fx" --phase before
printf '2' >"$fx/check.rc"
run "$fx" --phase after
run "$fx" --compare
expect_rc 1 "compare exits 1 when the root check turns non-zero"
expect_has "TRIPWIRE" "compare names the tripwire"

# --- lexical drop beyond the threshold fails; within it passes ----------------
mk_fixture fx
run "$fx" --phase before
set_score "$fx" 20 10
run "$fx" --phase after
run "$fx" --compare
expect_rc 1 "compare exits 1 when a lexical score falls 1 -> 0.5"

mk_fixture fx
run "$fx" --phase before
set_score "$fx" 20 19
run "$fx" --phase after
run "$fx" --compare
expect_rc 0 "compare exits 0 for a 0.05 drop (1 -> 0.95, not larger than the threshold)"

# --- usage errors -------------------------------------------------------------
mk_fixture fx
run "$fx" --compare
expect_rc 2 "compare without snapshots exits 2"
run "$fx" --phase sideways
expect_rc 2 "bad --phase exits 2"

run "$fx" --plugin .. --phase before
expect_rc 2 "a --plugin of .. is refused"

# --- untrusted names never reach shell arithmetic -----------------------------
mk_fixture fx
mkdir -p "$fx/plugins/pl/skills/"$'evil\trc[$(touch PWNED)]\t1'
printf -- '---\nname: evil\ndescription: x\n---\nb\n' >"$fx/plugins/pl/skills/"$'evil\trc[$(touch PWNED)]\t1'/SKILL.md
run "$fx" --phase before --dry-run
if [[ "$OUT" == *"- evil"* ]]; then bad "a skill dir with an unsafe name is skipped" "$OUT"; else ok "a skill dir with an unsafe name is skipped"; fi
expect_has "skipping skill dir with an unsafe name" "the skip is reported, not silent"
run "$fx" --phase before
run "$fx" --phase after
(cd "$fx" && FIXTURE_ROOT="$fx" SKILL_REWRITE_MEASURE_ROOT="$fx" SKILL_REWRITE_MEASURE_CHECK_BIN="$STUB_CHECK" \
  SKILL_REWRITE_MEASURE_SCORE_BIN="$STUB_SCORE" bash "$SCRIPT" --plugin pl --compare >/dev/null 2>&1)
if [[ -e "$fx/PWNED" ]]; then bad "compare never evaluates a skill name" "payload ran"; else ok "compare never evaluates a skill name"; fi

mk_fixture fx
run "$fx" --phase before
run "$fx" --phase after
printf 'skill\tx\trc[0]\t1\tn/a\tsha\n' >>"$fx/.work/skill-rewrite/pl/after.tsv"
run "$fx" --compare
expect_rc 2 "compare refuses a snapshot row with a non-numeric field"

# --- help carries the runbook and the script never calls claude -----------------
OUT="$(bash "$SCRIPT" --help 2>&1)"
RC=$?
expect_rc 0 "--help exits 0"
expect_has "emit-plugin-eval" "help names emit-plugin-eval"
expect_has "claude plugin eval" "help names claude plugin eval"
expect_has "/docs-hygiene:compress compare ORIG_DIR NEW_DIR" "help names the compress compare step"
if grep -Eq '(^|[^A-Za-z_-])claude[[:space:]]' < <(grep -v '^[[:space:]]*#' "$SCRIPT"); then
  bad "script never invokes claude" "executable line mentions claude"
else
  ok "script never invokes claude"
fi

test_harness::report
