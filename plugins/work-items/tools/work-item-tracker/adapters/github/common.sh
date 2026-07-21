# shellcheck shell=bash
# Shared helpers for the GitHub adapter — sourced by every verb script. Identity
# routing (CONTRACT.md "Identity routing (GitHub adapter)"): writes prefer a bot
# wrapper (gh-bot.sh) when the consuming repo provides one, falling back to bare gh
# for plugin-lift portability; claim assignment stays on bare gh so @me resolves to
# the session identity.

[[ -n "${_WIT_GH_COMMON_LOADED:-}" ]] && return 0
readonly _WIT_GH_COMMON_LOADED=1

WIT_GH_ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WIT_GH_ADAPTER_DIR

# A consumer may shadow this adapter with a local copy (CONTRACT.md "Adapter
# resolution") while still running the bundled dispatcher; the shared seam libs
# below then resolve relative to that copy and can be absent. A missing required
# lib must hard-fail with a clear diagnostic (exit 3 — setup/config error), never
# let sourcing fail silently and leave a verb emitting a malformed (e.g. empty-id)
# record. Runs before the EX_* constants below exist, so it uses the literal.
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
wit_gh_require_seam_lib "$WIT_GH_ADAPTER_DIR/../../lib/lease.sh"
# shellcheck source=../../lib/lease.sh
source "$WIT_GH_ADAPTER_DIR/../../lib/lease.sh"

# wit_gh_resolve_bot_wrapper — echo the bot wrapper path using consumer-local-first
# resolution (CONTRACT.md "Identity routing (GitHub adapter)"), mirroring the
# adapter two-root resolution (CONTRACT.md "Adapter resolution"): a consuming
# repo's own wrapper at ${CLAUDE_PROJECT_DIR}/tools/github-auth/gh-bot.sh wins,
# independent of where the adapter itself resolved from (a shadowed
# consumer-local adapter must still find the consumer's wrapper, not miss it via
# its own directory); otherwise the plugin-bundled path beside this adapter tree.
wit_gh_resolve_bot_wrapper() {
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    local consumer_wrapper="$CLAUDE_PROJECT_DIR/tools/github-auth/gh-bot.sh"
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
readonly EX_AUTH=4
readonly EX_NOT_FOUND=5
readonly EX_CONFLICT=7
readonly EX_UNAVAILABLE=8

# Set by wit_run_gh; declared here so a read before the first call does not trip
# `set -u` (call-order independence).
WIT_GH_OUT=""

wit_usage_error() {
  printf '%s: %s\n' "$(basename "${BASH_SOURCE[1]}")" "$1" >&2
  exit "$EX_USAGE"
}

# wit_require_github_id <id> — parse an ID and require its provider be `github`.
# The shared grammar (lib/id.sh) accepts any provider by design; the GitHub
# adapter must reject foreign-provider IDs so a `local-markdown:…#N` never
# silently operates on a GitHub issue. Sets the WIT_ID_* globals on success.
wit_require_github_id() {
  wit_parse_id "$1" || return 1
  [[ "$WIT_ID_PROVIDER" == "github" ]] || return 1
}

# wit_help_if_requested <usage-text> <args…> — print usage + exit 0 when the
# first arg is --help. Adapter verbs are dispatched by the core, but each is a
# standalone entry script (skill-script contract) and answers --help directly.
wit_help_if_requested() {
  local usage="$1"
  shift
  if [[ "${1:-}" == "--help" ]]; then
    printf '%s\n' "$usage"
    exit 0
  fi
}

# gh_write <gh-args…> — write op through the bot wrapper when available.
gh_write() {
  if [[ -f "$WIT_GH_BOT" ]]; then
    bash "$WIT_GH_BOT" "$@"
  else
    gh "$@"
  fi
}

# wit_map_gh_error <stderr-text> — echo the contract exit code for a failed gh call.
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

# wit_run_gh <writer:write|read> <gh-args…> — run gh (routed by writer), capture
# stdout to WIT_GH_OUT; on failure print stderr and exit with the mapped code.
wit_run_gh() {
  local writer="$1" err rc
  shift
  local errfile
  errfile="$(mktemp)"
  if [[ "$writer" == "write" ]]; then
    WIT_GH_OUT="$(gh_write "$@" 2>"$errfile")"
  else
    WIT_GH_OUT="$(gh "$@" 2>"$errfile")"
  fi
  rc=$?
  err="$(cat "$errfile")"
  rm -f "$errfile"
  if ((rc != 0)); then
    printf '%s\n' "$err" >&2
    exit "$(wit_map_gh_error "$err")"
  fi
  WIT_GH_OUT="$(printf '%s' "$WIT_GH_OUT" | wit_strip_cr)"
}

# wit_resolve_repo <--repo value or empty> — echo owner/repo (explicit override or
# derived from the CWD git remote per CONTRACT.md "Setup (binding file)").
wit_resolve_repo() {
  local explicit="${1:-}"
  if [[ -n "$explicit" ]]; then
    printf '%s\n' "$explicit"
    return 0
  fi
  wit_run_gh read repo view --json owner,name --jq '.owner.login + "/" + .name'
  printf '%s\n' "$WIT_GH_OUT"
}

# wit_issue_url <owner> <repo> <number>
wit_issue_url() {
  printf 'https://github.com/%s/%s/issues/%s\n' "$1" "$2" "$3"
}

# shellcheck disable=SC2016  # jq program — $sv/$or are jq variables, not bash expansions
readonly WIT_ITEM_JQ='{
  schema_version: $sv,
  id: ("github:" + $or + "#" + (.number | tostring)),
  title: .title,
  state: (.state | ascii_downcase),
  assignees: [(.assignees // [])[] | .login],
  labels: [(.labels // [])[] | .name],
  type: (.issueType.name // null),
  blocked_by_count: ([(.blockedBy.nodes // [])[] | select(.state == "OPEN")] | length),
  parent_id: (
    if (.parent // null) != null and (.parent.url // null) != null
    then (.parent.url
          | capture("github.com/(?<o>[^/]+)/(?<r>[^/]+)/issues/(?<n>[0-9]+)")
          | "github:" + .o + "/" + .r + "#" + .n)
    else null
    end),
  url: .url
}'

# wit_emit_item <owner> <repo> <number> — fetch the issue and emit the normalized
# item object (CONTRACT.md "JSON output contract"). blocked_by_count counts OPEN
# blockers only (closed blockers stay in blockedBy.totalCount — Tier-0 verified).
wit_emit_item() {
  local owner="$1" repo="$2" number="$3"
  wit_run_gh read issue view "$number" -R "$owner/$repo" \
    --json number,title,state,assignees,labels,issueType,blockedBy,parent,url
  printf '%s\n' "$WIT_GH_OUT" | jq -c --arg sv "$WIT_SCHEMA_VERSION" --arg or "$owner/$repo" "$WIT_ITEM_JQ"
}

# wit_list_lease_comments <owner> <repo> <number> — JSON array of
# {id, node_id, body, created_at} for lease-marker comments, ascending id.
wit_list_lease_comments() {
  local owner="$1" repo="$2" number="$3"
  wit_run_gh read api --paginate "repos/$owner/$repo/issues/$number/comments" \
    --jq '[.[] | select(.body | startswith("<!-- work-item-lease v1")) | {id, node_id, body, created_at}]'
  printf '%s\n' "$WIT_GH_OUT" | jq -c -s 'add // []'
}
