# shellcheck shell=bash

[[ -n "${_WIT_GITEA_COMMON_LOADED:-}" ]] && return 0
readonly _WIT_GITEA_COMMON_LOADED=1

WIT_GITEA_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WIT_GITEA_ADAPTER_DIR

WIT_GITEA_SEAM_LIB="${WIT_SEAM_LIB_DIR:-$WIT_GITEA_ADAPTER_DIR/../../lib}"
readonly WIT_GITEA_SEAM_LIB

wit_gitea_require_seam_lib() {
  [[ -f "$1" ]] && return 0
  printf 'work-item-tracker gitea adapter: required seam library not found: %s\n' "$1" >&2
  printf '  set WIT_SEAM_LIB_DIR to the work-item-tracker lib/ directory, or vendor the seam\n' >&2
  exit 3
}

wit_gitea_require_seam_lib "$WIT_GITEA_SEAM_LIB/id.sh"
# shellcheck source=../../lib/id.sh disable=SC1091
source "$WIT_GITEA_SEAM_LIB/id.sh"
wit_gitea_require_seam_lib "$WIT_GITEA_SEAM_LIB/json.sh"
# shellcheck source=../../lib/json.sh disable=SC1091
source "$WIT_GITEA_SEAM_LIB/json.sh"
wit_gitea_require_seam_lib "$WIT_GITEA_SEAM_LIB/verb-cli.sh"
# shellcheck source=../../lib/verb-cli.sh disable=SC1091
source "$WIT_GITEA_SEAM_LIB/verb-cli.sh"
wit_gitea_require_seam_lib "$WIT_GITEA_SEAM_LIB/binding.sh"
# shellcheck source=../../lib/binding.sh disable=SC1091
source "$WIT_GITEA_SEAM_LIB/binding.sh"

readonly EX_INTERNAL=1
readonly EX_USAGE=2
readonly EX_CONFIG=3
readonly EX_AUTH=4
readonly EX_NOT_FOUND=5
readonly EX_CONFLICT=7
readonly EX_UNAVAILABLE=8

readonly WIT_GITEA_CURL_BIN="${WIT_GITEA_CURL:-curl}"

readonly WIT_GITEA_HOSTNAME_RE='^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$'
readonly WIT_GITEA_DEFAULT_HOST_SUFFIX=''

wit_gitea_host_under_pin() {
  local host="$1" pin="$2"
  [[ "$pin" == .* ]] || pin=".$pin"
  [[ "$host" == *"$pin" || "$host" == "${pin#.}" ]]
}
readonly WIT_GITEA_ENV_NAME_RE='^[A-Za-z_][A-Za-z0-9_]*$'
readonly WIT_GITEA_SCOPE_RE='^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$'

readonly WIT_GITEA_DEFAULT_PAGE_SIZE=50
WIT_GITEA_LIST_ITEMS_MAX="$(jq -r '.limits.list_items_max' "$WIT_GITEA_ADAPTER_DIR/capabilities.json" 2>/dev/null)"
if [[ ! "$WIT_GITEA_LIST_ITEMS_MAX" =~ ^[1-9][0-9]*$ ]]; then
  printf 'work-item-tracker gitea adapter: limits.list_items_max in %s/capabilities.json must be a positive integer, got: %s\n' \
    "$WIT_GITEA_ADAPTER_DIR" "${WIT_GITEA_LIST_ITEMS_MAX:-<unreadable>}" >&2
  exit "$EX_CONFIG"
fi
readonly WIT_GITEA_LIST_ITEMS_MAX

WIT_GITEA_BODY=""
WIT_GITEA_STATUS=""

wit_gitea_unimplemented() {
  printf '%s: gitea adapter verb %s is a generated scaffold with no provider mapping yet\n' \
    "$(basename "${BASH_SOURCE[1]}")" "$1" >&2
  printf '  fill in its PROVIDER MAPPING block, or set verbs["%s"]=false in capabilities.json\n' "$1" >&2
  exit "$EX_INTERNAL"
}

wit_gitea_nonempty_array() {
  [[ "$(jq -r 'if (type == "array" and length > 0) then "yes" else "no" end' <<<"$1")" == "yes" ]]
}

wit_gitea_bad_elements() {
  jq -rc --arg re "$1" '[.[] | select((type != "string") or (test($re) | not))]' <<<"$2"
}

# Sets the WIT_ID_* globals.
# shellcheck disable=SC2154  # WIT_ID_PROVIDER is exported by wit_parse_id in the seam's id.sh, sourced above through a runtime-resolved path ShellCheck cannot follow
wit_require_gitea_id() {
  wit_parse_id "$1" || return 1
  [[ "$WIT_ID_PROVIDER" == "gitea" ]] || return 1
}

wit_need_gitea_config() {
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
  WIT_GITEA_HOST="$(jq -r '.config.gitea.host // empty' <<<"$ejson")"
  WIT_GITEA_AUTH_ENV="$(jq -r '.config.gitea.auth_env // empty' <<<"$ejson")"
  WIT_GITEA_SCOPES="$(jq -c '.config.gitea.scopes // []' <<<"$ejson")"
  WIT_GITEA_PAGE_SIZE="$(jq -r --arg d "$WIT_GITEA_DEFAULT_PAGE_SIZE" \
    '.config.gitea | if has("page_size") then .page_size else $d end' <<<"$ejson")"

  local allow_custom_domain host_suffix
  allow_custom_domain="$(jq -r '.config.gitea.allow_custom_domain // false' <<<"$ejson")"
  host_suffix="$(jq -r --arg d "$WIT_GITEA_DEFAULT_HOST_SUFFIX" '.config.gitea.host_suffix // $d' <<<"$ejson")"

  local missing=""
  [[ -n "$WIT_GITEA_HOST" ]] || missing+=" config.gitea.host"
  [[ -n "$WIT_GITEA_AUTH_ENV" ]] || missing+=" config.gitea.auth_env"

  wit_gitea_nonempty_array "$WIT_GITEA_SCOPES" ||
    missing+=" config.gitea.scopes[](non-empty array)"
  if [[ -n "$missing" ]]; then
    printf '%s: gitea binding missing/invalid required config:%s — see the adapter README\n' "$name" "$missing" >&2
    exit "$EX_CONFIG"
  fi

  local bad=""
  if ! [[ "$WIT_GITEA_HOST" =~ $WIT_GITEA_HOSTNAME_RE ]]; then
    bad+=" host:'$WIT_GITEA_HOST'(not a bare hostname)"
  elif [[ -n "$host_suffix" && "$allow_custom_domain" != "true" ]] &&
    ! wit_gitea_host_under_pin "$WIT_GITEA_HOST" "$host_suffix"; then
    bad+=" host:'$WIT_GITEA_HOST'(not under $host_suffix; set config.gitea.allow_custom_domain=true to allow)"
  fi
  [[ "$WIT_GITEA_AUTH_ENV" =~ $WIT_GITEA_ENV_NAME_RE ]] ||
    bad+=" auth_env:'$WIT_GITEA_AUTH_ENV'(not a valid env var name)"
  local bad_scopes
  bad_scopes="$(wit_gitea_bad_elements "$WIT_GITEA_SCOPE_RE" "$WIT_GITEA_SCOPES")"
  [[ "$bad_scopes" == "[]" ]] || bad+=" scopes:$bad_scopes"
  [[ "$WIT_GITEA_PAGE_SIZE" =~ ^[1-9][0-9]*$ ]] ||
    bad+=" page_size:'$WIT_GITEA_PAGE_SIZE'(must be a positive integer)"
  if [[ -n "$bad" ]]; then
    printf '%s: invalid gitea config value(s):%s — see the adapter README\n' "$name" "$bad" >&2
    exit "$EX_CONFIG"
  fi

  command -v "$WIT_GITEA_CURL_BIN" >/dev/null 2>&1 ||
    {
      printf '%s: prerequisite missing: curl (Gitea / Forgejo REST over HTTPS) — see CONTRACT.md Prerequisites\n' "$name" >&2
      exit "$EX_CONFIG"
    }
  export WIT_GITEA_HOST WIT_GITEA_AUTH_ENV WIT_GITEA_SCOPES WIT_GITEA_PAGE_SIZE
}

wit_gitea_scope_in_scope() {
  jq -e --arg k "$1" 'index($k) != null' <<<"$WIT_GITEA_SCOPES" >/dev/null
}

wit_gitea_token() {
  local token="${!WIT_GITEA_AUTH_ENV:-}"
  if [[ -z "$token" ]]; then
    printf '%s: gitea credential env var %s is unset or empty (config.gitea.auth_env)\n' \
      "$(basename "${BASH_SOURCE[1]}")" "$WIT_GITEA_AUTH_ENV" >&2
    exit "$EX_AUTH"
  fi
  printf '%s' "$token"
}

wit_gitea_auth_header() {
  local token
  token="$(wit_gitea_token)" || exit "$?"
  printf 'Authorization: token %s' "$token"
}

wit_gitea_http() {
  local method="$1" path="$2" body="${3:-}"
  local url="https://$WIT_GITEA_HOST/api/v1$path"
  local auth raw rc hdrs
  auth="$(wit_gitea_auth_header)" || exit "$?"
  hdrs="$(mktemp)" || {
    printf 'gitea: could not create a temp file for response headers\n' >&2
    exit "$EX_INTERNAL"
  }
  local curl_args=(-sS -X "$method" -H "Accept: application/json" --proto '=https' -D "$hdrs" -w $'\n%{http_code}' -K -)
  [[ -z "$body" ]] || curl_args+=(-H "Content-Type: application/json" --data "$body")
  raw="$(printf 'header = "%s"\nurl = "%s"\n' "$auth" "$url" |
    "$WIT_GITEA_CURL_BIN" "${curl_args[@]}" 2>/dev/null)"
  rc=$?
  if ((rc != 0)); then
    rm -f "$hdrs"
    printf 'gitea: request to %s failed (curl exit %s) — network or endpoint unavailable\n' "$path" "$rc" >&2
    exit "$EX_UNAVAILABLE"
  fi
  WIT_GITEA_STATUS="${raw##*$'\n'}"
  WIT_GITEA_BODY="$(printf '%s' "${raw%$'\n'*}" | wit_strip_cr)"
  # shellcheck disable=SC2034  # read by list-items.sh and create-item.sh; this file is sourced-only
  WIT_GITEA_TOTAL_COUNT=""
  if [[ -s "$hdrs" ]]; then
    # shellcheck disable=SC2034  # ditto
    WIT_GITEA_TOTAL_COUNT="$(wit_strip_cr <"$hdrs" |
      sed -n 's/^[Xx]-[Tt]otal-[Cc]ount:[[:space:]]*\([0-9][0-9]*\).*$/\1/p' | tail -1)"
  fi
  rm -f "$hdrs"
}

wit_gitea_require_array() {
  local kind
  kind="$(jq -r 'type' <<<"$WIT_GITEA_BODY" 2>/dev/null)" || kind=""
  [[ "$kind" == "array" ]] && return 0
  printf 'gitea: %s — expected a JSON array, got %s\n' "$1" "${kind:-non-JSON}" >&2
  exit "$EX_INTERNAL"
}

wit_gitea_require_ok() {
  local ctx="$1" code="$WIT_GITEA_STATUS"
  case "$code" in
  2*) return 0 ;;
  401 | 403)
    printf 'gitea: %s — authentication/authorization failed (HTTP %s)\n' "$ctx" "$code" >&2
    exit "$EX_AUTH"
    ;;
  404)
    printf 'gitea: %s — not found (HTTP 404)\n' "$ctx" >&2
    exit "$EX_NOT_FOUND"
    ;;
  400)
    if [[ "$WIT_GITEA_BODY" == *"CrossRepositoryDependencies not enabled"* ]]; then
      printf 'gitea: %s — this instance has ALLOW_CROSS_REPOSITORY_DEPENDENCIES disabled, so a dependency edge cannot cross repositories (HTTP 400)\n' "$ctx" >&2
    else
      printf 'gitea: %s — request rejected (HTTP 400): %s\n' "$ctx" "$WIT_GITEA_BODY" >&2
    fi
    exit "$EX_CONFLICT"
    ;;
  409 | 412 | 422 | 423)
    printf 'gitea: %s — conflict/precondition (HTTP %s)\n' "$ctx" "$code" >&2
    exit "$EX_CONFLICT"
    ;;
  429)
    printf 'gitea: %s — rate limited (HTTP 429); retry later\n' "$ctx" >&2
    exit "$EX_UNAVAILABLE"
    ;;
  5*)
    printf 'gitea: %s — server error (HTTP %s)\n' "$ctx" "$code" >&2
    exit "$EX_UNAVAILABLE"
    ;;
  *)
    printf 'gitea: %s — unexpected response (HTTP %s): %s\n' "$ctx" "$code" "$WIT_GITEA_BODY" >&2
    exit "$EX_INTERNAL"
    ;;
  esac
}

# shellcheck disable=SC2016,SC2034  # jq program — $sv/$bbc are jq args, not bash; used by verb scripts
readonly WIT_GITEA_NORMALIZE_PROGRAM="$WIT_JQ_DEF_UTC_TS"'
  def qualify(n): "gitea:" + (.repository.full_name // "") + "#" + (n | tostring);
  {
    schema_version: $sv,
    id: qualify(.number),
    title: (.title // ""),
    state: (if (.state) == "closed" then "closed" else "open" end),
    assignees: [ (.assignees // [])[] | .login // empty ],
    labels: [ (.labels // [])[] | .name // empty ],
    type: null,
    blocked_by_count: $bbc,
    blocked_by_wont_do_count: 0,
    parent_id: null,
    url: (.html_url // ""),
    created_at: (.created_at | wit_utc_ts),
    milestone: null
  }'

wit_gitea_blocked_by_count() {
  local owner="$1" repo="$2" index="$3" page=1 total=0 got counts
  while :; do
    wit_gitea_http GET "/repos/$owner/$repo/issues/$index/dependencies?page=$page&limit=$WIT_GITEA_PAGE_SIZE"
    if [[ "$WIT_GITEA_STATUS" == "404" ]]; then
      printf '0'
      return 0
    fi
    wit_gitea_require_ok "listing dependencies of $owner/$repo#$index"
    counts="$(printf '%s' "$WIT_GITEA_BODY" |
      jq -r '[length, ([.[] | select(.state != "closed")] | length)] | @tsv' 2>/dev/null)" || counts=""
    [[ "$counts" =~ ^[0-9]+$'\t'[0-9]+$ ]] || counts=$'0\t0'
    got="${counts%%$'\t'*}"
    total=$((total + ${counts##*$'\t'}))
    ((got < WIT_GITEA_PAGE_SIZE)) && break
    page=$((page + 1))
    ((page * WIT_GITEA_PAGE_SIZE > WIT_GITEA_LIST_ITEMS_MAX)) && break
  done
  printf '%s' "$total"
}

# shellcheck disable=SC2034  # WIT_GITEA_OWNER/REPO are read by the sourcing verb scripts, not within this lib
wit_gitea_scope_parts() {
  WIT_GITEA_OWNER="${1%%/*}"
  WIT_GITEA_REPO="${1#*/}"
}
