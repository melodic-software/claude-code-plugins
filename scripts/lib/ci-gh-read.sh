# shellcheck shell=bash
# Writes ci-status's gh_read helper for the step-body tests. Sourced, never
# executed.
#
#   ci_gh_read::install <workflow> <dir>
#
# Runs the `Write the rate-limit-aware read helper` step body of <workflow>
# with RUNNER_TEMP=<dir>, which leaves <dir>/gh-read.sh for the step bodies
# under test to source. Returns non-zero when the step is missing or fails.
ci_gh_read::install() {
  local workflow="$1" dir="$2"
  awk '$0 == "      - name: Write the rate-limit-aware read helper" { on = 1; next }
    on && /^      - / { exit }
    on && /^        run: \|$/ { body = 1; next }
    body && /^          / { print substr($0, 11); next }
    body && /^[[:blank:]]*$/ { print ""; next }
    body { exit }' "$workflow" >"$dir/gh-read-step.sh"
  [[ -s "$dir/gh-read-step.sh" ]] || return 1
  RUNNER_TEMP="$dir" bash -e "$dir/gh-read-step.sh" && [[ -s "$dir/gh-read.sh" ]]
}
