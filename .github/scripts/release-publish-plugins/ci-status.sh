#!/usr/bin/env bash
set -euo pipefail
: "${GITHUB_REPOSITORY:?}" "${1:?usage: ci-status.sh [--unfinished] <sha>}"

ACTIONS_APP_ID=15368

if [[ $1 == --unfinished ]]; then
  exec gh api "repos/$GITHUB_REPOSITORY/commits/${2:?}/check-runs?app_id=$ACTIONS_APP_ID&filter=all&per_page=100" --paginate \
    --jq '.check_runs[] | select(.status != "completed") | .name'
fi

gate_runs() { gh api "repos/$GITHUB_REPOSITORY/commits/$1/check-runs?check_name=$2&app_id=$ACTIONS_APP_ID&filter=latest&per_page=100" --jq .check_runs; }
runs=$(gate_runs "$1" 'CI%20Status')
[[ $(jq length <<<"$runs") -gt 0 ]] || runs=$(gate_runs "$1" ci-status)

# shellcheck disable=SC2016  # the $ names are jq variables, not shell
jq -r '
  . as $runs
  | [$runs[] | try (.started_at | fromdateiso8601) catch null] as $t
  | (if $t != [] and all($t[]; . != null)
     then ($t | max) as $last | [range($runs | length) | select($t[.] == $last) | $runs[.]]
     else $runs end) as $deciding
  | if $deciding == [] or any($deciding[]; .status != "completed") then "pending"
    else [$deciding[].conclusion | select(. != "success")] as $failed
    | if any($failed[]; . == "failure") then "failure"
      elif $failed != [] then ($failed[0] // "pending")
      else "success" end
    end' <<<"$runs"
