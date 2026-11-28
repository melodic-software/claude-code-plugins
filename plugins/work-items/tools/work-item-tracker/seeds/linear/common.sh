# shellcheck shell=bash
# shellcheck disable=SC2016  # every single-quoted `$name` in this file is a GraphQL or jq variable, never a shell one — that is exactly why the documents are single-quoted, so the shell cannot touch them

[[ -n "${_WIT_LINEAR_COMMON_LOADED:-}" ]] && return 0
readonly _WIT_LINEAR_COMMON_LOADED=1

WIT_LINEAR_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WIT_LINEAR_ADAPTER_DIR

WIT_LINEAR_SEAM_LIB="${WIT_SEAM_LIB_DIR:-$WIT_LINEAR_ADAPTER_DIR/../../lib}"
readonly WIT_LINEAR_SEAM_LIB

wit_linear_require_seam_lib() {
  [[ -f "$1" ]] && return 0
  printf 'work-item-tracker linear adapter: required seam library not found: %s\n' "$1" >&2
  printf '  set WIT_SEAM_LIB_DIR to the work-item-tracker lib/ directory, or vendor the seam\n' >&2
  exit 3
}

wit_linear_require_seam_lib "$WIT_LINEAR_SEAM_LIB/id.sh"
# shellcheck source=../../lib/id.sh disable=SC1091
source "$WIT_LINEAR_SEAM_LIB/id.sh"
wit_linear_require_seam_lib "$WIT_LINEAR_SEAM_LIB/json.sh"
# shellcheck source=../../lib/json.sh disable=SC1091
source "$WIT_LINEAR_SEAM_LIB/json.sh"
wit_linear_require_seam_lib "$WIT_LINEAR_SEAM_LIB/verb-cli.sh"
# shellcheck source=../../lib/verb-cli.sh disable=SC1091
source "$WIT_LINEAR_SEAM_LIB/verb-cli.sh"
wit_linear_require_seam_lib "$WIT_LINEAR_SEAM_LIB/binding.sh"
# shellcheck source=../../lib/binding.sh disable=SC1091
source "$WIT_LINEAR_SEAM_LIB/binding.sh"

readonly EX_INTERNAL=1
readonly EX_USAGE=2
readonly EX_CONFIG=3
readonly EX_AUTH=4
readonly EX_NOT_FOUND=5
readonly EX_CONFLICT=7
readonly EX_UNAVAILABLE=8

readonly WIT_LINEAR_CURL_BIN="${WIT_LINEAR_CURL:-curl}"

readonly WIT_LINEAR_HOSTNAME_RE='^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$'
readonly WIT_LINEAR_DEFAULT_HOST_SUFFIX='.linear.app'

wit_linear_host_under_pin() {
  local host="$1" pin="$2"
  [[ "$pin" == .* ]] || pin=".$pin"
  [[ "$host" == *"$pin" || "$host" == "${pin#.}" ]]
}
readonly WIT_LINEAR_ENV_NAME_RE='^[A-Za-z_][A-Za-z0-9_]*$'
readonly WIT_LINEAR_SCOPE_RE='^[a-z0-9][a-z0-9-]*/[A-Z][A-Z0-9]*$'

WIT_LINEAR_DEFAULT_DONE_TYPES="$(jq -cn '["completed","canceled","duplicate"]')"
readonly WIT_LINEAR_DEFAULT_DONE_TYPES

readonly WIT_LINEAR_DEFAULT_PAGE_SIZE=50
WIT_LINEAR_LIST_ITEMS_MAX="$(jq -r '.limits.list_items_max' "$WIT_LINEAR_ADAPTER_DIR/capabilities.json" 2>/dev/null)"
if [[ ! "$WIT_LINEAR_LIST_ITEMS_MAX" =~ ^[1-9][0-9]*$ ]]; then
  printf 'work-item-tracker linear adapter: limits.list_items_max in %s/capabilities.json must be a positive integer, got: %s\n' \
    "$WIT_LINEAR_ADAPTER_DIR" "${WIT_LINEAR_LIST_ITEMS_MAX:-<unreadable>}" >&2
  exit "$EX_CONFIG"
fi
# shellcheck disable=SC2034  # read by list-items.sh, list-sub-items.sh and create-item.sh; this file is sourced-only
readonly WIT_LINEAR_LIST_ITEMS_MAX

readonly WIT_LINEAR_LEASE_PREFIX='<!-- work-item-lease v1 '
readonly WIT_LINEAR_LEASE_SUFFIX=' -->'

WIT_LINEAR_BODY=""
WIT_LINEAR_STATUS=""

wit_linear_unimplemented() {
  printf '%s: linear adapter verb %s is a generated scaffold with no provider mapping yet\n' \
    "$(basename "${BASH_SOURCE[1]}")" "$1" >&2
  printf '  fill in its PROVIDER MAPPING block, or set verbs["%s"]=false in capabilities.json\n' "$1" >&2
  exit "$EX_INTERNAL"
}

wit_linear_nonempty_array() {
  jq -e 'type == "array" and length > 0' <<<"$1" >/dev/null
}

wit_linear_bad_elements() {
  jq -rc --arg re "$1" '[.[] | select((type != "string") or (test($re) | not))]' <<<"$2"
}

# Sets the WIT_ID_* globals.
# shellcheck disable=SC2154  # WIT_ID_PROVIDER is exported by wit_parse_id in the seam's id.sh, sourced above through a runtime-resolved path ShellCheck cannot follow
wit_require_linear_id() {
  wit_parse_id "$1" || return 1
  [[ "$WIT_ID_PROVIDER" == "linear" ]] || return 1
}

wit_need_linear_config() {
  local name binding ejson
  name="$(basename "${BASH_SOURCE[1]}")"
  binding="$(wit_find_binding)" ||
    {
      printf '%s: %s; see CONTRACT.md Setup\n' "$name" "$(wit_no_binding_reason)" >&2
      exit "$EX_CONFIG"
    }
  ejson="$(wit_effective_binding_json "$binding")" ||
    {
      printf '%s: invalid binding at %s — run /work-items:setup check for the itemized breakdown; see CONTRACT.md Setup\n' "$name" "$binding" >&2
      exit "$EX_CONFIG"
    }
  WIT_LINEAR_HOST="$(jq -r '.config.linear.host // empty' <<<"$ejson")"
  WIT_LINEAR_AUTH_ENV="$(jq -r '.config.linear.auth_env // empty' <<<"$ejson")"
  WIT_LINEAR_SCOPES="$(jq -c '.config.linear.scopes // []' <<<"$ejson")"
  if [[ "$(jq -r '.config.linear | has("done_state_types")' <<<"$ejson")" == "true" ]]; then
    WIT_LINEAR_DONE_TYPES="$(jq -c '.config.linear.done_state_types' <<<"$ejson")"
  else
    WIT_LINEAR_DONE_TYPES="$WIT_LINEAR_DEFAULT_DONE_TYPES"
  fi
  if [[ "$(jq -r '.config.linear | has("page_size")' <<<"$ejson")" == "true" ]]; then
    WIT_LINEAR_PAGE_SIZE="$(jq -r '.config.linear.page_size' <<<"$ejson")"
  else
    WIT_LINEAR_PAGE_SIZE="$WIT_LINEAR_DEFAULT_PAGE_SIZE"
  fi
  WIT_LINEAR_LEASE_TTL_HOURS="$(jq -r '.config.lease_ttl_hours // 24' <<<"$ejson")"
  WIT_LINEAR_LEASE_TTL_MINUTES="$(jq -r '.config.lease_ttl_minutes // 0' <<<"$ejson")"

  local allow_custom_domain host_suffix
  allow_custom_domain="$(jq -r '.config.linear.allow_custom_domain // false' <<<"$ejson")"
  host_suffix="$(jq -r --arg d "$WIT_LINEAR_DEFAULT_HOST_SUFFIX" '.config.linear.host_suffix // $d' <<<"$ejson")"

  local missing=""
  [[ -n "$WIT_LINEAR_HOST" ]] || missing+=" config.linear.host"
  [[ -n "$WIT_LINEAR_AUTH_ENV" ]] || missing+=" config.linear.auth_env"

  wit_linear_nonempty_array "$WIT_LINEAR_SCOPES" ||
    missing+=" config.linear.scopes[](non-empty array)"
  if [[ -n "$missing" ]]; then
    printf '%s: linear binding missing/invalid required config:%s — see the adapter README\n' "$name" "$missing" >&2
    exit "$EX_CONFIG"
  fi

  local bad=""
  if ! [[ "$WIT_LINEAR_HOST" =~ $WIT_LINEAR_HOSTNAME_RE ]]; then
    bad+=" host:'$WIT_LINEAR_HOST'(not a bare hostname)"
  elif [[ -n "$host_suffix" && "$allow_custom_domain" != "true" ]] &&
    ! wit_linear_host_under_pin "$WIT_LINEAR_HOST" "$host_suffix"; then
    bad+=" host:'$WIT_LINEAR_HOST'(not under $host_suffix; set config.linear.allow_custom_domain=true to allow)"
  fi
  [[ "$WIT_LINEAR_AUTH_ENV" =~ $WIT_LINEAR_ENV_NAME_RE ]] ||
    bad+=" auth_env:'$WIT_LINEAR_AUTH_ENV'(not a valid env var name)"
  local bad_scopes
  bad_scopes="$(wit_linear_bad_elements "$WIT_LINEAR_SCOPE_RE" "$WIT_LINEAR_SCOPES")"
  [[ "$bad_scopes" == "[]" ]] || bad+=" scopes:$bad_scopes"
  if [[ "$(jq -r '[.[] | split("/")[0]] | unique | length' <<<"$WIT_LINEAR_SCOPES")" != "1" ]]; then
    bad+=" scopes(all entries must share one workspace — an API key reaches exactly one)"
  fi
  wit_linear_nonempty_array "$WIT_LINEAR_DONE_TYPES" ||
    bad+=" done_state_types(must be a non-empty array)"
  if [[ "$WIT_LINEAR_PAGE_SIZE" =~ ^[1-9][0-9]*$ ]]; then
    [[ "$WIT_LINEAR_PAGE_SIZE" -le 250 ]] ||
      bad+=" page_size:'$WIT_LINEAR_PAGE_SIZE'(exceeds linear's cap of 250 for a connection's first)"
  else
    bad+=" page_size:'$WIT_LINEAR_PAGE_SIZE'(must be a positive integer)"
  fi
  [[ "$WIT_LINEAR_LEASE_TTL_HOURS" =~ ^[0-9]+$ ]] ||
    bad+=" lease_ttl_hours:'$WIT_LINEAR_LEASE_TTL_HOURS'(must be a non-negative integer)"
  [[ "$WIT_LINEAR_LEASE_TTL_MINUTES" =~ ^[0-9]+$ ]] ||
    bad+=" lease_ttl_minutes:'$WIT_LINEAR_LEASE_TTL_MINUTES'(must be a non-negative integer)"
  if [[ -n "$bad" ]]; then
    printf '%s: invalid linear config value(s):%s — see the adapter README\n' "$name" "$bad" >&2
    exit "$EX_CONFIG"
  fi

  command -v "$WIT_LINEAR_CURL_BIN" >/dev/null 2>&1 ||
    {
      printf '%s: prerequisite missing: curl (Linear REST over HTTPS) — see CONTRACT.md Prerequisites\n' "$name" >&2
      exit "$EX_CONFIG"
    }
  export WIT_LINEAR_HOST WIT_LINEAR_AUTH_ENV WIT_LINEAR_SCOPES WIT_LINEAR_DONE_TYPES \
    WIT_LINEAR_PAGE_SIZE WIT_LINEAR_LEASE_TTL_HOURS WIT_LINEAR_LEASE_TTL_MINUTES
}

wit_linear_scope_in_scope() {
  jq -e --arg k "$1" 'index($k) != null' <<<"$WIT_LINEAR_SCOPES" >/dev/null
}

wit_linear_token() {
  local token="${!WIT_LINEAR_AUTH_ENV:-}"
  if [[ -z "$token" ]]; then
    printf '%s: linear credential env var %s is unset or empty (config.linear.auth_env)\n' \
      "$(basename "${BASH_SOURCE[1]}")" "$WIT_LINEAR_AUTH_ENV" >&2
    exit "$EX_AUTH"
  fi
  printf '%s' "$token"
}

wit_linear_auth_header() {
  local token
  token="$(wit_linear_token)" || exit "$?"
  printf 'Authorization: %s' "$token"
}

wit_linear_http() {
  local method="$1" path="$2" body="${3:-}"
  local url="https://$WIT_LINEAR_HOST/graphql$path"
  local auth raw rc
  auth="$(wit_linear_auth_header)" || exit "$?"
  local curl_args=(-sS -X "$method" -H "Accept: application/json" --proto '=https' -w $'\n%{http_code}' -K -)
  if [[ -n "$body" ]]; then
    curl_args+=(-H "Content-Type: application/json" --data "$body")
  fi
  raw="$(printf 'header = "%s"\nurl = "%s"\n' "$auth" "$url" |
    "$WIT_LINEAR_CURL_BIN" "${curl_args[@]}" 2>/dev/null)"
  rc=$?
  if ((rc != 0)); then
    printf 'linear: request to %s failed (curl exit %s) — network or endpoint unavailable\n' "$path" "$rc" >&2
    exit "$EX_UNAVAILABLE"
  fi
  WIT_LINEAR_STATUS="${raw##*$'\n'}"
  WIT_LINEAR_BODY="$(printf '%s' "${raw%$'\n'*}" | wit_strip_cr)"
}

wit_linear_require_ok() {
  local ctx="$1" code="$WIT_LINEAR_STATUS"
  case "$code" in
  2*) return 0 ;;
  401 | 403)
    printf 'linear: %s — authentication/authorization failed (HTTP %s)\n' "$ctx" "$code" >&2
    exit "$EX_AUTH"
    ;;
  404)
    printf 'linear: %s — not found (HTTP 404)\n' "$ctx" >&2
    exit "$EX_NOT_FOUND"
    ;;
  409 | 412 | 422)
    printf 'linear: %s — conflict/precondition (HTTP %s)\n' "$ctx" "$code" >&2
    exit "$EX_CONFLICT"
    ;;
  429)
    printf 'linear: %s — rate limited (HTTP 429); retry later\n' "$ctx" >&2
    exit "$EX_UNAVAILABLE"
    ;;
  5*)
    printf 'linear: %s — server error (HTTP %s)\n' "$ctx" "$code" >&2
    exit "$EX_UNAVAILABLE"
    ;;
  *)
    printf 'linear: %s — unexpected response (HTTP %s): %s\n' "$ctx" "$code" "$WIT_LINEAR_BODY" >&2
    exit "$EX_INTERNAL"
    ;;
  esac
}

# shellcheck disable=SC2034  # consumed by the verb scripts; this file is sourced-only
readonly WIT_LINEAR_ISSUE_FIELDS='
  id
  identifier
  number
  title
  url
  createdAt
  state { type name }
  assignee { displayName email }
  labels(first: 50) { nodes { name } }
  parent { identifier team { key } number }
  team { key }
  inverseRelations(first: 100) { nodes { type issue { state { type } } } }
'

# Read by the verb scripts, which is why ShellCheck cannot see it used from inside this sourced lib.
# shellcheck disable=SC2034
WIT_LINEAR_DATA=""

wit_linear_gql() {
  local query="$1" vars="${2:-{\}}" ctx="${3:-graphql request}"
  local payload
  payload="$(jq -cn --arg q "$query" --argjson v "$vars" '{query: $q, variables: $v}')"
  wit_linear_http POST "" "$payload"
  wit_linear_require_ok "$ctx"

  local errors
  errors="$(jq -c '.errors // []' <<<"$WIT_LINEAR_BODY" 2>/dev/null)" || errors='[]'
  if [[ "$errors" != "[]" ]]; then
    local first_msg first_code
    first_msg="$(jq -r '.[0].message // "unknown GraphQL error"' <<<"$errors")"
    first_code="$(jq -r '.[0].extensions.type // .[0].extensions.code // ""' <<<"$errors")"
    printf 'linear: %s — %s\n' "$ctx" "$first_msg" >&2
    case "$(printf '%s' "$first_code" | tr '[:upper:]' '[:lower:]')" in
    *authentication* | *forbidden* | *unauthorized*) exit "$EX_AUTH" ;;
    *notfound* | *not_found*) exit "$EX_NOT_FOUND" ;;
    *ratelimit* | *unavailable*) exit "$EX_UNAVAILABLE" ;;
    *) exit "$EX_INTERNAL" ;;
    esac
  fi

  # shellcheck disable=SC2034  # read by the verb scripts that call this helper
  WIT_LINEAR_DATA="$(jq -c '.data // {}' <<<"$WIT_LINEAR_BODY" 2>/dev/null)" || {
    printf 'linear: %s — response carried no JSON data object\n' "$ctx" >&2
    exit "$EX_INTERNAL"
  }
}

# shellcheck disable=SC2016,SC2034  # jq program — $sv/$ws/$dt are jq args, not bash; used by verb scripts
readonly WIT_LINEAR_NORMALIZE_PROGRAM="$WIT_JQ_DEF_UTC_TS"'
  def is_done($t): ($dt | index($t)) != null;
  def qualify(team; num): "linear:" + $ws + "/" + team + "#" + (num | tostring);
  {
    schema_version: $sv,
    id: qualify(.team.key // ""; .number),
    title: (.title // ""),
    state: (if is_done(.state.type // "") then "closed" else "open" end),
    assignees: [ (.assignee.displayName // .assignee.email // empty) ],
    labels: [ (.labels.nodes // [])[] | .name // empty ],
    type: null,
    blocked_by_count: ([ (.inverseRelations.nodes // [])[]
      | select(.type == "blocks")
      | (.issue.state.type // "") as $t
      | select((is_done($t) and $t == "completed") | not) ] | length),
    blocked_by_wont_do_count: ([ (.inverseRelations.nodes // [])[]
      | select(.type == "blocks")
      | (.issue.state.type // "") as $t
      | select(is_done($t) and $t != "completed") ] | length),
    parent_id: (if (.parent // null) == null then null
                else qualify(.parent.team.key // ""; .parent.number) end),
    url: (.url // ""),
    created_at: (.createdAt | wit_utc_ts),
    milestone: null
  }'

# shellcheck disable=SC2034  # WIT_LINEAR_TEAM is read by the verb scripts
wit_linear_scope_parts() {
  WIT_LINEAR_TEAM="${1#*/}"
}

wit_linear_workspace() { jq -r '.[0] | split("/")[0]' <<<"$WIT_LINEAR_SCOPES"; }

wit_linear_normalize() {
  jq -c --arg sv "$WIT_SCHEMA_VERSION" --arg ws "$(wit_linear_workspace)" \
    --argjson dt "$WIT_LINEAR_DONE_TYPES" \
    "$WIT_LINEAR_NORMALIZE_PROGRAM" <<<"$1"
}

# shellcheck disable=SC2034  # WIT_LINEAR_ISSUE is read by the verb scripts
wit_linear_fetch_issue() {
  local team="$1" number="$2" q
  q="query(\$team: String!, \$num: Float!) {
    issues(filter: { team: { key: { eq: \$team } }, number: { eq: \$num } }, first: 1) {
      nodes { $WIT_LINEAR_ISSUE_FIELDS }
    }
  }"
  wit_linear_gql "$q" \
    "$(jq -cn --arg t "$team" --argjson n "$number" '{team: $t, num: $n}')" \
    "fetching $team-$number"
  WIT_LINEAR_ISSUE="$(jq -c '.issues.nodes[0] // empty' <<<"$WIT_LINEAR_DATA")"
  if [[ -z "$WIT_LINEAR_ISSUE" ]]; then
    printf 'linear: %s-%s not found in workspace %s\n' "$team" "$number" "$(wit_linear_workspace)" >&2
    exit "$EX_NOT_FOUND"
  fi
}

wit_linear_require_scoped_id() {
  wit_require_linear_id "$1" || wit_usage_error "not a linear item id: $1"
  wit_linear_scope_in_scope "$WIT_ID_OWNER/$WIT_ID_REPO" ||
    wit_usage_error "$WIT_ID_OWNER/$WIT_ID_REPO is not in config.linear.scopes (the declared scope)"
  wit_linear_scope_parts "$WIT_ID_OWNER/$WIT_ID_REPO"
}

wit_linear_now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

wit_linear_epoch() {
  local ts="$1"
  [[ "$ts" != *.* ]] || ts="${ts%%.*}Z"
  # portability-ok: GNU-first rung of a dual-dialect ladder
  date -u -d "$ts" +%s 2>/dev/null || date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$ts" +%s 2>/dev/null || printf ''
}

wit_linear_lease_marker() {
  printf '%s%s%s' "$WIT_LINEAR_LEASE_PREFIX" "$1" "$WIT_LINEAR_LEASE_SUFFIX"
}

wit_linear_lease_json() {
  local body="$1" rest
  [[ "$body" == *"$WIT_LINEAR_LEASE_PREFIX"* ]] || return 1
  rest="${body#*"$WIT_LINEAR_LEASE_PREFIX"}"
  rest="${rest%%"$WIT_LINEAR_LEASE_SUFFIX"*}"
  jq -e -c . <<<"$rest" 2>/dev/null
}

wit_linear_lease_live() {
  local lease="$1" superseded renewed epoch ttl now
  superseded="$(jq -r '.superseded_at // empty' <<<"$lease")"
  [[ -z "$superseded" ]] || return 1
  renewed="$(jq -r '.renewed_at // empty' <<<"$lease")"
  [[ -n "$renewed" ]] || return 1
  epoch="$(wit_linear_epoch "$renewed")"
  [[ -n "$epoch" ]] || return 1
  ttl=$(($(jq -r '.ttl_hours // 0' <<<"$lease") * 3600 + $(jq -r '.ttl_minutes // 0' <<<"$lease") * 60))
  now="$(date -u +%s)"
  ((epoch + ttl > now))
}

wit_linear_handle() {
  local secs frac
  secs="$(wit_linear_epoch "$1")"
  [[ -n "$secs" ]] || {
    printf '0'
    return 0
  }
  frac="000"
  if [[ "$1" == *.* ]]; then
    frac="${1#*.}"
    frac="${frac%Z}000"
  fi
  printf '%s%s' "$secs" "${frac:0:3}"
}

WIT_LINEAR_VIEWER=""
WIT_LINEAR_VIEWER_ID=""
wit_linear_resolve_viewer() {
  wit_linear_gql 'query { viewer { id displayName email } }' '{}' "resolving the authenticated user"
  WIT_LINEAR_VIEWER_ID="$(jq -r '.viewer.id // empty' <<<"$WIT_LINEAR_DATA")"
  WIT_LINEAR_VIEWER="$(jq -r '.viewer.displayName // .viewer.email // empty' <<<"$WIT_LINEAR_DATA")"
  if [[ -z "$WIT_LINEAR_VIEWER_ID" || -z "$WIT_LINEAR_VIEWER" ]]; then
    printf 'linear: could not resolve the authenticated user from the API key\n' >&2
    exit "$EX_AUTH"
  fi
}

wit_linear_activity_since() {
  local issue_id="$1" since="$2" cursor="" has_next="true" q page node body cepoch
  q='query($id: String!, $first: Int!, $after: String) {
    issue(id: $id) {
      comments(first: $first, after: $after) {
        nodes { body createdAt }
        pageInfo { hasNextPage endCursor }
      }
    }
  }'
  while [[ "$has_next" == "true" ]]; do
    wit_linear_gql "$q" \
      "$(jq -cn --arg id "$issue_id" --argjson f "$WIT_LINEAR_PAGE_SIZE" --arg a "$cursor" \
        '{id: $id, first: $f, after: (if ($a | length) > 0 then $a else null end)}')" \
      "checking activity on $issue_id"
    page="$(jq -c '.issue.comments // {nodes: [], pageInfo: {hasNextPage: false}}' <<<"$WIT_LINEAR_DATA")"
    while IFS= read -r node; do
      [[ -n "$node" ]] || continue
      body="$(jq -r '.body // ""' <<<"$node")"
      [[ "$body" != *"$WIT_LINEAR_LEASE_PREFIX"* ]] || continue
      cepoch="$(wit_linear_epoch "$(jq -r '.createdAt' <<<"$node")")"
      [[ -n "$cepoch" ]] || continue
      if ((cepoch > since)); then
        return 0
      fi
    done < <(jq -c '.nodes[]?' <<<"$page")
    has_next="$(jq -r '.pageInfo.hasNextPage // false' <<<"$page")"
    cursor="$(jq -r '.pageInfo.endCursor // ""' <<<"$page")"
    [[ -n "$cursor" ]] || break
  done
  return 1
}

wit_linear_lease_comments() {
  local issue_id="$1" cursor="" has_next="true" all='[]' q page node body lease handle cid
  q='query($id: String!, $first: Int!, $after: String) {
    issue(id: $id) {
      comments(first: $first, after: $after) {
        nodes { id body createdAt }
        pageInfo { hasNextPage endCursor }
      }
    }
  }'
  while [[ "$has_next" == "true" ]]; do
    wit_linear_gql "$q" \
      "$(jq -cn --arg id "$issue_id" --argjson f "$WIT_LINEAR_PAGE_SIZE" --arg a "$cursor" \
        '{id: $id, first: $f, after: (if ($a | length) > 0 then $a else null end)}')" \
      "listing comments on $issue_id"
    page="$(jq -c '.issue.comments // {nodes: [], pageInfo: {hasNextPage: false}}' <<<"$WIT_LINEAR_DATA")"
    while IFS= read -r node; do
      [[ -n "$node" ]] || continue
      body="$(jq -r '.body // ""' <<<"$node")"
      lease="$(wit_linear_lease_json "$body")" || continue
      cid="$(jq -r '.id' <<<"$node")"
      handle="$(jq -r '.lease_comment_id // empty' <<<"$lease")"
      [[ "$handle" =~ ^[0-9]+$ ]] || handle="$(wit_linear_handle "$(jq -r '.createdAt' <<<"$node")")"
      all="$(jq -c --argjson h "$handle" --arg c "$cid" --argjson l "$lease" \
        '. + [{handle: $h, comment_id: $c, lease: $l}]' <<<"$all")" || {
        printf 'linear: could not accumulate lease comments on %s — refusing to report an empty lease set\n' \
          "$issue_id" >&2
        exit "$EX_INTERNAL"
      }
    done < <(jq -c '.nodes[]?' <<<"$page")
    has_next="$(jq -r '.pageInfo.hasNextPage // false' <<<"$page")"
    cursor="$(jq -r '.pageInfo.endCursor // ""' <<<"$page")"
    [[ -n "$cursor" ]] || break
  done
  jq -c 'sort_by(.handle, .comment_id)' <<<"$all"
}

wit_linear_post_comment() {
  wit_linear_gql \
    'mutation($input: CommentCreateInput!) { commentCreate(input: $input) { success comment { id createdAt } } }' \
    "$(jq -cn --arg id "$1" --arg b "$2" '{input: {issueId: $id, body: $b}}')" \
    "posting a comment on $1"
  local out
  out="$(jq -c '.commentCreate.comment // empty' <<<"$WIT_LINEAR_DATA")"
  [[ -n "$out" ]] || {
    printf 'linear: comment creation reported no comment\n' >&2
    exit "$EX_INTERNAL"
  }
  printf '%s' "$out"
}

wit_linear_update_comment() {
  wit_linear_gql \
    'mutation($id: String!, $input: CommentUpdateInput!) { commentUpdate(id: $id, input: $input) { success } }' \
    "$(jq -cn --arg id "$1" --arg b "$2" '{id: $id, input: {body: $b}}')" \
    "updating comment $1"
}

wit_linear_set_assignee() {
  wit_linear_gql \
    'mutation($id: String!, $input: IssueUpdateInput!) { issueUpdate(id: $id, input: $input) { success } }' \
    "$(jq -cn --arg id "$1" --arg u "$2" '{id: $id, input: {assigneeId: (if ($u | length) > 0 then $u else null end)}}')" \
    "setting the assignee on $1"
}
