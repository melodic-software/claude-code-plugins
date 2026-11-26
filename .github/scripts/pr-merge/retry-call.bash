# shellcheck shell=bash
# shellcheck disable=SC2034 # retry_call_unknown and retry_call_waited are read by the caller
retry_call() {
  local tries=1 attempt=1 budget err rc stop until wait ceiling
  retry_call_unknown=
  retry_call_waited=0
  if [[ ${1-} == --read ]]; then
    tries=3
    shift
  fi
  budget=$1
  shift
  err=$(mktemp) || {
    retry_call_unknown="no temp file for the call's stderr"
    return 2
  }
  while :; do
    rc=0
    "$@" 2>"$err" || rc=$?
    cat "$err" >&2
    if ((rc == 0)); then
      rm -f "$err"
      return 0
    fi
    stop=$(rate_stop_from "$err" "$*")
    until=$(api_budget_stop_until any)
    if [[ -n $until ]]; then
      wait=$((until - $(date +%s)))
      ((wait < 0)) && wait=0
    else
      ceiling=$((15 << (attempt - 1)))
      wait=$((RANDOM % (ceiling + 1)))
    fi
    if ((attempt < tries && wait <= budget)); then
      budget=$((budget - wait))
      retry_call_waited=$((retry_call_waited + wait))
      sleep "$wait"
      attempt=$((attempt + 1))
      continue
    fi
    if [[ -n $stop ]]; then
      retry_call_unknown="rate limited ($stop)"
    elif ((tries == 1)); then
      retry_call_unknown="failed once"
    elif ((attempt >= tries)); then
      retry_call_unknown="failed $attempt times"
    else
      retry_call_unknown="a wait of $wait s is past the budget"
    fi
    rm -f "$err"
    return 2
  done
}
