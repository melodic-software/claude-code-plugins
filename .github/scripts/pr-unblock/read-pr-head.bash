# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # pr_fields is read by the sourcing step; GITHUB_REPOSITORY is set by Actions
# read_pr_fields <number> <jq fields>: reads the pull request through `gh api`
# (the api-budget wrapper's gh when the caller defined it) and leaves the
# fields, one per line, in pr_fields. A failed read prints
# `::error::the PR could not be read (<class>): <stderr>` and returns 1; the
# caller ends the step, or, with READ_PR_FAILURE=warning or notice, goes on and
# the line takes that level. Classes: rate-limit (a 429, a rate-limit message or the
# wrapper's refusal) is never read again; transient (a 5xx, a network error or
# a body that is not JSON) is read once more after a wait drawn from 0 to 10 s (full jitter); other is
# final.
# Source it from the default branch checkout, never from the PR's head.
read_pr_fields() {
  local err attempt class reason level
  err=$(mktemp)
  for attempt in 1 2; do
    if pr_fields=$(gh api "repos/$GITHUB_REPOSITORY/pulls/$1" --jq "$2" 2>"$err"); then
      rm -f "$err"
      return 0
    fi
    class=other
    if grep -qiE 'rate limit|RATE_LIMITED|abuse detection|HTTP 429|was not sent' "$err" ||
      { declare -F api_budget_stop_until >/dev/null && [[ -n $(api_budget_stop_until core) ]]; }; then
      class=rate-limit
    elif grep -qiE 'HTTP 5[0-9][0-9]|unexpected end of JSON input|invalid character|error connecting to|connection reset|connection refused|i/o timeout|tls handshake timeout|unexpected eof|timed out|timeout' "$err"; then
      class=transient
    fi
    reason=$(tr '\r\n' '  ' <"$err" | cut -c1-300 | sed 's/ *$//')
    reason=${reason//%/%25}
    if [[ $class == transient && $attempt == 1 ]]; then
      echo "::warning::reading #$1 failed (transient): ${reason:-no error text}; reading again"
      sleep $((RANDOM % 11))
      continue
    fi
    case ${READ_PR_FAILURE:-} in warning | notice) level=$READ_PR_FAILURE ;; *) level=error ;; esac
    echo "::$level::the PR could not be read ($class): ${reason:-no error text}"
    rm -f "$err"
    return 1
  done
}
