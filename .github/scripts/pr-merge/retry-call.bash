# shellcheck shell=bash
# retry_call [--read] <budget-seconds> <command...>: runs the command in this
# shell and returns 0 when it succeeds, else 2 for unknown, with the reason in
# retry_call_unknown. With --read a failure is tried again, three runs at most:
# after a rate limit it waits until the rate guard's stop, otherwise a capped
# exponential backoff with full jitter. Waits add up against the budget, and a
# wait that does not fit is not slept. Without --read the command runs once, so
# a write that may have landed is never repeated. A caller's completeness check
# goes in the command: a 200 that fails it is a failure. Source api-budget.bash
# and rate-stop.bash first.
# shellcheck disable=SC2034 # retry_call_unknown is read by the caller
retry_call() {
  local tries=1 attempt=1 budget err rc stop until wait ceiling
  retry_call_unknown=
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
