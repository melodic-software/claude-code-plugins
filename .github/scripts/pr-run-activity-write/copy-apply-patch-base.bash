# shellcheck shell=bash disable=SC2153,SC2154,SC2249,SC2292 # the step sets the uppercase env
mkdir -p "$RUNNER_TEMP/pr-unblock" "$RUNNER_TEMP/pr-merge" "$RUNNER_TEMP/lib" "$DEST/$(dirname "$RULES")"
cp .base/.github/scripts/lib/retry-fetch.mjs "$RUNNER_TEMP/lib/"
cp .base/.github/scripts/lib/run-main.mjs "$RUNNER_TEMP/lib/"
cp .base/.github/scripts/pr-unblock/thread-scope.mjs "$RUNNER_TEMP/pr-unblock/"
cp .base/.github/scripts/pr-unblock/dependency-classify.mjs "$RUNNER_TEMP/pr-unblock/"
cp .base/.github/scripts/pr-unblock/escalation-routes.mjs "$RUNNER_TEMP/pr-unblock/"
cp .base/.github/scripts/pr-unblock/escalation-routes.json "$RUNNER_TEMP/pr-unblock/"
cp .base/.github/scripts/pr-merge/merge-holds.mjs "$RUNNER_TEMP/pr-merge/"
cp ".base/$RULES" "$DEST/$RULES"
if [ -f .base/.github/dependabot.yml ]; then
  cp .base/.github/dependabot.yml "$DEST/.github/dependabot.yml"
fi
if [ "$PATCH_PREPARE" = shared-copies ]; then
  mkdir -p "$DEST/scripts"
  git -C .base show "$MERGE_BASE_SHA:scripts/shared-copies.txt" >"$DEST/scripts/shared-copies.txt"
fi
echo "dir=$DEST" >>"$GITHUB_OUTPUT"
