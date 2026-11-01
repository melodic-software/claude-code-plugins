# shellcheck shell=bash
# Rate-limit readings from a job's own API responses. GET /rate_limit reports
# a different bucket from the one a job's calls spend, so each reading comes
# from the x-ratelimit-* headers of a response the job already got. A reading
# is one line in $RUNNER_TEMP/api-budget/<token>:
#   <status> <limit> <remaining> <used> <reset epoch> <resource> <route>
# (`na` for a missing value). api-budget.mjs appends the same lines;
# babysit_gh.py appends them without the route. A request the gh wrapper
# counts with no header block to read (each page of --paginate, a call that is
# not `gh api`) is a line `request <route>`, `request graphql` for a GraphQL
# request. The route is the request's path templated by API_BUDGET_ROUTE
# below, so it never holds a query, a name or a token. Never
# fails the caller, except that a stop the rate guard below cannot record ends
# the step.
#
#   api_budget_read <token> <file> [route]
#                               gh api -i output: the header block at the start
#                               becomes a reading under route (`other` when
#                               unset), the body goes to stdout byte for byte
#   api_budget_route <gh args>  the templated route of a gh api call's path
#   api_budget_wrap_gh <token>  defines gh() so `gh api` runs with -i through
#                               api_budget_read, keeping stdout, stderr and the
#                               exit status as they were (not --paginate, whose
#                               per-page header blocks are left out), behind
#                               the rate guard below; every gh call also counts
#                               each request it sends (api_budget_traced)
#
# The rate guard, rate-guard.mjs's shell port: once a response shows a pool
# exhausted, no gh call goes to that pool before its reset for the rest of the
# job; each refusal returns 1 with an error naming the reset, and so does a
# call GitHub refused. A call GitHub answered with a 2xx keeps its answer and
# gh's status, so no caller resends a write GitHub accepted, unless its stop
# cannot be recorded, which ends the step first (below). Its stops are
# lines `<pool> <reset epoch>` in $RUNNER_TEMP/api-budget/stop; a stop whose time is a guess (no header gave
# it) goes in $RUNNER_TEMP/api-budget/guessed too. Readers take only lines
# shaped `^([a-z_]+|\*) [0-9]{1,12}$` and ended by a newline, as
# rate-guard.mjs does, so a fragment a short write left spoils only the line
# it runs into. A missing stop file holds no stop; one that exists but cannot
# be read holds every pool until 999999999999, with an error naming it.
#
# Most calls run in $(...) subshells, whose variables never reach the shell
# that started them, so the file is what carries a stop from one call to the
# next. A stop the file cannot take (no space, no permission) would leave
# every later call free to reach the exhausted pool. So the step ends there:
# the error names the pool, API_BUDGET_UNRECORDED refuses every later call in
# this shell, and from a subshell every shell from its parent up to the
# step's shell ($$) is sent TERM, so no caller's retry loop in a capture
# around it sends again. A caller may hold a subshell's stderr in a file it
# reads only after the call, so both error lines go to a copy of the stderr
# the step had when api_budget_wrap_gh ran. Callers must not trap TERM or run
# the wrapper under a nested bash -c, whose $$ is the inner shell: either
# leaves the step running.
#
#   api_budget_classify         jq filter: rate-guard.mjs's classify over
#                               {status, headers, body, now (ms), pool, floor,
#                               cap}
#   api_budget_pool <gh args>   the pool a gh call spends: graphql, search,
#                               code_search or core, `any` for a non-api call
#   api_budget_stop_until <pool>
#                               the epoch second <pool> is stopped until, if
#                               it is
#   api_budget_guessed <epoch>  whether a stop until <epoch> is a guess
#   api_budget_observe <file> <pool> <what>
#                               reads gh api -i output and stops its pool when
#                               it is exhausted, returning 1 unless the
#                               answer is a 2xx; under
#                               API_BUDGET_READ_FLOOR of the planned budget
#                               left, warns once (unset: no floor; ci-status
#                               sets it to the read-floor default);
#                               the plan is the header's limit, at most
#                               API_BUDGET_LIMIT_CAP (unset: no cap; ci-status
#                               sets github-token's limit-cap default)
#   api_budget_emit <token>...  the hub collector's notice for each refused
#                               (403/429) reading and for the last reading of
#                               each resource and reset, as one token reads
#                               several core counters, each with its own
#                               reset; core comes last, ending on the job's
#                               latest core reading; cost is the rise in used
#                               since the first earlier reading with the same
#                               reset and resource, else na
#   api_budget_emit_content     the notice for the job's content-creating
#                               writes: count and most in any 60 s
#   api_budget_emit_calls <token>...
#                               the hub's api-calls notice for each token,
#                               `<token>=N not-modified=M graphql=K`: N is the
#                               job's own requests, M its 304 answers, which
#                               GitHub does not count, and K the GraphQL ones
#                               among N, which spend their own pool; 0 for a
#                               token with no reading
#   api_budget_emit_routes <token>...
#                               the api-routes notice for each token,
#                               `<token> <route>=<count> ... rest=<count>`:
#                               the N above by route, most first (ties by
#                               route), at most 15 routes and 1000 bytes, the
#                               rest summed; `other` for a line with no route
#
# pr-require-checks.yml's ci-status job and mark-lanes step carry this file
# verbatim in their API_BUDGET_SH env (neither has a checkout of this
# directory); log-api-budget.test.mjs keeps the three the same.

api_budget_read() {
  local state=${RUNNER_TEMP:-}/api-budget/${1:-} lines
  if [[ -z ${RUNNER_TEMP:-} || ! ${1:-} =~ ^[a-z][a-z0-9-]{0,39}$ ]] || ! mkdir -p "${state%/*}" 2>/dev/null; then
    state=/dev/null
  fi
  # Only the block at the very start is headers, so a body line shaped like a
  # status line stays body. awk reads the block and prints its line count;
  # tail then writes the body byte for byte.
  lines=$(awk -v state="$state" -v route="${3:-other}" "$API_BUDGET_ROUTE"'
    function val(k, re) { return (k in h && h[k] ~ re) ? h[k] : "na" }
    function flush() {
      if (!api_route_ok(route)) route = "other"
      printf "%s %s %s %s %s %s %s\n", status, val("limit", "^[0-9]+$"), val("remaining", "^[0-9]+$"),
        val("used", "^[0-9]+$"), val("reset", "^[0-9]+$"), val("resource", "^[a-z_]+$"), route >>state
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
  [[ -n ${API_BUDGET_ERR_FD:-} ]] || exec {API_BUDGET_ERR_FD}>&2
  # shellcheck disable=SC2329 # called by the script that sources this file
  gh() {
    local arg out pool route rc=0
    pool=$(api_budget_pool "$@")
    api_budget_refuse "$pool" "gh $*" || return 1
    ! api_budget_is_content "$@" || api_budget_count_content
    if [[ ${1:-} != api ]]; then
      api_budget_pass "$@"
      return
    fi
    route=$(api_budget_route "$@")
    for arg; do
      case $arg in
        # --paginate prints a header block per page, which could not be told
        # from body text that looks like one: no reading, only its requests.
        --silent | --slurp | --paginate) api_budget_pass "$@"; return ;;
        # The caller reads the headers itself: the guard reads them too, and
        # the output goes on unchanged.
        -i | --include)
          out=$(mktemp 2>/dev/null) || { api_budget_pass "$@"; return; }
          api_budget_traced "$out" "$@" || rc=$?
          api_budget_observe "$out" "$pool" "gh $*" || rc=1
          api_budget_read "$API_BUDGET_GH_TOKEN" "$out" "$route" >/dev/null
          cat "$out"
          rm -f "$out"
          return "$rc"
          ;;
        *) ;;
      esac
    done
    out=$(mktemp 2>/dev/null) || { api_budget_pass "$@"; return; }
    # The wrapper under every call, gh_read included: the same call with -i.
    api_budget_traced "$out" api -i "${@:2}" || rc=$?
    api_budget_observe "$out" "$pool" "gh $*" || rc=1
    api_budget_read "$API_BUDGET_GH_TOKEN" "$out" "$route"
    rm -f "$out"
    return "$rc"
  }
}

# A call whose headers the wrapper cannot read: a failure whose text names a
# rate limit, or a 429, stops every pool, for the documented minute on a
# secondary limit and otherwise for an hour, past any primary reset
# (rate-guard.mjs's SIGNALS).
api_budget_pass() {
  local err rc=0 seconds=3600
  err=$(mktemp 2>/dev/null) || { command gh "$@"; return; }
  api_budget_traced - "$@" 2>"$err" || rc=$?
  cat "$err" >&2
  if ((rc != 0)) && grep -qiE 'rate limit|RATE_LIMITED|abuse detection|\(HTTP 429\)' "$err"; then
    ! grep -qiE 'secondary rate limit|abuse detection' "$err" || seconds=60
    api_budget_stop '*' $(($(date +%s) + seconds)) fallback "gh $*" || :
  fi
  rm -f "$err"
  return "$rc"
}

# api_budget_traced <out|-> <gh args>: gh with GH_DEBUG=1, stdout to <out>
# (`-`: left as it is). That level logs only head lines per request (`* Request
# at`, `* Request to <url>`, `* Request took`), never headers or bodies, which
# GH_DEBUG=api adds and which no filter could tell from gh's own text. Each
# request to a GitHub API URL (a redirect to a download host is not one) is a
# `request` line in the token's file, less the one an <out> header block
# already gives a reading. Once gh exits, its stderr goes on without what the
# debug level adds: those lines, a `* <error>` line while a request is open,
# `[git ...]` command lines, and the `lookup ...` line under `error connecting
# to`. Returns gh's status.
api_budget_traced() {
  local out=$1 log rc=0 skip=0 nl=0 first state=${RUNNER_TEMP:-}/api-budget/${API_BUDGET_GH_TOKEN:-}
  shift
  log=$(mktemp 2>/dev/null) || {
    if [[ $out == - ]]; then command gh "$@"; else command gh "$@" >"$out"; fi
    return
  }
  if [[ $out == - ]]; then
    GH_DEBUG=1 command gh "$@" 2>"$log" || rc=$?
  else
    GH_DEBUG=1 command gh "$@" >"$out" 2>"$log" || rc=$?
    read -r first <"$out" 2>/dev/null
    [[ ! ${first:-} =~ ^HTTP/[0-9.]+\ [0-9]{3} ]] || skip=1
  fi
  if [[ -z ${RUNNER_TEMP:-} || ! ${API_BUDGET_GH_TOKEN:-} =~ ^[a-z][a-z0-9-]{0,39}$ ]] || ! mkdir -p "${state%/*}" 2>/dev/null; then
    state=/dev/null
  fi
  [[ $(tail -c 1 "$log" | od -An -c) != *'\n'* ]] || nl=1
  awk -v state="$state" -v skip="$skip" -v nl="$nl" "$API_BUDGET_ROUTE"'
    /^\* Request at / { open++; next }
    /^\* Request took / { if (open) open--; next }
    /^\* Request to / {
      if ($4 ~ /^https:\/\/((api|uploads)\.github\.com|[^\/]+\/api)\// && ++n > skip) print "request " api_route($4) >>state
      next
    }
    /^\* (Using proxy|Skipping TLS verification): / || (open && /^\* /) || /^\[git[] ]/ { next }
    /^lookup / && kept ~ /^error connecting to / { kept = ""; next }
    { printf "%s%s", sep, $0; sep = "\n"; kept = $0; last = NR }
    END { close(state); if (sep != "" && (nl || last != NR)) printf "\n" }
  ' "$log" >&2
  rm -f "$log"
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

# Awk functions, rate-guard.mjs's routeOf and routeOk: api_route gives a
# request's URL or gh api path as a route that holds no query, name or token,
# by routeOf's rules (a URL on a host other than api.github.com and
# uploads.github.com is other, unless its path starts with /api/, as on
# GHES); api_route_ok says whether a route has only REST path words
# (rate-guard.mjs's REST_PATH_WORDS, the same list: log-api-budget.test.mjs
# checks) and placeholders.
# shellcheck disable=SC2016 # an awk program
API_BUDGET_ROUTE='function api_words(   w, i, n) {
    if (api_words_read) return
    n = split("api v3 repos orgs users user installation app graphql pulls issues comments reviews requested_reviewers git refs ref heads tags trees blobs commits compare merges merge check-runs check-suites statuses status labels assignees milestones events timeline actions runs jobs attempts artifacts logs rerun rerun-failed-jobs workflows dispatches variables secrets contents branches protection rules rulesets collaborators permission teams members hooks deployments environments releases search code reactions files rate_limit annotations repositories installations access_tokens pending_deployments cancel update-branch dismissals readme matching-refs languages notifications", w, " ")
    for (i = 1; i <= n; i++) API_WORD[w[i]] = 1
    API_WORD["{n}"] = API_WORD["{sha}"] = API_WORD["{repo}"] = API_WORD["{x}"] = 1
    api_words_read = 1
  }
  function api_hex(seg) { return length(seg) >= 7 && seg ~ /^[0-9A-Fa-f]+$/ }
  function api_route_ok(r,   n, s, i) {
    if (r == "graphql" || r == "other") return 1
    if (r == "" || length(r) > 80) return 0
    api_words()
    n = split(r, s, "/")
    for (i = 1; i <= n; i++) if (!(s[i] in API_WORD)) return 0
    return 1
  }
  function api_route(u,   n, s, i, seg, out, tail, name, host, rest) {
    api_words()
    sub(/[?#].*$/, "", u)
    if (u ~ /^[A-Za-z][A-Za-z0-9+.-]*:\/\//) {
      rest = u
      sub(/^[A-Za-z][A-Za-z0-9+.-]*:\/\//, "", rest)
      host = rest
      sub(/\/.*$/, "", host)
      sub(/^[^\/]*/, "", rest)
      if (tolower(host) != "api.github.com" && tolower(host) != "uploads.github.com" && rest !~ /^\/api\//) return "other"
      u = rest
    }
    sub(/^\/+/, "", u)
    sub(/^api\/(v3\/)?/, "", u)
    sub(/\/+$/, "", u)
    if (u == "graphql") return "graphql"
    if (u == "") return "other"
    n = split(u, s, "/")
    out = ""
    tail = name = 0
    for (i = 1; i <= n; i++) {
      seg = s[i]
      if (tail || name) { seg = (seg ~ /^[0-9]+$/) ? "{n}" : api_hex(seg) ? "{sha}" : "{x}"; name = 0 }
      else if (i == 2 && s[1] == "repos" && n >= 3) { seg = "{repo}"; i++ }
      else if (seg ~ /^[0-9]+$/) seg = "{n}"
      else if (api_hex(seg)) seg = "{sha}"
      else if (!(seg in API_WORD) || seg ~ /^(api|v3|graphql|[{].*)$/) seg = "{x}"
      else if (seg ~ /^(contents|ref|refs|matching-refs|readme|compare|trees)$/) tail = 1
      else if (seg ~ /^(labels|branches|tags|users|orgs|teams|members|collaborators|assignees|environments|secrets|variables|workflows|commits|blobs|statuses|releases)$/) name = 1
      out = out (out == "" ? "" : "/") seg
    }
    return length(out) > 80 ? "other" : out
  }'

api_budget_route() {
  local method='' fields='' mutation='' path=''
  [[ ${1:-} == api ]] && api_budget_scan "${@:2}"
  printf '%s\n' "${path//$'\n'/ }" | awk "$API_BUDGET_ROUTE"' NR == 1 { print api_route($0) }'
}

# api_budget_scan <gh api args>: sets the caller's method, fields, mutation and
# path locals from a gh api call's flags and its first bare argument. A value
# joined to its flag (--method=POST, -XPOST, -fquery=...) is read as the
# separated form.
api_budget_scan() {
  local arg prev=''
  for arg; do
    if [[ -z $prev ]]; then
      case $arg in
        --method=* | --field=* | --raw-field=* | --input=*) prev=${arg%%=*} arg=${arg#*=} ;;
        -X?* | -f?* | -F?*) prev=${arg:0:2} arg=${arg:2} arg=${arg#=} ;;
        *) ;;
      esac
    fi
    case $prev in
      -X | --method) method=${arg^^} ;;
      -f | -F | --field | --raw-field) fields=1; [[ ! $arg =~ ^query=[[:space:]]*mutation ]] || mutation=1 ;;
      --input) fields=1 ;;
      -H | --header | --jq | -q | -t | --template | --hostname | --cache | -p | --preview) ;;
      *) [[ $arg == -* || -n $path ]] || path=$arg ;;
    esac
    case $arg in -X | --method | -f | -F | --field | --raw-field | --input | -H | --header | --jq | -q | -t | --template | --hostname | --cache | -p | --preview) prev=$arg ;; *) prev= ;; esac
  done
}

api_budget_stop_until() {
  local file=${RUNNER_TEMP:-/tmp}/api-budget/stop up
  if [[ ! -e $file ]]; then
    # Missing (ENOENT) only when the nearest path part above it that exists
    # is a directory it can search; else ENOTDIR or EACCES.
    up=$file
    while [[ $up == */* ]]; do
      up=${up%/*}
      [[ -e ${up:-/} ]] && break
    done
    [[ -d ${up:-/} && -x ${up:-/} ]] && return 0
  fi
  if [[ -d $file ]] || ! { : <"$file"; } 2>/dev/null; then
    echo "::error::the rate guard's stop file $file cannot be read, so every GitHub API pool counts as stopped" >&2
    echo 999999999999
    return 0
  fi
  # The x ends an unterminated last line in a non-digit, so it never matches.
  { cat -- "$file"; printf x; } | awk -v pool="$1" -v now="$(date +%s)" '/^([a-z_]+|\*) [0-9]+$/ && length($2) <= 12 && ($1 == pool || $1 == "*" || pool == "any") && $2 + 0 > now + 0 && $2 + 0 > max { max = $2 + 0 }
    END { if (max) print max }'
}

api_budget_guessed() {
  local file=${RUNNER_TEMP:-/tmp}/api-budget/guessed
  [[ -s $file ]] && awk -v t="$1" '/^([a-z_]+|\*) [0-9]+$/ && length($2) <= 12 && $2 == t { found = 1 } END { exit !found }' "$file"
}

api_budget_label() { [[ $1 == '*' || $1 == any ]] && echo API || echo "$1 API"; }
api_budget_when() { jq -rn --argjson t "$1" '$t | todate'; }

api_budget_refuse() {
  local until
  if [[ -n ${API_BUDGET_UNRECORDED:-} ]]; then
    echo "::error::'$2' was not sent: GitHub's $(api_budget_label "$API_BUDGET_UNRECORDED") stop could not be recorded, so this step sends no further call" >&2
    return 1
  fi
  until=$(api_budget_stop_until "$1")
  [[ -z $until ]] && return 0
  echo "::error::'$2' was not sent: GitHub's $(api_budget_label "$1") rate limit holds until $(api_budget_when "$until")" >&2
  return 1
}

api_budget_stop() {
  local dir=${RUNNER_TEMP:-/tmp}/api-budget lines
  lines=("::error::'$4' hit GitHub's $(api_budget_label "$1") rate limit: no call to it before $(api_budget_when "$2") ($3); ${5:-the call returns 1}")
  # One printf per line: the line and its newline go in one write.
  if mkdir -p "$dir" 2>/dev/null && { printf '%s %s\n' "$1" "$2" >>"$dir/stop"; } 2>/dev/null &&
    { [[ $3 != fallback ]] || { printf '%s %s\n' "$1" "$2" >>"$dir/guessed"; } 2>/dev/null; }; then
    printf '%s\n' "${lines[@]}" >&2
    return 1
  fi
  API_BUDGET_UNRECORDED=$1
  lines+=("::error::GitHub's $(api_budget_label "$1") stop could not be recorded in $dir; later calls would reach the exhausted pool, so this step ends")
  { printf '%s\n' "${lines[@]}" >&"${API_BUDGET_ERR_FD:-2}"; } 2>/dev/null || printf '%s\n' "${lines[@]}" >&2
  if ((BASH_SUBSHELL > 0)); then
    # Each parent up to $$, from /proc/<pid>/stat's ppid; only $$ when the
    # walk cannot reach it.
    local pid=$BASHPID stat up=()
    while ((pid != $$)) && read -r stat 2>/dev/null <"/proc/$pid/stat"; do
      read -r _ pid _ <<<"${stat##*) }"
      up+=("$pid")
    done
    ((pid == $$)) || up=("$$")
    kill -s TERM "${up[@]}" 2>/dev/null
  fi
  exit 1
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
  | ($in.status == 403 or $in.status == 429 or $gq) as $flagged
  | ($flagged and any($texts[]; test("rate limit|abuse detection"; "i"))) as $msg
  | ($flagged and any($texts[]; test("secondary rate limit|abuse detection"; "i"))) as $secondary
  | ($in.status == 429) as $many
  | ((if ($b | type) == "object" then ($b.errors // []) else [] end)
      | if type == "array" then any(.[]; type == "object" and .type == "RATE_LIMITED") else false end) as $gql
  | ($rem == 0 or $ra != null or $msg or $gql or $many) as $latched
  | (if $in.cap != null and $lim != null then ([$lim, $in.cap] | min) else $lim end) as $planned
  | ($in.floor != null and $lim != null and $lim > 0 and $rem != null and $planned - ($lim - $rem) < $in.floor * $planned) as $low
  | if ($latched | not) then {latched: false, low: $low, reset_source: null, reset: null, pool: null}
    else (($in.now / 1000) | floor) as $n
    | [(if $ra != null then [$n + $ra, "retry-after"] else empty end),
       (if $rem == 0 and $reset != null then [$reset, "x-ratelimit-reset"] else empty end)] as $c
    | (if ($c | length) > 0 then ($c | reduce .[1:][] as $x (.[0]; if $x[0] > .[0] then $x else . end)) else null end) as $best
    | (if $best != null and $best[0] > $n then $best
       else [$n + (if $best != null or $secondary then 60 else 3600 end), "fallback"] end
       | .[0] |= ([., 999999999999] | min)) as $at
    | (($h["x-ratelimit-resource"] // "") | tostring) as $res
    | {latched: true, low: $low, reset_source: $at[1], reset: $at[0],
       pool: (if $ra != null or $secondary or (($msg or $many) and $rem != 0) then "*" elif ($res | test("^[a-z_]+$")) then $res else $in.pool end)}
    end'

api_budget_observe() {
  local file=$1 pool=$2 what=$3 start verdict latched low source reset stop status dir=${RUNNER_TEMP:-/tmp}/api-budget
  start=$(awk 'NR == 1 && !/^HTTP\/[0-9.]+ [0-9][0-9][0-9]/ { exit } { sub(/\r$/, "") } NR > 1 && $0 == "" { print NR; exit }' "$file")
  [[ -n $start ]] || return 0
  verdict=$(jq -rn --rawfile raw "$file" --argjson start "$start" --arg pool "$pool" --argjson now "$(($(date +%s) * 1000))" \
    --arg floor "${API_BUDGET_READ_FLOOR:-}" --arg cap "${API_BUDGET_LIMIT_CAP:-}" '($raw | split("\n")) as $l
    | ($l[0] | split(" ")[1] | tonumber) as $status
    | ([$l[1:$start - 1][] | sub("\r$"; "") | capture("^(?<k>[^:]+):[ \t]*(?<v>.*)$") | {(.k | ascii_downcase): .v}] | add // {}) as $headers
    | {status: $status, headers: $headers, body: ($l[$start:] | join("\n")), now: $now, pool: $pool,
       floor: ($floor | tonumber? // null), cap: ($cap | tonumber? // null)}
    | '"$API_BUDGET_CLASSIFY"' | "\(.latched) \(.low) \(.reset_source) \(.reset) \(.pool)"' 2>/dev/null) || return 0
  read -r latched low source reset stop <<<"$verdict"
  if [[ $latched == true ]]; then
    read -r _ status _ <"$file"
    if [[ $status == 2[0-9][0-9] ]]; then
      api_budget_stop "$stop" "$reset" "$source" "$what" "its answer stands, and later calls to it are refused" || :
      return 0
    fi
    api_budget_stop "$stop" "$reset" "$source" "$what" || return 1
  elif [[ $low == true ]] && mkdir -p "$dir" 2>/dev/null && [[ ! -e $dir/low-$pool ]]; then
    : >"$dir/low-$pool"
    echo "::warning::GitHub's $pool API has under its read floor left; reads continue" >&2
  fi
}

# A gh call that creates or changes content GitHub's content-creation limit
# counts, as rate-guard.mjs's isContentWrite judges a request: a gh api write
# (-X POST, PATCH or PUT, or a field with no -X, which gh sends as POST) to an
# issue, pull request, comment, review or label path, a graphql mutation, or
# a gh issue or pr command that writes.
api_budget_is_content() {
  local method='' fields='' mutation='' path=''
  case "${1:-} ${2:-}" in
    "issue create" | "issue comment" | "issue edit" | "issue close" | "issue reopen" | \
      "pr create" | "pr comment" | "pr edit" | "pr review" | "pr close" | "pr reopen" | "label create") return 0 ;;
    api\ *) ;;
    *) return 1 ;;
  esac
  api_budget_scan "${@:2}"
  [[ -n $method ]] || { [[ -n $fields ]] && method=POST; } || method=GET
  [[ $method == POST || $method == PATCH || $method == PUT ]] || return 1
  if [[ $path == graphql ]]; then
    [[ -n $mutation ]]
    return
  fi
  [[ /${path#/} =~ ^/repos/[^/]+/[^/]+/(issues|pulls)(/[0-9]+(/(comments|labels|reviews|assignees|requested_reviewers))?|/[0-9]+/comments/[0-9]+/replies|/comments/[0-9]+)?/?(\?|$) ]]
}

api_budget_count_content() {
  local dir=${RUNNER_TEMP:-}/api-budget
  [[ -n ${RUNNER_TEMP:-} ]] && mkdir -p "$dir" 2>/dev/null && date +%s >>"$dir/content-creation"
  return 0
}

# The job's content-creating writes, from the lines rate-guard.mjs and the gh
# wrapper append: the count and the most in any sixty seconds. Nothing without
# a write.
api_budget_emit_content() {
  local file=${RUNNER_TEMP:-}/api-budget/content-creation where workflow=${GITHUB_WORKFLOW_REF:-}
  [[ -n ${RUNNER_TEMP:-} && -s $file ]] || return 0
  workflow=${workflow%%@*}
  workflow=${workflow#*/*/}
  where="workflow=${workflow:-na} job=${GITHUB_JOB:-na} run=${GITHUB_RUN_ID:-na} attempt=${GITHUB_RUN_ATTEMPT:-na}"
  sort -n "$file" | awk -v where="$where" '/^[0-9]+$/ { t[++n] = $1; while (t[n] - t[j + 1] >= 60) j++; if (n - j > max) max = n - j }
    END { if (n) printf "::notice title=api-budget::content-creation %s count=%d max-per-minute=%d\n", where, n, max }'
  return 0
}

api_budget_emit_calls() {
  local token file
  for token; do
    file=${RUNNER_TEMP:-}/api-budget/$token
    [[ -n ${RUNNER_TEMP:-} && $token =~ ^[a-z][a-z0-9-]{0,39}$ ]] || continue
    [[ -s $file ]] || file=/dev/null
    awk '$1 != 304 { n++ } $1 == 304 { m++ } $6 == "graphql" || $2 == "graphql" { g++ } END { printf "::notice title=api-calls::%s=%d not-modified=%d graphql=%d\n", token, n, m, g }' token="$token" "$file"
  done
  return 0
}

api_budget_emit_routes() {
  local token file
  for token; do
    file=${RUNNER_TEMP:-}/api-budget/$token
    [[ -n ${RUNNER_TEMP:-} && $token =~ ^[a-z][a-z0-9-]{0,39}$ ]] || continue
    [[ -s $file ]] || file=/dev/null
    # The route is the last field of a `request` line and the seventh of a
    # reading; a line without one, or with one not in the route's shape, is other.
    awk "$API_BUDGET_ROUTE"' $1 == 304 { next }
      { r = "other" }
      $1 == "request" && NF >= 2 { r = $NF }
      $1 != "request" && NF == 7 { r = $7 }
      { if (!api_route_ok(r)) r = "other"; n[r]++ }
      END { for (r in n) print n[r], r }' "$file" | LC_ALL=C sort -k1,1nr -k2,2 |
      awk -v head="::notice title=api-routes::$token" '
        { add = " " $2 "=" $1 }
        !full && NR <= 15 && length(head line add) + 16 <= 1000 { line = line add; next }
        { full = 1; rest += $1 }
        END { printf "%s%s rest=%d\n", head, line, rest }'
  done
  return 0
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
      NF == 6 || NF == 7 { n++; s[n] = $1; l[n] = $2; r[n] = $3; u[n] = $4; t[n] = $5; res[n] = $6 }
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
        for (i = 1; i <= n; i++) last[res[i], t[i]] = i
        for (i = 1; i <= n; i++) if ((s[i] == 403 || s[i] == 429) && last[res[i], t[i]] != i) line(i)
        for (i = 1; i <= n; i++) if (last[res[i], t[i]] == i && res[i] != "core") line(i)
        for (i = 1; i <= n; i++) if (last[res[i], t[i]] == i && res[i] == "core") line(i)
      }' "$file"
  done
  return 0
}
