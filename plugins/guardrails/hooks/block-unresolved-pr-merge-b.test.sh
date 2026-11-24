#!/usr/bin/env bash

# shellcheck disable=SC2016
set -uo pipefail

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
# shellcheck source=block-unresolved-pr-merge-fixtures.sh
source "$(dirname "${BASH_SOURCE[0]}")/block-unresolved-pr-merge-fixtures.sh"

PV_DIGEST=79b4cc554b80dca6
pv_scenario() {
  scenario none none green green
  echo '{"state":"open","head":{"sha":"abc123","ref":"feat/x","repo":{"full_name":"acme/widgets"}},"base":{"ref":"main","repo":{"full_name":"acme/widgets","default_branch":"main"}},"user":{"id":9,"login":"kyle","type":"User"},"labels":[]}' >"$FIX/pr.json"
  local conf='merge:\n  agent-identity: lanes-app[bot]\n  verify-authors: lane-or-owner # who pr-verify judges\n'
  printf '{"data":{"repository":{"w":{"oid":"f00"},"c":{"text":"%s"},"t":{"text":"{\\"actors\\":[{\\"id\\":9}]}"}}}}\n' "$conf" >"$FIX/graphql_scope.json"
}
pv_artifact() {
  [[ -f "$FIX/artifacts.json" ]] || echo '{"artifacts":[]}' >"$FIX/artifacts.json"
  jq --arg n "$1" --argjson id "$2" --arg b "${3:-main}" '.artifacts += [{name: $n, expired: false, workflow_run: {id: $id, head_branch: $b}}]' \
    "$FIX/artifacts.json" >"$FIX/artifacts.next" && mv "$FIX/artifacts.next" "$FIX/artifacts.json"
}
pv_pass() {
  pv_artifact "pr-verify-42-abc123-$1" "$2"
  local o="${3-}"
  [[ -n "$o" ]] || o='{}'
  jq -n --argjson o "$o" '{status: "completed", conclusion: "success", path: ".github/workflows/pr-verify.yml",
    event: "workflow_run", head_branch: "main", repository: {full_name: "acme/widgets"},
    head_repository: {full_name: "acme/widgets"}} + $o' >"$FIX/run_$2.json"
}

pv_scenario
run "pr-verify: --auto before any verdict" 'gh pr merge 42 --auto --squash' 2
assert_contains "no verdict -> names the head" "$ERR" "at its head abc123"
assert_contains "no verdict -> says to wait, then retry" "$ERR" "Wait for pr-verify's verdict on abc123, then retry"
assert_contains "no verdict -> names the user's escape" "$ERR" "block_unresolved_pr_merge_enabled"
assert_eq "no verdict -> four artifact reads, one per pass name" 4 "$(grep -c actions/artifacts "$FIX/calls")"
for c in 'gh api graphql -f query="mutation{enqueuePullRequest(input:{pullRequestId:\"PR_x\"}){clientMutationId}}"' \
  'gh api -X PUT repos/acme/widgets/pulls/42/merge' \
  'gh pr merge 42 --squash'; do
  pv_scenario
  run "pr-verify: before any verdict: $c" "$c" 2
  assert_contains "no verdict, $c -> refused" "$ERR" "no pr-verify PASS or PASS-NOTES verdict"
done

pv_scenario
pv_pass "pass-notes-$PV_DIGEST" 7001
run "pr-verify: PASS-NOTES at the head" 'gh pr merge 42 --auto --squash' 0
assert_eq "PASS at head -> no stderr" "" "$ERR"
assert_contains "PASS at head -> the run behind the artifact is read" "$(calls)" "repos/acme/widgets/actions/runs/7001"
pv_scenario
pv_pass pass 7002
run "pr-verify: PASS at the head stops at the first pass" 'gh pr merge 42 --auto' 0
assert_absent "first-name PASS -> no further artifact read" "$(calls)" "pass-notes"

pv_scenario
pv_pass fail 7003
run "pr-verify: FAIL at the head, label already removed" 'gh pr merge 42 --auto' 2
assert_contains "FAIL at head -> refused" "$ERR" "no pr-verify PASS or PASS-NOTES verdict at its head abc123"
pv_scenario
jq '.labels = [{name: "pr-verify-failed"}]' "$FIX/pr.json" >"$FIX/pr.next" && mv "$FIX/pr.next" "$FIX/pr.json"
run "pr-verify: FAIL label on the PR" 'gh pr merge 42 --auto' 2
assert_contains "FAIL label -> the hold label refuses" "$ERR" "Hold labels: pr-verify-failed"
assert_absent "FAIL label -> no verdict read" "$(calls)" "actions/artifacts"

pv_scenario
pv_artifact pr-verify-42-old999-pass 7004
pv_artifact "pr-verify-42-old999-pass-notes-$PV_DIGEST" 7004
pv_pass fail-old 7004
run "pr-verify: PASS only at an older head" 'gh pr merge 42 --auto' 2
assert_absent "older head's PASS -> its run is never read" "$(calls)" "actions/runs/7004"
pv_scenario
pv_pass pass 7005 '{"conclusion":"failure"}'
run "pr-verify: pass artifact from a run that failed" 'gh pr merge 42 --auto' 2
pv_scenario
pv_pass pass-unused 7006 '{"head_branch":"feat/x"}'
pv_artifact pr-verify-42-abc123-pass 7006 feat/x
run "pr-verify: pass artifact uploaded off the default branch" 'gh pr merge 42 --auto' 2
assert_absent "off-default artifact -> its run is never read" "$(calls)" "actions/runs/7006"

pv_scenario
touch "$FIX/artifacts_error"
run "pr-verify: a failed artifact read fails open" 'gh pr merge 42 --auto' 0
assert_contains "failed verdict read -> says it runs unchecked" "$OUT" "for its pr-verify verdict"
assert_contains "failed verdict read -> names the error" "$OUT" "HTTP 502"
pv_scenario
jq '.user = {id: 77, login: "dependabot[bot]", type: "Bot"}' "$FIX/pr.json" >"$FIX/pr.next" && mv "$FIX/pr.next" "$FIX/pr.json"
run "pr-verify: a dependency-manager PR is outside its scope" 'gh pr merge 42 --auto' 0
assert_eq "dependabot -> no scope read, only the threads read" 1 "$(grep -cx graphql "$FIX/calls")"
assert_absent "dependabot -> no verdict read" "$(calls)" "actions/artifacts"
pv_scenario
jq '.head.repo.full_name = "fork/widgets"' "$FIX/pr.json" >"$FIX/pr.next" && mv "$FIX/pr.next" "$FIX/pr.json"
run "pr-verify: a fork PR is outside its scope" 'gh pr merge 42 --auto' 0
assert_absent "fork -> no verdict read" "$(calls)" "actions/artifacts"
pv_scenario
echo '{"data":{"repository":{"w":null,"c":null,"t":null}}}' >"$FIX/graphql_scope.json"
run "pr-verify: a repository without pr-verify" 'gh pr merge 42 --auto' 0
assert_absent "no pr-verify -> no verdict read" "$(calls)" "actions/artifacts"
pv_scenario
jq '.user = {id: 5, login: "someone", type: "User"}' "$FIX/pr.json" >"$FIX/pr.next" && mv "$FIX/pr.next" "$FIX/pr.json"
run "pr-verify: an author lane-or-owner does not judge" 'gh pr merge 42 --auto' 0
assert_absent "untrusted author -> no verdict read" "$(calls)" "actions/artifacts"
pv_scenario
jq '.user = {id: 5, login: "lanes-app[bot]", type: "Bot"}' "$FIX/pr.json" >"$FIX/pr.next" && mv "$FIX/pr.next" "$FIX/pr.json"
run "pr-verify: the lanes App's PR is judged" 'gh pr merge 42 --auto' 2

for mode in '\"any\"' "'any'"; do
  pv_scenario
  jq '.user = {id: 5, login: "someone", type: "User"}' "$FIX/pr.json" >"$FIX/pr.next" && mv "$FIX/pr.next" "$FIX/pr.json"
  printf '{"data":{"repository":{"w":{"oid":"f00"},"c":{"text":"merge:\\n  verify-authors: %s\\n"},"t":null}}}\n' "$mode" >"$FIX/graphql_scope.json"
  run "pr-verify: quoted verify-authors $mode judges every author" 'gh pr merge 42 --auto' 2
done
pv_scenario
jq '.user = {id: 5, login: "Lanes-App[bot]", type: "Bot"}' "$FIX/pr.json" >"$FIX/pr.next" && mv "$FIX/pr.next" "$FIX/pr.json"
printf '{"data":{"repository":{"w":{"oid":"f00"},"c":{"text":"merge:\\n  agent-identity: lanes-app\\n"},"t":null}}}\n' >"$FIX/graphql_scope.json"
run "pr-verify: the lanes App matched without [bot] or case" 'gh pr merge 42 --auto' 2

pv_scenario
touch "$FIX/graphql_refused"
printf 'merge:\n  verify-authors: lane-or-owner\n' >"$FIX/contents_pr-pipeline.yaml"
echo '{"actors":[{"id":9}]}' >"$FIX/contents_trusted-actors.json"
echo '{"path":".github/workflows/pr-verify.yml"}' >"$FIX/contents_pr-verify.yml"
run "pr-verify: GraphQL refused, scope read over REST" 'gh pr merge 42 --auto' 2
assert_contains "REST scope -> the base branch's settings" "$(calls)" "contents/docs/conventions/pr-pipeline.yaml?ref=main"
rm -f "$FIX/contents_pr-verify.yml"
: >"$FIX/calls"
run "pr-verify: GraphQL refused, no workflow on the base" 'gh pr merge 42 --auto' 0
assert_absent "REST, no workflow -> no settings read" "$(calls)" "pr-pipeline.yaml"

pv_scenario
invoke "$(jq -n '{tool_name: "mcp__github__enable_pr_auto_merge", tool_input: {owner: "acme", repo: "widgets", pullNumber: 42}}')"
assert_exit "pr-verify: MCP enable_pr_auto_merge before any verdict" 2 "$RC"
assert_contains "MCP, no verdict -> refused" "$ERR" "no pr-verify PASS or PASS-NOTES verdict"
pv_scenario
assert_contains "pr-verify: the artifact read names the head" "$(invoke "$(command_json 'gh pr merge 42 --auto')"; calls)" "actions/artifacts?name=pr-verify-42-abc123-pass&"
pv_scenario
echo '{"errors":[{"message":"boom"}]}' >"$FIX/graphql_scope.json"
touch "$FIX/graphql_refused"
echo '{"path":".github/workflows/pr-verify.yml"}' >"$FIX/contents_pr-verify.yml"
touch "$FIX/contents_error"
run "pr-verify: a scope read that fails with an error other than 404 fails open" 'gh pr merge 42 --auto' 0
assert_contains "failed scope read -> runs unchecked" "$OUT" "for its pr-verify verdict"

STD_SHA=0123456789abcdef0123456789abcdef01234567
pv_std() {
  pv_scenario
  jq --arg s "$1" '.data.repository.s = {text: $s} | .data.repository.t.text = "{\"actors\":[{\"id\":5}]}"' \
    "$FIX/graphql_scope.json" >"$FIX/scope.next" && mv "$FIX/scope.next" "$FIX/graphql_scope.json"
  printf '{"sha":"%s"}\n' "$STD_SHA" >"$FIX/commits_main.json"
  echo '{"actors":[{"id":9}]}' >"$FIX/contents_trusted-actors.json"
}
pv_std $'pr_open_state: ready\ntrusted_actors_source: standards # opt in\n'
run "pr-verify: opted in, the standards list judges the author" 'gh pr merge 42 --auto' 2
assert_contains "opted in -> resolves standards main once" "$(calls)" "repos/melodic-software/standards/commits/main"
assert_contains "opted in -> reads the list at that commit" "$(calls)" "repos/melodic-software/standards/contents/components/trusted-actors/trusted-actors.json?ref=$STD_SHA"
pv_std $'trusted_actors_source: repository\n'
run "pr-verify: trusted_actors_source repository keeps the copy" 'gh pr merge 42 --auto' 0
assert_absent "repository source -> no standards read" "$(calls)" "melodic-software/standards"
pv_std ''
run "pr-verify: no opt-in keeps the copy" 'gh pr merge 42 --auto' 0
assert_absent "no opt-in -> no standards read" "$(calls)" "melodic-software/standards"
pv_std $'trusted_actors_source: elsewhere\n'
run "pr-verify: an unknown trusted_actors_source fails open" 'gh pr merge 42 --auto' 0
assert_contains "unknown source -> runs unchecked, naming it" "$OUT" "trusted_actors_source elsewhere is not repository or standards"
pv_std $'trusted_actors_source: standards\n'
rm -f "$FIX/commits_main.json"
run "pr-verify: standards main unreadable fails open" 'gh pr merge 42 --auto' 0
assert_contains "standards unreadable -> runs unchecked" "$OUT" "for its pr-verify verdict"
pv_std $'trusted_actors_source: standards\n'
touch "$FIX/graphql_refused"
printf 'merge:\n  verify-authors: lane-or-owner\n' >"$FIX/contents_pr-pipeline.yaml"
printf 'trusted_actors_source: "standards"\n' >"$FIX/contents_source-control.yaml"
echo '{"path":".github/workflows/pr-verify.yml"}' >"$FIX/contents_pr-verify.yml"
run "pr-verify: GraphQL refused, the opt-in read over REST" 'gh pr merge 42 --auto' 2
assert_contains "REST opt-in -> the base branch's source-control.yaml" "$(calls)" "contents/docs/conventions/source-control.yaml?ref=main"
assert_contains "REST opt-in -> the standards list at one commit" "$(calls)" "trusted-actors.json?ref=$STD_SHA"

for c in 'gh pr edit 42 --remove-label pr-verify-failed' 'gh pr edit 42 --remove-label bug,PR-Verify-Failed' \
  'gh pr edit 42 --remove-label=pr-verify-failed' 'gh issue edit 42 -R acme/widgets --remove-label pr-verify-failed' \
  'gh pr edit 42 --remove-label pr-verify-failed && gh pr merge 42 --auto' \
  'gh api -X DELETE repos/acme/widgets/issues/42/labels/pr-verify-failed' \
  'curl -X DELETE -H "Authorization: token x" https://api.github.com/repos/acme/widgets/issues/42/labels/pr-verify-failed' \
  'L=pr-verify-failed; gh pr edit 42 --remove-label "$L"' \
  'gh api -X DELETE repos/acme/widgets/issues/42/labels/pr%2Dverify%2Dfailed' \
  'gh label delete pr-verify-failed --yes' \
  'gh label edit -R acme/widgets pr-verify-failed --name gone' \
  'gh label edit --name gone -c ff0000 pr-verify-failed'; do
  scenario none none green green
  run "label removal: $c" "$c" 2
  assert_contains "label removal, $c -> says why" "$ERR" "removes the pr-verify-failed label"
  assert_eq "label removal, $c -> no gh call" "" "$(calls)"
done
for c in 'gh pr edit 42 --remove-label bug' 'gh pr edit 42 --add-label pr-verify-failed' \
  'gh api repos/acme/widgets/issues/42/labels/pr-verify-failed' 'grep -n pr-verify-failed docs/a.md' \
  'gh label delete stale-label --yes' 'gh api -X DELETE repos/acme/widgets/issues/42/labels/bug%20fix'; do
  scenario unresolved requested failed failed
  run "not a pr-verify-failed removal: $c" "$c" 0
  assert_eq "not a removal, $c -> no gh call" "" "$(calls)"
done
GQL_UNLABEL='gh api graphql -f query="mutation{removeLabelsFromLabelable(input:{labelableId:\"PR_x\",labelIds:[\"LA_1\"]}){clientMutationId}}"'
scenario none none green green
echo '{"data":{"nodes":[{"name":"pr-verify-failed"}]}}' >"$FIX/graphql_labels.json"
run "GraphQL removeLabelsFromLabelable of pr-verify-failed" "$GQL_UNLABEL" 2
assert_contains "GraphQL label removal -> says why" "$ERR" "removes the pr-verify-failed label"
scenario none none green green
echo '{"data":{"nodes":[{"name":"bug"}]}}' >"$FIX/graphql_labels.json"
run "GraphQL removeLabelsFromLabelable of another label" "$GQL_UNLABEL" 0
scenario none none green green
run "GraphQL label removal whose label read fails" "$GQL_UNLABEL" 0
assert_contains "GraphQL label read fails -> runs unchecked" "$OUT" "runs unchecked"
scenario none none green green
run "GraphQL label removal with label ids from a variable" 'gh api graphql -f query="mutation(\$l:[ID!]!){removeLabelsFromLabelable(input:{labelableId:\"PR_x\",labelIds:\$l}){clientMutationId}}" -f "l[]=$LID"' 2
assert_contains "GraphQL label removal, non-literal ids -> refused" "$ERR" "names no literal LA_ label id"
scenario none none green green
run "label removal, switched off" 'gh pr edit 42 --remove-label pr-verify-failed' 0 CLAUDE_PLUGIN_OPTION_BLOCK_UNRESOLVED_PR_MERGE_ENABLED=false

echo
echo "block-unresolved-pr-merge-b: $PASS passed, $FAIL failed"
((FAIL == 0))
