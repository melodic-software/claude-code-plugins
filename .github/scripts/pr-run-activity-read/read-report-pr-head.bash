# shellcheck shell=bash disable=SC2153,SC2154,SC2249,SC2292 # the step sets the uppercase env
# shellcheck source=/dev/null
{ . .base/.github/actions/log-api-budget/api-budget.bash 2>/dev/null && api_budget_wrap_gh github-token; } || true
# shellcheck source=/dev/null
. .base/.github/scripts/pr-unblock/read-pr-head.bash
sha=""
if [[ $PR_NUMBER =~ ^[1-9][0-9]*$ ]] && read_pr_fields "$PR_NUMBER" .head.sha; then
  sha=$pr_fields
fi
if ! [[ $sha =~ ^[0-9a-f]{40}$ ]]; then
  echo "No PR head SHA read"
  sha=""
fi
echo "sha=$sha" >>"$GITHUB_OUTPUT"
if [[ $PR_NUMBER =~ ^[1-9][0-9]*$ ]]; then echo "number=$PR_NUMBER" >>"$GITHUB_OUTPUT"; fi
if [ -n "$RUN_PR_NUMBER" ] && [ "$RUN_PR_NUMBER" != "$PR_NUMBER" ]; then
  echo "::error::the run job's pr-number is not the PR the caller or event names"
  echo "pr-mismatch=true" >>"$GITHUB_OUTPUT"
fi
