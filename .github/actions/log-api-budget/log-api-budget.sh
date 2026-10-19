#!/usr/bin/env bash
# Logs each named token's REST budget in pr-merge's rate-line shape:
#   <phase> <name> core remaining=R used=U limit=L reset=<ISO> graphql remaining=G
# read from the x-ratelimit-* headers of GET /rate_limit, which does not count
# against the primary limit
# (https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api).
# A `start` reading is kept in STATE_DIR; any later phase adds
# used-since-start=N (or window-rolled when the reset moved) and writes one
# step-summary line `<name>-cost=N ...` for all tokens. Never fails.
#
# Env: PHASE (start, end, ...), TOKENS (one "name token" pair per line),
# STATE_DIR, GITHUB_STEP_SUMMARY.
set -uo pipefail

summary=${GITHUB_STEP_SUMMARY:-/dev/null}
PHASE=${PHASE:?}
STATE_DIR=${STATE_DIR:?}
mkdir -p "$STATE_DIR" || exit 0
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
  header() { sed -nE "s/^x-ratelimit-$1:[[:blank:]]*([0-9]+)$/\1/Ip" <<<"$response" | head -n1; }
  limit=$(header limit)
  remaining=$(header remaining)
  used=$(header used)
  reset=$(header reset)
  graphql=$(sed '1,/^$/d' <<<"$response" | jq -r '.resources.graphql.remaining // empty' 2>/dev/null)
  at=$(jq -rn --arg r "$reset" '$r | tonumber | todate' 2>/dev/null || echo unknown)
  line="$PHASE $name core remaining=${remaining:-unknown} used=${used:-unknown} limit=${limit:-unknown} reset=$at"
  [[ -z $graphql ]] || line+=" graphql remaining=$graphql"
  if [[ $PHASE == start ]]; then
    printf '%s %s\n' "$used" "$reset" >"$STATE_DIR/$name"
  elif read -r start_used start_reset 2>/dev/null <"$STATE_DIR/$name"; then
    if [[ -n $used && $start_used =~ ^[0-9]+$ && $start_reset == "$reset" ]]; then
      cost=$((used - start_used))
      line+=" used-since-start=$cost"
    else
      cost=unknown
      line+=" used-since-start=window-rolled"
    fi
    costs+=("$name-cost=$cost")
  fi
  echo "::notice title=api-budget::$line"
  echo "api-budget: $line" >>"$summary"
done <<<"${TOKENS:-}"
if ((${#costs[@]} > 0)); then
  echo "${costs[*]}" >>"$summary"
fi
exit 0
