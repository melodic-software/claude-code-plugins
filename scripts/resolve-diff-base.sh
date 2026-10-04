#!/usr/bin/env bash
# Resolve the ref every diff-scoped step of ci.yml diffs against, for the
# `scope` job's "Resolve the diff base" step.
#
#   scripts/resolve-diff-base.sh
#
# Run from the checkout, with full history. Reads GITHUB_EVENT_NAME,
# GITHUB_REPOSITORY, GITHUB_REF_NAME and BASE_REF; writes `ref=<base>` to
# $GITHUB_OUTPUT, or nothing for the whole tree. Always exits 0: every failure
# resolves toward the whole tree.
#
# - pull_request: origin/$BASE_REF.
# - push: the newest commit on HEAD's first-parent line (HEAD excluded) with a
#   green ci push run on this branch. Everything after that commit is untested,
#   so the range from it covers every commit no green run has passed. Commits
#   are matched against one listing of the branch's recent ci push runs; a
#   commit the listing does not show as green is asked about directly by
#   head_sha, for the nearest LOOKUPS commits, because the listing has come back
#   without green runs it should have held (#6134). The whole tree when history
#   is shallow, no green ancestor turns up, or the range touches the shared test
#   machinery.
# - anything else (schedule, dispatch): the whole tree.
set -uo pipefail

WALK=200
LOOKUPS=20
LISTED=100
event=${GITHUB_EVENT_NAME:-}
output=${GITHUB_OUTPUT:-/dev/null}

whole() {
  echo "::notice::$1; this $event run tests the whole tree."
  exit 0
}

case "$event" in
pull_request)
  echo "ref=origin/${BASE_REF:-}" >>"$output"
  exit 0
  ;;
push) ;;
*) whole "A $event run has no diff base" ;;
esac

runs="repos/${GITHUB_REPOSITORY:-}/actions/workflows/ci.yml/runs?branch=${GITHUB_REF_NAME:-}&event=push"
green='[.workflow_runs[] | select(.conclusion == "success") | .head_sha]'

[[ "$(git rev-parse --is-shallow-repository 2>&1)" == false ]] ||
  whole "History is shallow or unreadable, so ancestry cannot be determined"
line=$(git rev-list --first-parent --max-count="$WALK" HEAD^ 2>&1) ||
  whole "HEAD's ancestry could not be read: $line"

if listed=$(gh api "$runs&per_page=$LISTED" --jq "$green | .[]" 2>&1); then
  echo "The listing of the last $LISTED ci push runs holds $(grep -c . <<<"$listed") green; newest first: $(head -5 <<<"$listed" | cut -c1-9 | tr '\n' ' ')"
else
  echo "The ci push runs could not be listed ($listed); asking commit by commit."
  listed=''
fi

base='' how='' n=0
for sha in $line; do
  n=$((n + 1))
  if grep -qx "$sha" <<<"$listed"; then
    base=$sha how='green in the listing'
    break
  fi
  if ((n <= LOOKUPS)); then
    if found=$(gh api "$runs&head_sha=$sha" --jq "$green | length" 2>&1); then
      if [[ "$found" != 0 ]]; then
        base=$sha how='green by head_sha lookup, missing from the listing'
        break
      fi
      echo "Skipped ${sha:0:9} ($n back): no green ci push run."
    else
      echo "Skipped ${sha:0:9} ($n back): the head_sha lookup failed ($found)."
    fi
  fi
done
[[ -n "$base" ]] || whole "No commit among the last $WALK on HEAD's first-parent line has a green ci push run"

infra=$(git diff --name-only "$base" HEAD -- .github/workflows/ci.yml .github/actions \
  '.github/requirements-ci*.txt' 'scripts/run-plugin-tests*' 'scripts/affected-tests*' \
  'scripts/plan-test-lanes*' 'scripts/run-outside-node-suites*' 'scripts/outside-node-*.txt' \
  'scripts/resolve-diff-base*' scripts/lib \
  .shellcheckrc .node-version .python-version package.json package-lock.json) ||
  whole "git diff $base failed"
[[ -z "$infra" ]] || whole "The range since $base ($n back, $how) touches the shared test machinery: ${infra//$'\n'/ }"
echo "::notice::Diff base: $base, the newest green push run HEAD descends from ($n back on the first-parent line, $how)."
echo "ref=$base" >>"$output"
