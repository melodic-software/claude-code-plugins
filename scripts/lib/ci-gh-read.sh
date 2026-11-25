# shellcheck shell=bash
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
  rm -rf "$1/pr-reads" "$1/api-budget"
  echo "$2" >"$1/gh-read.deadline"
}
