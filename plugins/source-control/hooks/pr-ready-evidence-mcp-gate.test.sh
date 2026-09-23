#!/usr/bin/env bash
# Black-box contract test for pr-ready-evidence-mcp-gate.sh, the MCP-surface
# sibling of pr-ready-evidence-gate.test.sh.
#
# WHAT IS ASSERTED. The payload handling unique to this surface (a flip is
# `draft: false` and nothing else, and the origin-remote scope guard) beside the
# verdict both surfaces share (a missing row nudges, a stale terminal row
# nudges, a complete ledger says nothing). Every case asserts exit 0: this gate
# is advisory and may never fail a call.
#
# Self-contained: builds a throwaway git repository with its own evidence map
# and its own ledger file, and invokes the hook as a subprocess.

set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/pr-ready-evidence-mcp-gate.sh"

PASS=0
FAIL=0

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not on PATH -- pr-ready-evidence-mcp-gate tests skipped"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

OWNER=acme-corp
REPO_NAME=widgets
REPO="$WORK/repo"
mkdir -p "$REPO/.claude/observability"
git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.invalid
git -C "$REPO" config user.name "Evidence Test"
git -C "$REPO" remote add origin "https://github.com/$OWNER/$REPO_NAME.git"
printf 'echo base\n' >"$REPO/a.sh"
{
  printf '# source-control config\n\n## pr_skill_evidence\n\n'
  # shellcheck disable=SC2016  # the pattern field is a literal markdown code span
  printf -- '- code | `**/*.sh` | verification:confirm! simplify\n'
} >"$REPO/.claude/source-control.md"
git -C "$REPO" add -A
git -C "$REPO" commit -qm "base"
git -C "$REPO" branch -q -M main
git -C "$REPO" update-ref refs/remotes/origin/main HEAD
git -C "$REPO" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
git -C "$REPO" checkout -qb work
printf 'echo work\n' >>"$REPO/a.sh"
git -C "$REPO" commit -qam "work"
HEAD_SHA="$(git -C "$REPO" rev-parse HEAD)"
PREV_SHA="$(git -C "$REPO" rev-parse HEAD~1)"
LEDGER="$REPO/.claude/observability/skill-usage.jsonl"
# The number the create step records for the branch: what the payload's
# pullNumber is matched against.
git -C "$REPO" config branch.work.pr-number 1

ledger() {
  local pair
  : >"$LEDGER"
  for pair in "$@"; do
    printf '{"event":"SkillUse","skill":"%s","sha":"%s","ts":"2026-09-19T00:00:00Z"}\n' \
      "${pair%%=*}" "${pair#*=}" >>"$LEDGER"
  done
}

# payload <owner> <repo> <draft-json-or-empty> [tool]
payload() {
  local tool="${4:-mcp__github__update_pull_request}"
  if [[ -n "$3" ]]; then
    jq -cn --arg d "$REPO" --arg o "$1" --arg r "$2" --argjson dr "$3" --arg t "$tool" \
      '{session_id:"ready-evidence-mcp-test", cwd:$d, tool_name:$t, tool_input:{owner:$o, repo:$r, pullNumber:1, draft:$dr}}'
  else
    jq -cn --arg d "$REPO" --arg o "$1" --arg r "$2" --arg t "$tool" \
      '{session_id:"ready-evidence-mcp-test", cwd:$d, tool_name:$t, tool_input:{owner:$o, repo:$r, pullNumber:1}}'
  fi
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
nudges "draft:false with no evidence names every missing skill" \
  "$(payload $OWNER $REPO_NAME false)" \
  "verification:confirm" "simplify" "/source-control:pull-request ready" "$HEAD_SHA"

ledger "verification:confirm=$PREV_SHA" "simplify=$HEAD_SHA"
nudges "a terminal row left behind by a later commit reads stale" \
  "$(payload $OWNER $REPO_NAME false)" \
  "stale: verification:confirm" "$PREV_SHA"

# --- The target is not this checkout's pull request ---------------------------
# The ledger and HEAD describe this branch and nothing else, so a flip of some
# other pull request is never judged by them.

# payload_number <pullNumber-json>: a draft:false flip of that pull request.
payload_number() {
  jq -cn --arg d "$REPO" --arg o "$OWNER" --arg r "$REPO_NAME" --argjson n "$1" \
    '{session_id:"ready-evidence-mcp-test", cwd:$d, tool_name:"mcp__github__update_pull_request", tool_input:{owner:$o, repo:$r, pullNumber:$n, draft:false}}'
}

ledger
quiet "another pull request's number is not judged by this branch" \
  "$(payload_number 7)"

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

notices "a payload without a number cannot be matched, so it is noticed and not judged" \
  "$(payload_number null)" \
  "cannot match"
git -C "$REPO" config --unset branch.work.pr-number
notices "a flip on a branch with no recorded number is noticed and not judged" \
  "$(payload $OWNER $REPO_NAME false)" \
  "records no pull request number" "git config branch.work.pr-number 1"
git -C "$REPO" config branch.work.pr-number 1

# --- MUST STAY QUIET ----------------------------------------------------------

ledger "verification:confirm=$HEAD_SHA" "simplify=$HEAD_SHA"
quiet "a complete ledger says nothing" "$(payload $OWNER $REPO_NAME false)"

ledger
quiet "draft:true converts back to a draft and owes no evidence" \
  "$(payload $OWNER $REPO_NAME true)"
quiet "an update carrying no draft field flips nothing" \
  "$(payload $OWNER $REPO_NAME '')"
quiet "another repository's flip is out of scope" \
  "$(payload other-org other-repo false)"
quiet "a payload naming no owner is an undeterminable target" \
  "$(payload '' $REPO_NAME false)"
quiet "an unrelated tool says nothing" \
  "$(payload $OWNER $REPO_NAME false mcp__github__create_pull_request)"
quiet "empty stdin says nothing" ""

# Trailing newlines on the exact-match fields were chomped by the `$(jq ...)`
# reader this hook's batched read replaced, and must still be.
nudges "an owner with a trailing newline still names this repository" \
  "$(payload "$OWNER"$'\n' $REPO_NAME false)" \
  "verification:confirm"
nudges "a tool name with a trailing newline still matches" \
  "$(payload $OWNER $REPO_NAME false "mcp__github__update_pull_request"$'\n')" \
  "verification:confirm"

# A repository whose map declares no classes is inert.
mv "$REPO/.claude/source-control.md" "$WORK/map.md"
quiet "a repository with no evidence map is inert" "$(payload $OWNER $REPO_NAME false)"
mv "$WORK/map.md" "$REPO/.claude/source-control.md"

# Kill switch: one switch stands both surfaces down.
RC=0
OUT="$(CLAUDE_PLUGIN_OPTION_PR_READY_EVIDENCE_GATE_ENABLED=false bash "$HOOK" \
  <<<"$(payload $OWNER $REPO_NAME false)" 2>/dev/null)" || RC=$?
if ((RC == 0)) && [[ -z "$OUT" ]]; then
  pass "the kill switch stands the gate down"
else
  fail "the kill switch stands the gate down (exit $RC, output: ${OUT:-<silent>})"
fi

# --- No ledger: one notice per (session, agent), then silence -----------------
rm -f "$LEDGER"
DATA="$WORK/plugin-data"
mkdir -p "$DATA"
RC=0
FIRST="$(CLAUDE_PLUGIN_DATA="$DATA" bash "$HOOK" <<<"$(payload $OWNER $REPO_NAME false)" 2>/dev/null)" || RC=$?
SECOND="$(CLAUDE_PLUGIN_DATA="$DATA" bash "$HOOK" <<<"$(payload $OWNER $REPO_NAME false)" 2>/dev/null)"
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
