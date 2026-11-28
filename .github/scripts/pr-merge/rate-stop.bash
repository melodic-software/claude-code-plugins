# shellcheck shell=bash
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

rate_stop_server() {
  api_budget_server_status any "$(api_budget_stop_until any)"
}

rate_stop_cause() {
  local status
  if status=$(rate_stop_server); then
    echo "a GitHub server error hold (HTTP $status with a Retry-After)"
  else
    echo "a GitHub rate limit"
  fi
}

rate_stop_from() {
  local stop seconds=3600
  stop=$(rate_stop_label)
  if [[ -z $stop ]] && ! grep -qE 'no call to it before|was not sent: GitHub' "$1" 2>/dev/null &&
    grep -qiE 'rate limit|RATE_LIMITED|abuse detection|HTTP 429' "$1" 2>/dev/null; then
    ! grep -qiE 'secondary rate limit|abuse detection' "$1" || seconds=60
    api_budget_stop '*' $(($(date +%s) + seconds)) fallback "$2" 2>/dev/null || :
    stop=$(rate_stop_label)
  fi
  echo "$stop"
}
