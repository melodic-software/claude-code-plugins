#!/usr/bin/env bash
# Runs the `Recheck a non-human enqueue` step body of
# .github/workflows/pr-require-checks.yml's unattended-recheck job under the
# shell Actions gives a step with no `shell:` (bash -e), against a stub `gh`.
# The step runs the real `babysit_merge_policy.py recheck` from a checkout of
# the queue's base, here this tree.
#
# The merge-group backstop (#6202, "Amendment (auto-merge-safe-prs)", D1): an
# entry a human enqueued passes without reading the policy terms; any other
# entry (a null enqueuer, an App, the agent identity even when it reads as a
# `User`) fails first on the rung and the kill switches, then on every fixed
# rule. Each expected outcome and limit (200 lines, 8 files, ALLGREEN) is that
# rule set's; the reason strings are the recheck's own names for them.
# test-scope: .github/workflows/pr-require-checks.yml plugins/source-control/skills/babysit-prs/scripts/*.py
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/pr-require-checks.yml"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

if ! command -v python3 >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  fail "python3 and jq are required to run the recheck step"
  test_harness::report
  exit 1
fi

# --- The job and its step --------------------------------------------------

job="$(awk '/^  unattended-recheck:$/ { on = 1; print; next }
  on && /^  [a-z]/ { exit }
  on { print }' "$WORKFLOW")"
NAME='Recheck a non-human enqueue'
step="$(awk -v name="      - name: $NAME" '$0 == name { on = 1; print; next }
  on && /^      - / { exit }
  on { print }' <<<"$job")"
awk '/^        run: \|$/ { on = 1; next }
  on && /^          / { print substr($0, 11); next }
  on && /^[[:blank:]]*$/ { print ""; next }
  on { exit }' <<<"$step" >"$TMP_ROOT/body.sh"

if [[ ! -s "$TMP_ROOT/body.sh" ]]; then
  fail "no '$NAME' step with a run: | body in the unattended-recheck job of $WORKFLOW"
  test_harness::report
  exit 1
fi

has() {
  if [[ "$1" == *"$2"* ]]; then ok "$3"; else fail "$3: '$2' not found"; fi
}
has "$job" "    if: github.event_name == 'merge_group'" "the job runs on merge_group only"
has "$job" "    timeout-minutes: 10" "the job times out at 10 minutes"
# shellcheck disable=SC2016 # workflow literals to match, not shell expansions
{
  has "$job" '          ref: ${{ github.event.merge_group.base_sha }}' "the checkout is the queue's base"
  has "$job" "          path: queue-base" "the base is checked out into its own directory"
}
perms="$(awk '/^    permissions:$/ { on = 1; next } on && /^      / { print; next } on { exit }' <<<"$job" | sort | paste -sd' ')"
if [[ "$perms" == "      actions: read       contents: read       issues: read       pull-requests: read" ]]; then
  ok "the job holds exactly the four read scopes"
else
  fail "the job's permissions are '$perms'"
fi
# shellcheck disable=SC2016 # a workflow literal to match, not a shell expansion
if grep -qF '${{' "$TMP_ROOT/body.sh"; then
  fail "the run: body interpolates an expression; pass event fields through env"
else
  ok "the run: body reads event fields through env only"
fi
if [[ "$step" == *"continue-on-error"* ]]; then
  fail "the step must not continue on error: its exit code is the backstop"
else
  ok "the step fails the job on its exit code"
fi
needs="$(awk '/^  ci-status:$/ { on = 1; next } on && /^    needs:$/ { list = 1; next }
  list && /^      - / { print $2; next } list { exit }' "$WORKFLOW")"
if grep -qx unattended-recheck <<<"$needs"; then
  ok "ci-status needs the job"
else
  fail "ci-status does not need unattended-recheck"
fi

# --- The stub gh -----------------------------------------------------------
# It logs each call and answers from $FIX: a GraphQL call by its operation name
# plus its `n` and `a` variables, a REST call by its endpoint below the
# repository; `<key>.status` answers that HTTP status instead. Any other call
# fails as unreadable, so an unexpected read cannot pass.

mkdir -p "$TMP_ROOT/bin"
cat >"$TMP_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
if [[ "$1 $2" == "api graphql" ]]; then
  query="" extra=""
  for arg in "${@:3}"; do
    case "$arg" in
      query=*) query="${arg#query=}" ;;
      n=* | a=*) extra="$extra-${arg#*=}" ;;
    esac
  done
  key="graphql-$(sed -nE 's/^query ([A-Za-z]+).*/\1/p' <<<"$query")$extra"
else
  key="${2#repos/acme/widgets/}"
fi
key="${key//[^A-Za-z0-9._-]/_}"
if [[ -f "$FIX/$key.fails" ]] && (($(cat "$FIX/$key.fails") > 0)); then
  printf '%s\n' "$(($(cat "$FIX/$key.fails") - 1))" >"$FIX/$key.fails"
  printf 'gh: request failed (HTTP 502)\n' >&2
  exit 1
fi
if [[ -f "$FIX/$key.status" ]]; then
  printf 'gh: request failed (HTTP %s)\n' "$(cat "$FIX/$key.status")" >&2
  exit 1
fi
if [[ -f "$FIX/$key" ]]; then
  cat "$FIX/$key"
  exit 0
fi
printf 'stub: no fixture for %s\n' "$key" >&2
exit 1
EOF
printf '#!/usr/bin/env bash\n' >"$TMP_ROOT/bin/sleep"
chmod +x "$TMP_ROOT/bin/gh" "$TMP_ROOT/bin/sleep"

BASE=0123456789abcdef0123456789abcdef01234567
HEAD=89abcdef0123456789abcdef0123456789abcdef
QUEUE="refs/heads/gh-readonly-queue/main/pr-7-$BASE"
FIX="$TMP_ROOT/fix"

put() { cat >"$FIX/$1"; }
http() { printf '%s\n' "$2" >"$FIX/$1.status"; }
# patch <key> <jq filter>: edit one fixture in place.
patch() { jq "$2" "$FIX/$1" >"$FIX/$1.new" && mv "$FIX/$1.new" "$FIX/$1"; }
file_payload() {
  printf '{"type":"file","encoding":"base64","content":"%s"}' "$(printf '%s' "$1" | base64 | tr -d '\n')"
}
config() { file_payload "$1" | put "contents_docs_conventions_pr-pipeline.yaml_ref_$BASE"; }
tree() { # tree <sha> <path>...
  local sha="$1" path entries=""
  shift
  for path in "$@"; do entries+="${entries:+,}{\"path\":\"$path\",\"mode\":\"100644\",\"type\":\"blob\"}"; done
  printf '{"sha":"%s","truncated":false,"tree":[%s]}' "$sha" "$entries" | put "git_trees_${sha}_recursive_1"
}
files() { # files <additions-each> <path>...: one modified file per path, five deletions each
  local add="$1" path rows=""
  shift
  for path in "$@"; do
    rows+="${rows:+,}{\"filename\":\"$path\",\"status\":\"modified\",\"additions\":$add,\"deletions\":5,\"patch\":\"@@\"}"
  done
  printf '[[%s]]' "$rows" | put pulls_7_files_per_page_100
  patch "graphql-RecheckPullRequest-7" ".data.repository.pullRequest.changedFiles = $#"
  tree "$HEAD" "$@"
  tree "$BASE" "$@"
}
labeled() { # labeled <event> <label> <login> <type> <time>
  printf '{"event":"%s","label":{"name":"%s"},"actor":{"login":"%s","type":"%s"},"created_at":"%s"}' "$@"
}

PIPELINE='merge:
  rung: C2
  authority: local-babysit
  agent-identity: agent-lanes[bot]
  diff-check:
    max-changed-lines: 200
    denied-paths: ["docs/conventions/pr-pipeline.yaml"]
'

# A non-human entry that meets every term: a C2 issue labeled by a human, the
# opt-in label from a human, one small modified file, nothing else queued.
baseline() {
  rm -rf "$FIX" && mkdir -p "$FIX"
  config "$PIPELINE"
  file_payload $'## babysit_loop_merge\n\nc2-mechanical\n' | put "contents_.claude_source-control.md_ref_$BASE"
  put graphql-RecheckPullRequest-7 <<EOF
{"data":{"repository":{"pullRequest":{"number":7,"body":"Closes #42","headRefOid":"$HEAD",
 "changedFiles":1,"labels":{"totalCount":1,"nodes":[{"name":"merge: agent-allowed"}]},
 "timelineItems":{"nodes":[{"createdAt":"2026-10-12T13:00:00Z",
  "actor":{"__typename":"Bot","login":"agent-lanes"},"enqueuer":null}]}}}}}
EOF
  put graphql-PolicyEligibility-7 <<'EOF'
{"data":{"repository":{"pullRequest":{"number":7,"createdAt":"2026-10-12T12:00:00Z",
 "lastEditedAt":null,"isCrossRepository":false,"author":{"__typename":"User","login":"alice"},
 "headRepositoryOwner":{"login":"acme"},
 "labels":{"totalCount":1,"nodes":[{"name":"merge: agent-allowed"}]},
 "closingIssuesReferences":{"totalCount":1,"nodes":[{"number":42,"lastEditedAt":null,
  "repository":{"nameWithOwner":"acme/widgets"},
  "labels":{"totalCount":1,"nodes":[{"name":"work-class: mechanical"}]}}]}}}}}
EOF
  printf '[[%s]]' "$(labeled labeled 'work-class: mechanical' alice User 2026-10-11T09:00:00Z)" |
    put issues_42_timeline_per_page_100
  printf '[[%s]]' "$(labeled labeled 'merge: agent-allowed' alice User 2026-10-12T12:30:00Z)" |
    put issues_7_timeline_per_page_100
  printf '{"permission":"admin"}' | put collaborators_alice_permission
  printf '{"permission":"admin"}' | put collaborators_agent-lanes_permission
  # The step's vars context. The Actions-variables API answers 403 to a
  # merge-group GITHUB_TOKEN, so the step reads these instead.
  CASE_CAP=C2 CASE_REPO=false
  http actions_variables_per_page_1 403
  local filer
  for filer in github-actions_bot_ agent-lanes_bot_; do
    printf '{"data":{"repository":{"issues":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}}' |
      put "graphql-PolicyIssuesByAuthor-$filer"
  done
  printf '{"data":{"repository":{"mergeQueue":{"entries":{"totalCount":1,"nodes":[{"enqueuer":null,"pullRequest":{"number":7}}]}}}}}' |
    put graphql-PolicyMergeQueue
  printf '[[{"type":"merge_queue","parameters":{"grouping_strategy":"ALLGREEN"}}]]' |
    put rules_branches_main_per_page_100
  files 5 plugins/foo/README.md
  for key in issues_7_comments_per_page_100 pulls_7_reviews_per_page_100 pulls_7_comments_per_page_100; do
    printf '[[]]' | put "$key"
  done
}

# A workspace whose queue-base is this tree; `bare` has a base without the recheck.
mkdir -p "$TMP_ROOT/ws" "$TMP_ROOT/bare/queue-base"
ln -s "$ROOT" "$TMP_ROOT/ws/queue-base"

# expect <label> <want-rc> <want-out|-> [GITHUB_REF] [LANES_DISABLED] [workspace]
expect() {
  local label="$1" want_rc="$2" want_out="$3" out rc
  : >"$TMP_ROOT/log"
  out="$(cd "${6:-$TMP_ROOT/ws}" && PATH="$TMP_ROOT/bin:$PATH" STUB_LOG="$TMP_ROOT/log" FIX="$FIX" \
    GITHUB_REF="${4:-$QUEUE}" GITHUB_REPOSITORY=acme/widgets BASE_SHA="$BASE" BASE_REF=refs/heads/main \
    LANES_DISABLED="${5-false}" RUNG_CAP="$CASE_CAP" REPO_DISABLED="$CASE_REPO" \
    GH_TOKEN=stub bash -e "$TMP_ROOT/body.sh" 2>&1)" && rc=0 || rc=$?
  verdict "$label" "$want_rc" "$want_out" "$rc" "$out"
}
verdict() { # verdict <label> <want-rc> <want-out|-> <rc> <out>
  local label="$1" want_rc="$2" want_out="$3" rc="$4" out="$5"
  if [[ "$rc" -ne "$want_rc" ]]; then
    fail "$label: expected rc=$want_rc got rc=$rc out='$out'"
  elif [[ "$want_out" != - && "$out" != *"$want_out"* ]]; then
    fail "$label: output lacks '$want_out': '$out'"
  else
    ok "$label"
  fi
}
called() { grep -q -- "$1" "$TMP_ROOT/log"; }
# read_terms <label> <yes|no>: whether the run read past the enqueuer.
read_terms() {
  local read=no
  if called PolicyIssuesByAuthor; then read=yes; fi
  if [[ "$read" == "$2" ]]; then ok "$1"; else fail "$1: policy terms read: $read"; fi
}
not_called() {
  if called "$1"; then fail "$2: '$1' was read"; else ok "$2"; fi
}

# --- Who enqueued -------------------------------------------------------------

baseline
patch graphql-RecheckPullRequest-7 '.data.repository.pullRequest.timelineItems.nodes[0] |= (.actor = {"__typename":"User","login":"alice"} | .enqueuer = {"__typename":"User","login":"alice"})'
expect "a human-enqueued entry passes" 0 "human-enqueued"
read_terms "a human-enqueued entry reads no policy term" no

# The human test needs the configured identity, so pr-pipeline.yaml at the base
# is read first; an unreadable one fails a human entry too (fail closed).
baseline
patch graphql-RecheckPullRequest-7 '.data.repository.pullRequest.timelineItems.nodes[0] |= (.actor = {"__typename":"User","login":"alice"} | .enqueuer = {"__typename":"User","login":"alice"})'
http "contents_docs_conventions_pr-pipeline.yaml_ref_$BASE" 502
expect "a human entry fails when the config at the base is unreadable" 2 "unreadable"

baseline
patch graphql-RecheckPullRequest-7 '.data.repository.pullRequest.timelineItems.nodes[0] |= (.actor = {"__typename":"User","login":"agent-lanes"} | .enqueuer = {"__typename":"User","login":"agent-lanes"})'
expect "the identity configured as a User meeting every term passes" 0 -
read_terms "an entry the identity enqueued as a User is still checked" yes

baseline
patch graphql-RecheckPullRequest-7 '.data.repository.pullRequest.timelineItems.nodes[0] |= (.actor = {"__typename":"User","login":"agent-lanes"} | .enqueuer = {"__typename":"User","login":"agent-lanes"})'
config "${PIPELINE/rung: C2/rung: off}"
expect "the identity configured as a User fails when the rung is off" 1 "rung-off"

baseline
expect "a null enqueuer meeting every term passes" 0 -
read_terms "an entry with a null enqueuer is checked" yes

baseline
patch graphql-RecheckPullRequest-7 '.data.repository.pullRequest.timelineItems.nodes[0] |= (.actor = {"__typename":"User","login":"alice"})'
config "${PIPELINE/rung: C2/rung: off}"
expect "a human actor with a null enqueuer is still checked" 1 "rung-off"

baseline
patch graphql-RecheckPullRequest-7 '.data.repository.pullRequest.timelineItems.nodes[0] |= (.enqueuer = {"__typename":"User","login":"alice"})'
config "${PIPELINE/rung: C2/rung: off}"
expect "a human enqueuer with an App actor is still checked" 1 "rung-off"

baseline
printf '{"permission":"read"}' | put collaborators_alice_permission
patch graphql-RecheckPullRequest-7 '.data.repository.pullRequest.timelineItems.nodes[0] |= (.actor = {"__typename":"User","login":"alice"} | .enqueuer = {"__typename":"User","login":"alice"})'
config "${PIPELINE/rung: C2/rung: off}"
expect "a User without write permission is checked" 1 "rung-off"

baseline
patch graphql-RecheckPullRequest-7 '.data.repository.pullRequest.timelineItems.nodes = []'
expect "an unreadable enqueuer fails" 2 "enqueuer"

baseline
http graphql-RecheckPullRequest-7 502
expect "an unreadable pull request fails" 2 "unreadable"

# --- The rung and the kill switches fail first --------------------------------

first_fail() { # first_fail <label> <want-out>
  expect "$1" 1 "$2"
  not_called PolicyEligibility "$1 before any other term"
}

baseline
config $'version: 1\n'
first_fail "no merge: block fails" "rung-off"

baseline
config "${PIPELINE/local-babysit/pr-merge}"
first_fail "authority other than local-babysit fails" "rung-off:authority"

# In the step, the rung cap and both kill switches come from the vars context.
baseline
expect "the rung cap and switches are read from the vars context" 0 "meets every term"
not_called actions/variables "the step reads no Actions variable through the API"

for cap in off "" C4; do
  baseline
  CASE_CAP="$cap"
  first_fail "a rung cap of '$cap' fails" "rung-off:rungCap"
done

baseline
file_payload $'## babysit_loop_merge\n\nhuman-only\n' | put "contents_.claude_source-control.md_ref_$BASE"
first_fail "babysit_loop_merge human-only fails" "rung-off:babysit_loop_merge"

baseline
printf '{"data":{"repository":{"issues":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"number":5,"body":"<!-- babysit-merge-demotion sha=%s signal=dispatch -->","lastEditedAt":null}]}}}}' "$BASE" |
  put graphql-PolicyIssuesByAuthor-github-actions_bot_
printf '{"data":{"repository":{"issue":{"number":5,"state":"OPEN","body":"<!-- babysit-merge-demotion sha=%s signal=dispatch -->","createdAt":"2026-10-12T10:00:00Z","author":{"__typename":"Bot","login":"github-actions"},"userContentEdits":{"totalCount":0,"nodes":[]},"timelineItems":{"nodes":[]}}}}}' "$BASE" |
  put graphql-PolicyDemotionRecord-5
first_fail "an open demotion issue fails" "rung-off:demotion"

for value in true "" False; do
  baseline
  CASE_REPO="$value"
  first_fail "vars.CLAUDE_LANES_REPO_DISABLED '$value' fails" "kill-switch:repo-switch-not-false"
  baseline
  expect "vars.CLAUDE_LANES_DISABLED '$value' fails" 1 "kill-switch:org-switch-not-false" "" "$value"
  not_called PolicyEligibility "vars.CLAUDE_LANES_DISABLED '$value' fails before any other term"
done

# Run locally (no --vars-context), the recheck keeps the Actions-variables API
# path and its repository-shadow check.
api_vars() {
  rm -f "$FIX/actions_variables_per_page_1.status"
  printf '{"total_count":0,"variables":[]}' | put actions_variables_per_page_1
  printf '[{"total_count":1,"variables":[{"name":"CLAUDE_LANES_DISABLED","value":"false"}]}]' |
    put actions_organization-variables_per_page_100
  printf '{"name":"CLAUDE_LANES_REPO_DISABLED","value":"false"}' | put actions_variables_CLAUDE_LANES_REPO_DISABLED
  http actions_variables_CLAUDE_LANES_DISABLED 404
  http actions_variables_CLAUDE_LANES_MERGE_RUNG_CAP 404
}
local_recheck() { # local_recheck <label> <want-rc> <want-out|->
  local out rc
  : >"$TMP_ROOT/log"
  out="$(PATH="$TMP_ROOT/bin:$PATH" STUB_LOG="$TMP_ROOT/log" FIX="$FIX" GH_TOKEN=stub \
    python3 "$ROOT/plugins/source-control/skills/babysit-prs/scripts/babysit_merge_policy.py" recheck \
    --repo acme/widgets --pr 7 --base-sha "$BASE" --base-ref main 2>&1)" && rc=0 || rc=$?
  verdict "$1" "$2" "$3" "$rc" "$out"
}

baseline
api_vars
local_recheck "locally, the variables API proceeding passes" 0 "meets every term"
if called actions/variables/CLAUDE_LANES_REPO_DISABLED; then
  ok "locally, the switches are read through the API"
else
  fail "locally, the switches were not read through the API"
fi

baseline
api_vars
printf '{"name":"CLAUDE_LANES_MERGE_RUNG_CAP","value":"off"}' | put actions_variables_CLAUDE_LANES_MERGE_RUNG_CAP
rm -f "$FIX/actions_variables_CLAUDE_LANES_MERGE_RUNG_CAP.status"
local_recheck "locally, an API rung cap of off fails" 1 "rung-off:rungCap"

baseline
api_vars
printf '{"name":"CLAUDE_LANES_REPO_DISABLED","value":"true"}' | put actions_variables_CLAUDE_LANES_REPO_DISABLED
local_recheck "locally, CLAUDE_LANES_REPO_DISABLED not false fails" 1 "kill-switch:repo-switch-not-false"

baseline
api_vars
printf '[{"total_count":1,"variables":[{"name":"CLAUDE_LANES_DISABLED","value":"true"}]}]' |
  put actions_organization-variables_per_page_100
local_recheck "locally, the org switch not false fails" 1 "kill-switch:org-switch-not-false"

baseline
api_vars
rm -f "$FIX/actions_variables_CLAUDE_LANES_DISABLED.status"
printf '{"name":"CLAUDE_LANES_DISABLED","value":"false"}' | put actions_variables_CLAUDE_LANES_DISABLED
local_recheck "locally, a repository shadow of the org switch fails" 1 "kill-switch:repo-shadow-present"

baseline
# The rung cap is read first, from the same surface the sandbox saw answer 403.
local_recheck "locally, unreadable variables fail" 1 "rung-off:rungCap"

# --- Class, in flight, grouping -----------------------------------------------

baseline
patch graphql-PolicyEligibility-7 '.data.repository.pullRequest.closingIssuesReferences.nodes[0].labels.nodes = [{"name":"work-class: scoped"}]'
printf '[[%s]]' "$(labeled labeled 'work-class: scoped' alice User 2026-10-11T09:00:00Z)" |
  put issues_42_timeline_per_page_100
expect "a class above the rung fails" 1 "class-above-rung"

baseline
patch graphql-PolicyMergeQueue '.data.repository.mergeQueue.entries |= (.totalCount = 2 | .nodes += [{"enqueuer":{"__typename":"Bot","login":"agent-lanes"},"pullRequest":{"number":8}}])'
expect "another identity entry in flight fails" 1 "in-flight:identity-entry-queued:#8"

baseline
patch graphql-PolicyMergeQueue '.data.repository.mergeQueue.entries |= (.totalCount = 2 | .nodes += [{"enqueuer":{"__typename":"User","login":"alice"},"pullRequest":{"number":9}}])'
expect "a human entry ahead in the queue does not hold" 0 -

baseline
printf '[[{"type":"merge_queue","parameters":{"grouping_strategy":"HEADGREEN"}}]]' |
  put rules_branches_main_per_page_100
expect "a grouping strategy other than ALLGREEN fails" 1 "grouping:HEADGREEN"

# --- The fixed rules ------------------------------------------------------------

baseline
files 5 .github/workflows/x.yml
expect "a HIGH path fails" 1 "risk:high-path:.github/**"

baseline
files 196 plugins/foo/README.md
expect "201 changed lines fails" 1 "risk:lines-over"

baseline
files 195 plugins/foo/README.md
expect "200 changed lines passes" 0 -

baseline
files 1 plugins/foo/a.md plugins/foo/b.md plugins/foo/c.md plugins/foo/d.md plugins/foo/e.md \
  plugins/foo/f.md plugins/foo/g.md plugins/foo/h.md plugins/foo/i.md
expect "9 files fails" 1 "risk:files-over"

baseline
files 1 plugins/foo/a.md plugins/foo/b.md plugins/foo/c.md plugins/foo/d.md plugins/foo/e.md \
  plugins/foo/f.md plugins/foo/g.md plugins/foo/h.md
expect "8 files passes" 0 -

baseline
printf '[[%s]]' "$(labeled labeled 'merge: agent-allowed' agent-lanes Bot 2026-10-12T12:30:00Z)" |
  put issues_7_timeline_per_page_100
expect "an opt-in label from a non-human fails" 1 "ineligible:opt-in-label:labeler-not-human"

baseline
printf '[[%s]]' "$(labeled labeled 'work-class: mechanical' agent-lanes Bot 2026-10-11T09:00:00Z)" |
  put issues_42_timeline_per_page_100
expect "a class label from a non-human fails" 1 "ineligible:class-provenance:labeler-not-human"

baseline
patch graphql-RecheckPullRequest-7 '.data.repository.pullRequest.body = "Closes #42\n\nDo not merge until the release."'
expect "a body hold fails" 1 "body-hold"

baseline
printf '[[{"user":{"login":"alice","type":"User"},"body":"Please do not merge this yet."}]]' |
  put issues_7_comments_per_page_100
expect "a human blocking comment fails" 1 "human-blocking-comment:alice"

baseline
printf '[[{"user":{"login":"helper[bot]","type":"Bot"},"body":"Do not merge: CRITICAL regression"}]]' |
  put pulls_7_reviews_per_page_100
expect "a bot's blocking-looking comment does not hold" 0 -

# A lane-authored pull request needs no opt-in label, so only the label's
# history at enqueue can say a human took it away.
lane_authored() {
  patch graphql-PolicyEligibility-7 '.data.repository.pullRequest |= (.author = {"__typename":"Bot","login":"agent-lanes"} | .labels = {"totalCount":0,"nodes":[]})'
  patch graphql-RecheckPullRequest-7 '.data.repository.pullRequest.labels = {"totalCount":0,"nodes":[]}'
  printf '[[]]' | put issues_7_timeline_per_page_100
  printf '[[{"body":"<!-- work-item-lease v1 {\\"holder\\": \\"agent-lanes[bot]\\"} -->","created_at":"2026-10-12T11:00:00Z","user":{"login":"agent-lanes[bot]","type":"Bot"}}]]' |
    put issues_42_comments_per_page_100
}
baseline
lane_authored
expect "a lane-authored entry with no opt-in label passes" 0 -

baseline
lane_authored
printf '[[%s,%s]]' "$(labeled labeled 'merge: agent-allowed' alice User 2026-10-12T12:30:00Z)" \
  "$(labeled unlabeled 'merge: agent-allowed' alice User 2026-10-12T13:30:00Z)" |
  put issues_7_timeline_per_page_100
expect "an opt-in label it had at enqueue, now removed, fails" 1 "opt-in-label-removed"

baseline
lane_authored
printf '[[%s,%s]]' "$(labeled labeled 'merge: agent-allowed' alice User 2026-10-12T12:30:00Z)" \
  "$(labeled unlabeled 'merge: agent-allowed' alice User 2026-10-12T12:45:00Z)" |
  put issues_7_timeline_per_page_100
expect "an opt-in label removed before enqueue does not hold" 0 -

# GitHub's GITHUB_TOKEN cannot add to a merge queue, so a human queues
# Dependabot pull requests; one queued by a Bot is checked like any other.
baseline
config "${PIPELINE/rung: C2/rung: off}"
patch graphql-RecheckPullRequest-7 '.data.repository.pullRequest |= (.author = {"__typename":"Bot","login":"dependabot"} | .commits = {"totalCount":1} | .timelineItems.nodes[0] |= (.actor = {"__typename":"Bot","login":"github-actions"} | .enqueuer = {"__typename":"Bot","login":"github-actions"}))'
printf '[[{"author":{"login":"dependabot[bot]","type":"Bot"},"committer":{"login":"web-flow","type":"User"},"commit":{"verification":{"verified":true}}}]]' |
  put pulls_7_commits_per_page_100
file_payload 'name: pr-automerge-dependabot' | put "contents_.github_workflows_pr-automerge-dependabot.yml_ref_$BASE"
expect "a Dependabot PR queued by the Bot github-actions is checked" 1 "rung-off"
read_terms "a Dependabot PR queued by a Bot reads the policy terms" yes

# --- The step around the recheck ----------------------------------------------

# reads <label> <want>: how many times the run read the queued pull request.
reads() {
  local got
  got="$(grep -c RecheckPullRequest "$TMP_ROOT/log")"
  if [[ "$got" -eq "$2" ]]; then ok "$1"; else fail "$1: $got recheck run(s), wanted $2"; fi
}

# An unreadable answer (exit 2) is retried up to three runs; a failure is not.
baseline
printf '1\n' >"$FIX/graphql-RecheckPullRequest-7.fails"
expect "one transient unreadable read, then a pass, passes" 0 "meets every term"
reads "the transient read is retried once" 2

baseline
printf '3\n' >"$FIX/graphql-RecheckPullRequest-7.fails"
expect "three unreadable runs fail" 2 "unreadable"
reads "unreadable is retried at most three runs" 3

baseline
config "${PIPELINE/rung: C2/rung: off}"
expect "a failing recheck fails" 1 "rung-off"
reads "a failing recheck (exit 1) is not retried" 1

baseline
expect "a non-queue ref fails closed" 1 "cannot read a pull request number" refs/heads/main
not_called api "a non-queue ref reads nothing"

baseline
expect "a queue base without the recheck passes" 0 "predates" "" false "$TMP_ROOT/bare"
not_called api "a queue base without the recheck reads nothing"

test_harness::report
