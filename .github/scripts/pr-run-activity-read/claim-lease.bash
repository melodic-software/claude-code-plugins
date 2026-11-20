# shellcheck shell=bash disable=SC2153,SC2154,SC2249,SC2292 # the step sets the uppercase env
# shellcheck source=/dev/null
{ . .base/.github/actions/log-api-budget/api-budget.bash 2>/dev/null && api_budget_wrap_gh github-token; } || true
[[ $ISSUE_NUMBER =~ ^[1-9][0-9]*$ && $HOLDER =~ ^[1-9][0-9]*$ && $TIMEOUT_MINUTES =~ ^[1-9][0-9]*$ ]] || {
  echo "::error::the issue number, lanes App sender id or timeout is not a positive integer"
  exit 1
}
rc=0
out="$(bash "$TRACKER" claim "github:$REPO#$ISSUE_NUMBER" --lease-only --holder "$HOLDER" \
  --ttl-hours $(((TIMEOUT_MINUTES + 59) / 60 + 1)) --session-id "run-$GITHUB_RUN_ID")" || rc=$?
if [ "$rc" -eq 7 ]; then
  echo "::notice::already-leased: a live lease on #$ISSUE_NUMBER predates this run's, so no model runs"
  echo "lease=already-leased" >>"$GITHUB_OUTPUT"
  note="already-leased: another session holds a live lease on #$ISSUE_NUMBER, so run $GITHUB_SERVER_URL/$REPO/actions/runs/$GITHUB_RUN_ID ran no model."
  echo "$note" >>"$GITHUB_STEP_SUMMARY"
  gh api "repos/$REPO/issues/$ISSUE_NUMBER/comments" -f body="$note" --jq .id >/dev/null ||
    echo "::warning::could not comment the already-leased back-off on #$ISSUE_NUMBER"
  exit 0
fi
[ "$rc" -eq 0 ] || exit "$rc"
id="$(jq -r '.lease_comment_id' <<<"$out")"
[[ $id =~ ^[1-9][0-9]*$ ]] || {
  echo "::error::the claim returned no lease comment id; the lease expires at its TTL"
  exit 1
}
echo "lease=held" >>"$GITHUB_OUTPUT"
echo "lease-comment-id=$id" >>"$GITHUB_OUTPUT"
