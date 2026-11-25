#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

USAGE='usage: renew-lease.sh <id> --lease-comment-id <n>'
wit_help_if_requested "$USAGE" "$@"

ID="${1:-}"
[[ -n "$ID" ]] || wit_usage_error "$USAGE"
shift
LEASE_COMMENT_ID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --lease-comment-id)
    [[ $# -ge 2 ]] || wit_usage_error "--lease-comment-id needs a value"
    LEASE_COMMENT_ID="$2"
    shift 2
    ;;
  *) wit_usage_error "unexpected argument: $1" ;;
  esac
done
wit_require_linear_id "$ID" || wit_usage_error "not a linear item id: $ID"
[[ "$LEASE_COMMENT_ID" =~ ^[0-9]+$ ]] || wit_usage_error "--lease-comment-id is required and must be numeric"

wit_need_linear_config
wit_linear_require_scoped_id "$ID"

wit_linear_fetch_issue "$WIT_LINEAR_TEAM" "$WIT_ID_NUMBER"
ISSUE_UUID="$(jq -r '.id' <<<"$WIT_LINEAR_ISSUE")"

ENTRIES="$(wit_linear_lease_comments "$ISSUE_UUID")" || exit "$?"
MATCH="$(jq -c --argjson h "$LEASE_COMMENT_ID" '[.[] | select(.handle == $h)][0] // empty' <<<"$ENTRIES")"
if [[ -z "$MATCH" ]]; then
  printf 'linear: no lease with handle %s on %s\n' "$LEASE_COMMENT_ID" "$ID" >&2
  exit "$EX_CONFLICT"
fi

LEASE="$(jq -c '.lease' <<<"$MATCH")"
COMMENT_UUID="$(jq -r '.comment_id' <<<"$MATCH")"

if ! wit_linear_lease_live "$LEASE"; then
  if [[ -n "$(jq -r '.superseded_at // empty' <<<"$LEASE")" ]]; then
    printf 'linear: lease %s on %s was superseded — claim again rather than renewing\n' \
      "$LEASE_COMMENT_ID" "$ID" >&2
  else
    printf 'linear: lease %s on %s has expired — reclaim or claim again; a renew would undo a TTL handoff\n' \
      "$LEASE_COMMENT_ID" "$ID" >&2
  fi
  exit "$EX_CONFLICT"
fi

while IFS=$'\t' read -r ehandle earlier_lease; do
  if [[ -z "$ehandle" ]] || ! wit_linear_lease_live "$earlier_lease"; then continue; fi
  printf 'linear: lease %s on %s is outranked by the earlier live lease %s; not renewing\n' \
    "$LEASE_COMMENT_ID" "$ID" "$ehandle" >&2
  exit "$EX_CONFLICT"
done < <(jq -r --argjson h "$LEASE_COMMENT_ID" --arg c "$COMMENT_UUID" \
  '.[] | select(.handle < $h or (.handle == $h and .comment_id < $c)) | "\(.handle)\t\(.lease | tojson)"' <<<"$ENTRIES")

RENEWED="$(jq -c --arg t "$(wit_linear_now_iso)" '. + {renewed_at: $t}' <<<"$LEASE")"
wit_linear_update_comment "$COMMENT_UUID" "$(wit_linear_lease_marker "$RENEWED")"

jq -cn --arg sv "$WIT_SCHEMA_VERSION" --arg id "$ID" --argjson lease "$RENEWED" \
  '{schema_version: $sv, id: $id, holder: $lease.holder,
    acquired_at: $lease.acquired_at, renewed_at: $lease.renewed_at,
    ttl_hours: $lease.ttl_hours, ttl_minutes: ($lease.ttl_minutes // 0),
    lease_comment_id: $lease.lease_comment_id,
    session_id: ($lease.session_id // null)}'
