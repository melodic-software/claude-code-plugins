# shellcheck shell=bash

[[ -n "${_WIT_JIRA_COMMON_LOADED:-}" ]] && return 0
readonly _WIT_JIRA_COMMON_LOADED=1

WIT_JIRA_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WIT_JIRA_ADAPTER_DIR

WIT_JIRA_SEAM_LIB="${WIT_SEAM_LIB_DIR:-$WIT_JIRA_ADAPTER_DIR/../../lib}"
wit_jira_require_seam_lib() {
  [[ -f "$1" ]] && return 0
  printf 'work-item-tracker jira adapter: required seam library not found: %s\n' "$1" >&2
  printf '  set WIT_SEAM_LIB_DIR to the work-item-tracker lib/ directory, or run the adapter through the dispatcher\n' >&2
  exit 3
}

wit_jira_require_seam_lib "$WIT_JIRA_SEAM_LIB/id.sh"
# shellcheck source=../../lib/id.sh disable=SC1091
source "$WIT_JIRA_SEAM_LIB/id.sh"
wit_jira_require_seam_lib "$WIT_JIRA_SEAM_LIB/json.sh"
# shellcheck source=../../lib/json.sh disable=SC1091
source "$WIT_JIRA_SEAM_LIB/json.sh"
wit_jira_require_seam_lib "$WIT_JIRA_SEAM_LIB/verb-cli.sh"
# shellcheck source=../../lib/verb-cli.sh disable=SC1091
source "$WIT_JIRA_SEAM_LIB/verb-cli.sh"
wit_jira_require_seam_lib "$WIT_JIRA_SEAM_LIB/binding.sh"
# shellcheck source=../../lib/binding.sh disable=SC1091
source "$WIT_JIRA_SEAM_LIB/binding.sh"

readonly EX_INTERNAL=1
readonly EX_USAGE=2
readonly EX_CONFIG=3
readonly EX_AUTH=4
readonly EX_NOT_FOUND=5
readonly EX_UNAVAILABLE=8

readonly WIT_JIRA_CURL_BIN="${WIT_JIRA_CURL:-curl}"

readonly WIT_JIRA_DEFAULT_BLOCKED_BY_LINK_TYPE="Blocks"
WIT_JIRA_DEFAULT_DONE_KEYS="$(jq -cn '["done","completed"]')"
readonly WIT_JIRA_DEFAULT_DONE_KEYS

readonly WIT_JIRA_PROJECT_KEY_RE='^[A-Za-z][A-Za-z0-9_]*$'
readonly WIT_JIRA_CATEGORY_KEY_RE='^[A-Za-z][A-Za-z0-9-]*$'
readonly WIT_JIRA_ISSUE_KEY_RE='^[A-Za-z][A-Za-z0-9_]*-[0-9]+\z'

readonly WIT_JIRA_HOSTNAME_RE='^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$'
readonly WIT_JIRA_CLOUD_SUFFIX='.atlassian.net'
readonly WIT_JIRA_ENV_NAME_RE='^[A-Za-z_][A-Za-z0-9_]*$'

wit_jira_nonempty_array() {
  [[ "$(jq -r 'if (type == "array" and length > 0) then "yes" else "no" end' <<<"$1")" == "yes" ]]
}

wit_jira_bad_keys() {
  jq -rc --arg re "$1" '[.[] | select((type != "string") or (test($re) | not))]' <<<"$2"
}

WIT_JIRA_BODY=""
WIT_JIRA_STATUS=""

wit_jira_value_list() {
  jq -r 'map("\"\(.)\"") | join(",")' <<<"$1"
}

wit_require_jira_id() {
  wit_parse_id "$1" || return 1
  [[ "$WIT_ID_PROVIDER" == "jira" ]] || return 1
}

wit_need_jira_config() {
  local name binding ejson allow_custom_domain
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
  WIT_JIRA_SITE="$(jq -r '.config.jira.site // empty' <<<"$ejson")"
  WIT_JIRA_AUTH_EMAIL="$(jq -r '.config.jira.auth_email // empty' <<<"$ejson")"
  WIT_JIRA_AUTH_ENV="$(jq -r '.config.jira.auth_env // empty' <<<"$ejson")"
  WIT_JIRA_PROJECT_KEYS="$(jq -c '.config.jira.project_keys // []' <<<"$ejson")"
  WIT_JIRA_BLOCKED_BY_LINK_TYPE="$(jq -r --arg d "$WIT_JIRA_DEFAULT_BLOCKED_BY_LINK_TYPE" '.config.jira.blocked_by_link_type // $d' <<<"$ejson")"
  if [[ "$(jq -r '.config.jira | has("done_category_keys")' <<<"$ejson")" == "true" ]]; then
    WIT_JIRA_DONE_KEYS="$(jq -c '.config.jira.done_category_keys' <<<"$ejson")"
  else
    WIT_JIRA_DONE_KEYS="$WIT_JIRA_DEFAULT_DONE_KEYS"
  fi
  WIT_JIRA_RESOLUTIONS="$(jq -c '.config.jira | if has("resolutions") then .resolutions // "null-value" else null end' <<<"$ejson")"
  allow_custom_domain="$(jq -r '.config.jira.allow_custom_domain // false' <<<"$ejson")"
  local missing=""
  [[ -n "$WIT_JIRA_SITE" ]] || missing+=" config.jira.site"
  [[ -n "$WIT_JIRA_AUTH_EMAIL" ]] || missing+=" config.jira.auth_email"
  [[ -n "$WIT_JIRA_AUTH_ENV" ]] || missing+=" config.jira.auth_env"
  wit_jira_nonempty_array "$WIT_JIRA_PROJECT_KEYS" ||
    missing+=" config.jira.project_keys[](non-empty array)"
  wit_jira_nonempty_array "$WIT_JIRA_DONE_KEYS" ||
    missing+=" config.jira.done_category_keys(non-empty array)"
  if [[ -n "$missing" ]]; then
    printf '%s: jira binding missing/invalid required config:%s — see CONTRACT.md "jira adapter"\n' "$name" "$missing" >&2
    exit "$EX_CONFIG"
  fi
  local bad=""
  if ! [[ "$WIT_JIRA_SITE" =~ $WIT_JIRA_HOSTNAME_RE ]]; then
    bad+=" site:'$WIT_JIRA_SITE'(not a bare hostname)"
  elif [[ "$allow_custom_domain" != "true" && "$WIT_JIRA_SITE" != *"$WIT_JIRA_CLOUD_SUFFIX" ]]; then
    bad+=" site:'$WIT_JIRA_SITE'(non-atlassian.net; set config.jira.allow_custom_domain=true to allow)"
  fi
  [[ "$WIT_JIRA_AUTH_ENV" =~ $WIT_JIRA_ENV_NAME_RE ]] ||
    bad+=" auth_env:'$WIT_JIRA_AUTH_ENV'(not a valid env var name)"
  [[ "$(jq -r '(.config.jira.blocked_by_link_type) as $b | if $b == null then "default" elif (($b|type)=="string" and ($b|length)>0) then "ok" else "bad" end' <<<"$ejson")" != "bad" ]] ||
    bad+=" blocked_by_link_type(must be a non-empty string)"
  jq -e '. == null or (type == "object" and (keys == ["completed", "wont_do"])
      and all(.[]; type == "array" and all(.[]; type == "string" and length > 0))
      and ((.completed - (.completed - .wont_do)) == []))' <<<"$WIT_JIRA_RESOLUTIONS" >/dev/null ||
    bad+=" resolutions(must be {\"completed\":[ids],\"wont_do\":[ids]}, non-empty string ids, none in both)"
  local bad_pk bad_dk
  bad_pk="$(wit_jira_bad_keys "$WIT_JIRA_PROJECT_KEY_RE" "$WIT_JIRA_PROJECT_KEYS")"
  [[ "$bad_pk" == "[]" ]] || bad+=" project_keys:$bad_pk"
  bad_dk="$(wit_jira_bad_keys "$WIT_JIRA_CATEGORY_KEY_RE" "$WIT_JIRA_DONE_KEYS")"
  [[ "$bad_dk" == "[]" ]] || bad+=" done_category_keys:$bad_dk"
  if [[ -n "$bad" ]]; then
    printf '%s: invalid jira config value(s):%s — see CONTRACT.md "jira adapter"\n' "$name" "$bad" >&2
    exit "$EX_CONFIG"
  fi
  command -v "$WIT_JIRA_CURL_BIN" >/dev/null 2>&1 ||
    {
      printf '%s: prerequisite missing: curl (Jira Cloud REST over HTTPS) — see CONTRACT.md Prerequisites\n' "$name" >&2
      exit "$EX_CONFIG"
    }
  export WIT_JIRA_SITE WIT_JIRA_AUTH_EMAIL WIT_JIRA_AUTH_ENV WIT_JIRA_PROJECT_KEYS \
    WIT_JIRA_BLOCKED_BY_LINK_TYPE WIT_JIRA_DONE_KEYS WIT_JIRA_RESOLUTIONS
}

wit_jira_project_in_scope() {
  jq -e --arg k "$1" 'index($k) != null' <<<"$WIT_JIRA_PROJECT_KEYS" >/dev/null
}

wit_jira_token() {
  local token="${!WIT_JIRA_AUTH_ENV:-}"
  if [[ -z "$token" ]]; then
    printf '%s: jira API token env var %s is unset or empty (config.jira.auth_env)\n' \
      "$(basename "${BASH_SOURCE[1]}")" "$WIT_JIRA_AUTH_ENV" >&2
    exit "$EX_AUTH"
  fi
  printf '%s' "$token"
}

wit_jira_b64() {
  if printf '%s' "$1" | base64 -w0 2>/dev/null; then return 0; fi
  printf '%s' "$1" | base64 | tr -d '\n'
}

wit_jira_http() {
  local method="$1" path="$2" body="${3:-}"
  local url="https://$WIT_JIRA_SITE/rest/api/3$path"
  local token auth raw rc
  token="$(wit_jira_token)" || exit "$?"
  auth="$(wit_jira_b64 "$WIT_JIRA_AUTH_EMAIL:$token")"
  local curl_args=(-sS -X "$method" -H "Accept: application/json" -w $'\n%{http_code}' -K -)
  if [[ -n "$body" ]]; then
    curl_args+=(-H "Content-Type: application/json" --data "$body")
  fi
  raw="$(printf 'header = "Authorization: Basic %s"\nurl = "%s"\n' "$auth" "$url" |
    "$WIT_JIRA_CURL_BIN" "${curl_args[@]}" 2>/dev/null)"
  rc=$?
  if ((rc != 0)); then
    printf 'jira: request to %s failed (curl exit %s) — network or endpoint unavailable\n' "$path" "$rc" >&2
    exit "$EX_UNAVAILABLE"
  fi
  WIT_JIRA_STATUS="${raw##*$'\n'}"
  WIT_JIRA_BODY="$(printf '%s' "${raw%$'\n'*}" | wit_strip_cr)"
}

wit_jira_require_ok() {
  local ctx="$1" code="$WIT_JIRA_STATUS"
  case "$code" in
  2*) return 0 ;;
  401 | 403)
    printf 'jira: %s — authentication/authorization failed (HTTP %s)\n' "$ctx" "$code" >&2
    exit "$EX_AUTH"
    ;;
  404)
    printf 'jira: %s — not found (HTTP 404)\n' "$ctx" >&2
    exit "$EX_NOT_FOUND"
    ;;
  429)
    printf 'jira: %s — rate limited (HTTP 429); retry later\n' "$ctx" >&2
    exit "$EX_UNAVAILABLE"
    ;;
  5*)
    printf 'jira: %s — server error (HTTP %s)\n' "$ctx" "$code" >&2
    exit "$EX_UNAVAILABLE"
    ;;
  *)
    printf 'jira: %s — unexpected response (HTTP %s): %s\n' "$ctx" "$code" "$WIT_JIRA_BODY" >&2
    exit "$EX_INTERNAL"
    ;;
  esac
}

readonly WIT_JIRA_FIELDS="status,assignee,labels,issuetype,parent,issuelinks,summary,created"
export WIT_JIRA_FIELDS

wit_jira_blocker_resolutions() {
  local json keys n i chunk chunk_len jql body out page res missing
  json="$(cat)"
  if [[ "$WIT_JIRA_RESOLUTIONS" == "null" ]]; then
    printf '{}'
    return 0
  fi
  keys="$(jq -c --arg blk "$WIT_JIRA_BLOCKED_BY_LINK_TYPE" --argjson dk "$WIT_JIRA_DONE_KEYS" \
    --argjson pk "$WIT_JIRA_PROJECT_KEYS" --arg re "$WIT_JIRA_ISSUE_KEY_RE" '
    [(if type == "array" then .[] else . end) | (.fields.issuelinks // [])[]
      | select(.type.name == $blk and .inwardIssue != null) | .inwardIssue
      | select(.fields.status.statusCategory.key as $bk | ($dk | index($bk)) != null) | .key
      | select(type == "string" and test($re)) | select(split("-")[0] as $p | ($pk | index($p)) != null)]
    | unique' <<<"$json")"
  res="$(jq -c 'map({key: ., value: {class: "blocking"}}) | from_entries' <<<"$keys")"
  n="$(jq 'length' <<<"$keys")"
  for ((i = 0; i < n; i += 100)); do
    chunk="$(jq -c --argjson i "$i" '.[$i:$i + 100]' <<<"$keys")"
    chunk_len="$(jq 'length' <<<"$chunk")"
    jql="key in ($(wit_jira_value_list "$chunk"))"
    body="$(jq -cn --arg jql "$jql" --argjson mr "$chunk_len" \
      '{jql: $jql, fields: ["resolution"], maxResults: $mr}')"
    if out="$(wit_jira_http POST "/search/jql" "$body" 2>/dev/null && [[ "$WIT_JIRA_STATUS" == 2* ]] &&
      printf '%s' "$WIT_JIRA_BODY")" &&
      page="$(jq -ce --argjson rs "$WIT_JIRA_RESOLUTIONS" --argjson chunk "$chunk" '
        if (.issues | type) == "array" then
          [.issues[] | .key as $k | select(any($chunk[]; . == $k))
            | (.fields.resolution // null) as $r
            | {key: $k, value: (
                if $r == null then {class: "resolved"}
                elif any($rs.wont_do[]; . == ($r.id | tostring)) then {class: "wont_do"}
                elif any($rs.completed[]; . == ($r.id | tostring)) then {class: "resolved"}
                else {class: "blocking", unclassified: {id: ($r.id // null), name: ($r.name // null)}} end)}]
          | from_entries
        else error("no issues array") end' <<<"$out" 2>/dev/null)"; then
      res="$(jq -cn --argjson acc "$res" --argjson page "$page" '$acc + $page')"
      missing="$(jq -r --argjson page "$page" 'map(select(. as $k | $page | has($k) | not)) | join(", ")' <<<"$chunk")"
      [[ -z "$missing" ]] ||
        echo "wit_jira_blocker_resolutions: the resolution query did not return $missing; they keep blocking" >&2
    else
      echo "wit_jira_blocker_resolutions: resolution query failed; its $chunk_len done blocker(s) keep blocking" >&2
    fi
  done
  jq -r 'to_entries[] | select(.value.unclassified) | .value.unclassified as $u
    | "wit_jira_blocker_resolutions: blocker \(.key) has resolution \($u.name) (id \($u.id)), which config.jira.resolutions does not classify; it keeps blocking. Classify it with /work-items:setup apply."' \
    <<<"$res" >&2
  printf '%s' "$res"
}

# shellcheck disable=SC2016,SC2034  # jq program — $sv/$site/$dk/$blk/$res are jq args, not bash; used by verb scripts
readonly WIT_JIRA_NORMALIZE_PROGRAM="$WIT_JQ_DEF_UTC_TS"'
  def keyparts: (capture("^(?<p>[A-Za-z][A-Za-z0-9_]*)-(?<n>[0-9]+)$")
    // error("jira: unparsable issue key: " + (. | tostring)));
  def qualify: (keyparts | "jira:" + $site + "/" + .p + "#" + .n);
  def blockers: [(.fields.issuelinks // [])[]
    | select(.type.name == $blk and (.inwardIssue != null)) | .inwardIssue];
  def done: (.fields.status.statusCategory.key) as $bk | ($dk | index($bk)) != null;
  def class: .key as $k | ((if ($k | type) == "string" then $res[$k].class else null end) // "resolved");
  {
    schema_version: $sv,
    id: (.key | qualify),
    title: (.fields.summary // ""),
    state: (if done then "closed" else "open" end),
    assignees: [ .fields.assignee.accountId // empty ],
    labels: (.fields.labels // []),
    type: (.fields.issuetype.name // null),
    blocked_by_count: ([blockers[] | select((done | not) or class != "resolved")] | length),
    blocked_by_wont_do_count: ([blockers[] | select(done and class == "wont_do")] | length),
    parent_id: (.fields.parent.key // null | if . == null then null else qualify end),
    url: ("https://" + $site + "/browse/" + .key),
    created_at: (.fields.created | wit_utc_ts),
    milestone: null
  }'
