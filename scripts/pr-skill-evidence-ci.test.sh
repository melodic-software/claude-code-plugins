#!/usr/bin/env bash
# Regression tests for pr-skill-evidence-ci.sh.
#
#   bash scripts/pr-skill-evidence-ci.test.sh
#
# Black box through the CLI with `gh` stubbed on PATH and the evidence engine
# stubbed through SKILL_EVIDENCE_BIN: the verdict itself is the engine's
# contract and its own suite owns it, so pinning it here would test the engine
# twice and this reporter's transitions not at all. What IS pinned here is
# everything the reporter decides: which early exits it takes, which REST
# writes each verdict earns, that a label call is skipped when the pull request
# is already in the target state, that the comment keeps every earlier marker
# line, and that a `gh` failing on every call still leaves the exit status 0.
#
# The stub records every invocation to a log and the payload of every write to
# a second one, so an assertion reads what the reporter SENT rather than what
# it printed.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/pr-skill-evidence-ci.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

command -v jq >/dev/null 2>&1 || {
  printf 'pr-skill-evidence-ci.test.sh: jq is not available; nothing exercised\n' >&2
  exit 2
}

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

REPO_NAME="acme/app"
PR="5"
HEAD="1111111111111111111111111111111111111111"
ROW="2222222222222222222222222222222222222222"
MARKER_GAP="<!-- pr-skill-evidence head=$HEAD verdict=gap -->"
MARKER_CLEAN="<!-- pr-skill-evidence head=$HEAD verdict=clean -->"
OLD_MARKER="<!-- pr-skill-evidence head=3333333333333333333333333333333333333333 verdict=gap -->"

STUB_DIR="$TEST_TMPDIR/stub"
mkdir -p "$STUB_DIR"

cat >"$STUB_DIR/gh" <<'STUB'
#!/usr/bin/env bash
# Stubbed gh. Logs every invocation, captures the payload of a piped write, and
# answers each endpoint from a file or a variable the case set.
set -u
printf 'gh %s\n' "$*" >>"$GH_LOG"
case "$*" in
*"--input -"*) cat >>"$GH_STDIN_LOG" ;;
*) ;;
esac
# The `--jq` expression, so a case that supplies a comments FIXTURE gets the
# real filter applied to it rather than a canned answer. Real gh runs that
# expression itself, which is where the author filter lives.
JQ_FILTER=""
PREV=""
for arg in "$@"; do
  [[ "$PREV" == "--jq" ]] && JQ_FILTER="$arg"
  PREV="$arg"
done
if [[ -n "${GH_FAIL:-}" ]]; then
  printf 'stubbed gh failure\n' >&2
  exit 1
fi
case "$*" in
*--method*) exit 0 ;;
*labels/needs-skill-evidence*)
  [[ "${GH_LABEL_EXISTS:-1}" == "1" ]] || exit 1
  printf '{"name":"needs-skill-evidence"}\n'
  ;;
*issues/*/labels*) printf '%s\n' "${GH_LABELS:-}" ;;
*pulls/*/files*) cat "${GH_FILES_FILE:-/dev/null}" ;;
*compare/*)
  base="${*##*compare/}"
  base="${base%%...*}"
  printf '{"status":"ahead","base_commit":{"sha":"%s"},"merge_base_commit":{"sha":"%s"}}\n' \
    "$base" "$base"
  ;;
*pulls/*) cat "${GH_BODY_FILE:-/dev/null}" ;;
*issues/comments/*) cat "${GH_COMMENT_BODY_FILE:-/dev/null}" ;;
*issues/*/comments*)
  if [[ -n "${GH_COMMENTS_FILE:-}" ]]; then
    jq -r "${JQ_FILTER:-.}" "$GH_COMMENTS_FILE"
  else
    printf '%s\n' "${GH_COMMENT_ID:-}"
  fi
  ;;
*) printf '\n' ;;
esac
STUB
chmod +x "$STUB_DIR/gh"

cat >"$STUB_DIR/engine.sh" <<'STUB'
#!/usr/bin/env bash
# Stubbed skill-evidence.sh: logs its arguments and prints the canned report
# the case chose.
set -u
printf 'engine %s\n' "$*" >>"$ENGINE_LOG"
if [[ -n "${ENGINE_FAIL:-}" ]]; then
  printf 'stubbed usage error\n' >&2
  exit 2
fi
cat "$ENGINE_OUT"
STUB
chmod +x "$STUB_DIR/engine.sh"

BODY_FILE="$TEST_TMPDIR/body.md"
{
  printf '## Verification\n\n'
  printf '```skill-evidence\n'
  printf 'verification:confirm %s 2026-09-19T10:00:00Z\n' "$HEAD"
  printf 'simplify %s 2026-09-18T10:00:00Z\n' "$ROW"
  printf '```\n'
} >"$BODY_FILE"

FILES_FILE="$TEST_TMPDIR/files.txt"
printf 'scripts/thing.sh\ndocs/readme.md\n' >"$FILES_FILE"

GAP_REPORT="$TEST_TMPDIR/gap.txt"
printf 'class=code\nmissing=review:quality-gate,review:fanout\nverdict=gap\n' >"$GAP_REPORT"
CLEAN_REPORT="$TEST_TMPDIR/clean.txt"
printf 'class=code\nfresh=simplify sha=%s commits-since=1\nverdict=clean\n' "$ROW" >"$CLEAN_REPORT"
INERT_REPORT="$TEST_TMPDIR/inert.txt"
printf 'verdict=inert\n' >"$INERT_REPORT"

CASE=0
GH_LOG=""
GH_STDIN_LOG=""
RUN_OUT=""
RUN_CODE=0

# run <report-file> [VAR=value ...] — the reporter, with a fresh log pair and
# the pull-request environment a workflow step supplies.
run() {
  local report="$1"
  shift
  CASE=$((CASE + 1))
  GH_LOG="$TEST_TMPDIR/gh-$CASE.log"
  GH_STDIN_LOG="$TEST_TMPDIR/stdin-$CASE.log"
  : >"$GH_LOG"
  : >"$GH_STDIN_LOG"
  RUN_OUT="$(
    env -i \
      PATH="$STUB_DIR:$PATH" \
      HOME="${HOME:-/tmp}" \
      GH_TOKEN=stub \
      GITHUB_REPOSITORY="$REPO_NAME" \
      GITHUB_EVENT_NAME=pull_request \
      PR_NUMBER="$PR" \
      HEAD_SHA="$HEAD" \
      IS_DRAFT=false \
      HEAD_REPO="$REPO_NAME" \
      GH_LOG="$GH_LOG" \
      GH_STDIN_LOG="$GH_STDIN_LOG" \
      ENGINE_LOG="$TEST_TMPDIR/engine-$CASE.log" \
      ENGINE_OUT="$report" \
      GH_BODY_FILE="$BODY_FILE" \
      GH_FILES_FILE="$FILES_FILE" \
      SKILL_EVIDENCE_BIN="$STUB_DIR/engine.sh" \
      "$@" \
      bash "$SCRIPT" 2>&1
  )"
  RUN_CODE=$?
}

contains() {
  local name="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    ok "$name"
  else
    bad "$name" "expected '$needle' in: $haystack"
  fi
}

lacks() {
  local name="$1" haystack="$2" needle="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    ok "$name"
  else
    bad "$name" "expected '$needle' to be absent from: $haystack"
  fi
}

exits() {
  local name="$1" want="$2" got="$3"
  if [[ "$got" -eq "$want" ]]; then
    ok "$name"
  else
    bad "$name" "expected exit $want, got $got"
  fi
}

log() { cat "$GH_LOG"; }
payload() { cat "$GH_STDIN_LOG"; }

# --- early exits -------------------------------------------------------------

run "$GAP_REPORT" GITHUB_EVENT_NAME=push
exits "a push event exits 0" 0 "$RUN_CODE"
contains "a push event declines with a notice" "$RUN_OUT" "declined on a push event"
lacks "a push event calls no API" "$(log)" "gh api"

run "$GAP_REPORT" IS_DRAFT=true
exits "a draft exits 0" 0 "$RUN_CODE"
contains "a draft declines with a notice" "$RUN_OUT" "declined on a draft pull request"
lacks "a draft calls no API" "$(log)" "gh api"

run "$GAP_REPORT" HEAD_REPO=someone/fork
exits "a fork head exits 0" 0 "$RUN_CODE"
contains "a fork head declines with a notice" "$RUN_OUT" "declined on a fork head"
lacks "a fork head calls no API" "$(log)" "gh api"

# jq is checked before any work is attempted, so a PATH holding exactly what
# the script needs to reach that check, and no jq, proves the notice rather
# than a crash further down.
NOJQ_DIR="$TEST_TMPDIR/nojq"
mkdir -p "$NOJQ_DIR"
cp "$STUB_DIR/gh" "$NOJQ_DIR/gh"
for tool in bash dirname; do
  ln -s "$(command -v "$tool")" "$NOJQ_DIR/$tool"
done
CASE=$((CASE + 1))
RUN_OUT="$(
  env -i PATH="$NOJQ_DIR" HOME="${HOME:-/tmp}" \
    GITHUB_REPOSITORY="$REPO_NAME" GITHUB_EVENT_NAME=pull_request PR_NUMBER="$PR" \
    HEAD_SHA="$HEAD" IS_DRAFT=false HEAD_REPO="$REPO_NAME" \
    GH_LOG="$TEST_TMPDIR/gh-nojq.log" GH_STDIN_LOG="$TEST_TMPDIR/stdin-nojq.log" \
    bash "$SCRIPT" 2>&1
)"
RUN_CODE=$?
exits "a missing jq exits 0" 0 "$RUN_CODE"
contains "a missing jq declines with a notice" "$RUN_OUT" "jq is not on PATH"

# --- a gap creates the comment and adds the label ----------------------------

run "$GAP_REPORT" GH_COMMENT_ID="" GH_LABELS="" GH_LABEL_EXISTS=1
exits "a gap exits 0" 0 "$RUN_CODE"
contains "a gap is reported as a notice" "$RUN_OUT" "skill-evidence gap at $HEAD"
contains "a gap posts a new comment" "$(log)" "--method POST repos/$REPO_NAME/issues/$PR/comments"
contains "the new comment carries this head's gap marker" "$(payload)" "$MARKER_GAP"
contains "the new comment shows the gap lines" "$(payload)" "missing=review:quality-gate,review:fanout"
contains "a gap adds the label" "$(log)" "--method POST repos/$REPO_NAME/issues/$PR/labels"
contains "a row commit gets one compare call" "$(log)" "compare/$ROW...$HEAD"
lacks "the head itself gets no compare call" "$(log)" "compare/$HEAD...$HEAD"
contains "the engine reads the event head" "$(cat "$TEST_TMPDIR/engine-$CASE.log")" "--head $HEAD"

# --- a gap on a PR that already carries the label writes no label ------------

run "$GAP_REPORT" GH_COMMENT_ID="" GH_LABELS="needs-skill-evidence" GH_LABEL_EXISTS=1
exits "a gap with the label already on exits 0" 0 "$RUN_CODE"
lacks "a carried label is not written again" "$(log)" "--method POST repos/$REPO_NAME/issues/$PR/labels"
contains "the comment is still upserted" "$(log)" "--method POST repos/$REPO_NAME/issues/$PR/comments"

# --- a clean verdict rewrites the comment, keeps earlier markers, drops the label

OLD_COMMENT="$TEST_TMPDIR/old-comment.md"
printf '### Skill evidence: a gap\n\nstale text\n\n%s\n' "$OLD_MARKER" >"$OLD_COMMENT"
run "$CLEAN_REPORT" GH_COMMENT_ID=99 GH_COMMENT_BODY_FILE="$OLD_COMMENT" \
  GH_LABELS="needs-skill-evidence" GH_LABEL_EXISTS=1
exits "a clean verdict exits 0" 0 "$RUN_CODE"
contains "a clean verdict patches the existing comment" "$(log)" \
  "--method PATCH repos/$REPO_NAME/issues/comments/99"
contains "the rewritten comment keeps the earlier marker" "$(payload)" "$OLD_MARKER"
contains "the rewritten comment appends the clean marker" "$(payload)" "$MARKER_CLEAN"
lacks "the rewritten comment drops the stale visible text" "$(payload)" "stale text"
contains "a clean verdict removes the label" "$(log)" \
  "--method DELETE repos/$REPO_NAME/issues/$PR/labels/needs-skill-evidence"

run "$CLEAN_REPORT" GH_COMMENT_ID=99 GH_COMMENT_BODY_FILE="$OLD_COMMENT" \
  GH_LABELS="" GH_LABEL_EXISTS=1
exits "a clean verdict with no label exits 0" 0 "$RUN_CODE"
lacks "a label that is not carried is not removed" "$(log)" "--method DELETE"

# A re-run at the same head (a label flip or a body edit re-runs `ci-status`)
# records one marker for that head, not one per run.
SAME_HEAD_COMMENT="$TEST_TMPDIR/same-head-comment.md"
printf '### Skill evidence: a gap\n\nolder text\n\n%s\n%s\n' "$OLD_MARKER" "$MARKER_GAP" \
  >"$SAME_HEAD_COMMENT"
run "$GAP_REPORT" GH_COMMENT_ID=99 GH_COMMENT_BODY_FILE="$SAME_HEAD_COMMENT" \
  GH_LABELS="needs-skill-evidence" GH_LABEL_EXISTS=1
exits "a re-run at the same head exits 0" 0 "$RUN_CODE"
REPEATS="$(payload | grep -c "head=$HEAD verdict=gap")"
if [[ "$REPEATS" -eq 1 ]]; then
  ok "a re-run at the same head appends no second marker"
else
  bad "a re-run at the same head appends no second marker" "found $REPEATS markers for this head"
fi
contains "a re-run still keeps the earlier marker" "$(payload)" "$OLD_MARKER"

# --- only the Actions bot's own comment is rewritten -------------------------
# The marker is plain text and a pull request's comments are attacker-supplied.
# A marker-bearing comment under anyone else's name is left alone, and this
# step posts one of its own beside it.

OUTSIDER_COMMENTS="$TEST_TMPDIR/outsider-comments.json"
jq -n --arg body "$OLD_MARKER" \
  '[{id: 77, user: {login: "drive-by", type: "User"}, body: $body}]' >"$OUTSIDER_COMMENTS"
BOT_COMMENTS="$TEST_TMPDIR/bot-comments.json"
jq -n --arg body "$OLD_MARKER" \
  '[{id: 77, user: {login: "drive-by", type: "User"}, body: $body},
    {id: 88, user: {login: "github-actions[bot]", type: "Bot"}, body: $body}]' >"$BOT_COMMENTS"

run "$GAP_REPORT" GH_COMMENTS_FILE="$OUTSIDER_COMMENTS" GH_LABELS="" GH_LABEL_EXISTS=1
exits "an outsider's marker comment exits 0" 0 "$RUN_CODE"
lacks "an outsider's marker comment is not patched" "$(log)" "--method PATCH"
contains "an outsider's marker comment earns a fresh comment instead" "$(log)" \
  "--method POST repos/$REPO_NAME/issues/$PR/comments"

run "$GAP_REPORT" GH_COMMENTS_FILE="$BOT_COMMENTS" GH_COMMENT_BODY_FILE="$OLD_COMMENT" \
  GH_LABELS="" GH_LABEL_EXISTS=1
exits "the bot's own marker comment exits 0" 0 "$RUN_CODE"
contains "the bot's own marker comment is the one patched" "$(log)" \
  "--method PATCH repos/$REPO_NAME/issues/comments/88"

# --- a label the repository does not carry is a notice -----------------------

run "$GAP_REPORT" GH_COMMENT_ID="" GH_LABELS="" GH_LABEL_EXISTS=0
exits "a missing label exits 0" 0 "$RUN_CODE"
contains "a missing label names its owner" "$RUN_OUT" "github-iac"
lacks "a missing label is never created" "$(log)" "--method POST repos/$REPO_NAME/issues/$PR/labels"
contains "a missing label still leaves the comment" "$(log)" \
  "--method POST repos/$REPO_NAME/issues/$PR/comments"

# --- an inert map writes nothing ---------------------------------------------

run "$INERT_REPORT" GH_COMMENT_ID="" GH_LABELS="" GH_LABEL_EXISTS=1
exits "an inert map exits 0" 0 "$RUN_CODE"
contains "an inert map says so" "$RUN_OUT" "inert"
lacks "an inert map writes nothing" "$(log)" "--method"

# --- a failing gh is still a zero exit ---------------------------------------

run "$GAP_REPORT" GH_FAIL=1
exits "a gh that fails on every call exits 0" 0 "$RUN_CODE"
contains "a failing gh is a warning" "$RUN_OUT" "::warning::"

run "$GAP_REPORT" GH_COMMENT_ID="" GH_LABELS="" GH_LABEL_EXISTS=1 ENGINE_FAIL=1
exits "an engine usage error exits 0" 0 "$RUN_CODE"
contains "an engine usage error is a warning" "$RUN_OUT" "::warning::"
lacks "an engine usage error writes nothing" "$(log)" "--method"

# --- the step summary is written when the runner offers one ------------------

SUMMARY_FILE="$TEST_TMPDIR/summary.md"
: >"$SUMMARY_FILE"
run "$GAP_REPORT" GH_COMMENT_ID="" GH_LABELS="" GH_LABEL_EXISTS=1 \
  GITHUB_STEP_SUMMARY="$SUMMARY_FILE"
exits "a summarised run exits 0" 0 "$RUN_CODE"
contains "the verdict reaches the step summary" "$(cat "$SUMMARY_FILE")" "Skill evidence: gap"

test_harness::report
