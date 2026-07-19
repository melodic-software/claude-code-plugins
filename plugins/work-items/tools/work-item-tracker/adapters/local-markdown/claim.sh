#!/usr/bin/env bash
# claim <id> [--ttl-hours <n>] [--session-id <s>] — CONTRACT.md "Lease protocol".
# Single-writer store: race arbitration is a pre-write check — an existing LIVE
# lease means the item is claimed, so back off (exit 7) before writing anything.
# The lease is an inline marker plus a store-global numeric handle (lease_comment_id)
# that renew-lease addresses the way the GitHub adapter addresses a comment id.
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

wit_help_if_requested "usage: claim <id> [--ttl-hours <n>] [--session-id <s>]" "$@"

id="${1:-}"
[[ -n "$id" ]] || wit_usage_error "usage: claim <id> [--ttl-hours <n>] [--session-id <s>]"
shift
ttl="${WIT_LEASE_TTL_HOURS:-}" session_id=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ttl-hours)
      [[ $# -ge 2 ]] || wit_usage_error "--ttl-hours needs a value"
      ttl="$2"
      shift 2
      ;;
    --session-id)
      [[ $# -ge 2 ]] || wit_usage_error "--session-id needs a value"
      session_id="$2"
      shift 2
      ;;
    *) wit_usage_error "unknown argument: $1" ;;
  esac
done
wit_require_local_id "$id" || wit_usage_error "malformed or non-local-markdown id: $id"
[[ "$ttl" =~ ^[0-9]+$ ]] || wit_usage_error "--ttl-hours must be a non-negative integer (binding config.lease_ttl_hours supplies the default)"

wit_need_storage
number="$WIT_ID_NUMBER"
file="$(wit_item_file "$number")"
[[ -f "$file" ]] || {
  printf 'claim: no item %s\n' "$id" >&2
  exit "$EX_NOT_FOUND"
}

# Pre-write race check: a live lease already present means an established claim.
now_epoch="$(date -u +%s)"
active="$(wit_active_lease_json "$file")"
if [[ -n "$active" ]] && wit_lease_is_live "$active" "$now_epoch"; then
  printf 'claim: item already claimed by %s\n' "$(jq -r '.holder // "unknown"' <<<"$active")" >&2
  exit "$EX_CONFLICT"
fi

holder="$(git config user.name 2>/dev/null || true)"
[[ -n "$holder" ]] || holder="${USER:-local}"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
lease_id="$(wit_next_lease_id)"

lease="$(jq -cn --arg sv "$WIT_SCHEMA_VERSION" --arg holder "$holder" --arg now "$now" \
  --arg ttl "$ttl" --arg sid "$session_id" --arg cid "$lease_id" \
  '{schema_version: $sv, holder: $holder, acquired_at: $now, renewed_at: $now,
    ttl_hours: ($ttl | tonumber), lease_comment_id: ($cid | tonumber)}
   + (if $sid != "" then {session_id: $sid} else {} end)')"
printf '%s%s -->\n' "$WIT_LEASE_MARKER" "$lease" >>"$file"
wit_fm_set "$file" assignees "$(jq -cn --arg h "$holder" '[$h]')"

jq -cn --arg sv "$WIT_SCHEMA_VERSION" --arg id "$id" --arg holder "$holder" \
  --arg now "$now" --arg ttl "$ttl" --arg cid "$lease_id" --arg sid "$session_id" \
  '{schema_version: $sv, id: $id, holder: $holder, acquired_at: $now, renewed_at: $now,
    ttl_hours: ($ttl | tonumber), lease_comment_id: ($cid | tonumber),
    session_id: (if $sid != "" then $sid else null end)}'
