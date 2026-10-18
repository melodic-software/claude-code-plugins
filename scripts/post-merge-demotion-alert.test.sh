#!/usr/bin/env bash
# Runs the `File or comment on the demotion issue` step body of
# .github/workflows/post-merge-demotion-alert.yml under the shell Actions gives
# a step with no `shell:` (bash -e), against a stub `gh`.
#
# The step files the demotion record the babysit post-merge check and the
# merge-policy reader also use: an issue by github-actions[bot] whose body's
# first line is `<!-- babysit-merge-demotion sha=<S> signal=<name> -->`,
# labeled needs-human, one per (signal, SHA). When no merge in the failing range
# was enqueued by merge.agent-identity, it files the post-merge-failure record
# instead (`<!-- post-merge-failure sha=<S> signal=<name> -->`, needs-human, no
# demotion); anything unproven demotes. A matching record of either kind gets a comment
# instead; a run that is not a failed scheduled or dispatched full run, or a
# failed canary push run, on main files nothing. A full run's first failed
# attempt is re-run instead, and a later one files only for checks green on
# main's previous run of the same event; the gitleaks gate files nothing.
# test-scope: .github/workflows/post-merge-demotion-alert.yml
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/post-merge-demotion-alert.yml"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

NAME='File or comment on the demotion issue'
step="$(awk -v name="      - name: $NAME" '$0 == name { on = 1; print; next }
  on && /^      - / { exit }
  on { print }' "$WORKFLOW" 2>/dev/null)"
awk '/^        run: \|$/ { on = 1; next }
  on && /^          / { print substr($0, 11); next }
  on && /^[[:blank:]]*$/ { print ""; next }
  on { exit }' <<<"$step" >"$TMP_ROOT/body.sh"

if [[ ! -s "$TMP_ROOT/body.sh" ]]; then
  fail "no '$NAME' step with a run: | body in $WORKFLOW"
  test_harness::report
  exit 1
fi

# --- Workflow shape -----------------------------------------------------------
# Trigger names come from the two workflows' own `name:` lines.
full_name="$(sed -n 's/^name: //p' "$ROOT/.github/workflows/pr-require-checks.yml")"
canary_name="$(sed -n 's/^name: //p' "$ROOT/.github/workflows/post-merge-detect-silent-revert.yml")"
triggers="$(awk '/^  workflow_run:/ { on = 1; next } on && /^  [a-z]/ { exit } on' "$WORKFLOW")"
if [[ "$triggers" == *"workflows: [$full_name, $canary_name]"* && "$triggers" == *"types: [completed]"* ]]; then
  ok "workflow_run fires on completed $full_name and $canary_name runs"
else
  fail "workflow_run does not name both workflows: '$triggers'"
fi
if grep -q '^permissions: {}$' "$WORKFLOW" &&
  [[ "$(grep -oE '^ +[a-z-]+: (read|write)( |$)' "$WORKFLOW" | sed 's/^ *//; s/ *$//' | sort | paste -sd ' ')" == 'actions: write checks: read contents: read issues: write pull-requests: read' ]]; then
  ok "the token holds issues: write, actions: write and checks, contents and pull-requests read, nothing else"
else
  fail "permissions are not exactly issues: write, actions: write, checks: read, contents: read, pull-requests: read"
fi
if grep -qE '^[[:space:]]*-?[[:space:]]*uses:' "$WORKFLOW"; then
  fail "the workflow runs an action; it must check out and run nothing"
else
  ok "no action and no checkout"
fi
if grep -qF "\${{" "$TMP_ROOT/body.sh"; then
  fail "the step body interpolates an expression; pass it through env"
else
  ok "the step body takes every event field through env"
fi

# --- Step body ----------------------------------------------------------------
# The stub logs one line per call. A POST's -f fields go to post.<n>, one per
# line (a PATCH too). A GET applies its --jq filter to the matching fixture with jq, as gh does.
mkdir -p "$TMP_ROOT/bin"
cat >"$TMP_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
args=("$@") filter='' method=GET endpoint='' fields=()
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[i]}" in
    --jq) filter="${args[i + 1]}"; i=$((i + 1)) ;;
    -X) method="${args[i + 1]}"; i=$((i + 1)) ;;
    -f) fields+=("${args[i + 1]}"); i=$((i + 1)) ;;
    -H) i=$((i + 1)) ;;
    --paginate|api) ;;
    *) endpoint="${args[i]}" ;;
  esac
done
printf '%s %s\n' "$method" "$endpoint" >>"$STUB_DIR/log"
n=$(wc -l <"$STUB_DIR/log")
if [[ "$method" != GET && "${STUB_RERUN_POST_FAIL:-}" == 1 && "$endpoint" == */rerun-failed-jobs ]]; then
  printf '%s %s\n' "$method" "$endpoint" >>"$STUB_DIR/failed"
  exit 1
fi
if [[ "$method" != GET ]]; then
  printf '%s\n' "${fields[@]}" >"$STUB_DIR/post.$n"
  printf '{"number": 900}\n'
  exit 0
fi
[[ "${STUB_FAIL_READ:-}" != 1 ]] || exit 1
case "$endpoint" in
  */comments*) fixture="$STUB_DIR/comments.json" ;;
  */jobs*)
    fixture="$(sed -E 's#.*/runs/([0-9]+)/attempts/([0-9]+)/jobs.*#jobs.\1.\2.json#' <<<"$endpoint")"
    fixture="$STUB_DIR/$fixture"
    [[ -f "$fixture" ]] || fixture="$STUB_DIR/jobs.default.json"
    ;;
  */check-runs/*)
    fixture="$STUB_DIR/annotations.$(sed -E 's#.*/check-runs/([0-9]+)/.*#\1#' <<<"$endpoint").json"
    [[ -f "$fixture" ]] || fixture="$STUB_DIR/annotations.none.json"
    ;;
  */actions/workflows/*status=success*) fixture="$STUB_DIR/green.json" ;;
  */actions/workflows/*) fixture="$STUB_DIR/runs.json" ;;
  */compare/*) fixture="$STUB_DIR/compare.json" ;;
  */contents/*) exec cat "$STUB_DIR/pipeline.yaml" ;;
  graphql)
    printf '%s\n' "${fields[@]}" >"$STUB_DIR/graphql.$n"
    [[ "${STUB_FAIL_GRAPHQL:-}" != 1 ]] || exit 1
    fixture="$STUB_DIR/graphql.json"
    ;;
  */actions/runs/[0-9]*)
    # The re-run's attempt 2: in progress until poll STUB_POLLS, then
    # STUB_RERUN (never: it does not finish).
    polls=$(($(cat "$STUB_DIR/polls" 2>/dev/null || echo 0) + 1))
    echo "$polls" >"$STUB_DIR/polls"
    fixture="$STUB_DIR/rerun.json"
    if [[ "${STUB_RERUN:-never}" != never && "$polls" -ge "${STUB_POLLS:-2}" ]]; then
      jq -n --arg c "$STUB_RERUN" '{run_attempt: 2, status: "completed", conclusion: $c}' >"$fixture"
    else
      jq -n '{run_attempt: 2, status: "in_progress", conclusion: null}' >"$fixture"
    fi
    ;;
  *) fixture="$STUB_DIR/issues.json" ;;
esac
RUN_SHA="${STUB_RUN_SHA:-}" RUN_CREATED="${STUB_RUN_CREATED:-}" jq -r "$filter" "$fixture"
EOF
chmod +x "$TMP_ROOT/bin/gh"

SHA=0123456789abcdef0123456789abcdef01234567
OTHER=89abcdef0123456789abcdef0123456789abcdef
RUN_URL=https://github.com/o/r/actions/runs/4242
FULL="$full_name"
CANARY="$canary_name"

# issue <number> <body> [pull_request] [state] -> one REST issue object
issue() {
  jq -n --argjson n "$1" --arg body "$2" --arg pr "${3:-}" --arg state "${4:-open}" \
    '{number: $n, state: $state, body: $body, user: {login: "github-actions[bot]", type: "Bot"}}
     + (if $pr == "" then {} else {pull_request: {url: $pr}} end)'
}

CREATED=2026-10-17T16:26:00Z

# job <id> <name> [failed-step...] -> one failed job of the jobs API
job() {
  local id="$1" name="$2"
  shift 2
  jq -n --argjson id "$id" --arg name "$name" '$ARGS.positional as $failed
    | {id: $id, name: $name, conclusion: "failure",
       steps: ([{name: "Set up job", conclusion: "success"}] + [$failed[] | {name: ., conclusion: "failure"}])}' \
    --args "$@"
}

# baseline_run <id> <conclusion> [sha] -> one completed run of the runs API
baseline_run() {
  jq -n --argjson id "$1" --arg c "$2" --arg sha "${3:-$OTHER}" \
    '{id: $id, run_attempt: 1, conclusion: $c, status: "completed", head_branch: "main",
      head_sha: $sha, created_at: "2026-10-17T15:00:00Z"}'
}

# commit <sha> <parent> <author> <subject> -> one commit of the compare API
commit() {
  jq -n --arg sha "$1" --arg p "$2" --arg a "$3" --arg s "$4" \
    '{sha: $sha, parents: [{sha: $p}], author: {login: $a}, commit: {message: ($s + "\n\nbody")}}'
}

# green_run <sha> [event] [created_at] -> one successful run on main before the failing one
green_run() {
  jq -n --arg sha "$1" --arg e "${2:-workflow_dispatch}" --arg t "${3:-2026-10-17T14:00:00Z}" \
    '{id: 4000, event: $e, conclusion: "success", head_branch: "main", head_sha: $sha, created_at: $t}'
}

# Fixtures a test sets before run_step: JOBS (this attempt), BASE_JOBS (run
# 4141 attempt 1), RUNS (the baseline listing), ANNOTATIONS_<id>, GREEN (the
# last green full run listing; default one at OTHER), COMPARE (commits from
# the green SHA to the failing one; default SHA alone).
# run_step <workflow> <event> <conclusion> <branch> <head-repo> <sha> <issues-json> [comments-json]
run_step() {
  rm -rf "$TMP_ROOT/stub"
  mkdir -p "$TMP_ROOT/stub"
  printf '%s\n' "$7" >"$TMP_ROOT/stub/issues.json"
  printf '%s\n' "${8:-[]}" >"$TMP_ROOT/stub/comments.json"
  printf '{"jobs": [%s]}\n' "$(job 1 test-bash 'Run the bash tests')" >"$TMP_ROOT/stub/jobs.default.json"
  printf '{"jobs": [%s]}\n' "${JOBS-$(job 1 test-bash 'Run the bash tests')}" >"$TMP_ROOT/stub/jobs.4242.${ATTEMPT:-2}.json"
  printf '{"jobs": [%s]}\n' "${BASE_JOBS:-}" >"$TMP_ROOT/stub/jobs.4141.1.json"
  printf '{"workflow_runs": [%s]}\n' "${RUNS:-}" >"$TMP_ROOT/stub/runs.json"
  printf '{"workflow_runs": [%s]}\n' "${GREEN-$(green_run "$OTHER")}" >"$TMP_ROOT/stub/green.json"
  printf '{"commits": [%s]}\n' "${COMPARE-$(commit "$SHA" "$OTHER" octocat 'fix: a change (#1234)')}" >"$TMP_ROOT/stub/compare.json"
  printf '[]\n' >"$TMP_ROOT/stub/annotations.none.json"
  printf '%s\n' "${ANNOTATIONS_7:-[]}" >"$TMP_ROOT/stub/annotations.7.json"
  if [[ -n "${PIPELINE:-}" ]]; then
    printf '%s\n' "$PIPELINE" >"$TMP_ROOT/stub/pipeline.yaml"
  fi
  local graphql="${GRAPHQL:-}"
  printf '%s\n' "${graphql:-null}" >"$TMP_ROOT/stub/graphql.json"
  : >"$TMP_ROOT/stub/log"
  OUT="$(PATH="$TMP_ROOT/bin:$PATH" STUB_DIR="$TMP_ROOT/stub" STUB_FAIL_READ="${FAIL_READ:-}" \
    STUB_FAIL_GRAPHQL="${FAIL_GRAPHQL:-}" \
    STUB_RUN_SHA="$6" STUB_RUN_CREATED="$CREATED" STUB_RERUN="${RERUN:-}" POLL_SECONDS=0 \
    STUB_RERUN_POST_FAIL="${RERUN_POST_FAIL:-}" RUN_TRIGGERING_ACTOR="${STARTER:-octocat}" \
    GH_TOKEN=x GITHUB_REPOSITORY=o/r RUN_WORKFLOW="$1" RUN_EVENT="$2" RUN_CONCLUSION="$3" \
    RUN_BRANCH="$4" RUN_REPO="$5" RUN_SHA="$6" RUN_URL="$RUN_URL" RUN_ATTEMPT="${ATTEMPT:-2}" \
    RUN_ID=4242 RUN_WORKFLOW_ID=77 RUN_CREATED="$CREATED" \
    RUN_COMMIT_MESSAGE="${COMMIT_MESSAGE:-fix: a change (#1234)}" \
    bash -e "$TMP_ROOT/body.sh" 2>&1)" && RC=0 || RC=$?
  LOG="$(cat "$TMP_ROOT/stub/log")"
}

posts() { grep -c '^POST ' <<<"$LOG"; }
post_fields() { cat "$TMP_ROOT/stub/post.$(grep -n '^POST ' <<<"$LOG" | head -1 | cut -d: -f1)"; }

# files <label> <signal> <workflow> <event> <issues-json>
files() {
  local label="$1" signal="$2" fields body
  run_step "$3" "$4" "${CONCLUSION:-failure}" main o/r "$SHA" "$5"
  if [[ "$RC" -ne 0 ]]; then
    fail "$label: rc=$RC out='$OUT'"
    return
  fi
  if [[ "$(posts)" -ne 1 ]] || ! grep -qx 'POST repos/o/r/issues' <<<"$LOG"; then
    fail "$label: expected one issue POST, log='$LOG'"
    return
  fi
  fields="$(post_fields)"
  body="${fields#*body=}"
  if [[ "$body" != "<!-- babysit-merge-demotion sha=$SHA signal=$signal -->"$'\n'* ]]; then
    fail "$label: body's first line is not the marker: '${body%%$'\n'*}'"
  elif [[ "$body" != *"git revert $SHA"* || "$body" == *"revert -m"* ]]; then
    fail "$label: body lacks 'git revert $SHA'"
  elif [[ "$body" != *"- Failing run: $RUN_URL/attempts/${ATTEMPT:-2}"$'\n'* ]]; then
    fail "$label: body lacks the failing attempt's link"
  elif [[ "$body" != *"https://github.com/o/r/pull/1234"* ]]; then
    fail "$label: body lacks the pull request link"
  elif ! grep -qx 'labels\[\]=needs-human' <<<"$fields"; then
    fail "$label: issue is not labeled needs-human: '$fields'"
  elif [[ "$signal" != canary && ("$body" != *"- Main at the failing run: \`$SHA\`"* || "$body" == *"Merge commit"*) ]]; then
    fail "$label: a $signal record must name the SHA as main at the failing run"
  elif [[ "$signal" == canary && "$body" != *"- Merge commit: \`$SHA\`"* ]]; then
    fail "$label: body does not name the merge commit"
  else
    ok "$label"
  fi
}

# quiet <label> <workflow> <event> <conclusion> <branch> <head-repo>
quiet() {
  ATTEMPT="${ATTEMPT:-1}" run_step "$2" "$3" "$4" "$5" "$6" "$SHA" '[]'
  if [[ "$RC" -ne 0 ]]; then
    fail "$1: rc=$RC out='$OUT'"
  elif [[ -n "$LOG" ]]; then
    fail "$1: expected no gh call, log='$LOG'"
  else
    ok "$1"
  fi
}

MARKER="<!-- babysit-merge-demotion sha=$SHA signal=schedule -->"

files "failed scheduled full run on main files a schedule record" schedule "$FULL" schedule '[]'
files "failed dispatched full run on main files a dispatch record" dispatch "$FULL" workflow_dispatch '[]'
files "failed canary push run on main files a canary record" canary "$CANARY" push '[]'
if grep -qE 'status=success|/compare/' <<<"$LOG"; then
  fail "a canary record looked up a range: log='$LOG'"
else
  ok "a canary record looks up no range"
fi
files "a record for another signal on the same SHA is not a match" schedule "$FULL" schedule \
  "[$(issue 7 "<!-- babysit-merge-demotion sha=$SHA signal=canary -->")]"
files "a record for another SHA is not a match" schedule "$FULL" schedule \
  "[$(issue 7 "<!-- babysit-merge-demotion sha=$OTHER signal=schedule -->")]"
files "a marker below the first line is not a record" schedule "$FULL" schedule \
  "[$(issue 7 "intro"$'\n'"$MARKER")]"
files "a pull request carrying the marker is not a record" schedule "$FULL" schedule \
  "[$(issue 7 "$MARKER" https://api.github.com/repos/o/r/pulls/7)]"

run_step "$FULL" schedule failure main o/r "$SHA" "[$(issue 3 "x"), $(issue 41 "$MARKER"$'\n\nbody')]"
if [[ "$RC" -eq 0 && "$(posts)" -eq 1 ]] && grep -qx 'POST repos/o/r/issues/41/comments' <<<"$LOG" &&
  [[ "$(post_fields)" == "body=The post-merge check found this failure again: $RUN_URL/attempts/2" ]]; then
  ok "an existing record gets a comment with the attempt link, not a second issue"
else
  fail "existing record: rc=$RC log='$LOG' out='$OUT'"
fi

run_step "$FULL" schedule failure main o/r "$SHA" "[$(issue 41 "  "$'\n'"$MARKER"$'\r\nbody')]"
if [[ "$RC" -eq 0 && "$(posts)" -eq 1 ]] && grep -qx 'POST repos/o/r/issues/41/comments' <<<"$LOG"; then
  ok "leading blank lines and a CRLF ending still match the marker line"
else
  fail "whitespace around the marker: rc=$RC log='$LOG'"
fi

FILED="$MARKER"$'\n\n'"- Failing run: $RUN_URL/attempts/2"$'\n'
run_step "$FULL" schedule failure main o/r "$SHA" "[$(issue 41 "$FILED")]"
if [[ "$RC" -eq 0 && "$(posts)" -eq 0 ]]; then
  ok "a record that already names this attempt gets no comment"
else
  fail "record already naming the attempt: rc=$RC log='$LOG'"
fi

ATTEMPT=10 run_step "$FULL" schedule failure main o/r "$SHA" "[$(issue 41 "$FILED" '' closed)]"
if [[ "$RC" -eq 0 && "$(posts)" -eq 1 ]] && grep -qx 'PATCH repos/o/r/issues/41' <<<"$LOG" &&
  [[ "$(post_fields)" == *"$RUN_URL/attempts/10" ]]; then
  ok "a later failing attempt of the filed run reopens and comments (attempt 10 is not attempt 2)"
else
  fail "later failing attempt of the filed run: rc=$RC log='$LOG' out='$OUT'"
fi

# comment <login> <body> -> one REST issue comment object
comment() {
  jq -n --arg login "$1" --arg body "$2" '{user: {login: $login}, body: $body}'
}

run_step "$FULL" schedule failure main o/r "$SHA" "[$(issue 41 "$MARKER")]" \
  "[$(comment someone "$RUN_URL"), $(comment 'github-actions[bot]' "The post-merge check found this failure again: $RUN_URL/attempts/2")]"
if [[ "$RC" -eq 0 && "$(posts)" -eq 0 ]]; then
  ok "a record whose own comments already name this run gets no comment"
else
  fail "comment already naming the run: rc=$RC log='$LOG'"
fi

run_step "$FULL" schedule failure main o/r "$SHA" "[$(issue 41 "$MARKER")]" "[$(comment someone "seen $RUN_URL")]"
if [[ "$RC" -eq 0 && "$(posts)" -eq 1 ]] && grep -qx 'POST repos/o/r/issues/41/comments' <<<"$LOG"; then
  ok "a comment by anyone else naming the run does not suppress the sighting"
else
  fail "foreign comment naming the run: rc=$RC log='$LOG'"
fi

run_step "$FULL" schedule failure main o/r "$SHA" "[$(issue 41 "$MARKER" '' closed)]"
patch_line="$(grep -n '^PATCH repos/o/r/issues/41$' <<<"$LOG" | cut -d: -f1)"
comment_line="$(grep -n '^POST repos/o/r/issues/41/comments$' <<<"$LOG" | cut -d: -f1)"
if [[ "$RC" -eq 0 && -n "$patch_line" && -n "$comment_line" && "$patch_line" -lt "$comment_line" ]] &&
  grep -qx 'state=open' "$TMP_ROOT/stub/post.$patch_line" && [[ "$(posts)" -eq 1 ]]; then
  ok "a closed record is reopened, then commented, on a new failure"
else
  fail "closed record: rc=$RC log='$LOG' out='$OUT'"
fi

run_step "$FULL" schedule failure main o/r "$SHA" "[$(issue 41 "$MARKER" '' open)]"
if [[ "$RC" -eq 0 ]] && ! grep -q '^PATCH' <<<"$LOG"; then
  ok "an open record is not patched"
else
  fail "open record patched: log='$LOG'"
fi

ATTEMPT=3 run_step "$FULL" schedule success main o/r "$SHA" "[$(issue 41 "$FILED" '' closed)]"
if [[ "$RC" -eq 0 && "$(posts)" -eq 1 ]] && grep -qx 'POST repos/o/r/issues/41/comments' <<<"$LOG" &&
  [[ "$(post_fields)" == "body=re-run passed: $RUN_URL/attempts/3" ]] && ! grep -q '^PATCH' <<<"$LOG"; then
  ok "a re-run that passes comments on the record without reopening it"
else
  fail "re-run passed: rc=$RC log='$LOG' out='$OUT'"
fi

ATTEMPT=3 run_step "$FULL" schedule success main o/r "$SHA" "[$(issue 41 "$FILED")]" \
  "[$(comment 'github-actions[bot]' "re-run passed: $RUN_URL/attempts/3")]"
if [[ "$RC" -eq 0 && "$(posts)" -eq 0 ]]; then
  ok "a re-run pass already recorded is not commented twice"
else
  fail "duplicate re-run pass: rc=$RC log='$LOG'"
fi

ATTEMPT=4 run_step "$FULL" schedule failure main o/r "$SHA" "[$(issue 41 "$FILED" '' closed)]" \
  "[$(comment 'github-actions[bot]' "re-run passed: $RUN_URL/attempts/3")]"
if [[ "$RC" -eq 0 && "$(posts)" -eq 1 ]] && grep -qx 'PATCH repos/o/r/issues/41' <<<"$LOG" &&
  grep -qx 'POST repos/o/r/issues/41/comments' <<<"$LOG"; then
  ok "a failure after a passing re-run of the same run reopens and comments"
else
  fail "failure after re-run passed: rc=$RC log='$LOG' out='$OUT'"
fi

ATTEMPT=2 run_step "$FULL" schedule success main o/r "$SHA" \
  "[$(issue 41 "$MARKER"$'\n\n'"- Failing run: https://github.com/o/r/actions/runs/42421/attempts/1")]"
if [[ "$RC" -eq 0 && "$(posts)" -eq 0 ]]; then
  ok "a re-run pass is not noted on a record that names no failure of this run"
else
  fail "re-run pass on an unrelated record: rc=$RC log='$LOG'"
fi

ATTEMPT=2 run_step "$FULL" schedule success main o/r "$SHA" \
  "[$(issue 41 "$MARKER"$'\n\n'"- Failing run: https://github.com/o/r/actions/runs/1/attempts/1")]" \
  "[$(comment 'github-actions[bot]' "The post-merge check found this failure again: $RUN_URL/attempts/1")]"
if [[ "$RC" -eq 0 && "$(posts)" -eq 1 ]] && [[ "$(post_fields)" == "body=re-run passed: $RUN_URL/attempts/2" ]]; then
  ok "a re-run pass is noted when a filer comment recorded this run's failure"
else
  fail "re-run pass after a commented failure: rc=$RC log='$LOG'"
fi

ATTEMPT=2 run_step "$CANARY" push success main o/r "$SHA" '[]'
if [[ "$RC" -eq 0 ]] && ! grep -qE '^(POST|PATCH)' <<<"$LOG"; then
  ok "a re-run that passes with no record files nothing"
else
  fail "re-run pass without record: rc=$RC log='$LOG'"
fi

if grep -q 'creator=github-actions%5Bbot%5D' <<<"$LOG" && grep -q 'state=all' <<<"$LOG"; then
  ok "records are read by their filer, open and closed"
else
  fail "the issue read is not by creator github-actions[bot] over every state: '$LOG'"
fi

FAIL_READ=1 run_step "$FULL" schedule failure main o/r "$SHA" '[]'
if [[ "$RC" -ne 0 && "$(posts)" -eq 0 ]]; then
  ok "an unreadable issue list fails the job and files nothing"
else
  fail "unreadable issue list: rc=$RC log='$LOG'"
fi

COMMIT_MESSAGE=$'chore: no pull request number\n\n(#99) in the body' run_step "$FULL" schedule failure main o/r "$SHA" '[]'
if [[ "$RC" -eq 0 && "$(posts)" -eq 1 ]] && [[ "$(post_fields)" != *"/pull/"* ]]; then
  ok "a head commit with no (#N) subject links no pull request"
else
  fail "no PR number: rc=$RC log='$LOG' fields='$(post_fields 2>/dev/null)'"
fi

# --- The range since main's last green full run --------------------------------
run_step "$FULL" workflow_dispatch failure main o/r "$SHA" '[]'
body="$(post_fields)"
if [[ "$RC" -eq 0 && "$body" == *"- Pull request: https://github.com/o/r/pull/1234"* &&
  "$body" == *"git revert $SHA"* && "$body" == *"title=Post-merge dispatch failure after #1234: unattended"* &&
  "$body" != *"attributed to the range"* ]] &&
  grep -q "^GET repos/o/r/compare/$OTHER\.\.\.$SHA$" <<<"$LOG"; then
  ok "one merge since the last green full run keeps the single pull request and its revert"
else
  fail "one-merge range: rc=$RC log='$LOG' fields='$body'"
fi

MID=fedcba9876543210fedcba9876543210fedcba98
COMPARE="$(commit "$MID" "$OTHER" alice 'feat(planning): a join prompt (#8259)'), $(commit "$SHA" "$MID" bob 'ci: record suite times (#8260)')" \
  run_step "$FULL" workflow_dispatch failure main o/r "$SHA" '[]'
body="$(post_fields)"
if [[ "$RC" -eq 0 && "$(posts)" -eq 1 && "$body" == *"title=Post-merge dispatch failure after #8259..#8260: unattended"* &&
  "$body" == *"attributed to the range"* && "$body" == *"\`$OTHER\`"* &&
  "$body" == *"https://github.com/o/r/pull/8259, merge commit \`$MID\`, by alice"* &&
  "$body" == *"https://github.com/o/r/pull/8260, merge commit \`$SHA\`, by bob"* &&
  "$body" == *"- Failing run: $RUN_URL/attempts/2"$'\n'* && "$body" != *"git revert"* &&
  "$body" != *"- Pull request:"* && "$body" == *"picks the merge responsible, and reverts that one."* ]]; then
  ok "two merges since the last green full run are both named, with no single revert"
else
  fail "two-merge range: rc=$RC log='$LOG' fields='$body'"
fi

SIDE=3333333333333333333333333333333333333333
COMPARE="$(commit "$SIDE" "$OTHER" carol 'wip on a side branch'), $(commit "$MID" "$OTHER" alice 'feat(planning): a join prompt (#8259)'), $(
  jq -n --arg sha "$SHA" --arg p1 "$MID" --arg p2 "$SIDE" \
    '{sha: $sha, parents: [{sha: $p1}, {sha: $p2}], author: {login: "bob"}, commit: {message: "Merge (#8260)"}}'
)" run_step "$FULL" workflow_dispatch failure main o/r "$SHA" '[]'
body="$(post_fields)"
if [[ "$RC" -eq 0 && "$(posts)" -eq 1 && "$body" == *"title=Post-merge dispatch failure after #8259..#8260: unattended"* &&
  "$body" != *"$SIDE"* && "$body" != *"carol"* ]]; then
  ok "the range follows first parents and leaves a merged side branch's commits out"
else
  fail "first-parent walk: rc=$RC log='$LOG' fields='$body'"
fi

GREEN='' run_step "$FULL" schedule failure main o/r "$SHA" '[]'
body="$(post_fields)"
if [[ "$RC" -eq 0 && "$(posts)" -eq 1 && "$body" == *"could not be found"* &&
  "$body" == *"- Pull request: https://github.com/o/r/pull/1234"* && "$body" == *"- Main at the failing run: \`$SHA\`"* &&
  "$body" != *"git revert"* && "$body" == *"finds the merge responsible before reverting anything."* ]] &&
  ! grep -q '/compare/' <<<"$LOG"; then
  ok "with no green full run to start from, the record says so and names the head commit without a revert"
else
  fail "base unknown: rc=$RC log='$LOG' fields='$body'"
fi

COMPARE="$(commit "$SHA" "$MID" bob 'ci: record suite times (#8260)')" \
  run_step "$FULL" schedule failure main o/r "$SHA" '[]'
body="$(post_fields)"
if [[ "$RC" -eq 0 && "$(posts)" -eq 1 && "$body" == *"could not be found"* &&
  "$body" != *"attributed to the range"* && "$body" != *"git revert"* ]]; then
  ok "a first-parent chain that never reaches the green SHA lists no range"
else
  fail "chain misses base: rc=$RC log='$LOG' fields='$body'"
fi

OLD=1111111111111111111111111111111111111111 PRS=2222222222222222222222222222222222222222
GREEN="$(green_run "$OLD" workflow_dispatch 2026-10-17T12:00:00Z), $(green_run "$OTHER" schedule 2026-10-17T14:00:00Z), $(green_run "$PRS" pull_request 2026-10-17T15:00:00Z)" \
  run_step "$FULL" schedule failure main o/r "$SHA" '[]'
if [[ "$RC" -eq 0 && "$(posts)" -eq 1 ]] && grep -q "^GET repos/o/r/compare/$OTHER\.\.\.$SHA$" <<<"$LOG"; then
  ok "the base is the newest green schedule or dispatch run, never a pull_request run"
else
  fail "base choice: rc=$RC log='$LOG'"
fi

# --- Who put the range's merges in the queue ----------------------------------
# A decoy agent-identity outside `merge:` must not be read.
PIPE=$'lanes:\n  agent-identity: decoy[bot]\n\nmerge:\n  rung: C2\n  agent-identity: melodic-automation-lanes[bot]\n  report-only: false'
# enq <number> <login> <typename> [enqueuer-login enqueuer-typename] -> one
# aliased pullRequest whose latest AddedToMergeQueueEvent that actor (and
# enqueuer, by default the same) made; enq <number> alone has none.
enq() {
  if [[ $# -eq 1 ]]; then
    printf '"p%s": {"timelineItems": {"nodes": []}}' "$1"
    return
  fi
  jq -nc --arg n "p$1" --arg l "$2" --arg t "$3" --arg el "${4:-$2}" --arg et "${5:-$3}" \
    '{($n): {timelineItems: {nodes: [{actor: {__typename: $t, login: $l}, enqueuer: {__typename: $et, login: $el}}]}}}' |
    sed 's/^{//; s/}$//'
}
gq() {
  local IFS=,
  jq -nc --argjson p "{$*}" '{data: {rateLimit: {cost: 1, remaining: 4999}, repository: $p}}'
}

PIPELINE="$PIPE" GRAPHQL="$(gq "$(enq 1234 octocat User)")" run_step "$FULL" workflow_dispatch failure main o/r "$SHA" '[]'
fields="$(post_fields)"
body="${fields#*body=}"
if [[ "$RC" -eq 0 && "$(posts)" -eq 1 && "$body" == "<!-- post-merge-failure sha=$SHA signal=dispatch -->"$'\n'* &&
  "$fields" != *babysit-merge-demotion* && "$fields" == *"title=Post-merge dispatch failure after #1234: lane not demoted"* &&
  "$body" == *"the lane is NOT demoted"* && "$body" != *"rung off until"* &&
  "$body" == *"- Pull request: https://github.com/o/r/pull/1234, by octocat"* && "$OUT" == *"cost 1 remaining 4999"* ]] &&
  grep -qx 'labels\[\]=needs-human' <<<"$fields" && [[ "$(grep -cx 'GET graphql' <<<"$LOG")" -eq 1 ]] &&
  grep -q 'p1234: pullRequest(number: 1234)' "$TMP_ROOT/stub/graphql.$(grep -nx 'GET graphql' <<<"$LOG" | cut -d: -f1)"; then
  ok "a window of human-enqueued merges files a needs-human record that does not demote"
else
  fail "human-only window: rc=$RC log='$LOG' out='$OUT' fields='$fields'"
fi

TWO="$(commit "$MID" "$OTHER" alice 'feat(planning): a join prompt (#8259)'), $(commit "$SHA" "$MID" bob 'ci: record suite times (#8260)')"
COMPARE="$TWO" PIPELINE="$PIPE" GRAPHQL="$(gq "$(enq 8259 alice User)" "$(enq 8260 bob User)")" \
  run_step "$FULL" schedule failure main o/r "$SHA" '[]'
fields="$(post_fields)"
if [[ "$RC" -eq 0 && "$(posts)" -eq 1 && "${fields#*body=}" == "<!-- post-merge-failure sha=$SHA signal=schedule -->"$'\n'* &&
  "$fields" == *"title=Post-merge schedule failure after #8259..#8260: lane not demoted"* &&
  "$fields" == *"pull/8259, merge commit \`$MID\`, by alice"* && "$fields" == *"pull/8260, merge commit \`$SHA\`, by bob"* ]]; then
  ok "a scheduled run over two human merges lists both with their authors and does not demote"
else
  fail "human-only range: rc=$RC log='$LOG' fields='$fields'"
fi

# demotes <label>: the run filed today's demotion record.
demotes() {
  local fields
  fields="$(post_fields 2>/dev/null)"
  if [[ "$RC" -eq 0 && "$(posts)" -eq 1 && "${fields#*body=}" == "<!-- babysit-merge-demotion sha=$SHA signal="* &&
    "$fields" == *": unattended merging demoted"* && "$fields" == *"rung off until"* ]]; then
    ok "$1"
  else
    fail "$1: rc=$RC log='$LOG' out='$OUT' fields='$fields'"
  fi
}

COMPARE="$TWO" PIPELINE="$PIPE" GRAPHQL="$(gq "$(enq 8259 alice User)" "$(enq 8260 melodic-automation-lanes Bot)")" \
  run_step "$FULL" schedule failure main o/r "$SHA" '[]'
demotes "a window with one lane enqueue among human merges demotes (a Bot login gains [bot])"
if [[ "$OUT" != *"lookup for 2 pull requests: cost 1"* ]]; then
  fail "the mixed window's lookup did not answer: out='$OUT'"
fi

PIPELINE="$PIPE" GRAPHQL="$(gq "$(enq 1234 octocat User melodic-automation-lanes Bot)")" \
  run_step "$FULL" workflow_dispatch failure main o/r "$SHA" '[]'
demotes "a human actor with the lanes App as enqueuer demotes"

MANY='' at="$OTHER"
for i in $(seq 1 101); do
  c="$(printf '%040x' "$i")"
  if [[ "$i" -eq 101 ]]; then c="$SHA"; fi
  MANY="${MANY:+$MANY, }$(commit "$c" "$at" alice "feat: change $i (#$i)")"
  at="$c"
done
COMPARE="$MANY" PIPELINE="$PIPE" GRAPHQL="$(gq "$(enq 1 alice User)")" run_step "$FULL" schedule failure main o/r "$SHA" '[]'
demotes "a range of 101 merges demotes"
if grep -qx 'GET graphql' <<<"$LOG" || [[ "$(post_fields)" != *"range of 101 merges"* ]]; then
  fail "a 101-merge range made the lookup or was not read as 101 merges: log='$LOG'"
fi

PIPELINE="$PIPE" GRAPHQL="$(gq "$(enq 1234 octocat User)")" ATTEMPT=1 run_step "$CANARY" push failure main o/r "$SHA" '[]'
demotes "a canary failure demotes even with a human-only lookup available"
if grep -qE 'GET (graphql|repos/o/r/contents/)' <<<"$LOG"; then
  fail "a canary made the lookup: log='$LOG'"
fi

PIPELINE="$PIPE" FAIL_GRAPHQL=1 run_step "$FULL" workflow_dispatch failure main o/r "$SHA" \
  "[$(issue 41 "<!-- post-merge-failure sha=$SHA signal=dispatch -->")]"
if [[ "$RC" -eq 0 && "$(posts)" -eq 1 ]] && grep -qx 'POST repos/o/r/issues/41/comments' <<<"$LOG" &&
  ! grep -qx 'GET graphql' <<<"$LOG"; then
  ok "a later attempt updates the post-merge-failure record without a lookup"
else
  fail "existing record with failing lookup: rc=$RC log='$LOG'"
fi

PIPELINE="$PIPE" FAIL_GRAPHQL=1 run_step "$FULL" workflow_dispatch failure main o/r "$SHA" '[]'
demotes "a failed merge-queue lookup demotes"

PIPELINE="$PIPE" GRAPHQL="$(gq "$(enq 1234)")" run_step "$FULL" workflow_dispatch failure main o/r "$SHA" '[]'
demotes "a merge with no merge-queue event demotes"

PIPELINE="$PIPE" GRAPHQL='{"data": {"rateLimit": {"cost": 1, "remaining": 1}, "repository": {}}}' \
  run_step "$FULL" workflow_dispatch failure main o/r "$SHA" '[]'
demotes "a lookup that answers for fewer pull requests than asked demotes"

GRAPHQL="$(gq "$(enq 1234 octocat User)")" run_step "$FULL" workflow_dispatch failure main o/r "$SHA" '[]'
demotes "an unreadable agent identity demotes"
if grep -qx 'GET graphql' <<<"$LOG"; then
  fail "the lookup ran without an identity: log='$LOG'"
fi

COMPARE="$(commit "$MID" "$OTHER" alice 'a direct commit'), $(commit "$SHA" "$MID" bob 'ci: record suite times (#8260)')" \
  PIPELINE="$PIPE" GRAPHQL="$(gq "$(enq 8260 bob User)")" run_step "$FULL" schedule failure main o/r "$SHA" '[]'
demotes "a range commit with no (#N) subject demotes"

GREEN='' PIPELINE="$PIPE" GRAPHQL="$(gq "$(enq 1234 octocat User)")" run_step "$FULL" schedule failure main o/r "$SHA" '[]'
demotes "an unknown range demotes"

PIPELINE="$PIPE" GRAPHQL="$(gq "$(enq 1234 octocat User)")" run_step "$FULL" workflow_dispatch failure main o/r "$SHA" \
  "[$(issue 41 "<!-- post-merge-failure sha=$SHA signal=dispatch -->")]"
if [[ "$RC" -eq 0 && "$(posts)" -eq 1 ]] && grep -qx 'POST repos/o/r/issues/41/comments' <<<"$LOG"; then
  ok "an existing non-demoting record gets the comment, not a second issue"
else
  fail "existing non-demoting record: rc=$RC log='$LOG'"
fi

# --- Re-run, baseline and the gitleaks gate ------------------------------------
RERUN=success ATTEMPT=1 run_step "$FULL" schedule failure main o/r "$SHA" '[]'
if [[ "$RC" -eq 0 && "$(head -1 <<<"$LOG")" == 'POST repos/o/r/actions/runs/4242/rerun-failed-jobs' &&
  "$(grep -c '^GET repos/o/r/actions/runs/4242$' <<<"$LOG")" -eq 2 && "$(posts)" -eq 1 ]]; then
  ok "a full run's first failed attempt re-runs its failed jobs and a passing re-run files nothing"
else
  fail "re-run passes: rc=$RC log='$LOG' out='$OUT'"
fi

RERUN=failure ATTEMPT=1 RUNS="$(baseline_run 4141 success)" run_step "$FULL" schedule failure main o/r "$SHA" '[]'
issue_fields="$(cat "$TMP_ROOT/stub/post.$(grep -n '^POST repos/o/r/issues$' <<<"$LOG" | cut -d: -f1)" 2>/dev/null)"
if [[ "$RC" -eq 0 ]] && grep -q '^GET repos/o/r/actions/runs/4242/attempts/2/jobs' <<<"$LOG" &&
  [[ "$issue_fields" == *"- Failing run: $RUN_URL/attempts/2"$'\n'"- Newly failing: test-bash"* ]]; then
  ok "a failing re-run is judged on its own attempt against the baseline and files"
else
  fail "re-run fails: rc=$RC log='$LOG' out='$OUT'"
fi

RERUN=failure ATTEMPT=1 RUNS="$(baseline_run 4141 failure)" BASE_JOBS="$(job 2 test-bash 'Run the bash tests')" \
  run_step "$FULL" schedule failure main o/r "$SHA" '[]'
if [[ "$RC" -eq 0 && "$(posts)" -eq 1 && "$OUT" == *"already failing before"* ]]; then
  ok "a failing re-run on a check already red before files nothing"
else
  fail "re-run fails on a pre-existing check: rc=$RC log='$LOG' out='$OUT'"
fi

RERUN=success RERUN_POST_FAIL=1 ATTEMPT=1 run_step "$FULL" schedule failure main o/r "$SHA" '[]'
if [[ "$RC" -eq 0 && "$(posts)" -eq 1 && "$OUT" == *"could not re-run"* && "$OUT" == *"passed: nothing to file"* ]]; then
  ok "a re-run another actor already started is waited for when this one cannot start"
else
  fail "re-run POST refused: rc=$RC log='$LOG' out='$OUT'"
fi

STARTER='github-actions[bot]' ATTEMPT=1 run_step "$FULL" workflow_dispatch failure main o/r "$SHA" '[]'
if [[ "$RC" -eq 0 && "$(posts)" -eq 1 ]] && grep -qx 'POST repos/o/r/issues' <<<"$LOG" &&
  ! grep -q 'rerun-failed-jobs\|^GET repos/o/r/actions/runs/4242$' <<<"$LOG"; then
  ok "a run the bot started is not re-run here and attempt 1 is judged"
else
  fail "bot-started run: rc=$RC log='$LOG' out='$OUT'"
fi

JOBS='' run_step "$FULL" schedule failure main o/r "$SHA" '[]'
if [[ "$RC" -eq 0 && "$(posts)" -eq 1 && "$(post_fields)" == *"- Newly failing: pr-require-checks.yml: no failed jobs"* ]]; then
  ok "a red run with no failed job files a record"
else
  fail "zero-job red run: rc=$RC log='$LOG' out='$OUT'"
fi

JOBS='' RUNS="$(baseline_run 4141 startup_failure)" BASE_JOBS='' run_step "$FULL" schedule failure main o/r "$SHA" '[]'
if [[ "$RC" -eq 0 && "$(posts)" -eq 0 && "$OUT" == *"already failing before"* ]]; then
  ok "a red run with no failed job after the same red before files nothing"
else
  fail "zero-job red run after the same: rc=$RC log='$LOG' out='$OUT'"
fi

RERUN=never ATTEMPT=1 run_step "$FULL" schedule failure main o/r "$SHA" '[]'
issue_fields="$(cat "$TMP_ROOT/stub/post.$(grep -n '^POST repos/o/r/issues$' <<<"$LOG" | cut -d: -f1)" 2>/dev/null)"
if [[ "$RC" -eq 0 && "$(grep -c '^GET repos/o/r/actions/runs/4242$' <<<"$LOG")" -eq 20 &&
  "$issue_fields" == *"- Failing run: $RUN_URL/attempts/1"$'\n'* && "$OUT" == *"did not finish"* ]]; then
  ok "a re-run that does not finish in 20 polls leaves attempt 1 to demote"
else
  fail "re-run timeout: rc=$RC log='$LOG' out='$OUT'"
fi

ATTEMPT=1 files "a canary's first failed attempt files without a re-run" canary "$CANARY" push '[]'
if grep -q 'rerun-failed-jobs' <<<"$LOG"; then
  fail "a canary run was re-run: log='$LOG'"
fi

RUNS="$(baseline_run 4141 failure)" BASE_JOBS="$(job 2 test-bash 'Run the bash tests')" \
  run_step "$FULL" schedule failure main o/r "$SHA" '[]'
if [[ "$RC" -eq 0 && "$(posts)" -eq 0 && "$OUT" == *"already failing before"* ]]; then
  ok "a check already red on main's previous run files nothing"
else
  fail "pre-existing failure: rc=$RC log='$LOG' out='$OUT'"
fi

RUNS="$(baseline_run 4141 success)" files "a check green on main's previous run files a record" \
  schedule "$FULL" schedule '[]'

RUNS="$(baseline_run 4141 failure)" BASE_JOBS="$(job 2 lint-shell ShellCheck)" \
  run_step "$FULL" schedule failure main o/r "$SHA" '[]'
if [[ "$RC" -eq 0 && "$(posts)" -eq 1 && "$(post_fields)" == *"- Newly failing: test-bash"* ]]; then
  ok "another check red on main's previous run does not excuse this one"
else
  fail "different pre-existing check: rc=$RC log='$LOG'"
fi

RUNS="$(baseline_run 4141 failure "$SHA")" BASE_JOBS="$(job 2 test-bash 'Run the bash tests')" \
  run_step "$FULL" schedule failure main o/r "$SHA" '[]'
if [[ "$RC" -eq 0 && "$(posts)" -eq 1 ]]; then
  ok "a run at the same SHA is not the baseline"
else
  fail "same-SHA baseline: rc=$RC log='$LOG'"
fi

RUNS="$(baseline_run 4141 failure)" BASE_JOBS="$(job 2 test-bash 'Run the bash tests')" \
  run_step "$FULL" workflow_dispatch failure main o/r "$SHA" '[]'
if grep -q 'runs?event=workflow_dispatch&branch=main&status=completed&created=%3C' <<<"$LOG"; then
  ok "the baseline is read for the same event"
else
  fail "baseline event: log='$LOG'"
fi

GITLEAKS='[{"annotation_level": "failure", "title": "", "message": "Process completed with exit code 1."},
  {"annotation_level": "failure", "title": "gitleaks failed", "message": "Hygiene check finished with outcome: failure."}]'
LINT_RED="$(job 7 lint-repo 'Aggregate hygiene results'), $(job 8 ci-status 'Aggregate lane results')"
JOBS="$LINT_RED" ANNOTATIONS_7="$GITLEAKS" run_step "$FULL" schedule failure main o/r "$SHA" '[]'
if [[ "$RC" -eq 0 && "$(posts)" -eq 0 && "$OUT" == *"no merge can cause"* ]]; then
  ok "a failure only on the all-branches gitleaks gate files nothing"
else
  fail "gitleaks only: rc=$RC log='$LOG' out='$OUT'"
fi

JOBS="$LINT_RED" ANNOTATIONS_7="$(jq -c '. + [{annotation_level: "failure", title: "markdown failed", message: "x"}]' <<<"$GITLEAKS")" \
  run_step "$FULL" schedule failure main o/r "$SHA" '[]'
if [[ "$RC" -eq 0 && "$(posts)" -eq 1 && "$(post_fields)" == *"- Newly failing: lint-repo: markdown failed"$'\n'* ]]; then
  ok "another gate beside gitleaks files, naming only that gate"
else
  fail "gate beside gitleaks: rc=$RC log='$LOG' fields='$(post_fields 2>/dev/null)'"
fi

quiet "a failed pull_request run files nothing" "$FULL" pull_request failure main o/r
quiet "a failed merge_group run files nothing" "$FULL" merge_group failure main o/r
quiet "a dispatched canary run files nothing" "$CANARY" workflow_dispatch failure main o/r
quiet "a successful scheduled run files nothing" "$FULL" schedule success main o/r
quiet "a successful canary push run files nothing" "$CANARY" push success main o/r
CONCLUSION=cancelled files "a cancelled scheduled run files a record" schedule "$FULL" schedule '[]'
quiet "a failed run on another branch files nothing" "$FULL" workflow_dispatch failure feat/x o/r
quiet "a failed run from a fork's main files nothing" "$FULL" schedule failure main fork/r
quiet "another workflow files nothing" "some-other-workflow" schedule failure main o/r
CONCLUSION=timed_out files "a timed-out scheduled run files a record" schedule "$FULL" schedule '[]'

run_step "$FULL" schedule failure main o/r 'abc123' '[]'
if [[ "$RC" -ne 0 && -z "$LOG" ]]; then
  ok "a head SHA that is not 40 hex characters fails without a call"
else
  fail "short sha: rc=$RC log='$LOG'"
fi

ATTEMPT=x run_step "$FULL" schedule failure main o/r "$SHA" '[]'
if [[ "$RC" -ne 0 && -z "$LOG" ]]; then
  ok "a run attempt that is not a positive integer fails without a call"
else
  fail "bad attempt: rc=$RC log='$LOG'"
fi

test_harness::report
