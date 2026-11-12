# shellcheck shell=bash
# The rate-limit stop this job's stop file holds, as one label for the jobs
# after it: `every pool until <time>` while a `*` stop holds, else `the <pool>
# pool until <time>` for the pool whose stop ends last. The time is the latest
# reset any stop still holds. Source api-budget.bash first: its
# api_budget_stop_until reads the file by the readers' rule (rate-guard.vectors.json
# stop_files), so a CRLF line, a torn line or a past stop counts for nothing,
# and an unreadable file holds every pool. Prints nothing when no stop holds.
rate_stop_label() {
  local until pool p
  until=$(api_budget_stop_until any)
  [[ -n $until ]] || return 0
  if [[ -n $(api_budget_stop_until '*') ]]; then
    pool="every pool"
  else
    pool="an unnamed pool"
    while read -r p; do
      if [[ $(api_budget_stop_until "$p") == "$until" ]]; then
        pool="the $p pool"
        break
      fi
    done < <(grep -aoE '^[a-z_]+ [0-9]{1,12}$' "${RUNNER_TEMP:-/tmp}/api-budget/stop" 2>/dev/null | cut -d' ' -f1 | sort -u)
  fi
  echo "$pool until $(api_budget_when "$until")"
}

# The 5xx when the stops ending at rate_stop_label's time are server error
# holds by the job's cause file (api_budget_server_status); returns 1 for a
# rate limit, the safe reading, with no stop or no cause too.
rate_stop_server() {
  api_budget_server_status any "$(api_budget_stop_until any)"
}

# That stop's cause in words: `a GitHub server error hold (HTTP <5xx> with a
# Retry-After)`, else `a GitHub rate limit`.
rate_stop_cause() {
  local status
  if status=$(rate_stop_server); then
    echo "a GitHub server error hold (HTTP $status with a Retry-After)"
  else
    echo "a GitHub rate limit"
  fi
}

# The stop after a failed call whose stderr is in <file>: the one the rate guard
# recorded, else, when gh's message names a rate limit or a 429 but the guard
# saw no headers, the stop api_budget_pass records for such a call (every
# pool, a minute for a secondary limit, else an hour), recorded the same way.
# Prints nothing when the call was no rate limit.
rate_stop_from() {
  local stop seconds=3600
  stop=$(rate_stop_label)
  if [[ -z $stop ]] && grep -qiE 'rate limit|RATE_LIMITED|abuse detection|HTTP 429' "$1" 2>/dev/null; then
    ! grep -qiE 'secondary rate limit|abuse detection' "$1" || seconds=60
    api_budget_stop '*' $(($(date +%s) + seconds)) fallback "$2" 2>/dev/null || :
    stop=$(rate_stop_label)
  fi
  echo "$stop"
}
