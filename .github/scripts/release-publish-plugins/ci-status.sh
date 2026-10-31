#!/usr/bin/env bash
# ci-status.sh <sha>
# ci-status.sh --unfinished <sha>
#
# Print the ci-status result on <sha> in GITHUB_REPOSITORY: success, pending,
# failure when any deciding run failed, else another deciding run's
# non-success conclusion. Only GitHub Actions' runs are read: it is the app the
# ruleset requires ci-status from, so another app's run of that name, with any
# start time it chooses, never decides. Any GITHUB_TOKEN with checks: write
# posts as that app too, as the ruleset's own check does. filter=latest keeps the latest run of
# each check suite, so a re-triggered workflow leaves an older run beside a
# newer one: the runs that started last decide, and all runs do when one has
# no readable start time. No run, or one not completed, is pending. Exit
# non-zero when the runs cannot be read.
#
# --unfinished prints the name of every GitHub Actions check run on <sha>, of
# any name, that has not completed: ci-status has no run until a full run's
# lanes finish, so it alone cannot show them running. filter=all, since it can
# only show more unfinished runs than filter=latest.
set -euo pipefail
: "${GITHUB_REPOSITORY:?}" "${1:?usage: ci-status.sh [--unfinished] <sha>}"

ACTIONS_APP_ID=15368

if [[ $1 == --unfinished ]]; then
  # gh applies --jq to each page, so this prints names, never one verdict per page.
  exec gh api "repos/$GITHUB_REPOSITORY/commits/${2:?}/check-runs?app_id=$ACTIONS_APP_ID&filter=all&per_page=100" --paginate \
    --jq '.check_runs[] | select(.status != "completed") | .name'
fi

# shellcheck disable=SC2016  # the $ names are jq variables, not shell
gh api "repos/$GITHUB_REPOSITORY/commits/$1/check-runs?check_name=ci-status&app_id=$ACTIONS_APP_ID&filter=latest&per_page=100" --jq '
  .check_runs as $runs
  | [$runs[] | try (.started_at | fromdateiso8601) catch null] as $t
  | (if $t != [] and all($t[]; . != null)
     then ($t | max) as $last | [range($runs | length) | select($t[.] == $last) | $runs[.]]
     else $runs end) as $deciding
  | if $deciding == [] or any($deciding[]; .status != "completed") then "pending"
    else [$deciding[].conclusion | select(. != "success")] as $failed
    | if any($failed[]; . == "failure") then "failure"
      elif $failed != [] then ($failed[0] // "pending")
      else "success" end
    end'
