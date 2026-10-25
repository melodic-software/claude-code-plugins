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
