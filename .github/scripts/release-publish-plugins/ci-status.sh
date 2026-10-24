#!/usr/bin/env bash
# ci-status.sh <sha>
#
# Print the ci-status result on <sha> in GITHUB_REPOSITORY: success, pending,
# failure when any deciding run failed, else another deciding run's
# non-success conclusion. Only GitHub Actions' runs are read: it is the app the
# ruleset requires ci-status from, so another app's run of that name, with any
# start time it chooses, never decides. filter=latest keeps the latest run of
# each check suite, so a re-triggered workflow leaves an older run beside a
# newer one: the runs that started last decide, and all runs do when one has
# no readable start time. No run, or one not completed, is pending. Exit
# non-zero when the runs cannot be read.
set -euo pipefail
: "${GITHUB_REPOSITORY:?}" "${1:?usage: ci-status.sh <sha>}"

ACTIONS_APP_ID=15368

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
