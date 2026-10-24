# shellcheck shell=bash
# Writes ci-status's gh_read helper for the step-body tests. Sourced, never
# executed.
#
#   ci_gh_read::install <workflow> <dir> [budget]
#
# Runs the `Write the rate-limit-aware read helper` step body of <workflow>
# with RUNNER_TEMP=<dir> and the job's GH_READ_* env values, which leaves
# <dir>/gh-read.sh for the step bodies under test to source. With `budget`,
# the job's API_BUDGET_SH goes in too, so every gh call runs through the
# api-budget wrapper and its rate guard, as in the job. Returns non-zero when
# the step is missing or fails.
#
#   ci_gh_read::reset <dir> <deadline>
#
# Clears the rate-guard stops an earlier case left in <dir> and sets the
# wait deadline to the epoch second <deadline>, so a case runs on a stub clock.
ci_gh_read::install() {
  local workflow="$1" dir="$2" budget=
  if [[ ${3:-} == budget ]]; then
    budget=$(awk '/^      API_BUDGET_SH: \|$/ { on = 1; next }
      on && /^        / { print substr($0, 9); next }
      on && /^[[:blank:]]*$/ { print ""; next }
      on { exit }' "$workflow")
    [[ -n "$budget" ]] || return 1
  fi
  awk '$0 == "      - name: Write the rate-limit-aware read helper" { on = 1; next }
    on && /^      - / { exit }
    on && /^        run: \|$/ { body = 1; next }
    body && /^          / { print substr($0, 11); next }
    body && /^[[:blank:]]*$/ { print ""; next }
    body { exit }' "$workflow" >"$dir/gh-read-step.sh"
  [[ -s "$dir/gh-read-step.sh" ]] || return 1
  local job_seconds margin
  job_seconds=$(sed -nE 's/^      GH_READ_JOB_SECONDS: ([0-9]+)$/\1/p' "$workflow")
  margin=$(sed -nE 's/^      GH_READ_MARGIN_SECONDS: ([0-9]+)$/\1/p' "$workflow")
  [[ -n "$job_seconds" && -n "$margin" ]] || return 1
  API_BUDGET_SH="$budget" RUNNER_TEMP="$dir" GH_READ_JOB_SECONDS="$job_seconds" GH_READ_MARGIN_SECONDS="$margin" \
    bash -e "$dir/gh-read-step.sh" && [[ -s "$dir/gh-read.sh" ]]
}

ci_gh_read::reset() {
  rm -rf "$1/api-budget"
  echo "$2" >"$1/gh-read.deadline"
}
