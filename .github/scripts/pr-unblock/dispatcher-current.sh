#!/usr/bin/env bash
set -uo pipefail
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
[[ $head != "$(git -C .base rev-parse -q --verify HEAD)" ]] || exit 0
blob=$(gh api "repos/$GITHUB_REPOSITORY/contents/$path?ref=$head" --jq .sha) && [[ $blob =~ ^[0-9a-f]{40}$ ]] ||
  leave "cannot read $path at $head"
if [[ $blob != "$(git -C .base rev-parse -q --verify "HEAD:$path")" ]]; then
  echo "::warning::dispatcher-stale: $path at dispatcher run $DISPATCHER_RUN_ID's head $head differs from the default branch tip, so the broker would refuse this run's tokens; no model ran, and a dispatcher on the tip's file sends this PR again"
  echo "stale=true" >>"$GITHUB_OUTPUT"
fi
