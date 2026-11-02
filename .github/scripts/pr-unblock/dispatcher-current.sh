#!/usr/bin/env bash
# dispatcher-current.sh: whether a dispatched run's dispatcher ran the tip's copy
# of its workflow file. The broker refuses every write token such a run asks for
# as workflow-modified, so its model turn could never land. Compares the blob at
# the dispatcher run's head with the default branch tip's, the broker's own rule,
# for whichever dispatcher file the run names. Read-only; run from the workspace
# root with the tip checked out at .base.
#
# Environment:
#   GH_TOKEN            token with actions: read and contents: read
#   GITHUB_REPOSITORY   owner/repo
#   DISPATCHER_RUN_ID   the dispatcher run the dispatch names
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
run=$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$DISPATCHER_RUN_ID" --jq '.path, .head_sha') ||
  leave "cannot read dispatcher run $DISPATCHER_RUN_ID"
{ read -r path && read -r head; } <<<"$run"
[[ ${path:-} =~ ^\.github/workflows/[A-Za-z0-9._-]+\.ya?ml$ && ${head:-} =~ ^[0-9a-f]{40}$ ]] ||
  leave "dispatcher run $DISPATCHER_RUN_ID names no workflow file and head"
blob=$(gh api "repos/$GITHUB_REPOSITORY/contents/$path?ref=$head" --jq .sha) ||
  leave "cannot read $path at $head"
[[ $blob =~ ^[0-9a-f]{40}$ ]] || leave "cannot read $path at $head"
if [[ $blob != "$(git -C .base rev-parse -q --verify "HEAD:$path")" ]]; then
  echo "::warning::dispatcher-stale: $path at dispatcher run $DISPATCHER_RUN_ID's head $head differs from the default branch tip, so the broker would refuse this run's tokens; no model ran, and a dispatcher on the tip's file sends this PR again"
  echo "stale=true" >>"$GITHUB_OUTPUT"
fi
