# shellcheck shell=bash

[[ -n "${_WIT_GH_COMMON_LOADED:-}" ]] && return 0
readonly _WIT_GH_COMMON_LOADED=1

WIT_GH_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WIT_GH_ADAPTER_DIR

wit_gh_require_seam_lib() {
  [[ -f "$1" ]] && return 0
  printf 'work-item-tracker github adapter: required seam library not found: %s\n' "$1" >&2
  printf '  a shadowed consumer-local adapter must still resolve the bundled seam lib/ directory\n' >&2
  exit 3
}

wit_gh_require_seam_lib "$WIT_GH_ADAPTER_DIR/../../lib/id.sh"
# shellcheck source=../../lib/id.sh
source "$WIT_GH_ADAPTER_DIR/../../lib/id.sh"
wit_gh_require_seam_lib "$WIT_GH_ADAPTER_DIR/../../lib/json.sh"
# shellcheck source=../../lib/json.sh
source "$WIT_GH_ADAPTER_DIR/../../lib/json.sh"
wit_gh_require_seam_lib "$WIT_GH_ADAPTER_DIR/../../lib/verb-cli.sh"
# shellcheck source=../../lib/verb-cli.sh
source "$WIT_GH_ADAPTER_DIR/../../lib/verb-cli.sh"
wit_gh_require_seam_lib "$WIT_GH_ADAPTER_DIR/../../lib/lease.sh"
# shellcheck source=../../lib/lease.sh
source "$WIT_GH_ADAPTER_DIR/../../lib/lease.sh"
wit_gh_require_seam_lib "$WIT_GH_ADAPTER_DIR/../../lib/binding.sh"
# shellcheck source=../../lib/binding.sh
source "$WIT_GH_ADAPTER_DIR/../../lib/binding.sh"
wit_gh_require_seam_lib "$WIT_GH_ADAPTER_DIR/../../lib/gh-version.sh"
# shellcheck source=../../lib/gh-version.sh
source "$WIT_GH_ADAPTER_DIR/../../lib/gh-version.sh"
# shellcheck source=/dev/null
[[ -z "${RUNNER_TEMP:-}" ]] || ! . "${BASH_SOURCE[0]%/*}/../../../../../../.github/actions/log-api-budget/api-budget.bash" 2>/dev/null || api_budget_wrap_gh github-token

wit_gh_resolve_bot_wrapper() {
  local root
  if root="$(wit_project_root)" && [[ -n "$root" ]]; then
    local consumer_wrapper="$root/tools/github-auth/gh-bot.sh"
    if [[ -f "$consumer_wrapper" ]]; then
      printf '%s\n' "$consumer_wrapper"
      return 0
    fi
  fi
  printf '%s\n' "$WIT_GH_ADAPTER_DIR/../../../github-auth/gh-bot.sh"
}

WIT_GH_BOT="$(wit_gh_resolve_bot_wrapper)"
readonly WIT_GH_BOT

readonly EX_INTERNAL=1
readonly EX_USAGE=2
readonly EX_CONFIG=3
readonly EX_AUTH=4
readonly EX_NOT_FOUND=5
readonly EX_CAPABILITY=6
readonly EX_CONFLICT=7
readonly EX_UNAVAILABLE=8

WIT_GH_OUT=""
WIT_GH_ERR=""
WIT_GH_NATIVE_STATUS_WRITTEN=""

wit_usage_error() {
  printf '%s: %s\n' "$(basename "${BASH_SOURCE[${#BASH_SOURCE[@]} - 1]}")" "$1" >&2
  exit "$EX_USAGE"
}

wit_require_github_id() {
  wit_parse_id "$1" || return 1
  [[ "$WIT_ID_PROVIDER" == "github" ]] || return 1
}

wit_write_pause() {
  sleep "${WIT_WRITE_SPACING_S:-1}"
}

gh_write() {
  wit_write_pause
  if [[ -f "$WIT_GH_BOT" ]]; then
    bash "$WIT_GH_BOT" "$@"
  else
    gh "$@"
  fi
}

wit_map_gh_error() {
  local err="$1"
  case "$err" in
  *"Could not resolve"* | *"Not Found"* | *"HTTP 404"*) echo "$EX_NOT_FOUND" ;;
  *"HTTP 401"* | *"HTTP 403"* | *"not logged in"* | *authentication*) echo "$EX_AUTH" ;;
  *"rate limit"* | *"no such host"* | *"connection refused"* | *timeout* | *"network"*) echo "$EX_UNAVAILABLE" ;;
  *maximum* | *"limit of"*) echo "$EX_CONFLICT" ;;
  *) echo "$EX_INTERNAL" ;;
  esac
}

wit_require_graphql_session() {
  if wit_gh_session_refuses_graphql; then
    printf '%s: %s is unavailable in this Claude Code cloud session: its GitHub proxy refuses GraphQL and this has no REST form\n' \
      "$(basename "${BASH_SOURCE[${#BASH_SOURCE[@]} - 1]}")" "$1" >&2
    exit "$EX_CONFIG"
  fi
}

wit_run_gh() {
  local writer="$1" err rc errfile
  shift
  errfile="$(mktemp)"
  if [[ "$writer" == "write" ]]; then
    WIT_GH_OUT="$(gh_write "$@" 2>"$errfile")"
  else
    WIT_GH_OUT="$(gh "$@" 2>"$errfile")"
  fi
  rc=$?
  err="$(<"$errfile")"
  rm -f "$errfile"
  if ((rc != 0)); then
    if [[ -n "${WIT_GH_NATIVE_TRY:-}" && "$err" == *"$WIT_GH_GRAPHQL_REFUSAL_PREFIX"* ]]; then
      return 10
    fi
    printf '%s\n' "$err" >&2
    exit "$(wit_map_gh_error "$err")"
  fi
  WIT_GH_OUT="$(printf '%s' "$WIT_GH_OUT" | wit_strip_cr)"
}

wit_run_gh_native() {
  WIT_GH_NATIVE_TRY=1 wit_run_gh "$@"
}

wit_gh_capture() {
  local writer="$1" rc errfile
  shift
  errfile="$(mktemp)"
  if [[ "$writer" == "write" ]]; then
    WIT_GH_OUT="$(gh_write "$@" 2>"$errfile")"
  else
    WIT_GH_OUT="$(gh "$@" 2>"$errfile")"
  fi
  rc=$?
  WIT_GH_ERR="$(<"$errfile")"
  rm -f "$errfile"
  WIT_GH_OUT="$(printf '%s' "$WIT_GH_OUT" | wit_strip_cr)"
  return "$rc"
}

wit_gh_issue_exists() {
  local out
  out="$(gh api "repos/$1/$2/issues/$3" --jq '.number' 2>/dev/null)" || return 1
  [[ "$(wit_strip_cr <<<"$out")" =~ ^[0-9]+$ ]]
}

wit_gh_is_feature_unavailable() {
  local err="$1" owner="$2" repo="$3" number="$4" check_404="${5:-1}"
  [[ "$err" == *"rate limit"* ]] && return 1
  case "$err" in
  *"HTTP 403"* | *"403 Forbidden"* | *"unknown command"* | *"unknown flag"* | *"doesn't exist on type"* | *"Cannot query field"*)
    return 0
    ;;
  *"HTTP 404"* | *"Not Found"*)
    [[ "$check_404" == "1" ]] && wit_gh_issue_exists "$owner" "$repo" "$number" && return 0
    return 1
    ;;
  *)
    return 1
    ;;
  esac
}

wit_gh_emit_unavailable() {
  local verb="$1" id="$2" fallback="$3" reason="$4" extra_json="${5:-}"
  [[ -n "$extra_json" ]] || extra_json='{}'
  printf '%s: %s; fallback: %s\n' "$verb" "$reason" "$fallback" >&2
  jq -cn --arg sv "$WIT_SCHEMA_VERSION" --arg id "$id" --arg reason "$reason" \
    --arg fallback "$fallback" --argjson extra "$extra_json" \
    '({schema_version: $sv, id: $id, available: false, reason: $reason, fallback: $fallback} + $extra)'
  exit "$EX_CAPABILITY"
}

wit_gh_is_native_status_unavailable() {
  local err="$1" owner="$2" repo="$3" number="$4"
  [[ "$err" == *"rate limit"* ]] && return 1
  case "$err" in
  *"HTTP 422"* | *"Unprocessable Entity"* | *"is not a valid status"* | *"unknown field"*)
    return 0
    ;;
  esac
  wit_gh_is_feature_unavailable "$err" "$owner" "$repo" "$number" 1
}

wit_gh_try_set_native_status() {
  local owner="$1" repo="$2" number="$3" status_name="$4" applied=""
  # shellcheck disable=SC2034  # read by sourcing verb scripts (claim.sh)
  WIT_GH_NATIVE_STATUS_WRITTEN=""
  [[ -n "$status_name" ]] || return 1
  if wit_gh_capture write api -X PATCH "repos/$owner/$repo/issues/$number" -f "status=$status_name"; then
    applied="$(jq -r 'if type == "object" and (.status | type) == "object" and (.status.name | type) == "string" and (.status.name | length) > 0 then .status.name else empty end' <<<"$WIT_GH_OUT" 2>/dev/null)" || applied=""
    if [[ -n "$applied" ]]; then
      # shellcheck disable=SC2034  # read by sourcing verb scripts (claim.sh)
      WIT_GH_NATIVE_STATUS_WRITTEN="$applied"
      return 0
    fi
    return 1
  fi
  if wit_gh_is_native_status_unavailable "$WIT_GH_ERR" "$owner" "$repo" "$number"; then
    return 1
  fi
  printf 'native status dual-write skipped for %s/%s#%s (%s): %s\n' \
    "$owner" "$repo" "$number" "$status_name" "${WIT_GH_ERR%%$'\n'*}" >&2
  return 1
}

wit_gh_annotate_native_status() {
  local owner="$1" repo="$2" number="$3" json ns="" out
  json="$(cat)"
  if jq -e '(.status | type) == "object" and (.status.name | type) == "string" and (.status.name | length) > 0' <<<"$json" >/dev/null 2>&1; then
    printf '%s' "$json"
    return 0
  fi
  if out="$(gh api "repos/$owner/$repo/issues/$number" 2>/dev/null)"; then
    ns="$(printf '%s' "$out" | wit_strip_cr | jq -r 'if type == "object" and (.status | type) == "object" and (.status.name | type) == "string" and (.status.name | length) > 0 then .status.name else empty end' 2>/dev/null)" || ns=""
  fi
  if [[ -n "$ns" ]]; then
    printf '%s' "$json" | jq -c --arg ns "$ns" '. + {nativeStatus: $ns}'
  else
    printf '%s' "$json"
  fi
}

wit_gh_annotate_list_native_statuses() {
  local target_repo="$1" state="$2" limit="$3" label="${4:-}" json rest_label=() page=1 map='{}' seen='{}' wanted='{}'
  local out meta page_len=0 issue_count=0 has_status=0 status_checked=0 fetched_issues=0 remaining=0
  json="$(cat)"
  if ! jq -e 'type == "array" and length > 0' <<<"$json" >/dev/null 2>&1 ||
    jq -e 'any(.[]; (.status | type) == "object")' <<<"$json" >/dev/null 2>&1; then
    printf '%s' "$json"
    return 0
  fi
  wanted="$(jq -c --argjson limit "$limit" 'reduce (.[:$limit][] | .number | tostring) as $n ({}; .[$n] = true)' <<<"$json" 2>/dev/null)" || {
    printf '%s' "$json"
    return 0
  }
  [[ "$wanted" != "{}" ]] || {
    printf '%s' "$json"
    return 0
  }
  [[ -n "$label" && "$label" != *,* ]] && rest_label=(-f "labels=$label")
  while :; do
    out="$(gh api -X GET "repos/$target_repo/issues" -f state="$state" -f per_page=100 \
      -f page="$page" "${rest_label[@]+"${rest_label[@]}"}" 2>/dev/null)" || break
    out="$(printf '%s' "$out" | wit_strip_cr)"
    meta="$(jq -r 'if type != "array" then error end
      | [length, ([.[] | select(has("pull_request") | not)] | length),
         (if any(.[]; select(has("pull_request") | not) | has("status")) then 1 else 0 end)]
      | @tsv' <<<"$out" 2>/dev/null)" || break
    IFS=$'\t' read -r page_len issue_count has_status <<<"$meta"
    if ((issue_count > 0)); then
      if ((status_checked == 0)); then
        status_checked=1
        ((has_status)) || break
      fi
      map="$(printf '%s\n%s' "$map" "$out" | jq -cs '.[0] + (reduce (.[1][] | select(has("pull_request") | not)
        | select((.status | type) == "object" and (.status.name | type) == "string" and (.status.name | length) > 0))
        as $i ({}; .[($i.number | tostring)] = $i.status.name))' 2>/dev/null)" || break
      seen="$(printf '%s\n%s' "$seen" "$out" | jq -cs '.[0] + (reduce (.[1][] | select(has("pull_request") | not))
        as $i ({}; .[($i.number | tostring)] = true))' 2>/dev/null)" || break
      fetched_issues=$((fetched_issues + issue_count))
      remaining="$(printf '%s\n%s' "$wanted" "$seen" | jq -cs '.[0] as $w | .[1] as $s | [($w | keys_unsorted)[] | select($s[.] | not)] | length' 2>/dev/null)" || break
      ((remaining == 0)) && break
    fi
    ((page_len == 100 && fetched_issues <= limit)) || break
    page=$((page + 1))
  done
  if [[ "$map" == "{}" ]]; then
    printf '%s' "$json"
  else
    printf '%s' "$json" | jq -c --argjson m "$map" 'map((.number | tostring) as $n | if ($m | has($n)) then . + {nativeStatus: $m[$n]} else . end)'
  fi
}

wit_gh_mutate_relates() {
  local verb="$1" mutation="$2" id="$3" o1="$4" r1="$5" n1="$6" other="$7" o2="$8" r2="$9" n2="${10}"
  local extra_unavail id_a id_b gql_err mutation_query
  extra_unavail="$(jq -cn --arg other "$other" '{related_to: $other, linked: false}')"
  if [[ "$id" == "$other" ]]; then
    wit_usage_error "cannot relate an item to itself: $id"
  fi
  if wit_gh_session_refuses_graphql; then
    wit_gh_emit_unavailable "$verb" "$id" "refs-comment" \
      "${mutation} requires GraphQL, unavailable in this Claude Code cloud session" "$extra_unavail"
  fi
  # shellcheck disable=SC2016  # GraphQL variables, not bash expansions
  if ! wit_gh_capture read api graphql \
    -f query='query($o1:String!,$r1:String!,$n1:Int!,$o2:String!,$r2:String!,$n2:Int!){a:repository(owner:$o1,name:$r1){issue(number:$n1){id}} b:repository(owner:$o2,name:$r2){issue(number:$n2){id}}}' \
    -f o1="$o1" -f r1="$r1" -F n1="$n1" -f o2="$o2" -f r2="$r2" -F n2="$n2"; then
    if wit_gh_is_feature_unavailable "$WIT_GH_ERR" "$o1" "$r1" "$n1" 0; then
      wit_gh_emit_unavailable "$verb" "$id" "refs-comment" "$WIT_GH_ERR" "$extra_unavail"
    fi
    printf '%s\n' "$WIT_GH_ERR" >&2
    exit "$(wit_map_gh_error "$WIT_GH_ERR")"
  fi
  id_a="$(jq -r '.data.a.issue.id // empty' <<<"$WIT_GH_OUT" 2>/dev/null)"
  id_b="$(jq -r '.data.b.issue.id // empty' <<<"$WIT_GH_OUT" 2>/dev/null)"
  if [[ -z "$id_a" ]]; then
    printf '%s: issue not found: %s\n' "$verb" "$id" >&2
    exit "$EX_NOT_FOUND"
  fi
  if [[ -z "$id_b" ]]; then
    printf '%s: related issue not found: %s\n' "$verb" "$other" >&2
    exit "$EX_NOT_FOUND"
  fi
  # shellcheck disable=SC2016  # GraphQL variables, not bash expansions
  case "$mutation" in
  addRelatesTo)
    mutation_query='mutation($issueId:ID!,$relatedIssueId:ID!){addRelatesTo(input:{issueId:$issueId,relatedIssueId:$relatedIssueId}){issue{number} relatedIssue{number}}}'
    ;;
  removeRelatesTo)
    mutation_query='mutation($issueId:ID!,$relatedIssueId:ID!){removeRelatesTo(input:{issueId:$issueId,relatedIssueId:$relatedIssueId}){issue{number} relatedIssue{number}}}'
    ;;
  *)
    printf '%s: unsupported relates mutation: %s\n' "$verb" "$mutation" >&2
    exit "$EX_INTERNAL"
    ;;
  esac
  if ! wit_gh_capture write api graphql \
    -f query="$mutation_query" \
    -f issueId="$id_a" -f relatedIssueId="$id_b"; then
    if wit_gh_is_feature_unavailable "$WIT_GH_ERR" "$o1" "$r1" "$n1" 1; then
      wit_gh_emit_unavailable "$verb" "$id" "refs-comment" "$WIT_GH_ERR" "$extra_unavail"
    fi
    printf '%s\n' "$WIT_GH_ERR" >&2
    exit "$(wit_map_gh_error "$WIT_GH_ERR")"
  fi
  gql_err="$(jq -r '[(.errors // [])[] | .message // empty] | join("; ")' <<<"$WIT_GH_OUT" 2>/dev/null)"
  if [[ -n "$gql_err" ]]; then
    if wit_gh_is_feature_unavailable "$gql_err" "$o1" "$r1" "$n1" 1; then
      wit_gh_emit_unavailable "$verb" "$id" "refs-comment" "$gql_err" "$extra_unavail"
    fi
    printf '%s: %s\n' "$verb" "$gql_err" >&2
    exit "$(wit_map_gh_error "$gql_err")"
  fi
  if [[ "$mutation" == "addRelatesTo" ]]; then
    jq -cn --arg sv "$WIT_SCHEMA_VERSION" --arg id "$id" --arg other "$other" \
      '{schema_version: $sv, id: $id, related_to: $other, available: true, linked: true, symmetric: true}'
  else
    jq -cn --arg sv "$WIT_SCHEMA_VERSION" --arg id "$id" --arg other "$other" \
      '{schema_version: $sv, id: $id, related_to: $other, available: true, linked: false, unlinked: true, symmetric: true}'
  fi
}

wit_resolve_repo() {
  local explicit="${1:-}" mode="${2:-}" out err rc errfile
  if [[ -n "$explicit" && "$mode" != write ]]; then
    printf '%s\n' "$explicit"
    return 0
  fi
  errfile="$(mktemp)"
  # shellcheck source=target-repo.sh
  out="$(
    [[ -n "$explicit" ]] && export GH_REPO="$explicit"
    if [[ "$mode" == write ]]; then set -- --write; else set --; fi
    . "$WIT_GH_ADAPTER_DIR/target-repo.sh" 2>"$errfile"
  )"
  rc=$?
  err="$(<"$errfile")"
  rm -f "$errfile"
  [[ -n "$err" ]] && printf '%s\n' "$err" >&2
  if ((rc != 0)); then
    [[ "$err" == *"target-repo: the remotes name"* || "$err" == *"target-repo: you cannot push to"* ]] && exit 3
    exit "$(wit_map_gh_error "$err")"
  fi
  wit_run_gh read api "repos/$(printf '%s' "$out" | wit_strip_cr)" --jq .full_name
  printf '%s\n' "$WIT_GH_OUT"
}

wit_read_assignees() {
  wit_run_gh read api "repos/$1/$2/issues/$3" --jq '[.assignees[].login]'
}

_wit_edit_assignee() {
  local method="$1" writer="$2"
  [[ "$writer" == "write" ]] || wit_write_pause
  wit_run_gh "$writer" api --method "$method" "repos/$3/$4/issues/$5/assignees" \
    -f "assignees[]=$6" --jq '[.assignees[].login]'
}

wit_add_assignee() { _wit_edit_assignee POST "$@"; }

wit_remove_assignee() { _wit_edit_assignee DELETE "$@"; }

wit_try_remove_assignee() {
  wit_write_pause
  gh api --method DELETE "repos/$1/$2/issues/$3/assignees" \
    -f "assignees[]=$4" >/dev/null 2>&1 || true
}

wit_try_add_assignee() {
  wit_write_pause
  gh api --method POST "repos/$1/$2/issues/$3/assignees" \
    -f "assignees[]=$4" >/dev/null 2>&1 || true
}

wit_try_read_assignees() {
  WIT_GH_OUT="$(gh api "repos/$1/$2/issues/$3" --jq '[.assignees[].login]' 2>/dev/null)"
}

wit_issue_url() {
  printf 'https://github.com/%s/%s/issues/%s\n' "$1" "$2" "$3"
}

# shellcheck disable=SC2034  # the WIT_EDGE_* globals are read by the sourcing verb scripts, not within this lib
wit_parse_edge_args() {
  local usage="$1" option="$2"
  shift 2
  local id="${1:-}"
  [[ -n "$id" ]] || wit_usage_error "$usage"
  shift
  local other=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    "--$option")
      [[ $# -ge 2 ]] || wit_usage_error "--$option needs a value"
      other="$2"
      shift 2
      ;;
    *) wit_usage_error "unknown argument: $1" ;;
    esac
  done
  [[ -n "$other" ]] || wit_usage_error "--$option is required"
  wit_require_github_id "$id" || wit_usage_error "malformed or non-github id: $id"
  WIT_EDGE_ID="$id"
  WIT_EDGE_OWNER="$WIT_ID_OWNER"
  WIT_EDGE_REPO="$WIT_ID_REPO"
  WIT_EDGE_NUMBER="$WIT_ID_NUMBER"
  wit_require_github_id "$other" || wit_usage_error "malformed or non-github --$option id: $other"
  WIT_EDGE_OTHER="$other"
  WIT_EDGE_OTHER_OWNER="$WIT_ID_OWNER"
  WIT_EDGE_OTHER_REPO="$WIT_ID_REPO"
  WIT_EDGE_OTHER_NUMBER="$WIT_ID_NUMBER"
  WIT_EDGE_OTHER_URL="$(wit_issue_url "$WIT_ID_OWNER" "$WIT_ID_REPO" "$WIT_ID_NUMBER")"
}

# shellcheck disable=SC2016  # jq program — $sv/$or are jq variables, not bash expansions
readonly WIT_ITEM_JQ="$WIT_JQ_DEF_UTC_TS"'{
  schema_version: $sv,
  id: ("github:" + $or + "#" + (.number | tostring)),
  title: .title,
  state: (.state | ascii_downcase),
  assignees: [(.assignees // [])[] | .login],
  labels: [(.labels // [])[] | .name],
  type: (.issueType.name // null),
  blocked_by_count: ([(.blockedBy.nodes // [])[] | select(.state != "CLOSED" or .reasonRead == false
    or .stateReason == "NOT_PLANNED" or .stateReason == "DUPLICATE" or .wontDoLabel == true)] | length),
  blocked_by_wont_do_count: ([(.blockedBy.nodes // [])[] | select(.state == "CLOSED"
    and (.stateReason == "NOT_PLANNED" or .stateReason == "DUPLICATE" or .wontDoLabel == true))] | length),
  parent_id: (
    if (.parent // null) != null and (.parent.url // null) != null
    then (.parent.url
          | capture("github.com/(?<o>[^/]+)/(?<r>[^/]+)/issues/(?<n>[0-9]+)")
          | "github:" + .o + "/" + .r + "#" + .n)
    else null
    end),
  url: .url,
  created_at: (.createdAt | wit_utc_ts),
  milestone: (.milestone.title // null),
  native_status: (if (.nativeStatus // null) != null then .nativeStatus
                  elif (.status | type) == "object" then (.status.name // null)
                  elif (.status | type) == "string" and (.status | length) > 0 then .status
                  else null end)
}'

_wit_gh_read_binding() {
  local binding
  binding="$(wit_find_binding)" || return 1
  _WIT_GH_BINDING_JSON="$(wit_effective_binding_json "$binding")" || {
    echo "github: invalid binding at $binding; run /work-items:setup check" >&2
    exit "$EX_CONFIG"
  }
}

wit_gh_load_wont_do_labels() {
  WIT_GH_WONT_DO_LABELS='[]'
  _wit_gh_read_binding || return 0
  WIT_GH_WONT_DO_LABELS="$(jq -c '(.config.github // {}) as $g
    | if ($g | type) != "object" or ($g | has("wont_do_labels") | not) then []
      elif ($g.wont_do_labels | type) == "array" and all($g.wont_do_labels[]; type == "string" and length > 0)
      then $g.wont_do_labels | map(ascii_downcase)
      else "bad" end' <<<"$_WIT_GH_BINDING_JSON")"
  if [[ "$WIT_GH_WONT_DO_LABELS" == '"bad"' ]]; then
    echo "github: config.github.wont_do_labels must be an array of non-empty label names" >&2
    exit "$EX_CONFIG"
  fi
}

wit_gh_load_status_trust() {
  WIT_GH_STATUS_TRUST=""
  _wit_gh_read_binding || return 0
  WIT_GH_STATUS_TRUST="$(jq -c '(.config.github // {}) as $g
    | def text: type == "string" and length > 0;
    def relative: text and (startswith("/") | not) and (split("/") | index("..") | not);
    def standards: ltrimstr("standards:") | index(":") as $i
      | $i != null and (.[:$i] | test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")) and (.[$i + 1:] | relative);
    if ($g | type) != "object" or ($g | has("status_trust") | not) then null
    elif ($g.status_trust | type) == "object" and ($g.status_trust.trusted_actors | text and (if startswith("standards:") then standards else relative end))
      and ($g.status_trust.model | relative) and ($g.status_trust.lanes_app | text)
    then $g.status_trust | {trusted_actors, model, lanes_app}
    else "bad" end' <<<"$_WIT_GH_BINDING_JSON")"
  case "$WIT_GH_STATUS_TRUST" in
  null) WIT_GH_STATUS_TRUST="" ;;
  '"bad"')
    echo "github: config.github.status_trust must set trusted_actors (a repo-relative path or standards:<owner>/<repo>:<path>), model (a repo-relative path) and lanes_app (a login)" >&2
    exit "$EX_CONFIG"
    ;;
  *) ;;
  esac
}

wit_gh_annotate_blocker_reasons() {
  local json ids n i reasons='[]' out page args id
  json="$(cat)"
  ids="$(printf '%s' "$json" | jq -c '[(if type == "array" then .[] else . end)
    | (.blockedBy.nodes // [])[] | select(.state == "CLOSED") | .id] | unique')"
  n="$(jq 'length' <<<"$ids")"
  for ((i = 0; i < n; i += 100)); do
    args=()
    while IFS= read -r id; do
      args+=(-f "ids[]=$id")
    done <<<"$(jq -r --argjson i "$i" '.[$i:$i + 100][]' <<<"$ids")"
    # shellcheck disable=SC2016  # GraphQL query — $ids is a GraphQL variable, not a bash expansion
    if out="$(gh api graphql -f query='query($ids:[ID!]!){nodes(ids:$ids){... on Issue{id stateReason labels(first:100){nodes{name}}}}}' \
      "${args[@]}" 2>/dev/null)" &&
      page="$(jq -ce '[(.data.nodes // [])[] | select(. != null)]' <<<"$out" 2>/dev/null)"; then
      reasons="$(jq -cn --argjson acc "$reasons" --argjson page "$page" '$acc + $page')"
    else
      echo "wit_gh_annotate_blocker_reasons: close-reason query failed; closed blockers keep blocking" >&2
    fi
  done
  printf '%s' "$json" | jq -c --argjson r "$reasons" --argjson wl "${WIT_GH_WONT_DO_LABELS:-[]}" '
    (reduce $r[] as $x ({}; .[$x.id] = $x)) as $by_id
    | def ann: if (.blockedBy.nodes // null) == null then .
        else .blockedBy.nodes |= map(if .state == "CLOSED"
          then .id as $i | .stateReason = $by_id[$i].stateReason | .reasonRead = ($by_id | has($i))
            | .wontDoLabel = any(($by_id[$i].labels.nodes // [])[]; (.name | ascii_downcase) as $n | any($wl[]; . == $n))
          else . end) end;
    if type == "array" then map(ann) else ann end'
}

wit_emit_item() {
  local owner="$1" repo="$2" number="$3" native=0
  local rest_to_view='{number, title, state, assignees, labels, issueType: .type, url: .html_url, createdAt: .created_at, milestone, status}'
  if wit_gh_has_native_surface; then
    wit_run_gh_native read issue view "$number" -R "$owner/$repo" \
      --json number,title,state,assignees,labels,issueType,blockedBy,parent,url,createdAt,milestone &&
      native=1
  fi
  if ((native)); then
    wit_gh_load_wont_do_labels
    printf '%s' "$WIT_GH_OUT" | wit_gh_annotate_blocker_reasons |
      wit_gh_annotate_native_status "$owner" "$repo" "$number" |
      jq -c --arg sv "$WIT_SCHEMA_VERSION" --arg or "$owner/$repo" "$WIT_ITEM_JQ"
  else
    wit_run_gh read api "repos/$owner/$repo/issues/$number"
    if jq -e 'has("pull_request")' <<<"$WIT_GH_OUT" >/dev/null; then
      echo "wit_emit_item: $owner/$repo#$number is a pull request, not an issue" >&2
      exit "$EX_NOT_FOUND"
    fi
    jq -c --arg sv "$WIT_SCHEMA_VERSION" --arg or "$owner/$repo" "$rest_to_view | $WIT_ITEM_JQ" <<<"$WIT_GH_OUT"
  fi
}

wit_patch_lease_comment() {
  wit_run_gh write api --method PATCH "repos/$1/$2/issues/comments/$3" \
    -f body="${WIT_LEASE_MARKER}$4 -->" --jq '.id'
}

wit_list_lease_comments() {
  local owner="$1" repo="$2" number="$3"
  wit_run_gh read api --paginate "repos/$owner/$repo/issues/$number/comments?per_page=100" \
    --jq '[.[] | select(.body | startswith("<!-- work-item-lease v1")) | {id, node_id, body, created_at, author_association, user: {login: .user.login, type: .user.type}}]'
  jq -cs 'add // [] | map(select(.author_association == "OWNER" or .author_association == "MEMBER"
    or .author_association == "COLLABORATOR" or .user.type == "Bot"))' <<<"$WIT_GH_OUT"
}

wit_try_supersede_lease_comment() {
  local superseded
  superseded="$(jq -c --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '. + {superseded_at: $ts}' <<<"$4")"
  gh_write api --method PATCH "repos/$1/$2/issues/comments/$3" \
    -f body="${WIT_LEASE_MARKER}${superseded} -->" >/dev/null 2>&1
}

wit_lease_released_by_run() {
  local sid run_id status verb
  sid="$(jq -r '.session_id // empty' <<<"$2")"
  [[ "$sid" =~ ^run-([1-9][0-9]{0,19})$ ]] || return 1
  run_id="${BASH_REMATCH[1]}"
  verb="$(basename "$0" .sh)"
  status="$(gh api "repos/$WIT_ID_OWNER/$WIT_ID_REPO/actions/runs/$run_id" --jq '.status' 2>/dev/null)" || {
    printf '%s: could not read run %s status; lease kept\n' "$verb" "$run_id" >&2
    return 1
  }
  [[ "$(wit_strip_cr <<<"$status")" == completed ]] || return 1
  wit_try_supersede_lease_comment "$WIT_ID_OWNER" "$WIT_ID_REPO" "$1" "$2"
  printf '%s: lease comment %s was held by run %s, which has completed; treated as released\n' \
    "$verb" "$1" "$run_id" >&2
}

wit_hand_back_assignee() {
  local owner="$1" repo="$2" number="$3" login="$4" own="$5" leases now
  _wit_list_at_clock "$owner" "$repo" "$number" || _wit_list_at_clock "$owner" "$repo" "$number" || leases='[]'
  _wit_login_holds_other "$leases" "$login" "$own" "$now" && return 0
  if wit_try_read_assignees "$owner" "$repo" "$number"; then
    jq -e --arg l "$login" 'any(.[]; . == $l)' <<<"$WIT_GH_OUT" >/dev/null || return 0
  fi
  wit_try_remove_assignee "$owner" "$repo" "$number" "$login"
  _wit_list_at_clock "$owner" "$repo" "$number" || _wit_list_at_clock "$owner" "$repo" "$number" || return 0
  _wit_login_holds_other "$leases" "$login" "$own" "$now" || return 0
  wit_try_add_assignee "$owner" "$repo" "$number" "$login"
  _wit_list_at_clock "$owner" "$repo" "$number" || _wit_list_at_clock "$owner" "$repo" "$number" || return 0
  _wit_login_holds_other "$leases" "$login" "$own" "$now" || wit_try_remove_assignee "$owner" "$repo" "$number" "$login"
}

_wit_list_at_clock() {
  now="$(date -u +%s)"
  leases="$(wit_list_lease_comments "$1" "$2" "$3")"
}

_wit_login_holds_other() {
  local row cand now="$4"
  while IFS= read -r row; do
    [[ -n "$row" && "$(jq -r '.id' <<<"$row")" != "$3" ]] || continue
    cand="$(wit_lease_json "$(jq -r '.body' <<<"$row")")"
    [[ -n "$cand" && "$(jq -r '.holder // empty' <<<"$cand")" == "$2" ]] || continue
    { wit_lease_is_live "$cand" "$now" || wit_lease_is_live "$cand" "$(date -u +%s)"; } && return 0
  done < <(jq -c '.[]' <<<"$1")
  return 1
}
