#!/usr/bin/env bash
# renew-lease <id> --lease-comment-id <n> — CONTRACT.md "Lease protocol". Bumps
# renewed_at in place on the addressed lease. The handle is store-global, so a
# stale or cross-item handle would otherwise renew a DIFFERENT item's lease and
# report success for <id>; the handle's owning item is verified against <id> first.
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

wit_help_if_requested "usage: renew-lease <id> --lease-comment-id <n>" "$@"

id="${1:-}"
[[ -n "$id" ]] || wit_usage_error "usage: renew-lease <id> --lease-comment-id <n>"
shift
lease_comment_id=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --lease-comment-id)
      [[ $# -ge 2 ]] || wit_usage_error "--lease-comment-id needs a value"
      lease_comment_id="$2"
      shift 2
      ;;
    *) wit_usage_error "unknown argument: $1" ;;
  esac
done
wit_require_local_id "$id" || wit_usage_error "malformed or non-local-markdown id: $id"
[[ "$lease_comment_id" =~ ^[0-9]+$ ]] || wit_usage_error "--lease-comment-id must be numeric"

wit_need_storage
number="$WIT_ID_NUMBER"

found="$(wit_find_lease_file "$lease_comment_id")" || {
  printf 'renew-lease: no lease with handle %s\n' "$lease_comment_id" >&2
  exit "$EX_CONFLICT"
}
lease_number="${found%%$'\t'*}"
old_line="${found#*$'\t'}"

if [[ "$lease_number" != "$number" ]]; then
  printf 'renew-lease: lease %s belongs to item #%s, not #%s\n' \
    "$lease_comment_id" "$lease_number" "$number" >&2
  exit "$EX_CONFLICT"
fi

file="$(wit_item_file "$number")"
lease_json="$(wit_lease_json "$old_line")"

# The addressed lease must BE the active lease (newest non-superseded). A
# superseded/older handle renewing would resurrect a lease its owner no longer holds.
active_id="$(jq -r '.lease_comment_id // empty' <<<"$(wit_active_lease_json "$file")")"
if [[ "$active_id" != "$lease_comment_id" ]]; then
  printf 'renew-lease: lease %s is not the active lease (active: %s)\n' \
    "$lease_comment_id" "${active_id:-none}" >&2
  exit "$EX_CONFLICT"
fi

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
renewed="$(jq -c --arg ts "$now" '. + {renewed_at: $ts}' <<<"$lease_json")"
new_line="${WIT_LEASE_MARKER}${renewed} -->"

tmp="$(mktemp)"
awk -v old="$old_line" -v new="$new_line" '$0 == old { print new; next } { print }' "$file" >"$tmp" && mv "$tmp" "$file"

jq -c --arg sv "$WIT_SCHEMA_VERSION" --arg id "$id" --arg cid "$lease_comment_id" \
  '{schema_version: $sv, id: $id, holder: .holder, acquired_at: .acquired_at,
    renewed_at: .renewed_at, ttl_hours: .ttl_hours,
    lease_comment_id: ($cid | tonumber), session_id: (.session_id // null)}' <<<"$renewed"
