#!/usr/bin/env bash
# Runs the `File or comment on the demotion issue` step body of
# .github/workflows/post-merge-demotion-alert.yml under the shell Actions gives
# a step with no `shell:` (bash -e), against a stub `gh`.
#
# The step files the demotion record the babysit post-merge check and the
# merge-policy reader also use: an issue by github-actions[bot] whose body's
# first line is `<!-- babysit-merge-demotion sha=<S> signal=<name> -->`,
# labeled needs-human, one per (signal, SHA). A matching record gets a comment
# instead; a run that is not a failed scheduled or dispatched full run, or a
# failed canary push run, on main files nothing.
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
if [[ "$(grep -c 'issues: write' "$WORKFLOW")" -eq 1 ]] && grep -q '^permissions: {}$' "$WORKFLOW" &&
  [[ "$(grep -cE '^ +[a-z-]+: (read|write)( |$)' "$WORKFLOW")" -eq 1 ]]; then
  ok "the token holds issues: write and nothing else"
else
  fail "permissions are not exactly issues: write"
fi
if grep -qE '^\s*-?\s*uses:' "$WORKFLOW"; then
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
    --paginate|api) ;;
    *) endpoint="${args[i]}" ;;
  esac
done
printf '%s %s\n' "$method" "$endpoint" >>"$STUB_DIR/log"
n=$(wc -l <"$STUB_DIR/log")
if [[ "$method" != GET ]]; then
  printf '%s\n' "${fields[@]}" >"$STUB_DIR/post.$n"
  printf '{"number": 900}\n'
  exit 0
fi
[[ "${STUB_FAIL_READ:-}" != 1 ]] || exit 1
case "$endpoint" in
  */comments*) fixture="$STUB_DIR/comments.json" ;;
  *) fixture="$STUB_DIR/issues.json" ;;
esac
jq -r "$filter" "$fixture"
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

# run_step <workflow> <event> <conclusion> <branch> <head-repo> <sha> <issues-json> [comments-json]
run_step() {
  rm -rf "$TMP_ROOT/stub"
  mkdir -p "$TMP_ROOT/stub"
  printf '%s\n' "$7" >"$TMP_ROOT/stub/issues.json"
  printf '%s\n' "${8:-[]}" >"$TMP_ROOT/stub/comments.json"
  : >"$TMP_ROOT/stub/log"
  OUT="$(PATH="$TMP_ROOT/bin:$PATH" STUB_DIR="$TMP_ROOT/stub" STUB_FAIL_READ="${FAIL_READ:-}" \
    GH_TOKEN=x GITHUB_REPOSITORY=o/r RUN_WORKFLOW="$1" RUN_EVENT="$2" RUN_CONCLUSION="$3" \
    RUN_BRANCH="$4" RUN_REPO="$5" RUN_SHA="$6" RUN_URL="$RUN_URL" RUN_ATTEMPT="${ATTEMPT:-1}" \
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
  elif [[ "$body" != *"$RUN_URL"* ]]; then
    fail "$label: body lacks the failing run link"
  elif [[ "$body" != *"https://github.com/o/r/pull/1234"* ]]; then
    fail "$label: body lacks the pull request link"
  elif ! grep -qx 'labels\[\]=needs-human' <<<"$fields"; then
    fail "$label: issue is not labeled needs-human: '$fields'"
  elif [[ "$signal" == schedule && ("$body" != *"- Main at the failing run: \`$SHA\`"* || "$body" == *"Merge commit"*) ]]; then
    fail "$label: a schedule record must name the SHA as main at the failing run"
  elif [[ "$signal" != schedule && "$body" != *"- Merge commit: \`$SHA\`"* ]]; then
    fail "$label: body does not name the merge commit"
  else
    ok "$label"
  fi
}

# quiet <label> <workflow> <event> <conclusion> <branch> <head-repo>
quiet() {
  run_step "$2" "$3" "$4" "$5" "$6" "$SHA" '[]'
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
  [[ "$(post_fields)" == *"$RUN_URL"* ]]; then
  ok "an existing record gets a comment with the run link, not a second issue"
else
  fail "existing record: rc=$RC log='$LOG' out='$OUT'"
fi

run_step "$FULL" schedule failure main o/r "$SHA" "[$(issue 41 "  "$'\n'"$MARKER"$'\r\nbody')]"
if [[ "$RC" -eq 0 && "$(posts)" -eq 1 ]] && grep -qx 'POST repos/o/r/issues/41/comments' <<<"$LOG"; then
  ok "leading blank lines and a CRLF ending still match the marker line"
else
  fail "whitespace around the marker: rc=$RC log='$LOG'"
fi

run_step "$FULL" schedule failure main o/r "$SHA" "[$(issue 41 "$MARKER"$'\n'"- Failing run: $RUN_URL")]"
if [[ "$RC" -eq 0 && "$(posts)" -eq 0 ]]; then
  ok "a record that already names this run gets no comment"
else
  fail "record already naming the run: rc=$RC log='$LOG'"
fi

# comment <login> <body> -> one REST issue comment object
comment() {
  jq -n --arg login "$1" --arg body "$2" '{user: {login: $login}, body: $body}'
}

run_step "$FULL" schedule failure main o/r "$SHA" "[$(issue 41 "$MARKER")]" \
  "[$(comment someone "$RUN_URL"), $(comment 'github-actions[bot]' "The post-merge check found this failure again: $RUN_URL")]"
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

ATTEMPT=2 run_step "$FULL" schedule success main o/r "$SHA" "[$(issue 41 "$MARKER" '' closed)]"
if [[ "$RC" -eq 0 && "$(posts)" -eq 1 ]] && grep -qx 'POST repos/o/r/issues/41/comments' <<<"$LOG" &&
  [[ "$(post_fields)" == "body=re-run passed: $RUN_URL" ]] && ! grep -q '^PATCH' <<<"$LOG"; then
  ok "a re-run that passes comments on the record without reopening it"
else
  fail "re-run passed: rc=$RC log='$LOG' out='$OUT'"
fi

ATTEMPT=2 run_step "$FULL" schedule success main o/r "$SHA" "[$(issue 41 "$MARKER")]" \
  "[$(comment 'github-actions[bot]' "re-run passed: $RUN_URL")]"
if [[ "$RC" -eq 0 && "$(posts)" -eq 0 ]]; then
  ok "a re-run pass already recorded is not commented twice"
else
  fail "duplicate re-run pass: rc=$RC log='$LOG'"
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

test_harness::report
