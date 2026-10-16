#!/usr/bin/env bash
# Contract test for block-unresolved-pr-merge.sh (guardrails plugin).
#
# Black-box: invokes the hook as a subprocess with a PreToolUse payload on
# stdin and a fake `gh` first on PATH. The fake answers each `gh api` endpoint
# from a fixture file, applies the guard's own --jq filter with the real jq,
# and logs every endpoint it was asked for, so a stay-quiet case can also prove
# the guard never reached the network.

# shellcheck disable=SC2016  # command strings are literal test input, never expanded here
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/block-unresolved-pr-merge.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"
jq_crlf_free
unset CLAUDE_CODE_REMOTE CLAUDE_PLUGIN_OPTION_BLOCK_UNRESOLVED_PR_MERGE_ENABLED

FIX="$TEST_TMPDIR/fixtures"
BIN="$TEST_TMPDIR/bin"
mkdir -p "$FIX" "$BIN"

# --- the fake gh ----------------------------------------------------------------
cat >"$BIN/gh" <<'FAKE'
#!/usr/bin/env bash
fix="$FAKE_GH_DIR"
[[ "${1-}" == api ]] || exit 3
shift
endpoint="" filter="" query=""
while (($#)); do
  case "$1" in
  --jq | -q) filter="$2"; shift 2 ;;
  -f | -F | --raw-field | --field)
    [[ "$2" == query=* ]] && query="${2#query=}"
    [[ "$2" == id=* ]] && printf 'node %s\n' "${2#id=}" >>"$fix/calls"
    shift 2
    ;;
  -X | --method | -H | --header) shift 2 ;;
  -*) shift ;;
  *) [[ -z "$endpoint" ]] && endpoint="$1"; shift ;;
  esac
done
printf '%s\n' "$endpoint" >>"$fix/calls"
# exec, so a timeout kills this process itself and no orphan holds the pipe.
[[ -n "${FAKE_GH_SLEEP:-}" ]] && exec sleep "$FAKE_GH_SLEEP"
# A slow but answering gh: each call waits, then serves its fixture.
[[ -n "${FAKE_GH_DELAY:-}" ]] && sleep "$FAKE_GH_DELAY"
if [[ -f "$fix/fail" ]]; then
  echo "gh: Bad credentials (HTTP 401)" >&2
  exit 1
fi
case "$endpoint" in
graphql)
  if [[ -f "$fix/graphql_refused" ]]; then
    echo "gh: GitHub GraphQL is not available from Claude Code sessions; use the REST API (HTTP 403)" >&2
    exit 1
  fi
  if [[ "$query" == *"node("* ]]; then f=graphql_node.json; else f=graphql_threads.json; fi
  ;;
*/ccr/review_threads) f=ccr.json ;;
*/reviews\?*) f=reviews.json ;;
*/check-runs\?*) f=checks.json ;;
*/status\?*) f=status.json ;;
*/pulls\?*) f=pulls_list.json ;;
*/pulls/[0-9]*) f=pr.json ;;
*) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
esac
if [[ ! -f "$fix/$f" ]]; then
  echo "gh: Not Found (HTTP 404)" >&2
  exit 1
fi
if [[ -n "$filter" ]]; then
  jq -r "$filter" "$fix/$f" || exit 1
else
  cat "$fix/$f"
fi
FAKE
chmod +x "$BIN/gh"

# scenario <threads> <changes> <checks> <statuses>: write a fresh fixture set.
#   threads:  none | unresolved | resolved
#   changes:  none | requested | requested-then-approved
#   checks:   green | failed | pending
#   statuses: green | failed | pending
scenario() {
  rm -rf "$FIX"
  mkdir -p "$FIX"
  : >"$FIX/calls"
  cat >"$FIX/pr.json" <<'J'
{"state":"open","head":{"sha":"abc123"},"base":{"repo":{"full_name":"acme/widgets"}}}
J
  echo '[{"number":42}]' >"$FIX/pulls_list.json"
  echo '{"data":{"node":{"number":42,"repository":{"nameWithOwner":"acme/widgets"}}}}' >"$FIX/graphql_node.json"
  local resolved=false
  [[ "$1" == resolved ]] && resolved=true
  if [[ "$1" == none ]]; then
    echo '{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false},"nodes":[]}}}}}' >"$FIX/graphql_threads.json"
    echo '[]' >"$FIX/ccr.json"
  else
    cat >"$FIX/graphql_threads.json" <<J
{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false},"nodes":[
 {"isResolved":$resolved,"path":"src/app.py","line":12,"originalLine":12,
  "comments":{"nodes":[{"body":"P2: this drops the error\nmore detail","url":"https://github.com/acme/widgets/pull/42#discussion_r7"}]}}]}}}}}
J
    echo "[{\"resolved\":$resolved,\"outdated\":false,\"path\":\"src/app.py\",\"line\":12,\"comment_ids\":[7,8]}]" >"$FIX/ccr.json"
  fi
  case "$2" in
  none) echo '[{"user":{"login":"amy"},"state":"COMMENTED"}]' >"$FIX/reviews.json" ;;
  requested) echo '[{"user":{"login":"amy"},"state":"APPROVED"},{"user":{"login":"bob"},"state":"CHANGES_REQUESTED"},{"user":{"login":"bob"},"state":"COMMENTED"}]' >"$FIX/reviews.json" ;;
  requested-then-approved) echo '[{"user":{"login":"bob"},"state":"CHANGES_REQUESTED"},{"user":{"login":"bob"},"state":"APPROVED"}]' >"$FIX/reviews.json" ;;
  *) return 1 ;;
  esac
  case "$3" in
  green) echo '{"total_count":2,"check_runs":[{"name":"build","status":"completed","conclusion":"success"},{"name":"lint","status":"completed","conclusion":"skipped"}]}' >"$FIX/checks.json" ;;
  failed) echo '{"total_count":2,"check_runs":[{"name":"build","status":"completed","conclusion":"failure"},{"name":"lint","status":"completed","conclusion":"success"}]}' >"$FIX/checks.json" ;;
  pending) echo '{"total_count":1,"check_runs":[{"name":"build","status":"in_progress","conclusion":null}]}' >"$FIX/checks.json" ;;
  # Two runs of one check on one head (#7473, azure-iac#26): the newer listed
  # first, as the endpoint returned them there.
  superseded-failure | superseded-cancelled)
    local old="${3#superseded-}"
    echo '{"total_count":2,"check_runs":[{"id":902,"name":"ci-status","app":{"id":15368},"status":"completed","conclusion":"success","started_at":"2026-10-14T16:55:30Z","completed_at":"2026-10-14T16:55:43Z"},{"id":901,"name":"ci-status","app":{"id":15368},"status":"completed","conclusion":"'"$old"'","started_at":"2026-10-14T15:29:01Z","completed_at":"2026-10-14T15:29:16Z"}]}' >"$FIX/checks.json"
    ;;
  regressed) echo '{"total_count":2,"check_runs":[{"id":901,"name":"ci-status","app":{"id":15368},"status":"completed","conclusion":"success","started_at":"2026-10-14T15:29:01Z","completed_at":"2026-10-14T15:29:16Z"},{"id":902,"name":"ci-status","app":{"id":15368},"status":"completed","conclusion":"failure","started_at":"2026-10-14T16:55:30Z","completed_at":"2026-10-14T16:55:43Z"}]}' >"$FIX/checks.json" ;;
  # The newer run (higher id) failed but finished before the older success did,
  # or carries a caller-set future completed_at on the older success.
  regressed-early) echo '{"total_count":2,"check_runs":[{"id":901,"name":"ci-status","app":{"id":15368},"status":"completed","conclusion":"success","started_at":"2026-10-14T10:00:00Z","completed_at":"2099-01-01T00:00:00Z"},{"id":902,"name":"ci-status","app":{"id":15368},"status":"completed","conclusion":"failure","started_at":"2026-10-14T10:05:00Z","completed_at":"2026-10-14T10:10:00Z"}]}' >"$FIX/checks.json" ;;
  # A newer run still in progress, started before the older one completed.
  newer-pending) echo '{"total_count":2,"check_runs":[{"id":901,"name":"ci-status","app":{"id":15368},"status":"completed","conclusion":"success","started_at":"2026-10-14T10:00:00Z","completed_at":"2026-10-14T10:10:00Z"},{"id":902,"name":"ci-status","app":{"id":15368},"status":"in_progress","conclusion":null,"started_at":"2026-10-14T10:05:00Z","completed_at":null}]}' >"$FIX/checks.json" ;;
  # An older run still in progress, then a newer run that skipped the job.
  pending-then-skipped) echo '{"total_count":2,"check_runs":[{"id":901,"name":"test","app":{"id":15368},"status":"in_progress","conclusion":null,"started_at":"2026-10-14T10:00:00Z","completed_at":null},{"id":902,"name":"test","app":{"id":15368},"status":"completed","conclusion":"skipped","started_at":"2026-10-14T10:20:00Z","completed_at":"2026-10-14T10:20:00Z"}]}' >"$FIX/checks.json" ;;
  # A later event skipped the job that had failed.
  failed-then-skipped) echo '{"total_count":2,"check_runs":[{"id":901,"name":"test","app":{"id":15368},"status":"completed","conclusion":"failure","started_at":"2026-10-14T10:00:00Z","completed_at":"2026-10-14T10:10:00Z"},{"id":902,"name":"test","app":{"id":15368},"status":"completed","conclusion":"skipped","started_at":"2026-10-14T10:20:00Z","completed_at":"2026-10-14T10:20:00Z"}]}' >"$FIX/checks.json" ;;
  # An older run cancelled, then a newer run that skipped the job (#7549).
  cancelled-then-skipped) echo '{"total_count":2,"check_runs":[{"id":901,"name":"test-bash","app":{"id":15368},"status":"completed","conclusion":"cancelled","started_at":"2026-10-16T05:22:25Z","completed_at":"2026-10-16T05:22:40Z"},{"id":902,"name":"test-bash","app":{"id":15368},"status":"completed","conclusion":"skipped","started_at":"2026-10-16T05:25:10Z","completed_at":"2026-10-16T05:25:10Z"}]}' >"$FIX/checks.json" ;;
  # A failure, then a cancelled run, then a skipped one: the failure still counts.
  failed-cancelled-skipped) echo '{"total_count":3,"check_runs":[{"id":900,"name":"test","app":{"id":15368},"status":"completed","conclusion":"failure","started_at":"2026-10-14T09:50:00Z","completed_at":"2026-10-14T09:55:00Z"},{"id":901,"name":"test","app":{"id":15368},"status":"completed","conclusion":"cancelled","started_at":"2026-10-14T10:00:00Z","completed_at":"2026-10-14T10:01:00Z"},{"id":902,"name":"test","app":{"id":15368},"status":"completed","conclusion":"skipped","started_at":"2026-10-14T10:20:00Z","completed_at":"2026-10-14T10:20:00Z"}]}' >"$FIX/checks.json" ;;
  # An older success, then a newer run that was cancelled.
  newer-cancelled) echo '{"total_count":2,"check_runs":[{"id":901,"name":"test","app":{"id":15368},"status":"completed","conclusion":"success","started_at":"2026-10-14T10:00:00Z","completed_at":"2026-10-14T10:10:00Z"},{"id":902,"name":"test","app":{"id":15368},"status":"completed","conclusion":"cancelled","started_at":"2026-10-14T10:20:00Z","completed_at":"2026-10-14T10:21:00Z"}]}' >"$FIX/checks.json" ;;
  *) return 1 ;;
  esac
  case "$4" in
  green) echo '{"state":"success","statuses":[{"context":"ci/legacy","state":"success"}]}' >"$FIX/status.json" ;;
  failed) echo '{"state":"failure","statuses":[{"context":"ci/legacy","state":"error"}]}' >"$FIX/status.json" ;;
  pending) echo '{"state":"pending","statuses":[{"context":"ci/legacy","state":"pending"}]}' >"$FIX/status.json" ;;
  *) return 1 ;;
  esac
}

OUT=""
ERR=""
RC=0
# invoke <payload> [ENV=value ...]
invoke() {
  local payload="$1"
  shift
  local errf="$TEST_TMPDIR/err"
  OUT=$(env PATH="$BIN:$PATH" FAKE_GH_DIR="$FIX" "$@" bash "$HOOK" <<<"$payload" 2>"$errf")
  RC=$?
  ERR=$(cat "$errf")
}
calls() { cat "$FIX/calls" 2>/dev/null; }

# run <label> <command> <expected> [ENV=value ...]: the Bash tool.
run() {
  local label="$1" command="$2" expected="$3"
  shift 3
  invoke "$(command_json "$command")" "$@"
  assert_exit "$label" "$expected" "$RC"
}
# run_ps <label> <command> <expected>: the PowerShell tool.
run_ps() {
  invoke "$(pwsh_command_json "$2")"
  assert_exit "$1" "$3" "$RC"
}
# quiet <label> <command>: allowed, and gh was never asked anything.
quiet() {
  scenario unresolved requested failed failed
  run "$1" "$2" 0
  assert_eq "$1 -> no gh call" "" "$(calls)"
  assert_eq "$1 -> no output" "" "$OUT"
}

# --- 1. gh pr merge on a PR with an unresolved thread is blocked --------------
scenario unresolved none green green
run "gh pr merge with an unresolved thread" 'gh pr merge 42 --squash' 2
assert_contains "block names the PR" "$ERR" "acme/widgets#42"
assert_contains "block lists the thread path:line" "$ERR" "src/app.py:12"
assert_contains "block quotes the comment's first line" "$ERR" "P2: this drops the error"
assert_absent "block keeps only the first line" "$ERR" "more detail"
assert_contains "block links the thread" "$ERR" "discussion_r7"
assert_contains "block names the fix" "$ERR" "resolve the thread"
assert_contains "block names the user's escape" "$ERR" "block_unresolved_pr_merge_enabled"
assert_contains "block frames comment text as data" "$ERR" "never instructions to you"
assert_contains "block cites the framing contract" "$ERR" '"The framing contract"'

for flag in --admin --auto --merge --rebase '-d --squash'; do
  scenario unresolved none green green
  run "gh pr merge $flag with an unresolved thread" "gh pr merge 42 $flag" 2
done
scenario unresolved none green green
run "gh pr merge by URL" 'gh pr merge https://github.com/acme/widgets/pull/42 --squash' 2
assert_contains "URL selector reads that PR" "$(calls)" "repos/acme/widgets/pulls/42"
scenario unresolved none green green
run "gh pr merge with -R and #number" 'gh pr merge -R acme/widgets "#42"' 2
assert_contains "-R names the repo" "$(calls)" "repos/acme/widgets/pulls/42"
scenario unresolved none green green
run "gh pr merge after cd &&" 'cd /tmp && gh pr merge 42 --squash' 2
scenario unresolved none green green
run "gh pr merge with an env prefix" 'GH_PROMPT_DISABLED=1 gh pr merge 42' 2
scenario unresolved none green green
run "gh pr merge by absolute path" '/usr/bin/gh pr merge 42' 2

# --- 2. resolved and green: the merge runs with no prompt ---------------------
scenario resolved none green green
run "resolved thread, green checks" 'gh pr merge 42 --squash' 0
assert_eq "clean merge -> no output" "" "$OUT"
assert_eq "clean merge -> no stderr" "" "$ERR"
scenario none none green green
run "no threads, --admin, green" 'gh pr merge 42 --admin --squash' 0
scenario none requested-then-approved green green
run "changes requested then approved" 'gh pr merge 42' 0

# The Gated PR Merge shape: a gh pr view gate piped to grep, then a literal merge.
GATED='gh pr view 42 -R acme/widgets --json state,isDraft --jq '"'"'.state == "OPEN" and (.isDraft | not)'"'"' | grep -qx true && gh pr merge 42 -R acme/widgets --squash --match-head-commit abc123'
scenario resolved none green green
run "gated merge on a clean PR" "$GATED" 0
assert_eq "gated merge clean -> no output" "" "$OUT"
assert_contains "gated merge reads the -R PR" "$(calls)" "repos/acme/widgets/pulls/42"
scenario unresolved none green green
run "gated merge with an open thread" "$GATED" 2
assert_contains "gated merge blocked -> lists the thread" "$ERR" "src/app.py:12"

# --- 3. change requests and checks ---------------------------------------------
scenario none requested green green
run "changes requested" 'gh pr merge 42' 2
assert_contains "names the reviewer" "$ERR" "Changes requested by: bob"
assert_absent "an approving reviewer is not listed" "$ERR" "amy"
scenario none none failed green
run "failed check run" 'gh pr merge 42 --auto' 2
assert_contains "names the failed check" "$ERR" "Failing checks: build"
scenario none none green failed
run "failed commit status" 'gh pr merge 42' 2
assert_contains "names the failed status" "$ERR" "ci/legacy"
scenario none none pending pending
run "pending checks block an immediate merge" 'gh pr merge 42 --squash' 2
assert_contains "names the pending checks" "$ERR" "Pending checks"
scenario none none pending pending
run "pending checks do not block --auto" 'gh pr merge 42 --auto --squash' 0
# Only the newest run of a check on the head counts (#7473).
for old in failure cancelled; do
  scenario none none "superseded-$old" green
  run "older $old superseded by a newer success" 'gh pr merge 42 --squash --match-head-commit abc123' 0
  assert_eq "superseded $old -> no stderr" "" "$ERR"
done
scenario none none regressed green
run "older success, newer failure" 'gh pr merge 42 --squash' 2
assert_contains "names the regressed check" "$ERR" "Failing checks: ci-status"
scenario none none regressed-early green
run "newer failure that finished before the older success" 'gh pr merge 42 --squash' 2
assert_contains "names the early-finishing failure" "$ERR" "Failing checks: ci-status"
scenario none none newer-pending green
run "newer pending run over an older success" 'gh pr merge 42 --squash' 2
assert_contains "names the newer pending run" "$ERR" "Pending checks (use --auto to merge once they pass): ci-status"
scenario none none failed-then-skipped green
run "a later skipped run does not clear a failure" 'gh pr merge 42 --squash' 2
assert_contains "names the skipped-over failure" "$ERR" "Failing checks: test"
scenario none none pending-then-skipped green
run "a newer skipped run supersedes an older pending one" 'gh pr merge 42 --squash' 0
assert_eq "pending then skipped -> no stderr" "" "$ERR"
scenario none none cancelled-then-skipped green
run "a newer skipped run supersedes an older cancelled one" 'gh pr merge 42 --squash' 0
assert_eq "cancelled then skipped -> no stderr" "" "$ERR"
scenario none none failed-cancelled-skipped green
run "a cancelled run between a failure and a skip does not clear the failure" 'gh pr merge 42 --squash' 2
assert_contains "names the failure behind the cancelled run" "$ERR" "Failing checks: test"
scenario none none newer-cancelled green
run "a newest cancelled run still blocks" 'gh pr merge 42 --squash' 2
assert_contains "names the cancelled check" "$ERR" "Failing checks: test"

# --- 4. REST, GraphQL and curl merge paths -------------------------------------
scenario unresolved none green green
run "gh api PUT pulls/n/merge" 'gh api -X PUT repos/acme/widgets/pulls/42/merge -f merge_method=squash' 2
scenario unresolved none green green
run "gh api --method put /repos/.../merge" 'gh api --method put /repos/acme/widgets/pulls/42/merge' 2
scenario unresolved none green green
run "gh api placeholders PUT merge" 'gh api -X PUT "repos/{owner}/{repo}/pulls/42/merge"' 2
scenario unresolved none green green
run "gh api PUT ccr/auto_merge" 'gh api -X PUT repos/acme/widgets/pulls/42/ccr/auto_merge' 2
scenario none none pending green
run "ccr auto_merge waits on pending checks" 'gh api -X PUT repos/acme/widgets/pulls/42/ccr/auto_merge' 0
scenario unresolved none green green
run "curl PUT merge" 'curl -sS -X PUT -H "Authorization: Bearer x" https://api.github.com/repos/acme/widgets/pulls/42/merge' 2
scenario unresolved none green green
run "gh api graphql mergePullRequest" 'gh api graphql -f query='"'"'mutation{mergePullRequest(input:{pullRequestId:"PR_kwDOabc"}){clientMutationId}}'"'"'' 2
assert_contains "node id resolved over GraphQL" "$(calls)" "graphql"
scenario unresolved none green green
run "gh api graphql enablePullRequestAutoMerge" 'gh api graphql -f query='"'"'mutation($id:ID!){enablePullRequestAutoMerge(input:{pullRequestId:$id}){clientMutationId}}'"'"' -f id=PR_kwDOabc' 2
scenario unresolved none green green
run "curl graphql enqueuePullRequest" 'curl -s https://api.github.com/graphql -d '"'"'{"query":"mutation{enqueuePullRequest(input:{pullRequestId:\"PR_kwDOabc\"}){clientMutationId}}"}'"'"'' 2
scenario unresolved none green green
run "curl graphql, id in JSON variables" 'curl -s https://api.github.com/graphql -d '"'"'{"query":"mutation($id:ID!){mergePullRequest(input:{pullRequestId:$id}){clientMutationId}}","variables":{"id":"PR_kwDOabc"}}'"'"'' 2
assert_contains "JSON variable -> that node is resolved" "$(calls)" "node PR_kwDOabc"
assert_contains "JSON variable -> the thread is listed" "$ERR" "src/app.py:12"
scenario unresolved none green green
run "curl graphql, JSON-escaped variables" 'curl -s https://api.github.com/graphql -d "{\"query\":\"mutation(\$id:ID!){mergePullRequest(input:{pullRequestId:\$id}){clientMutationId}}\",\"variables\":{\"id\":\"PR_kwDOesc\"}}"' 2
assert_contains "escaped JSON variable -> that node is resolved" "$(calls)" "node PR_kwDOesc"

# Only the id bound to pullRequestId is checked; a PR_ in another field is not.
scenario unresolved none green green
run "decoy id before the bound literal" 'gh api graphql -f query='"'"'mutation($id:ID!){mergePullRequest(input:{clientMutationId:"PR_decoy",pullRequestId:$id}){clientMutationId}}'"'"' -f id=PR_kwDOreal' 2
assert_contains "decoy -> the bound node is resolved" "$(calls)" "node PR_kwDOreal"
assert_absent "decoy -> the decoy is not resolved" "$(calls)" "node PR_decoy"
scenario none none green green
run "decoy literal, bound id from a substitution" 'gh api graphql -F id="$(jq -r .id <<<"$PR")" -f query='"'"'mutation($id:ID!){mergePullRequest(input:{clientMutationId:"PR_decoy",pullRequestId:$id}){clientMutationId}}'"'"'' 2
assert_contains "decoy + substitution -> refused as not a literal" "$ERR" "not a literal PR_ node id"
scenario none none green green
run "two different ids bound to pullRequestId" 'gh api graphql -f query='"'"'mutation{a:mergePullRequest(input:{pullRequestId:"PR_kwDOone"}){clientMutationId} b:mergePullRequest(input:{pullRequestId:"PR_kwDOtwo"}){clientMutationId}}'"'"'' 2
assert_contains "two bound ids -> refused" "$ERR" "not a literal PR_ node id"

# curl -T / --upload-file is a PUT over HTTP(S).
for up in '-T body.json' '--upload-file body.json' '-Tbody.json'; do
  scenario unresolved none green green
  run "curl $up to the merge route" "curl -sS $up https://api.github.com/repos/acme/widgets/pulls/42/merge" 2
done
quiet "curl -T with -X POST to the merge route" 'curl -sS -X POST -T body.json https://api.github.com/repos/acme/widgets/pulls/42/merge'

# --- 5. MCP merge tools -------------------------------------------------------------
mcp_json() {
  jq -n --arg t "$1" '{tool_name:$t,tool_input:{owner:"acme",repo:"widgets",pullNumber:42}}'
}
scenario unresolved none green green
invoke "$(mcp_json mcp__github__merge_pull_request)"
assert_exit "MCP merge_pull_request with a thread" 2 "$RC"
scenario unresolved none green green
invoke "$(mcp_json mcp__plugin_x_github__merge_pull_request)"
assert_exit "MCP merge under another server prefix" 2 "$RC"
scenario none none pending green
invoke "$(mcp_json mcp__github__enable_pr_auto_merge)"
assert_exit "MCP enable_pr_auto_merge waits on pending checks" 0 "$RC"
scenario none none green green
invoke "$(mcp_json mcp__github__merge_pull_request)"
assert_exit "MCP merge on a clean PR" 0 "$RC"

# --- 6. thread source: GraphQL refused falls back to the cloud route ---------
scenario unresolved none green green
touch "$FIX/graphql_refused"
run "GraphQL refused: CCR route finds the thread" 'gh pr merge 42' 2
assert_contains "CCR route was read" "$(calls)" "repos/acme/widgets/pulls/42/ccr/review_threads"
assert_contains "CCR thread links the first comment" "$ERR" "pull/42#discussion_r7"
scenario unresolved none green green
run "cloud session reads the CCR route first" 'gh pr merge 42' 2 CLAUDE_CODE_REMOTE=true
assert_absent "cloud session skips GraphQL when CCR answers" "$(calls)" "graphql"
scenario resolved none green green
touch "$FIX/graphql_refused"
run "GraphQL refused, CCR says resolved" 'gh pr merge 42' 0

# --- 7. current branch ----------------------------------------------------------------
REPO="$TEST_TMPDIR/repo"
git init -q -b feat/x "$REPO"
scenario unresolved none green green
invoke "$(jq -n --arg c 'gh pr merge --squash' --arg d "$REPO" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}')"
assert_exit "no selector: the current branch's PR" 2 "$RC"
assert_contains "head lookup names the branch" "$(calls)" "head={owner}:feat/x"

# --- 8. fails open, visibly ---------------------------------------------------------
scenario unresolved none green green
touch "$FIX/fail"
run "gh unauthenticated: fails open" 'gh pr merge 42' 0
assert_contains "unauthenticated -> says it will run unchecked" "$OUT" "will run unchecked"
assert_contains "unauthenticated -> carries gh's reason" "$OUT" "Bad credentials"
assert_contains "unauthenticated -> user channel too" "$OUT" '"systemMessage"'
NOGH="$TEST_TMPDIR/nogh"
mkdir -p "$NOGH"
for t in bash jq cat mktemp rm git dirname timeout; do
  p=$(command -v "$t") && ln -sf "$p" "$NOGH/$t"
done
scenario unresolved none green green
OUT=$(env PATH="$NOGH" FAKE_GH_DIR="$FIX" "$NOGH/bash" "$HOOK" <<<"$(command_json 'gh pr merge 42')" 2>/dev/null)
RC=$?
assert_exit "gh missing: fails open" 0 "$RC"
assert_contains "gh missing -> says so" "$OUT" "gh is not on PATH"
scenario unresolved none green green

# --- 8b. a GraphQL mutation whose PR cannot be resolved FAILS CLOSED --------
gql_refused() { # <label> <command>
  scenario none none green green
  run "$1" "$2" 2
  assert_contains "$1 -> says why" "$ERR" "could not be checked"
  assert_contains "$1 -> names the literal-id fix" "$ERR" "-f id=PR_"
}
gql_refused "mergePullRequest, id from a substitution" \
  'gh api graphql -F id="$(jq -r .id <<<"$PR")" -f query='"'"'mutation($id:ID!){mergePullRequest(input:{pullRequestId:$id}){clientMutationId}}'"'"''
gql_refused "enqueuePullRequest, id from a variable" \
  'gh api graphql -F id=$ID -f query='"'"'mutation($id:ID!){enqueuePullRequest(input:{pullRequestId:$id}){mergeQueueEntry{position}}}'"'"''
gql_refused "enablePullRequestAutoMerge, id from a quoted variable" \
  'gh api graphql -f id="$PR_ID" -f query='"'"'mutation($id:ID!){enablePullRequestAutoMerge(input:{pullRequestId:$id}){clientMutationId}}'"'"''
gql_refused "mutation named in a -f field, no id" 'gh api graphql --input mutation.json -f q=mergePullRequest'
# The shape source-control's merge reference (#7075, section 4.2.2) runs: a
# case arm inside a function body, a multi-line query, the id from jq.
SC_7075=$(
  cat <<'SHAPE'
case "$(jq -r .mergeStateStatus <<<"$PR")" in
  CLEAN)
    [ "$(jq -r .headRefOid <<<"$PR")" = "$HEAD_SHA" ] \
      || { echo 'head moved since 4.1: hold and re-run readiness' >&2; exit 1; }
    gh api graphql --silent -F id="$(jq -r .id <<<"$PR")" -F head="$HEAD_SHA" -f query='
      mutation($id: ID!, $head: GitObjectID!) {
        enqueuePullRequest(input: {pullRequestId: $id, expectedHeadOid: $head}) {
          mergeQueueEntry { position } } }' \
      || { echo 'enqueue refused: report the GitHub error above verbatim as the blocker' >&2; exit 1; }
    echo 'queued' ;;
esac
SHAPE
)
gql_refused "the #7075 merge-queue enqueue shape" "$SC_7075"
scenario unresolved none green green
touch "$FIX/fail"
run "literal node id that cannot be read: fails closed" 'gh api graphql -f query='"'"'mutation{mergePullRequest(input:{pullRequestId:"PR_kwDOabc"}){clientMutationId}}'"'"'' 2
assert_contains "unreadable node -> names the node" "$ERR" "PR_kwDOabc"
scenario unresolved none green green
rm "$FIX/graphql_threads.json" "$FIX/ccr.json"
run "no thread source answers: fails open" 'gh pr merge 42' 0
assert_contains "no thread source -> unchecked" "$OUT" "review threads"
scenario unresolved none green green
echo '{"state":"closed","head":{"sha":"abc123"},"base":{"repo":{"full_name":"acme/widgets"}}}' >"$FIX/pr.json"
run "closed PR: nothing to guard" 'gh pr merge 42' 0
assert_eq "closed PR -> no output" "" "$OUT"

# --- 9. MUST stay quiet: no merge at a command position (hook-precision rule 2)
quiet "merge named in a commit message" 'git commit -m "gh pr merge 42 after review"'
quiet "merge in single-quoted echo" "echo 'run gh pr merge 42 --admin'"
quiet "gh pr view" 'gh pr view 42 --json mergeable'
quiet "gh pr merge --disable-auto" 'gh pr merge 42 --disable-auto'
quiet "gh api GET of the merge endpoint" 'gh api repos/acme/widgets/pulls/42/merge'
quiet "gh api graphql query without a mutation" 'gh api graphql -f query='"'"'query{repository(owner:"a",name:"b"){pullRequest(number:1){mergeable}}}'"'"''
quiet "grep for a mutation name" 'grep -rn mergePullRequest src/'
quiet "git merge" 'git merge origin/main'
quiet "curl GET of a PR" 'curl -s https://api.github.com/repos/acme/widgets/pulls/42/merge'
quiet "a gh pr merge heredoc body" $'cat <<\'EOF\' > notes.md\ngh pr merge 42\nEOF'
quiet "no merge word at all" 'ls -la'
scenario unresolved requested failed failed
invoke "$(jq -n '{tool_name:"mcp__github__get_pull_request",tool_input:{owner:"a",repo:"b",pullNumber:1}}')"
assert_exit "an unrelated MCP tool" 0 "$RC"
assert_eq "an unrelated MCP tool -> no gh call" "" "$(calls)"

quiet "gh pr merge --help" 'gh pr merge --help'
quiet "gh pr merge -h" 'gh pr merge -h'
quiet "gh pr merge 42 --help" 'gh pr merge 42 --help'

# --- 9b. command-position prefixes are stepped over ------------------------
for c in 'if true; then gh pr merge 42; fi' 'for i in 1; do gh pr merge 42; done' \
  '{ gh pr merge 42; }' 'command gh pr merge 42' 'time gh pr merge 42' 'time -p gh pr merge 42' \
  'nohup gh pr merge 42' 'exec gh pr merge 42' 'gh pr -R acme/widgets merge 42' \
  'gh pr --repo=acme/widgets merge 42'; do
  scenario unresolved none green green
  run "prefixed: $c" "$c" 2
done
scenario unresolved none green green
run "gh pr -R before merge carries the repo" 'gh pr -R acme/widgets merge 42' 2
assert_contains "pre-subcommand -R names the repo" "$(calls)" "repos/acme/widgets/pulls/42"
quiet "gh pr -R repo view is not a merge" 'gh pr -R acme/widgets view 42'

# --- 9c. one time budget across every read, with or without `timeout` -----
# The budget has no environment knob, so these cases run a copy of the hook
# with its one budget line rewritten to 2 s, beside links to the libraries it
# sources.
SHORT="$TEST_TMPDIR/short-budget"
mkdir -p "$SHORT"
ln -sf "$HOOK_DIR/abort-boundary.sh" "$HOOK_DIR/hook-utils.sh" "$SHORT/"
sed 's/^BUPM_BUDGET_S=35$/BUPM_BUDGET_S=2/' "$HOOK" >"$SHORT/block-unresolved-pr-merge.sh"
assert_eq "the short-budget copy rewrote the budget line" "1" \
  "$(grep -c '^BUPM_BUDGET_S=2$' "$SHORT/block-unresolved-pr-merge.sh")"
HOOK_REAL="$HOOK"
HOOK="$SHORT/block-unresolved-pr-merge.sh"
scenario unresolved none green green
SECONDS=0
run "a hung gh is cut off by the budget" 'gh pr merge 42' 0 FAKE_GH_SLEEP=30
assert_contains "budget -> fails open, saying so" "$OUT" "will run unchecked"
if ((SECONDS < 8)); then ok "budget -> returned in ${SECONDS}s"; else bad "budget -> took ${SECONDS}s"; fi
NOTIMEOUT="$TEST_TMPDIR/notimeout"
mkdir -p "$NOTIMEOUT"
for t in bash jq cat mktemp rm git dirname sleep kill; do
  p=$(command -v "$t") && ln -sf "$p" "$NOTIMEOUT/$t"
done
ln -sf "$BIN/gh" "$NOTIMEOUT/gh"
scenario unresolved none green green
SECONDS=0
OUT=$(env PATH="$NOTIMEOUT" FAKE_GH_DIR="$FIX" FAKE_GH_SLEEP=30 \
  "$NOTIMEOUT/bash" "$HOOK" <<<"$(command_json 'gh pr merge 42')" 2>/dev/null)
assert_exit "no timeout binary: the watcher cuts gh off" 0 "$?"
assert_contains "no timeout binary -> fails open, saying so" "$OUT" "will run unchecked"
if ((SECONDS < 8)); then ok "no timeout binary -> returned in ${SECONDS}s"; else bad "no timeout binary -> took ${SECONDS}s"; fi
HOOK="$HOOK_REAL"
# No environment variable shortens the budget: settings.json `env` reaches a
# hook's environment, so a knob there could make every merge run unchecked.
# Five calls at 0.7 s outlast a 1 s budget, so a knob that took would fail open.
scenario unresolved none green green
run "an env var cannot shorten the budget" 'gh pr merge 42' 2 FAKE_GH_DELAY=0.7 GUARDRAILS_BUPM_BUDGET_S=1 BUPM_BUDGET_S=1
assert_contains "env var ignored -> the thread is still listed" "$ERR" "src/app.py:12"

# --- 10. PowerShell -----------------------------------------------------------------
scenario unresolved none green green
run_ps "PowerShell: gh pr merge" 'gh pr merge 42 --squash' 2
scenario unresolved none green green
run_ps "PowerShell: gh.exe pr merge after ;" 'Set-Location C:\repo; gh.exe pr merge 42' 2
scenario unresolved requested failed failed
run_ps "PowerShell: merge in a quoted Write-Host" 'Write-Host "gh pr merge 42"' 0
assert_eq "PowerShell quoted mention -> no gh call" "" "$(calls)"

# --- 11. kill switch -----------------------------------------------------------------
scenario unresolved none green green
run "switched off" 'gh pr merge 42' 0 CLAUDE_PLUGIN_OPTION_BLOCK_UNRESOLVED_PR_MERGE_ENABLED=false
assert_eq "switched off -> no gh call" "" "$(calls)"
scenario unresolved none green green
run "a bad switch value keeps the guard on" 'gh pr merge 42' 2 CLAUDE_PLUGIN_OPTION_BLOCK_UNRESOLVED_PR_MERGE_ENABLED=maybe

# --- 12. same verdict through the dispatcher -------------------------------------
scenario unresolved none green green
D_ERR=$(env PATH="$BIN:$PATH" FAKE_GH_DIR="$FIX" bash "$HOOK_DIR/run-guards.sh" block-unresolved-pr-merge.sh \
  <<<"$(command_json 'gh pr merge 42')" 2>&1 >/dev/null)
D_RC=$?
assert_exit "dispatched: blocks" 2 "$D_RC"
assert_contains "dispatched: lists the thread" "$D_ERR" "src/app.py:12"
scenario none none green green
env PATH="$BIN:$PATH" FAKE_GH_DIR="$FIX" bash "$HOOK_DIR/run-guards.sh" block-unresolved-pr-merge.sh \
  <<<"$(command_json 'gh pr merge 42')" >/dev/null 2>&1
assert_exit "dispatched: clean PR passes" 0 "$?"

echo
echo "block-unresolved-pr-merge: $PASS passed, $FAIL failed"
((FAIL == 0))
