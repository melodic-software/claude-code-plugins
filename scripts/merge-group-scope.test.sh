#!/usr/bin/env bash
# test-scope: .github/workflows/pr-require-checks.yml
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/pr-require-checks.yml"
SUT="$ROOT/scripts/merge-group-scope.sh"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"
# shellcheck source=lib/ci-step.sh
. "$ROOT/scripts/lib/ci-step.sh"
# shellcheck source=test-git-helpers.sh
. "$ROOT/scripts/test-git-helpers.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

mkdir -p "$TMP_ROOT/bin"
cat >"$TMP_ROOT/bin/planner" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_PLANNER_LOG"
printf '%s\n' "${STUB_X_PLAN:-}"
exit "${STUB_X_RC:-0}"
EOF
chmod +x "$TMP_ROOT/bin/planner"

cat >"$TMP_ROOT/pr-plan.txt" <<'EOF'
bash=true
bash_plan={"0":["fixture/s1.test.sh"],"1":["fixture/s2.test.sh"]}
python=true
python_plan={"0":["fixture/test_t1.py"]}
node=true
node_plan={"0":["fixture/n1"]}
EOF

# shellcheck disable=SC2016 # the template's literal variable names
DESC_TEMPLATE="$(sed -n 's/^ *-f description="\(full run [^"]*\)" \\$/\1/p' "$WORKFLOW")"
# shellcheck disable=SC2016 # the template's literal variable names
if [[ "$DESC_TEMPLATE" == *'$GITHUB_RUN_ID'*'$GITHUB_SHA'* ]]; then
  ok "Mark Lanes records the run and the merge commit it tests in its ci-lanes marker"
else
  fail "Mark Lanes' ci-lanes description does not carry the run id and GITHUB_SHA: '$DESC_TEMPLATE'"
fi
marker() {
  local d="${DESC_TEMPLATE//\$GITHUB_RUN_ID/100}"
  printf '%s\n' "${d//\$GITHUB_SHA/$1}"
}

build() {
  REPO="$TMP_ROOT/repo-$RANDOM$RANDOM"
  mkdir -p "$REPO/lib" "$REPO/docs"
  git_init_test_repo "$REPO" || return 1
  local g=(git_test_config "$REPO")
  echo a >"$REPO/lib/shared.sh"
  echo a >"$REPO/docs/x.md"
  echo a >"$REPO/p.sh"
  "${g[@]}" add -A && "${g[@]}" commit -qm c0 && "${g[@]}" branch -qM main
  local c0
  c0="$("${g[@]}" rev-parse HEAD)"
  "${g[@]}" checkout -qb pr && echo b >"$REPO/p.sh" && "${g[@]}" commit -qam head
  HEAD_SHA="$("${g[@]}" rev-parse HEAD)"
  "${g[@]}" checkout -q --detach "$c0" && "${g[@]}" merge -q --no-ff -m tested pr
  MERGE="$("${g[@]}" rev-parse HEAD)"
  "${g[@]}" checkout -q main
  if [[ -n "$1" ]]; then echo b >"$REPO/$1" && "${g[@]}" commit -qam main; fi
  GROUP_BASE="$("${g[@]}" rev-parse HEAD)"
  "${g[@]}" checkout -q --detach && "${g[@]}" merge -q --no-ff -m group pr
}

pull_json() { jq -cn --arg h "${PULL_HEAD-$HEAD_SHA}" '{number: 7, head: {sha: $h}}'; }
statuses_json() {
  jq -cn --arg s "$1" --arg d "${2-$(marker "$MERGE")}" --arg login "${3:-github-actions[bot]}" '
    "https://github.com/o/r/actions/runs/100" as $u
    | [{id: 2, context: "ci-lanes", state: $s, description: "All lanes passed.", target_url: $u, creator: {login: $login}},
       {id: 1, context: "ci-lanes", state: "pending", description: $d, target_url: $u, creator: {login: "github-actions[bot]"}}]'
}

run_sut() {
  : >"$TMP_ROOT/planner.log"
  : >"$TMP_ROOT/summary.md"
  pull_json >"$TMP_ROOT/pull.json"
  rm -f "$TMP_ROOT/statuses.json"
  if [[ -n "${STATUSES-}" ]]; then printf '%s\n' "$STATUSES" >"$TMP_ROOT/statuses.json"; fi
  OUT="$(STUB_PLANNER_LOG="$TMP_ROOT/planner.log" "$SUT" --pull "$TMP_ROOT/pull.json" \
    --statuses "$TMP_ROOT/statuses.json" --group-base "${GROUP_BASE_ARG-$GROUP_BASE}" --pr-plan "${PR_PLAN-$TMP_ROOT/pr-plan.txt}" \
    --summary "$TMP_ROOT/summary.md" --planner "$TMP_ROOT/bin/planner" --repo "$REPO" 2>"$TMP_ROOT/err")"
  RC=$?
  ERR="$(cat "$TMP_ROOT/err")"
}

expect_line() {
  if [[ "$RC" -eq 0 && "$OUT" == "mq-scope: $2" ]]; then ok "$1"; else fail "$1: rc=$RC got '$OUT' want 'mq-scope: $2' err='$ERR'"; fi
}

FALLBACK_LINE='would-run=4 would-skip=0 whole-tree-would-skip=0 tree-identical=unknown x-files=unknown est-job-min-saved=0'

build "" || fail "fixture: build failed"
STATUSES="$(statuses_json success)"
run_sut
expect_line "X empty: every unit and every whole-tree job would skip" \
  'would-run=0 would-skip=4 whole-tree-would-skip=6 tree-identical=true x-files=0 est-job-min-saved=0.3 fallback=none'
if [[ ! -s "$TMP_ROOT/planner.log" ]]; then ok "X empty: the planner does not run"; else fail "X empty ran the planner: $(cat "$TMP_ROOT/planner.log")"; fi

build docs/x.md || fail "fixture: build failed"
STATUSES="$(statuses_json success)"
STUB_X_PLAN='bash_plan={"0":["fixture/s9.test.sh"]}' run_sut
expect_line "X disjoint from the PR's selection: every unit would skip, the whole-tree jobs run" \
  'would-run=0 would-skip=4 whole-tree-would-skip=0 tree-identical=false x-files=1 est-job-min-saved=0.3 fallback=none'
if [[ "$(cat "$TMP_ROOT/planner.log")" == "-- docs/x.md" ]]; then ok "the planner plans X, the files main changed"; else fail "planner got '$(cat "$TMP_ROOT/planner.log")'"; fi

build lib/shared.sh || fail "fixture: build failed"
STATUSES="$(statuses_json success)"
STUB_X_PLAN=$'bash_plan={"0":["fixture/s2.test.sh","fixture/s9.test.sh"]}\nnode_plan={"0":["fixture/n1"]}' run_sut
expect_line "X overlapping: only units both plans select would run" \
  'would-run=2 would-skip=2 whole-tree-would-skip=0 tree-identical=false x-files=1 est-job-min-saved=0.2 fallback=none'
# shellcheck disable=SC2016 # markdown code spans, not expansions
if grep -qF '| bash units | 2 | 1 | 1 |' "$TMP_ROOT/summary.md" && grep -qF -- '- bash: `fixture/s1.test.sh`' "$TMP_ROOT/summary.md" &&
  grep -qF -- '- python: `fixture/test_t1.py`' "$TMP_ROOT/summary.md" && grep -qF 'nothing skipped' "$TMP_ROOT/summary.md"; then
  ok "the step summary tables each lane and names the units that would skip"
else
  fail "summary: $(cat "$TMP_ROOT/summary.md")"
fi
STUB_X_RC=2 run_sut
expect_line "a planner that fails over X falls back" "$FALLBACK_LINE fallback=x-plan-failed"

STATUSES="$(statuses_json failure)"
run_sut
expect_line "no green PR run: the newest ci-lanes verdict is red" "$FALLBACK_LINE fallback=no-green-pr-run"
if [[ "$ERR" == *"fallback: today's plan (no-green-pr-run)"* ]] && grep -qF 'Fallback: today' "$TMP_ROOT/summary.md"; then
  ok "a fallback is logged as today's plan"
else
  fail "fallback log: err='$ERR' summary='$(cat "$TMP_ROOT/summary.md")'"
fi
STATUSES="$(statuses_json success "" someone)"
run_sut
expect_line "a success no workflow wrote is no green PR run" "$FALLBACK_LINE fallback=no-green-pr-run"
STATUSES="$(statuses_json success "full run 100 in flight")"
run_sut
expect_line "a green run whose marker names no merge commit falls back" "$FALLBACK_LINE fallback=no-tested-merge-recorded"
STATUSES="$(statuses_json success "$(marker 0123456789abcdef0123456789abcdef01234567)")"
run_sut
expect_line "a tested merge commit origin cannot serve falls back" "$FALLBACK_LINE fallback=tested-merge-fetch-refused"
STATUSES=""
run_sut
expect_line "unreadable statuses fall back" "$FALLBACK_LINE fallback=statuses-unreadable"
STATUSES="$(statuses_json success)"
PR_PLAN="$TMP_ROOT/none.txt" run_sut
expect_line "no plan for the group falls back with nothing to run" \
  'would-run=0 would-skip=0 whole-tree-would-skip=0 tree-identical=unknown x-files=unknown est-job-min-saved=0 fallback=pr-plan-missing'
GROUP_BASE_ARG=main run_sut
expect_line "a group base that is not a commit SHA falls back" "$FALLBACK_LINE fallback=group-base-invalid"
PULL_HEAD="" run_sut
expect_line "a queued pull request with no head SHA falls back" "$FALLBACK_LINE fallback=pull-unreadable"
build "" || fail "fixture: build failed"
STATUSES="$(jq -c --arg d "$(marker 0123456789abcdef0123456789abcdef01234567)" '
  [.[0] | .id = 3] + [{id: 2, context: "ci-lanes", state: "pending", description: $d,
    target_url: "https://github.com/o/r/actions/runs/200", creator: {login: "github-actions[bot]"}}] + [.[1]]' <<<"$(statuses_json success)")"
run_sut
expect_line "the tested merge comes from the green run's own marker, not another run's" \
  'would-run=0 would-skip=4 whole-tree-would-skip=6 tree-identical=true x-files=0 est-job-min-saved=0.3 fallback=none'

ORIGIN="$TMP_ROOT/origin-$RANDOM$RANDOM.git"
git_test_config "$REPO" update-ref refs/pull/7/merge "$MERGE"
git_test_config "$REPO" update-ref refs/heads/group HEAD
git_test_config "$TMP_ROOT" clone -q --mirror "$REPO" "$ORIGIN"
git_test_config "$ORIGIN" config uploadpack.allowFilter true
git_test_config "$ORIGIN" config uploadpack.allowAnySHA1InWant true
CLONE="$TMP_ROOT/clone-$RANDOM$RANDOM"
git_test_config "$TMP_ROOT" clone -q --filter=blob:none --branch group "file://$ORIGIN" "$CLONE"
if GIT_NO_LAZY_FETCH=1 git_test_config "$CLONE" cat-file -e "$MERGE^{commit}" 2>/dev/null; then fail "fixture: the partial clone already holds the tested merge"; fi
REPO="$CLONE"
STATUSES="$(statuses_json success)"
run_sut
expect_line "a partial clone without the tested merge fetches it from origin" \
  'would-run=0 would-skip=4 whole-tree-would-skip=6 tree-identical=true x-files=0 est-job-min-saved=0.3 fallback=none'

build lib/shared.sh || fail "fixture: build failed"
git_test_config "$REPO" checkout -q --detach "$GROUP_BASE~1"
echo side >"$REPO/docs/x.md"
git_test_config "$REPO" commit -qam side
git_test_config "$REPO" merge -q --no-ff -m tested-side pr
MERGE="$(git_test_config "$REPO" rev-parse HEAD)"
git_test_config "$REPO" checkout -q --detach "$GROUP_BASE"
git_test_config "$REPO" merge -q --no-ff -m group pr
STATUSES="$(statuses_json success)"
run_sut
expect_line "a PR run whose tested base is not under the group base falls back" "$FALLBACK_LINE fallback=tested-base-not-ancestor"

git_test_config "$REPO" checkout -q -b other "$GROUP_BASE~1"
echo other >"$REPO/p.sh"
git_test_config "$REPO" commit -qam other
git_test_config "$REPO" checkout -q --detach "$GROUP_BASE~1"
git_test_config "$REPO" merge -q --no-ff -m tested-other other
STATUSES="$(statuses_json success "$(marker "$(git_test_config "$REPO" rev-parse HEAD)")")"
git_test_config "$REPO" checkout -q --detach "$GROUP_BASE"
git_test_config "$REPO" merge -q --no-ff -m group pr
run_sut
expect_line "a recorded merge commit of another head falls back" "$FALLBACK_LINE fallback=tested-merge-not-of-head"

NAME='Log what a narrower merge-group run would skip'
step="$(ci_step::read "$WORKFLOW" "$NAME" "$TMP_ROOT/body.sh")" || ci_step::abort "$WORKFLOW" "$NAME"
if [[ "$step" == *"if: github.event_name == 'merge_group'"* && "$step" == *"continue-on-error: true"* ]]; then
  ok "the step runs only in a merge group and cannot fail Select Tests"
else
  fail "the step lost its merge_group condition or continue-on-error: $step"
fi
step_id="$(sed -n 's/^        id: //p' <<<"$step")"
if [[ -n "$step_id" ]] && ! grep -qE "steps\.$step_id\b" "$WORKFLOW" && ! grep -q GITHUB_OUTPUT "$TMP_ROOT/body.sh"; then
  ok "nothing reads the step and it writes no output, so no job skips on it"
else
  fail "the step can feed a gate (id '$step_id'): $(grep -nE "steps\.${step_id:-none}\b" "$WORKFLOW")"
fi
order="$(grep -nE "^  (select-tests|lint-repo):$|^      - name: (Plan the test lanes|$NAME|Log the API budget at the end)$" "$WORKFLOW" | cut -d: -f1 | head -5 | paste -sd' ')"
read -r job_line plan_line step_line log_line next_job <<<"$order"
if [[ -n "${next_job:-}" && "$job_line" -lt "$plan_line" && "$plan_line" -lt "$step_line" && "$step_line" -lt "$log_line" && "$log_line" -lt "$next_job" ]]; then
  ok "the step sits in select-tests after the plan it reads"
else
  fail "the step is not in select-tests after the plan (lines: $order)"
fi

test_harness::report
