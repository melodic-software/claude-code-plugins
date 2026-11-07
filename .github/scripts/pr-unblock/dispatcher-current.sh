#!/usr/bin/env bash
# dispatcher-current.sh: whether a dispatched run's dispatcher ran the tip's copy
# of its workflow file. The broker refuses every write token such a run asks for
# as workflow-modified, so its model turn could never land. Compares the blob at
# the commit the dispatcher run ran with the default branch tip's, the broker's
# own rule, for whichever dispatcher file the run names. Read-only; run from the
# workspace root with the tip checked out at .base.
#
# Environment:
#   GH_TOKEN            token with actions: read and contents: read
#   GITHUB_REPOSITORY   owner/repo
#   DISPATCHER_RUN_ID   the dispatcher run the dispatch names
#   GITHUB_RUN_ID       this run, which a pull_request_target dispatcher's record names
#   GITHUB_OUTPUT       receives stale=true when the files differ
#
# Exit: 0. Anything unreadable sets nothing and leaves it to the broker. In a
# job, non-zero (killed by TERM) when the api-budget rate guard cannot record
# a rate-limit stop and ends the step (api_budget_stop).
set -uo pipefail
# In a job, each gh call keeps its rate-limit reading for the job-end
# api-budget notice (.github/actions/log-api-budget).
# shellcheck source=/dev/null
[[ -z "${RUNNER_TEMP:-}" ]] || ! . "${BASH_SOURCE[0]%/*}/../../../.github/actions/log-api-budget/api-budget.bash" 2>/dev/null || api_budget_wrap_gh github-token
: "${GITHUB_REPOSITORY:?}" "${GITHUB_OUTPUT:?}"

leave() {
  echo "::notice::$1; the token broker decides"
  exit 0
}

[[ ${DISPATCHER_RUN_ID:-} =~ ^[1-9][0-9]{0,14}$ ]] || leave "the dispatcher run id is malformed"
run=$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$DISPATCHER_RUN_ID" --jq '.path, .head_sha, .event') ||
  leave "cannot read dispatcher run $DISPATCHER_RUN_ID"
{ read -r path && read -r head && read -r event; } <<<"$run"
# A pull_request_target run's head_sha is the PR head; the default-branch commit
# it ran is the one its record names (check-trusted-trigger's rule), and with no
# record nothing is read.
if [[ ${event:-} == pull_request_target ]]; then
  [[ ${GITHUB_RUN_ID:-} =~ ^[1-9][0-9]{0,14}$ ]] || leave "this run's id is malformed"
  head=$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$DISPATCHER_RUN_ID/artifacts?per_page=100" --jq "[.artifacts[]
      | select(.expired == false and .workflow_run.id == $DISPATCHER_RUN_ID)
      | .name | capture(\"^pr-unblock-target-dispatched-(?<sha>[0-9a-f]{40})-$GITHUB_RUN_ID\$\").sha][0] // empty") ||
    leave "cannot read dispatcher run $DISPATCHER_RUN_ID's record"
  [[ $head =~ ^[0-9a-f]{40}$ ]] || leave "dispatcher run $DISPATCHER_RUN_ID has not recorded run $GITHUB_RUN_ID"
fi
[[ ${path:-} =~ ^\.github/workflows/[A-Za-z0-9._-]+\.ya?ml$ && ${head:-} =~ ^[0-9a-f]{40}$ ]] ||
  leave "dispatcher run $DISPATCHER_RUN_ID names no workflow file and head"
blob=$(gh api "repos/$GITHUB_REPOSITORY/contents/$path?ref=$head" --jq .sha) ||
  leave "cannot read $path at $head"
[[ $blob =~ ^[0-9a-f]{40}$ ]] || leave "cannot read $path at $head"
if [[ $blob != "$(git -C .base rev-parse -q --verify "HEAD:$path")" ]]; then
  echo "::warning::dispatcher-stale: $path at dispatcher run $DISPATCHER_RUN_ID's head $head differs from the default branch tip, so the broker would refuse this run's tokens; no model ran, and a dispatcher on the tip's file sends this PR again"
  echo "stale=true" >>"$GITHUB_OUTPUT"
fi
