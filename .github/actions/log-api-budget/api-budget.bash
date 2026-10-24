# shellcheck shell=bash
# Rate-limit readings from a job's own API responses. GET /rate_limit reports
# a different bucket from the one a job's calls spend, so each reading comes
# from the x-ratelimit-* headers of a response the job already got. A reading
# is one line in $RUNNER_TEMP/api-budget/<token>:
#   <status> <limit> <remaining> <used> <reset epoch> <resource>
# (`na` for a missing value). api-budget.mjs and babysit_gh.py append the same
# lines. Never fails the caller.
#
#   api_budget_read <token> <file>
#                               gh api -i output: the header block at the start
#                               becomes a reading, the body goes to stdout byte
#                               for byte
#   api_budget_wrap_gh <token>  defines gh() so `gh api` runs with -i through
#                               api_budget_read, keeping stdout, stderr and the
#                               exit status as they were (not --paginate, whose
#                               per-page header blocks are left out), behind
#                               the rate guard below
#
# The rate guard, rate-guard.mjs's shell port: once a response shows a pool
# exhausted, no gh call goes to that pool before its reset for the rest of the
# job; each refusal returns 1 with an error naming the reset. Its stops are
# lines `<pool> <reset epoch>` in $RUNNER_TEMP/api-budget/stop.
#   api_budget_classify         jq filter: rate-guard.mjs's classify over
#                               {status, headers, body, now (ms), pool, floor}
#   api_budget_pool <gh args>   the pool a gh call spends: graphql, search,
#                               code_search or core, `any` for a non-api call
#   api_budget_stop_until <pool>
#                               the epoch second <pool> is stopped until, if
#                               it is
#   api_budget_observe <file> <pool> <what>
#                               reads gh api -i output and stops its pool when
#                               it is exhausted; under API_BUDGET_READ_FLOOR of
#                               the limit left, warns once
#   api_budget_emit <token>...  the hub collector's notice for each refused
#                               (403/429) reading and for the last reading of
#                               each resource, core last; cost is
#                               the rise in used since the first earlier reading
#                               with the same reset and resource, else na
#
# pr-require-checks.yml's ci-status job carries this file verbatim in its
# API_BUDGET_SH env (it has no checkout of this directory);
# log-api-budget.test.mjs keeps the two the same.

api_budget_read() {
  local state=${RUNNER_TEMP:-}/api-budget/${1:-} lines
  if [[ -z ${RUNNER_TEMP:-} || ! ${1:-} =~ ^[a-z][a-z0-9-]{0,39}$ ]] || ! mkdir -p "${state%/*}" 2>/dev/null; then
    state=/dev/null
  fi
  # Only the block at the very start is headers, so a body line shaped like a
  # status line stays body. awk reads the block and prints its line count;
  # tail then writes the body byte for byte.
  lines=$(awk -v state="$state" '
    function val(k, re) { return (k in h && h[k] ~ re) ? h[k] : "na" }
    function flush() {
      printf "%s %s %s %s %s %s\n", status, val("limit", "^[0-9]+$"), val("remaining", "^[0-9]+$"),
        val("used", "^[0-9]+$"), val("reset", "^[0-9]+$"), val("resource", "^[a-z_]+$") >>state
      close(state)
      print NR
      done = 1
      exit
    }
    NR == 1 && !/^HTTP\/[0-9.]+ [0-9][0-9][0-9]/ { print 0; done = 1; exit }
    NR == 1 { status = $2; next }
    {
      line = $0
      sub(/\r$/, "", line)
      if (line == "") flush()
      if (tolower(line) ~ /^x-ratelimit-(limit|remaining|used|reset|resource):/) {
        k = tolower(line); sub(/^x-ratelimit-/, "", k); sub(/:.*/, "", k)
        v = line; sub(/^[^:]*:[ \t]*/, "", v)
        h[k] = v
      }
    }
    END { if (!done && NR) flush(); if (!done) print 0 }
  ' "$2") || lines=0
  tail -n +"$((${lines:-0} + 1))" "$2"
}

api_budget_wrap_gh() {
  API_BUDGET_GH_TOKEN=$1
  # shellcheck disable=SC2329 # called by the script that sources this file
  gh() {
    local arg out pool rc=0
    pool=$(api_budget_pool "$@")
    api_budget_refuse "$pool" "gh $*" || return 1
    if [[ ${1:-} != api ]]; then
      api_budget_pass "$@"
      return
    fi
    for arg; do
      case $arg in
        # --paginate prints a header block per page, which could not be told
        # from body text that looks like one: left as it is.
        --silent | --slurp | --paginate) api_budget_pass "$@"; return ;;
        # The caller reads the headers itself: the guard reads them too, and
        # the output goes on unchanged.
        -i | --include)
          out=$(mktemp 2>/dev/null) || { api_budget_pass "$@"; return; }
          command gh "$@" >"$out" || rc=$?
          api_budget_observe "$out" "$pool" "gh $*"
          cat "$out"
          rm -f "$out"
          return "$rc"
          ;;
        *) ;;
      esac
    done
    out=$(mktemp 2>/dev/null) || { api_budget_pass "$@"; return; }
    # gh-read-exempt: the wrapper under every call, gh_read included: the same call with -i.
    command gh api -i "${@:2}" >"$out" || rc=$?
    api_budget_observe "$out" "$pool" "gh $*"
    api_budget_read "$API_BUDGET_GH_TOKEN" "$out"
    rm -f "$out"
    return "$rc"
  }
}

# A call whose headers the wrapper cannot read: a failure whose text names a
# rate limit stops every pool for the documented minute.
api_budget_pass() {
  local err rc=0
  err=$(mktemp 2>/dev/null) || { command gh "$@"; return; }
  command gh "$@" 2>"$err" || rc=$?
  cat "$err" >&2
  if ((rc != 0)) && grep -qiE 'rate limit|RATE_LIMITED' "$err"; then
    api_budget_stop '*' $(($(date +%s) + 60)) fallback "gh $*"
  fi
  rm -f "$err"
  return "$rc"
}

api_budget_pool() {
  local arg
  [[ ${1:-} == api ]] || { echo any; return; }
  for arg in "${@:2}"; do
    case $arg in
      graphql) echo graphql; return ;;
      search/code* | /search/code*) echo code_search; return ;;
      search/* | /search/*) echo search; return ;;
      *) ;;
    esac
  done
  echo core
}

api_budget_stop_until() {
  local file=${RUNNER_TEMP:-/tmp}/api-budget/stop
  [[ -s $file ]] || return 0
  awk -v pool="$1" -v now="$(date +%s)" '($1 == pool || $1 == "*" || pool == "any") && $2 > now && $2 > max { max = $2 }
    END { if (max) print max }' "$file"
}

api_budget_label() { [[ $1 == '*' || $1 == any ]] && echo API || echo "$1 API"; }
api_budget_when() { jq -rn --argjson t "$1" '$t | todate'; }

api_budget_refuse() {
  local until
  until=$(api_budget_stop_until "$1")
  [[ -z $until ]] && return 0
  echo "::error::'$2' was not sent: GitHub's $(api_budget_label "$1") rate limit holds until $(api_budget_when "$until")" >&2
  return 1
}

api_budget_stop() {
  local dir=${RUNNER_TEMP:-/tmp}/api-budget
  mkdir -p "$dir" 2>/dev/null && echo "$1 $2" >>"$dir/stop"
  echo "::error::'$4' hit GitHub's $(api_budget_label "$1") rate limit: no call to it before $(api_budget_when "$2") ($3); this step fails" >&2
}

# shellcheck disable=SC2016 # a jq program
API_BUDGET_CLASSIFY='def num: if type == "string" and test("^[0-9]{1,12}$") then tonumber else null end;
  . as $in | ($in.headers // {}) as $h
  | ($h["x-ratelimit-remaining"] | num) as $rem | ($h["x-ratelimit-limit"] | num) as $lim
  | ($h["x-ratelimit-reset"] | num) as $reset | ($h["retry-after"] | num) as $ra
  | (if ($in.body | type) == "string" then ($in.body | try fromjson catch null) else $in.body end) as $b
  | ($in.pool == "graphql") as $gq
  | ((if ($b | type) == "object" then [$b.message] + (if $gq and (($b.errors // null) | type) == "array" then [$b.errors[] | if type == "object" then .message else null end] else [] end) else [] end)
      | map(. // "" | tostring)) as $texts
  | (($in.status == 403 or $in.status == 429 or $gq) and any($texts[]; test("rate limit"; "i"))) as $msg
  | ((if ($b | type) == "object" then ($b.errors // []) else [] end)
      | if type == "array" then any(.[]; type == "object" and .type == "RATE_LIMITED") else false end) as $gql
  | ($rem == 0 or $ra != null or $msg or $gql) as $latched
  | ($in.floor != null and $lim != null and $lim > 0 and $rem != null and $rem < $in.floor * $lim) as $low
  | if ($latched | not) then {latched: false, low: $low, reset_source: null, reset: null, pool: null}
    else (($in.now / 1000) | floor) as $n
    | [(if $ra != null then [$n + $ra, "retry-after"] else empty end),
       (if $rem == 0 and $reset != null then [$reset, "x-ratelimit-reset"] else empty end)] as $c
    | (if ($c | length) > 0 then ($c | reduce .[1:][] as $x (.[0]; if $x[0] > .[0] then $x else . end))
       else [$n + 60, "fallback"] end) as $at
    | (($h["x-ratelimit-resource"] // "") | tostring) as $res
    | {latched: true, low: $low, reset_source: $at[1], reset: $at[0],
       pool: (if $ra != null or ($msg and $rem != 0) then "*" elif ($res | test("^[a-z_]+$")) then $res else $in.pool end)}
    end'

api_budget_observe() {
  local file=$1 pool=$2 what=$3 start verdict latched low source reset stop dir=${RUNNER_TEMP:-/tmp}/api-budget
  start=$(awk 'NR == 1 && !/^HTTP\/[0-9.]+ [0-9][0-9][0-9]/ { exit } { sub(/\r$/, "") } NR > 1 && $0 == "" { print NR; exit }' "$file")
  [[ -n $start ]] || return 0
  verdict=$(jq -rn --rawfile raw "$file" --argjson start "$start" --arg pool "$pool" --argjson now "$(($(date +%s) * 1000))" \
    --arg floor "${API_BUDGET_READ_FLOOR:-}" '($raw | split("\n")) as $l
    | ($l[0] | split(" ")[1] | tonumber) as $status
    | ([$l[1:$start - 1][] | sub("\r$"; "") | capture("^(?<k>[^:]+):[ \t]*(?<v>.*)$") | {(.k | ascii_downcase): .v}] | add // {}) as $headers
    | {status: $status, headers: $headers, body: ($l[$start:] | join("\n")), now: $now, pool: $pool,
       floor: ($floor | tonumber? // null)}
    | '"$API_BUDGET_CLASSIFY"' | "\(.latched) \(.low) \(.reset_source) \(.reset) \(.pool)"' 2>/dev/null) || return 0
  read -r latched low source reset stop <<<"$verdict"
  if [[ $latched == true ]]; then
    api_budget_stop "$stop" "$reset" "$source" "$what"
  elif [[ $low == true ]] && mkdir -p "$dir" 2>/dev/null && [[ ! -e $dir/low-$pool ]]; then
    : >"$dir/low-$pool"
    echo "::warning::GitHub's $pool API has under its read floor left; non-essential reads stop" >&2
  fi
}

api_budget_emit() {
  local token file where workflow=${GITHUB_WORKFLOW_REF:-}
  workflow=${workflow%%@*}
  workflow=${workflow#*/*/}
  where="workflow=${workflow:-na} job=${GITHUB_JOB:-na} run=${GITHUB_RUN_ID:-na} attempt=${GITHUB_RUN_ATTEMPT:-na}"
  for token; do
    file=${RUNNER_TEMP:-}/api-budget/$token
    [[ -n ${RUNNER_TEMP:-} && -s $file ]] || continue
    awk -v token="$token" -v where="$where" '
      NF == 6 { n++; s[n] = $1; l[n] = $2; r[n] = $3; u[n] = $4; t[n] = $5; res[n] = $6 }
      function line(i,   j, cost) {
        cost = "na"
        if (u[i] != "na" && t[i] != "na") {
          for (j = 1; j < i; j++) if (t[j] == t[i] && res[j] == res[i] && u[j] != "na") break
          if (j < i && u[i] + 0 >= u[j] + 0) cost = u[i] - u[j]
        }
        printf "::notice title=api-budget::token=%s %s limit=%s remaining=%s used=%s reset=%s resource=%s cost=%s\n",
          token, where, l[i], r[i], u[i], t[i], res[i], cost
      }
      END {
        for (i = 1; i <= n; i++) last[res[i]] = i
        for (i = 1; i <= n; i++) if ((s[i] == 403 || s[i] == 429) && last[res[i]] != i) line(i)
        for (i = 1; i <= n; i++) if (last[res[i]] == i && res[i] != "core") line(i)
        if ("core" in last) line(last["core"])
      }' "$file"
  done
  return 0
}
