#!/usr/bin/env bash
# Logs each named token's REST budget in pr-merge's rate-line shape:
#   <phase> <name> core remaining=R used=U limit=L reset=<ISO> graphql remaining=G
# read from the x-ratelimit-* headers of GET /rate_limit, which does not count
# against the primary limit
# (https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api).
# A `start` reading is kept in STATE_DIR; any later phase adds
# used-since-start=N (or window-rolled when used fell or the reset moved more
# than RESET_DRIFT later) and writes one
# step-summary line `<name>-cost=N ...` for all tokens (N is unknown with no
# start reading), also the `costs` output. At that later phase each token's
# notice is the hub collector's line instead of the rate line:
#   token=<name> workflow=<path> job=<id> run=<id> attempt=<n> limit=L
#   remaining=R used=U reset=<epoch> resource=<name> cost=<N, or na>
# Never fails.
#
# Env: PHASE (start, end, ...), TOKENS (one "name token" pair per line),
# STATE_DIR, GITHUB_STEP_SUMMARY, GITHUB_OUTPUT, and the runner's
# GITHUB_WORKFLOW_REF, GITHUB_JOB, GITHUB_RUN_ID, GITHUB_RUN_ATTEMPT.
set -uo pipefail

summary=${GITHUB_STEP_SUMMARY:-/dev/null}
PHASE=${PHASE:?}
STATE_DIR=${STATE_DIR:?}
mkdir -p "$STATE_DIR" || exit 0
RESET_DRIFT=600 # seconds; twice the observed drift, a sixth of a window
workflow=${GITHUB_WORKFLOW_REF:-}
workflow=${workflow%%@*}
workflow=${workflow#*/*/}
where="workflow=${workflow:-na} job=${GITHUB_JOB:-na} run=${GITHUB_RUN_ID:-na} attempt=${GITHUB_RUN_ATTEMPT:-na}"
costs=()
while read -r name token; do
  [[ -n ${name:-} ]] || continue
  if [[ ! $name =~ ^[a-z][a-z0-9-]{0,39}$ || -z ${token:-} ]]; then
    echo "::warning::api-budget: skipped a token entry with no usable name or token"
    continue
  fi
  if ! response=$(GH_TOKEN=$token gh api -i rate_limit 2>/dev/null); then
    echo "::warning::api-budget: could not read the rate limit for $name"
    continue
  fi
  response=${response//$'\r'/}
  header() { sed -nE "s/^x-ratelimit-$1:[[:blank:]]*([0-9a-z_]+)$/\1/Ip" <<<"$response" | head -n1; }
  limit=$(header limit)
  remaining=$(header remaining)
  used=$(header used)
  reset=$(header reset)
  resource=$(header resource)
  graphql=$(sed '1,/^$/d' <<<"$response" | jq -r '.resources.graphql.remaining // empty' 2>/dev/null)
  at=$(jq -rn --arg r "$reset" '$r | tonumber | todate' 2>/dev/null || echo unknown)
  line="$PHASE $name core remaining=${remaining:-unknown} used=${used:-unknown} limit=${limit:-unknown} reset=$at"
  [[ -z $graphql ]] || line+=" graphql remaining=$graphql"
  notice=$line
  if [[ $PHASE == start ]]; then
    printf '%s %s\n' "$used" "$reset" >"$STATE_DIR/$name"
  else
    cost=unknown
    if read -r start_used start_reset 2>/dev/null <"$STATE_DIR/$name"; then
      # One window unless used fell or the reset moved later than drift allows:
      # a new hourly window resets about an hour after the old one, while within
      # one window the reported reset can drift (seen moving 5 minutes earlier).
      if [[ $used =~ ^[0-9]+$ && $reset =~ ^[0-9]+$ && $start_used =~ ^[0-9]+$ && $start_reset =~ ^[0-9]+$ ]] &&
        ((used >= start_used && reset <= start_reset + RESET_DRIFT)); then
        cost=$((used - start_used))
        line+=" used-since-start=$cost"
      else
        line+=" used-since-start=window-rolled"
      fi
    fi
    costs+=("$name-cost=$cost")
    [[ $cost != unknown ]] || cost=na
    notice="token=$name $where limit=${limit:-na} remaining=${remaining:-na} used=${used:-na} reset=${reset:-na} resource=${resource:-na} cost=$cost"
  fi
  echo "::notice title=api-budget::$notice"
  echo "api-budget: $line" >>"$summary"
done <<<"${TOKENS:-}"
if ((${#costs[@]} > 0)); then
  echo "${costs[*]}" >>"$summary"
  echo "costs=${costs[*]}" >>"${GITHUB_OUTPUT:-/dev/null}"
fi
exit 0
