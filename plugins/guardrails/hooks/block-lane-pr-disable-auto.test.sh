#!/usr/bin/env bash
# Contract test for block-lane-pr-disable-auto.sh (guardrails plugin).
#
# Black-box: each case pipes a PreToolUse payload into the guard, alone and
# under run-guards.sh, with a fake `gh` first on PATH that answers the author
# read from FAKE_GH_AUTHOR and logs each call, and asserts the same exit code
# both ways (2 = blocked, 0 = allowed).

# shellcheck disable=SC2016  # command strings are literal test input, never expanded here
# test-scope: plugins/guardrails/hooks/hooks.json plugins/guardrails/.claude-plugin/plugin.json
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD_UNDER_TEST="$HOOK_DIR/block-lane-pr-disable-auto.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"
jq_crlf_free
unset CLAUDE_PLUGIN_OPTION_BLOCK_LANE_PR_DISABLE_AUTO_ENABLED GH_REPO GH_HOST

BIN="$TEST_TMPDIR/bin"
CALLS="$TEST_TMPDIR/calls"
mkdir -p "$BIN"

# The fake gh: `pr view` prints FAKE_GH_AUTHOR, `api graphql` prints the node
# line the guard's --jq would build. FAKE_GH_FAIL=1 fails every call.
cat >"$BIN/gh" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_GH_CALLS"
if [[ -n "${FAKE_GH_FAIL:-}" ]]; then
  echo "gh: Could not resolve to a PullRequest (HTTP 404)" >&2
  exit 1
fi
case "$1 $2" in
"pr view") printf '%s\n' "$FAKE_GH_AUTHOR" ;;
"api graphql") printf 'acme/widgets#42 %s\n' "${FAKE_GH_AUTHOR#app/}" ;;
*) exit 3 ;;
esac
FAKE
chmod +x "$BIN/gh"

LANE='app/melodic-automation-lanes'
OTHER='octocat'
REASON_LANE='was opened by the lanes App (melodic-automation-lanes[bot])'
REASON_HOLD='hold it with the do-not-merge label instead'
REASON_UNREAD='could not tell which pull request this auto-merge disable targets'

# check <label> <expected exit> <author> <command> [needle] [env word ...]
check() {
  local label="$1" expected="$2" author="$3" command="$4" needle="${5-}" via
  shift 4
  (($#)) && shift
  for via in direct dispatched; do
    : >"$CALLS"
    guard_invoke --via "$via" --command "$command" -- \
      PATH="$BIN:$PATH" FAKE_GH_CALLS="$CALLS" FAKE_GH_AUTHOR="$author" "$@"
    assert_exit "$label ($via)" "$expected" "$GUARD_RC"
    [[ -z "$needle" ]] || assert_contains "$label ($via): reason" "$GUARD_ERR" "$needle"
  done
}
calls() { cat "$CALLS" 2>/dev/null; }

# --- 1. a lanes App pull request is blocked, with the hold-label fix ----------
check "--disable-auto on a lanes App PR" 2 "$LANE" 'gh pr merge 42 -R acme/widgets --disable-auto' "$REASON_LANE"
assert_contains "lanes PR: names the do-not-merge hold" "$GUARD_ERR" "$REASON_HOLD"
assert_contains "lanes PR: gives the label command" "$GUARD_ERR" "gh pr edit 42 -R acme/widgets --add-label do-not-merge"
assert_contains "lanes PR: says the lane re-arms it" "$GUARD_ERR" "re-arms the pull request by itself when the label comes off"
assert_contains "lanes PR: names the user's escape" "$GUARD_ERR" "block_lane_pr_disable_auto_enabled"
assert_eq "lanes PR: one author read" "pr view 42 -R acme/widgets --json author --jq .author.login" "$(calls)"
check "a [bot] login from REST is read the same" 2 'melodic-automation-lanes[bot]' 'gh pr merge 42 -R acme/widgets --disable-auto' "$REASON_LANE"
check "-R before merge" 2 "$LANE" 'gh pr -R acme/widgets merge 42 --disable-auto' "$REASON_LANE"
check "a PR URL" 2 "$LANE" 'gh pr merge https://github.com/acme/widgets/pull/42 --disable-auto' "$REASON_LANE"
check "after an env prefix and in a chain" 2 "$LANE" 'git fetch && GH_PROMPT_DISABLED=1 gh pr merge 42 -R acme/widgets --disable-auto' "$REASON_LANE"
check "--disable-auto=true" 2 "$LANE" 'gh pr merge 42 -R acme/widgets --disable-auto=true' "$REASON_LANE"
check "a dangling -R before the disable does not hang the guard" 2 "$LANE" 'gh pr -R; gh pr merge 42 -R acme/widgets --disable-auto' "$REASON_LANE"
check "GraphQL with -X POST before the endpoint" 2 "$LANE" \
  'gh api -X POST graphql -f query='"'"'mutation($id:ID!){disablePullRequestAutoMerge(input:{pullRequestId:$id}){clientMutationId}}'"'"' -f id=PR_kwDOabc' "$REASON_LANE"
check "no -R, no directory change" 2 "$LANE" 'gh pr merge 42 --disable-auto' "$REASON_LANE"
check "GraphQL disablePullRequestAutoMerge" 2 "$LANE" \
  'gh api graphql -f query='"'"'mutation($id:ID!){disablePullRequestAutoMerge(input:{pullRequestId:$id}){clientMutationId}}'"'"' -f id=PR_kwDOabc' "$REASON_LANE"
assert_contains "GraphQL: the node is read" "$(calls)" "id=PR_kwDOabc"
check "GraphQL inline id" 2 "$LANE" \
  'gh api graphql -f query='"'"'mutation{disablePullRequestAutoMerge(input:{pullRequestId:"PR_kwDOabc"}){clientMutationId}}'"'"'' "$REASON_LANE"

# --- 2. a pull request by another author passes ------------------------------
check "--disable-auto on another author's PR" 0 "$OTHER" 'gh pr merge 42 -R acme/widgets --disable-auto'
assert_eq "other author: no stderr" "" "$GUARD_ERR"
check "GraphQL on another author's PR" 0 "$OTHER" \
  'gh api graphql -f query='"'"'mutation($id:ID!){disablePullRequestAutoMerge(input:{pullRequestId:$id}){clientMutationId}}'"'"' -f id=PR_kwDOabc'

# --- 3. a target the guard cannot read is blocked ----------------------------
check "a PR number from a variable" 2 "$OTHER" 'gh pr merge "$N" -R acme/widgets --disable-auto' "$REASON_UNREAD"
assert_eq "variable target: gh is never asked" "" "$(calls)"
check "a repo from a variable" 2 "$OTHER" 'gh pr merge 42 -R "$REPO" --disable-auto' "$REASON_UNREAD"
check "a PR number from \$(...)" 2 "$OTHER" 'gh pr merge "$(gh pr list --json number -q .[0].number)" -R acme/widgets --disable-auto' "$REASON_UNREAD"
check "a backtick" 2 "$OTHER" 'gh pr merge `echo 42` -R acme/widgets --disable-auto' "$REASON_UNREAD"
check "no PR number" 2 "$OTHER" 'gh pr merge --disable-auto' "$REASON_UNREAD"
check "a gh pr subcommand from a variable" 2 "$OTHER" 'gh pr $VERB 42 -R acme/widgets --disable-auto' "$REASON_UNREAD"
check "no -R after a cd" 2 "$OTHER" 'cd ../other && gh pr merge 42 --disable-auto' "could not tell which repository"
check "no -R with GH_REPO" 2 "$OTHER" 'GH_REPO=acme/other gh pr merge 42 --disable-auto' "could not tell which repository"
check "GraphQL id from a variable" 2 "$OTHER" \
  'gh api graphql -f query='"'"'mutation($id:ID!){disablePullRequestAutoMerge(input:{pullRequestId:$id}){clientMutationId}}'"'"' -f id="$ID"' "$REASON_UNREAD"
check "GraphQL with two ids" 2 "$OTHER" \
  'gh api graphql -f query='"'"'mutation($id:ID!){disablePullRequestAutoMerge(input:{pullRequestId:$id}){clientMutationId}}'"'"' -f id=PR_a -f other=PR_b' "$REASON_UNREAD"
check "an author read that fails" 2 "$OTHER" 'gh pr merge 42 -R acme/widgets --disable-auto' "could not read the author" FAKE_GH_FAIL=1

# --- 4. what the guard leaves alone ------------------------------------------
check "--disable-auto=false" 0 "$LANE" 'gh pr merge 42 -R acme/widgets --disable-auto=false'
assert_eq "--disable-auto=false: gh is never asked" "" "$(calls)"
check "a merge without --disable-auto" 0 "$LANE" 'gh pr merge 42 -R acme/widgets --auto --squash'
assert_eq "no disable: gh is never asked" "" "$(calls)"
check "the flag named in prose" 0 "$LANE" 'echo "never run gh pr merge --disable-auto on a lanes PR"'
assert_eq "prose: gh is never asked" "" "$(calls)"
check "the kill switch" 0 "$LANE" 'gh pr merge 42 -R acme/widgets --disable-auto' "" CLAUDE_PLUGIN_OPTION_BLOCK_LANE_PR_DISABLE_AUTO_ENABLED=false
for via in direct dispatched; do
  guard_invoke --via "$via" --tool PowerShell --command 'gh pr merge 42 -R acme/widgets --disable-auto' -- \
    PATH="$BIN:$PATH" FAKE_GH_CALLS="$CALLS" FAKE_GH_AUTHOR="$LANE"
  assert_exit "the PowerShell tool is not matched ($via)" 0 "$GUARD_RC"
done

report
