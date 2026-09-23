#!/usr/bin/env bash
# Black-box contract test for pr-ready-evidence-gate.sh: the payload goes in on
# stdin, the verdict comes out as the hook's stdout JSON and its exit status,
# and nothing inside the hook is sourced or stubbed.
#
# WHAT IS ASSERTED. Two halves, side by side per the hook-precision discipline:
# the MUST-NUDGE cases (a mandatory skill with no row at HEAD, a terminal row
# left behind by a later commit) and the MUST-STAY-QUIET cases (a complete
# ledger, a command that is not a ready flip, a flip that follows a directory
# change, a flip aimed at another repository, an undo, the kill switch off, and
# a payload for another tool). Every case also asserts exit 0: this gate is
# advisory and may never fail a call, whatever it finds.
#
# Self-contained: builds a throwaway git repository with its own evidence map
# and its own ledger file, and invokes the hook as a subprocess.

set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/pr-ready-evidence-gate.sh"

PASS=0
FAIL=0

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not on PATH -- pr-ready-evidence-gate tests skipped"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

REPO="$WORK/repo"
mkdir -p "$REPO/.claude/observability"
git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.invalid
git -C "$REPO" config user.name "Evidence Test"
printf 'echo base\n' >"$REPO/a.sh"
{
  printf '# source-control config\n\n## pr_skill_evidence\n\n'
  # shellcheck disable=SC2016  # the pattern field is a literal markdown code span
  printf -- '- code | `**/*.sh` | verification:confirm! simplify\n'
} >"$REPO/.claude/source-control.md"
git -C "$REPO" add -A
git -C "$REPO" commit -qm "base"
git -C "$REPO" branch -q -M main
# The base the hook resolves: a remote-tracking ref plus the origin/HEAD
# symbolic ref a real clone carries.
git -C "$REPO" update-ref refs/remotes/origin/main HEAD
git -C "$REPO" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
git -C "$REPO" checkout -qb work
printf 'echo work\n' >>"$REPO/a.sh"
git -C "$REPO" commit -qam "work"
HEAD_SHA="$(git -C "$REPO" rev-parse HEAD)"
PREV_SHA="$(git -C "$REPO" rev-parse HEAD~1)"
LEDGER="$REPO/.claude/observability/skill-usage.jsonl"
# The number the create step records for the branch: what a numbered flip is
# matched against.
git -C "$REPO" config branch.work.pr-number 1

# ledger <skill>=<sha>...: rewrite the ledger with one SkillUse row per pair.
ledger() {
  local pair
  : >"$LEDGER"
  for pair in "$@"; do
    printf '{"event":"SkillUse","skill":"%s","sha":"%s","ts":"2026-09-19T00:00:00Z"}\n' \
      "${pair%%=*}" "${pair#*=}" >>"$LEDGER"
  done
}

# payload <command> [tool]: a Bash PreToolUse envelope rooted at the fixture.
payload() {
  jq -cn --arg d "$REPO" --arg c "$1" --arg t "${2:-Bash}" \
    '{session_id:"ready-evidence-test", cwd:$d, tool_name:$t, tool_input:{command:$c}}'
}

OUT=""
RC=0
invoke() {
  OUT="$(bash "$HOOK" <<<"$1" 2>/dev/null)"
  RC=$?
}

pass() {
  PASS=$((PASS + 1))
  echo "ok: $1"
}
fail() {
  FAIL=$((FAIL + 1))
  echo "FAIL: $1" >&2
}

# nudges <name> <payload> <substring>...: the hook emits additionalContext
# carrying every substring, and still exits 0.
nudges() {
  local name="$1" p="$2" want
  shift 2
  invoke "$p"
  if ((RC != 0)); then
    fail "$name: exit $RC, an advisory gate must exit 0"
    return
  fi
  if [[ "$OUT" != *additionalContext* ]]; then
    fail "$name: no additionalContext in the hook output (got: ${OUT:-<silent>})"
    return
  fi
  for want in "$@"; do
    if [[ "$OUT" != *"$want"* ]]; then
      fail "$name: additionalContext does not name '$want'"
      return
    fi
  done
  pass "$name"
}

# quiet <name> <payload>: the hook prints nothing and exits 0.
quiet() {
  local name="$1"
  invoke "$2"
  if ((RC != 0)); then
    fail "$name: exit $RC, an advisory gate must exit 0"
  elif [[ -n "$OUT" ]]; then
    fail "$name: expected silence, got: $OUT"
  else
    pass "$name"
  fi
}

# --- MUST NUDGE ---------------------------------------------------------------

ledger
nudges "a ready flip with no evidence names every missing skill" \
  "$(payload 'gh pr ready 1')" \
  "verification:confirm" "simplify" "/source-control:pull-request ready" "$HEAD_SHA"

ledger "verification:confirm=$PREV_SHA" "simplify=$HEAD_SHA"
nudges "a terminal row left behind by a later commit reads stale" \
  "$(payload 'gh pr ready')" \
  "stale: verification:confirm" "$PREV_SHA"

ledger
nudges "a flip reached through bash -c is still parsed" \
  "$(payload "bash -c 'gh pr ready 1'")" \
  "verification:confirm"

# The cloud proxy's own route. A session with no GraphQL is told to POST this
# path by name, so it is a flip and not a REST lookalike.
nudges "the cloud proxy's ccr ready_for_review route is a ready flip" \
  "$(payload 'gh api --method POST repos/acme/widgets/pulls/1/ccr/ready_for_review')" \
  "verification:confirm"

# The operand forms gh documents, each matched to this checkout's branch.
nudges "a URL operand is read by its trailing number" \
  "$(payload 'gh pr ready https://github.com/acme/widgets/pull/1')" \
  "verification:confirm"
nudges "a branch operand naming the current branch is this checkout's flip" \
  "$(payload 'gh pr ready work')" \
  "verification:confirm"
nudges "an operand after -- is still the target" \
  "$(payload 'gh pr ready -- 1')" \
  "verification:confirm"

# --- The target is not this checkout's pull request ---------------------------
# The ledger and HEAD describe this branch and nothing else, so a flip of some
# other pull request is never judged by them: provably another one is silent,
# and one the gate cannot match is noticed once and left unjudged.

ledger
quiet "another pull request's number is not judged by this branch" \
  "$(payload 'gh pr ready 7')"
quiet "another branch's flip is not judged by this branch" \
  "$(payload 'gh pr ready feature/other')"
quiet "the cloud route naming another pull request is not judged" \
  "$(payload 'gh api --method POST repos/acme/widgets/pulls/7/ccr/ready_for_review')"

# notices <name> <payload> <substring>...: a once-per-session skip notice
# carrying every substring, on both channels, and never the nudge's
# "missing:" line.
notices() {
  local name="$1" p="$2" want
  shift 2
  local data="$WORK/notice-$RANDOM"
  RC=0
  OUT="$(CLAUDE_PLUGIN_DATA="$data" bash "$HOOK" <<<"$p" 2>/dev/null)" || RC=$?
  if ((RC != 0)); then
    fail "$name: exit $RC, an advisory gate must exit 0"
    return
  fi
  if [[ "$OUT" != *systemMessage* || "$OUT" == *"missing:"* ]]; then
    fail "$name: expected a skip notice, got: ${OUT:-<silent>}"
    return
  fi
  for want in "$@"; do
    if [[ "$OUT" != *"$want"* ]]; then
      fail "$name: the notice does not name '$want'"
      return
    fi
  done
  pass "$name"
}

notices "the GraphQL mutation names a node id the gate cannot match, so it is noticed and not judged" \
  "$(payload "gh api graphql -f query='mutation { markPullRequestReadyForReview(input: {pullRequestId: \"x\"}) { clientMutationId } }'")" \
  "cannot match" "gh pr ready <number>"

git -C "$REPO" config --unset branch.work.pr-number
notices "a numbered flip on a branch with no recorded number is noticed and not judged" \
  "$(payload 'gh pr ready 1')" \
  "records no pull request number" "git config branch.work.pr-number 1"
ledger
nudges "a bare flip on that branch is still gh's current-branch flip and is judged" \
  "$(payload 'gh pr ready')" \
  "verification:confirm"
git -C "$REPO" config branch.work.pr-number 1

# --- MUST STAY QUIET ----------------------------------------------------------

ledger "verification:confirm=$HEAD_SHA" "simplify=$HEAD_SHA"
quiet "a complete ledger says nothing" "$(payload 'gh pr ready 1')"

ledger
quiet "a directory change earlier on the line puts the flip out of scope" \
  "$(payload 'cd /tmp && gh pr ready 1')"
quiet "another repository's flip is out of scope" \
  "$(payload 'gh pr ready 1 --repo other-org/other-repo')"
quiet "the short repo flag is out of scope too" \
  "$(payload 'gh pr ready -R other-org/other-repo')"
quiet "--undo converts back to a draft and owes no evidence" \
  "$(payload 'gh pr ready --undo')"
quiet "--help prints and flips nothing" "$(payload 'gh pr ready --help')"
quiet "a gh command that is not a ready flip says nothing" \
  "$(payload 'gh pr view 1')"
quiet "an unrelated gh api endpoint says nothing" \
  "$(payload 'gh api -X POST repos/acme/widgets/pulls/1/comments')"
quiet "a pull request read over the same path prefix is not a flip" \
  "$(payload 'gh api repos/acme/widgets/pulls/1')"
quiet "a GraphQL call that is not the mutation says nothing" \
  "$(payload "gh api graphql -f query='query { viewer { login } }'")"
quiet "a payload for another tool says nothing" \
  "$(payload 'gh pr ready 1' 'Read')"
quiet "empty stdin says nothing" ""

# A repository whose map declares no classes is inert: the mechanism is off
# there and the gate must not invent a verdict.
mv "$REPO/.claude/source-control.md" "$WORK/map.md"
quiet "a repository with no evidence map is inert" "$(payload 'gh pr ready 1')"
mv "$WORK/map.md" "$REPO/.claude/source-control.md"

# Kill switch: the whole gate stands down, nudge included.
RC=0
OUT="$(CLAUDE_PLUGIN_OPTION_PR_READY_EVIDENCE_GATE_ENABLED=false bash "$HOOK" \
  <<<"$(payload 'gh pr ready 1')" 2>/dev/null)" || RC=$?
if ((RC == 0)) && [[ -z "$OUT" ]]; then
  pass "the kill switch stands the gate down"
else
  fail "the kill switch stands the gate down (exit $RC, output: ${OUT:-<silent>})"
fi

# --- No ledger: one notice per (session, agent), then silence -----------------
# The notice is the visible half of a skip this gate cannot avoid; repeating it
# on every flip is the defect hook::notice_once exists to prevent.
rm -f "$LEDGER"
DATA="$WORK/plugin-data"
mkdir -p "$DATA"
RC=0
FIRST="$(CLAUDE_PLUGIN_DATA="$DATA" bash "$HOOK" <<<"$(payload 'gh pr ready 1')" 2>/dev/null)" || RC=$?
SECOND="$(CLAUDE_PLUGIN_DATA="$DATA" bash "$HOOK" <<<"$(payload 'gh pr ready 1')" 2>/dev/null)"
if ((RC == 0)) && [[ "$FIRST" == *"no skill-usage ledger"* ]] && [[ "$FIRST" == *"claude-ops"* ]] &&
  [[ "$FIRST" == *"skill_evidence_store"* ]] && [[ "$FIRST" != *"/source-control:pull-request ready"* ]]; then
  pass "a missing ledger is noticed, naming the claude-ops pairing and the option"
else
  fail "a missing ledger is noticed, naming the claude-ops pairing and the option (exit $RC, output: ${FIRST:-<silent>})"
fi
if [[ -z "$SECOND" ]]; then
  pass "the missing-ledger notice does not repeat in the same session"
else
  fail "the missing-ledger notice repeated: $SECOND"
fi

echo
echo "pass=$PASS fail=$FAIL"
((FAIL == 0))
