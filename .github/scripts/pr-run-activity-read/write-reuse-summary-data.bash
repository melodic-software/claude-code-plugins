# shellcheck shell=bash disable=SC2153,SC2154,SC2249,SC2292 # the step sets the uppercase env
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
ISSUE_LANE_WEB_HOSTS=$(yq -o=json -I=0 '(.activities."resolve-issue"."web-access" | select(.enabled == true) | .domains) // []' ".base/$CONFIG_PATH")
export ISSUE_LANE_WEB_HOSTS
if ! [[ $ISSUE_NUMBER =~ ^[1-9][0-9]{0,9}$ ]] || ! [[ $BASE_SHA =~ ^[0-9a-f]{40}$ ]] ||
  ! [[ $REUSE_BRANCH =~ ^work-resolve-issue/issue-${ISSUE_NUMBER}-[1-9][0-9]*-[1-9][0-9]*$ ]]; then
  echo "::error::the summary pass needs this issue's lane branch and a base commit"
  exit 1
fi
mkdir -p "$DATA"
node .base/.github/scripts/work-resolve-issue/write-issue.mjs
git init -q "$SRC"
git -C "$SRC" remote add origin "$GITHUB_SERVER_URL/$GITHUB_REPOSITORY"
git -C "$SRC" fetch -q --no-tags --filter=blob:none origin "$BASE_SHA" "refs/heads/$REUSE_BRANCH:refs/lane"
tip=$(git -C "$SRC" rev-parse --verify 'refs/lane^{commit}')
git -C "$SRC" diff --no-ext-diff --no-textconv --no-color "$BASE_SHA...$tip" >"$DATA/diff.patch"
bytes=$(stat -c %s "$DATA/diff.patch")
truncate -s '<1000000' "$DATA/diff.patch"
jq -n --argjson issue "$ISSUE_NUMBER" --arg branch "$REUSE_BRANCH" --arg base "$BASE_SHA" --arg tip "$tip" \
  --argjson bytes "$bytes" '{issue: $issue, branch: $branch, base_sha: $base, tip_sha: $tip,
  diff_bytes: $bytes, truncated: ($bytes > 1000000)}' >"$DATA/branch.json"
echo "tip=$tip" >>"$GITHUB_OUTPUT"
