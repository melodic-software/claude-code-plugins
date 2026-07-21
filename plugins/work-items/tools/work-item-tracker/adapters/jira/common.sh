# shellcheck shell=bash
# Shared helpers for the Jira Cloud adapter — sourced by every verb script.
# CONTRACT.md "jira adapter". Read/resolve-only surface: get-item, list-items,
# capabilities are supported; every write verb (create/claim/lease/link/sub-item)
# and list-sub-items are declared false in the manifest and exit 6 at the core gate,
# so no code path here mutates a Jira ticket (issue #379 hard constraint).
#
# Provider: Jira Cloud REST API v3. Auth: Basic (Atlassian account email + API
# token) — the token is read from the env var named by config.jira.auth_env, never
# stored in the tracked binding, and passed to curl via a stdin config (-K -) so it
# never appears in argv. HTTP goes through ${WIT_JIRA_CURL:-curl}; tests inject a
# mock binary there to exercise the read path offline (no live Jira calls).

[[ -n "${_WIT_JIRA_COMMON_LOADED:-}" ]] && return 0
readonly _WIT_JIRA_COMMON_LOADED=1

WIT_JIRA_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WIT_JIRA_ADAPTER_DIR

# A consumer may shadow this adapter with a local copy (CONTRACT.md "Adapter
# resolution") while still running the bundled dispatcher; the shared seam libs
# below then resolve relative to that copy and can be absent. A missing required
# lib must hard-fail with a clear diagnostic (exit 3 — setup/config error), never
# let sourcing fail silently and leave a verb emitting a malformed record. Runs
# before the EX_* constants below exist, so it uses the literal.
wit_jira_require_seam_lib() {
  [[ -f "$1" ]] && return 0
  printf 'work-item-tracker jira adapter: required seam library not found: %s\n' "$1" >&2
  printf '  a shadowed consumer-local adapter must still resolve the bundled seam lib/ directory\n' >&2
  exit 3
}

wit_jira_require_seam_lib "$WIT_JIRA_ADAPTER_DIR/../../lib/id.sh"
# shellcheck source=../../lib/id.sh
source "$WIT_JIRA_ADAPTER_DIR/../../lib/id.sh"
wit_jira_require_seam_lib "$WIT_JIRA_ADAPTER_DIR/../../lib/json.sh"
# shellcheck source=../../lib/json.sh
source "$WIT_JIRA_ADAPTER_DIR/../../lib/json.sh"
# binding.sh is sourced (not inherited): the dispatcher runs each verb as a fresh
# `bash <verb>.sh` subprocess, so only exported env vars cross — not wit_find_binding.
# The adapter re-locates the binding itself to read its jira-specific config subtree,
# rather than growing the shared binding.sh with jira keys (that shared lib already
# carries a provider-specific leak — config.storage_dir — that this adapter does not
# extend; the generalized fix is filed as a scoped follow-up).
wit_jira_require_seam_lib "$WIT_JIRA_ADAPTER_DIR/../../lib/binding.sh"
# shellcheck source=../../lib/binding.sh
source "$WIT_JIRA_ADAPTER_DIR/../../lib/binding.sh"

readonly EX_INTERNAL=1
readonly EX_USAGE=2
readonly EX_CONFIG=3
readonly EX_AUTH=4
readonly EX_NOT_FOUND=5
readonly EX_UNAVAILABLE=8

# HTTP command indirection: the sole testability seam. Tests point WIT_JIRA_CURL at a
# mock that returns canned responses, keeping the read path offline. Absent → real curl.
readonly WIT_JIRA_CURL_BIN="${WIT_JIRA_CURL:-curl}"

# Blocker link type + done-category keys default to the documented Jira standards but
# are configurable: they are the override seams for the two facts issue #379 deferred
# to a live-instance pass (#6 blocker link type, #4 the exact statusCategory "done"
# key — the spec's own example disagrees with real instances, so both known keys are
# defaulted here). The adapter is therefore independent of those deferred facts.
readonly WIT_JIRA_DEFAULT_BLOCKED_BY_LINK_TYPE="Blocks"
readonly WIT_JIRA_DEFAULT_DONE_KEYS='["done","completed"]'

# Values interpolated into a JQL query (project keys, statusCategory keys) are
# constrained to a strict allowlist BEFORE interpolation — the seam builds JQL by
# string assembly, so an unescaped `"` in a key would break out of the literal and
# inject arbitrary JQL. Allowlisting (reject the unexpected) is safer than escaping,
# and matches what Jira itself permits: project keys are letter-led alphanumerics
# (the same charset the normalizer's key parser accepts); statusCategory keys are
# letter-led alphanumerics plus hyphen (e.g. `in-flight`). Anything else is refused.
readonly WIT_JIRA_PROJECT_KEY_RE='^[A-Za-z][A-Za-z0-9_]*$'
readonly WIT_JIRA_CATEGORY_KEY_RE='^[A-Za-z][A-Za-z0-9-]*$'

# config.jira.site becomes the request host that receives the Basic-auth token, so it
# must be a BARE hostname — no scheme, path, userinfo (`@`), port, or control chars —
# lest a binding smuggle URL structure that redirects the credential off the tenant.
# And it must be an Atlassian Cloud host (*.atlassian.net) unless the binding
# explicitly opts into a custom domain: deny-by-default on credential egress, since a
# tracked binding is PR-modifiable and the token may be present in CI.
readonly WIT_JIRA_HOSTNAME_RE='^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$'
readonly WIT_JIRA_CLOUD_SUFFIX='.atlassian.net'
# auth_env is dereferenced via ${!name}; an invalid identifier aborts bash, so it must
# be a valid shell variable name.
readonly WIT_JIRA_ENV_NAME_RE='^[A-Za-z_][A-Za-z0-9_]*$'

# Set by wit_jira_http; declared here so a read before the first call does not trip
# `set -u`.
WIT_JIRA_BODY=""
WIT_JIRA_STATUS=""

wit_usage_error() {
  printf '%s: %s\n' "$(basename "${BASH_SOURCE[1]}")" "$1" >&2
  exit "$EX_USAGE"
}

# wit_help_if_requested <usage-text> <args…> — print usage + exit 0 on --help.
wit_help_if_requested() {
  local usage="$1"
  shift
  if [[ "${1:-}" == "--help" ]]; then
    printf '%s\n' "$usage"
    exit 0
  fi
}

# wit_require_jira_id <id> — parse an ID and require its provider be `jira`. The
# shared grammar accepts any provider; this adapter rejects foreign-provider IDs so
# a `github:…#N` never operates on a Jira issue. Sets the WIT_ID_* globals: OWNER is
# the Cloud site host, REPO is the project key, NUMBER is the issue number.
wit_require_jira_id() {
  wit_parse_id "$1" || return 1
  [[ "$WIT_ID_PROVIDER" == "jira" ]] || return 1
}

# wit_need_jira_config — load and validate the jira config subtree from the binding.
# Called by verbs AFTER arg parsing, so --help / usage errors stay offline and
# config-free (mirrors local-markdown's wit_need_storage). Exits 3 when the binding
# or a required key (site, non-empty project_keys, auth_email, auth_env) is missing.
# Exports WIT_JIRA_SITE, WIT_JIRA_PROJECT_KEYS (JSON array), WIT_JIRA_AUTH_EMAIL,
# WIT_JIRA_AUTH_ENV, WIT_JIRA_BLOCKED_BY_LINK_TYPE, WIT_JIRA_DONE_KEYS (JSON array).
wit_need_jira_config() {
  local name binding
  name="$(basename "${BASH_SOURCE[1]}")"
  binding="$(wit_find_binding)" ||
    {
      printf '%s: no binding found (.work-item-tracker.json) — see CONTRACT.md Setup\n' "$name" >&2
      exit "$EX_CONFIG"
    }
  WIT_JIRA_SITE="$(jq -r '.config.jira.site // empty' "$binding")"
  WIT_JIRA_AUTH_EMAIL="$(jq -r '.config.jira.auth_email // empty' "$binding")"
  WIT_JIRA_AUTH_ENV="$(jq -r '.config.jira.auth_env // empty' "$binding")"
  WIT_JIRA_PROJECT_KEYS="$(jq -c '.config.jira.project_keys // []' "$binding")"
  WIT_JIRA_BLOCKED_BY_LINK_TYPE="$(jq -r --arg d "$WIT_JIRA_DEFAULT_BLOCKED_BY_LINK_TYPE" '.config.jira.blocked_by_link_type // $d' "$binding")"
  WIT_JIRA_DONE_KEYS="$(jq -c --argjson d "$WIT_JIRA_DEFAULT_DONE_KEYS" '.config.jira.done_category_keys // $d' "$binding")"
  local allow_custom_domain
  allow_custom_domain="$(jq -r '.config.jira.allow_custom_domain // false' "$binding")"
  local missing=""
  [[ -n "$WIT_JIRA_SITE" ]] || missing+=" config.jira.site"
  [[ -n "$WIT_JIRA_AUTH_EMAIL" ]] || missing+=" config.jira.auth_email"
  [[ -n "$WIT_JIRA_AUTH_ENV" ]] || missing+=" config.jira.auth_env"
  # project_keys must be a non-empty ARRAY, not merely truthy: a scalar such as
  # "project_keys":"ABC" would satisfy a bare `length > 0` (string length 3), then
  # `.[]`/`map(...)` would jq-error into an empty clause (`project in ()`) that this
  # non-`set -e` script would otherwise ignore. Type-check first, then length.
  [[ "$(jq -r 'type' <<<"$WIT_JIRA_PROJECT_KEYS")" == "array" ]] &&
    [[ "$(jq -r 'length' <<<"$WIT_JIRA_PROJECT_KEYS")" -gt 0 ]] ||
    missing+=" config.jira.project_keys[](non-empty array)"
  # done_category_keys defaults when absent, but a present non-array OR EMPTY value is a
  # misconfiguration: an empty set builds `statusCategory not in ()` — invalid JQL Jira
  # rejects with 400 — not a silent fall-through to the default.
  [[ "$(jq -r 'type' <<<"$WIT_JIRA_DONE_KEYS")" == "array" ]] &&
    [[ "$(jq -r 'length' <<<"$WIT_JIRA_DONE_KEYS")" -gt 0 ]] ||
    missing+=" config.jira.done_category_keys(non-empty array)"
  if [[ -n "$missing" ]]; then
    printf '%s: jira binding missing/invalid required config:%s — see CONTRACT.md "jira adapter"\n' "$name" "$missing" >&2
    exit "$EX_CONFIG"
  fi
  # Value-level validation (all exit 3): the JQL-interpolated keys against their
  # allowlist charset (the query builders assemble by string concat, so an unvalidated
  # token could inject), plus the credential-bearing site host and the token env-var
  # name. Captured then iterated via here-string (MSYS process-sub gotcha); the loop
  # body only runs a regex, no fork.
  local bad="" k keys
  # site is the host the Basic-auth token is sent to: require a bare hostname (block
  # scheme/path/userinfo/port smuggling) and an Atlassian Cloud host unless the binding
  # explicitly opts into a custom domain (deny-by-default credential egress).
  if ! [[ "$WIT_JIRA_SITE" =~ $WIT_JIRA_HOSTNAME_RE ]]; then
    bad+=" site:'$WIT_JIRA_SITE'(not a bare hostname)"
  elif [[ "$allow_custom_domain" != "true" && "$WIT_JIRA_SITE" != *"$WIT_JIRA_CLOUD_SUFFIX" ]]; then
    bad+=" site:'$WIT_JIRA_SITE'(non-atlassian.net; set config.jira.allow_custom_domain=true to allow)"
  fi
  # auth_env is dereferenced via ${!name}; an invalid identifier aborts bash on first
  # read — reject it here (exit 3) with a clear message instead.
  [[ "$WIT_JIRA_AUTH_ENV" =~ $WIT_JIRA_ENV_NAME_RE ]] ||
    bad+=" auth_env:'$WIT_JIRA_AUTH_ENV'(not a valid env var name)"
  keys="$(jq -r '.[]' <<<"$WIT_JIRA_PROJECT_KEYS" | wit_strip_cr)"
  while IFS= read -r k; do
    [[ -n "$k" ]] || continue
    [[ "$k" =~ $WIT_JIRA_PROJECT_KEY_RE ]] || bad+=" project_keys:'$k'"
  done <<<"$keys"
  keys="$(jq -r '.[]' <<<"$WIT_JIRA_DONE_KEYS" | wit_strip_cr)"
  while IFS= read -r k; do
    [[ -n "$k" ]] || continue
    [[ "$k" =~ $WIT_JIRA_CATEGORY_KEY_RE ]] || bad+=" done_category_keys:'$k'"
  done <<<"$keys"
  if [[ -n "$bad" ]]; then
    printf '%s: invalid jira config value(s):%s — see CONTRACT.md "jira adapter"\n' "$name" "$bad" >&2
    exit "$EX_CONFIG"
  fi
  # curl is the read path's only prerequisite binary; gate here (exit 3, actionable)
  # rather than let the first request fail obscurely. WIT_JIRA_CURL_BIN is the real
  # curl by default or a test-injected mock — either way it must resolve.
  command -v "$WIT_JIRA_CURL_BIN" >/dev/null 2>&1 ||
    {
      printf '%s: prerequisite missing: curl (Jira Cloud REST over HTTPS) — see CONTRACT.md Prerequisites\n' "$name" >&2
      exit "$EX_CONFIG"
    }
  export WIT_JIRA_SITE WIT_JIRA_AUTH_EMAIL WIT_JIRA_AUTH_ENV WIT_JIRA_PROJECT_KEYS \
    WIT_JIRA_BLOCKED_BY_LINK_TYPE WIT_JIRA_DONE_KEYS
}

# wit_jira_project_in_scope <project-key> — 0 when the key is in the binding's
# config.jira.project_keys. That list is the declared read scope AND the authorization
# boundary: a bound workflow must not read tickets from a project it did not declare,
# even when the token can see them. get-item enforces this on the id's project,
# list-items on --repo — each maps a miss to its own usage error (exit 2) before any
# request, so the diagnostic names the calling verb.
wit_jira_project_in_scope() {
  [[ "$(jq -r --arg k "$1" 'if (index($k) != null) then "in" else "out" end' <<<"$WIT_JIRA_PROJECT_KEYS")" == "in" ]]
}

# wit_jira_token — echo the API token from the env var named by config.jira.auth_env.
# Exits 4 (auth) when that env var is unset or empty: the token is never stored in
# the tracked binding, only referenced by name. Call after wit_need_jira_config.
wit_jira_token() {
  local token="${!WIT_JIRA_AUTH_ENV:-}"
  if [[ -z "$token" ]]; then
    printf '%s: jira API token env var %s is unset or empty (config.jira.auth_env)\n' \
      "$(basename "${BASH_SOURCE[1]}")" "$WIT_JIRA_AUTH_ENV" >&2
    exit "$EX_AUTH"
  fi
  printf '%s' "$token"
}

# wit_jira_b64 <text> — base64 of stdin text, single line, portable across coreutils
# (-w0) and BSD/mac base64 (no -w flag).
wit_jira_b64() {
  if printf '%s' "$1" | base64 -w0 2>/dev/null; then return 0; fi
  printf '%s' "$1" | base64 | tr -d '\n'
}

# wit_jira_http <method> <path> [<json-body>] — call the Jira Cloud REST v3 API at
# https://<site>/rest/api/3<path>. The Basic auth header is fed through curl's stdin
# config (-K -) so the base64(email:token) credential never appears in argv. Captures
# the response body to WIT_JIRA_BODY and the HTTP status to WIT_JIRA_STATUS; on a
# curl transport failure (no status) exits 8. HTTP-status→exit-code mapping is left
# to the caller via wit_jira_require_ok so it can attach verb-specific context.
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

# wit_jira_require_ok <context> — map WIT_JIRA_STATUS to a contract exit code,
# printing WIT_JIRA_BODY's error text to stderr on failure. 2xx returns 0.
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

# The fields the normalized item object is derived from (CONTRACT.md "JSON output
# contract"). issuelinks carries each blocker's nested status inline (verified
# against the official OpenAPI spec: LinkedIssue.fields uses the Fields schema, which
# includes status.statusCategory), so blocked_by_count needs no second round-trip.
readonly WIT_JIRA_FIELDS="status,assignee,labels,issuetype,parent,issuelinks,summary"
# WIT_JIRA_FIELDS and WIT_JIRA_NORMALIZE_PROGRAM (below) are consumed by the sourcing
# verb scripts, not within this file; export so a standalone lint of this sourced-only
# file sees them as intentionally external (mirrors lib/json.sh exporting
# WIT_SCHEMA_VERSION and local-markdown/common.sh exporting its verb-referenced consts).
export WIT_JIRA_FIELDS

# wit_jira_normalize_program — a jq program that maps one raw Jira IssueBean into the
# seam's normalized item object (CONTRACT.md "JSON output contract"). Expects jq args
# $sv (schema version), $site (Cloud host), $dk (JSON array of done statusCategory
# keys), $blk (blocker link-type name). blocked_by_count counts only OPEN inward
# blockers (parity with the GitHub adapter's OPEN-only count).
# WIT_JIRA_NORMALIZE_PROGRAM is consumed by the sourcing verb scripts (get-item,
# list-items), not within this file — SC2034 is a false positive on a sourced-only
# lib. It is a jq program string, so it is not exported (an exported quoted program
# trips SC2089/2090); the disable marks it intentionally external instead.
# shellcheck disable=SC2016,SC2034  # jq program — $sv/$site/$dk/$blk are jq args, not bash; used by verb scripts
readonly WIT_JIRA_NORMALIZE_PROGRAM='
  def keyparts: capture("^(?<p>[A-Za-z][A-Za-z0-9_]*)-(?<n>[0-9]+)$");
  def qualify: (keyparts | "jira:" + $site + "/" + .p + "#" + .n);
  {
    schema_version: $sv,
    id: (.key | qualify),
    title: (.fields.summary // ""),
    state: ((.fields.status.statusCategory.key) as $k
      | if ($dk | index($k)) then "closed" else "open" end),
    assignees: [ .fields.assignee.accountId // empty ],
    labels: (.fields.labels // []),
    type: (.fields.issuetype.name // null),
    blocked_by_count: ([ (.fields.issuelinks // [])[]
      | select(.type.name == $blk and (.inwardIssue != null))
      | (.inwardIssue.fields.status.statusCategory.key) as $bk
      | select( ($dk | index($bk)) | not ) ] | length),
    parent_id: (if (.fields.parent.key // null) == null then null else (.fields.parent.key | qualify) end),
    url: ("https://" + $site + "/browse/" + .key)
  }'
