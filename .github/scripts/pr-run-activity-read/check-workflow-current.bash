# shellcheck shell=bash disable=SC2153,SC2154,SC2249,SC2292 # the step sets the uppercase env
caller=${WORKFLOW_REF%%@*}
caller=.github/workflows/${caller##*/.github/workflows/}
if [[ $caller != .github/workflows/?* || ! $WORKFLOW_SHA =~ ^[0-9a-f]{40}$ ]] ||
  ! git -C .base cat-file -e "$WORKFLOW_SHA^{commit}" 2>/dev/null; then
  echo "::notice::cannot read the run's workflow commit; the token broker decides"
  exit 0
fi
for path in "$caller" .github/workflows/pr-run-activity-write.yml; do
  if [ "$(git -C .base rev-parse -q --verify "$WORKFLOW_SHA:$path")" != "$(git -C .base rev-parse -q --verify "HEAD:$path")" ]; then
    echo "::warning::workflow-stale: $path differs from main's tip, so the broker would refuse this run's apply job; no model ran, and the run's report-outcome re-fires the issue on main's files"
    echo "stale=true" >>"$GITHUB_OUTPUT"
    exit 0
  fi
done
