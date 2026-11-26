#!/usr/bin/env bash
# Exit codes:
#   0  it stands
#   1  it does not, or it did not read
# shellcheck disable=SC2154 # the step env sets PR, HEAD_SHA and DEFAULT_BRANCH, and the runner GITHUB_REPOSITORY
set -euo pipefail
[[ -z "${RUNNER_TEMP:-}" ]] || ! . "${BASH_SOURCE[0]%/*}/../../../.github/actions/log-api-budget/api-budget.bash" 2>/dev/null || api_budget_wrap_gh github-token
[[ $PR =~ ^[1-9][0-9]{0,9}$ && $HEAD_SHA =~ ^[0-9a-f]{40}$ ]] || { echo "::error::PR and HEAD_SHA must be a number and a full SHA"; exit 1; }
set +e
fields=$(gh api "repos/$GITHUB_REPOSITORY/pulls/$PR" --jq '[.state, .head.repo.full_name, .base.ref, .head.sha] | @tsv')
status=$?
set -e
if [[ $status -ne 0 || -z $fields ]]; then
  echo "::error::pull request #$PR did not read"
  exit 1
fi
read -r state repo base head <<<"$fields"
if [[ $state != open || $repo != "$GITHUB_REPOSITORY" || $base != "$DEFAULT_BRANCH" ]]; then
  echo "::error::pull request #$PR is not an open pull request from this repository into $DEFAULT_BRANCH"
  exit 1
fi
if [[ $head != "$HEAD_SHA" ]]; then
  echo "::error::pull request #$PR's head moved to $head after the dispatch named $HEAD_SHA; no record is posted"
  exit 1
fi
echo "pull request #$PR stands at $HEAD_SHA"
