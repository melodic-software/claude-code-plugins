#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

USAGE='usage: claim.sh <id> [--ttl-hours <n>] [--ttl-minutes <n>] [--session-id <s>]
  --ttl-minutes (0-59) adds to --ttl-hours; for a sub-hour lease pass --ttl-hours 0'
wit_help_if_requested "$USAGE" "$@"

ID="${1:-}"
[[ -n "$ID" ]] || wit_usage_error "$USAGE"
shift
TTL_HOURS=""
TTL_MINUTES=""
SESSION_ID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --ttl-hours | --ttl-minutes | --session-id)
    [[ $# -ge 2 ]] || wit_usage_error "$1 needs a value"
    case "$1" in
    --ttl-hours) TTL_HOURS="$2" ;;
    --ttl-minutes) TTL_MINUTES="$2" ;;
    *) SESSION_ID="$2" ;;
    esac
    shift 2
    ;;
  *) wit_usage_error "unexpected argument: $1" ;;
  esac
done
wit_require_linear_id "$ID" || wit_usage_error "not a linear item id: $ID"
[[ -z "$TTL_HOURS" || "$TTL_HOURS" =~ ^[0-9]+$ ]] || wit_usage_error "--ttl-hours must be a non-negative integer"
[[ -z "$TTL_MINUTES" || "$TTL_MINUTES" =~ ^[0-9]+$ ]] || wit_usage_error "--ttl-minutes must be a non-negative integer"

wit_need_linear_config
wit_linear_require_scoped_id "$ID"

TTL_HOURS="${TTL_HOURS:-$WIT_LINEAR_LEASE_TTL_HOURS}"
TTL_MINUTES="${TTL_MINUTES:-$WIT_LINEAR_LEASE_TTL_MINUTES}"

wit_linear_resolve_viewer
HOLDER="$WIT_LINEAR_VIEWER"
wit_linear_fetch_issue "$WIT_LINEAR_TEAM" "$WIT_ID_NUMBER"
ISSUE_UUID="$(jq -r '.id' <<<"$WIT_LINEAR_ISSUE")"

EXISTING="$(wit_linear_lease_comments "$ISSUE_UUID")" || exit "$?"
while IFS= read -r entry; do
  [[ -n "$entry" ]] || continue
  lease="$(jq -c '.lease' <<<"$entry")"
  wit_linear_lease_live "$lease" || continue
  other="$(jq -r '.holder // ""' <<<"$lease")"
  printf 'linear: %s is already claimed by %s (live lease) — not claiming\n' "$ID" "$other" >&2
  exit "$EX_CONFLICT"
done < <(jq -c '.[]' <<<"$EXISTING")

wit_linear_set_assignee "$ISSUE_UUID" "$WIT_LINEAR_VIEWER_ID"

COMMENT_UUID=""

_wit_linear_other_live_lease() {
  local entry
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    [[ "$(jq -r '.comment_id' <<<"$entry")" != "$COMMENT_UUID" ]] || continue
    wit_linear_lease_live "$(jq -c '.lease' <<<"$entry")" && return 0
  done < <(jq -c '.[]' <<<"$1")
  return 1
}

_wit_linear_claim_rollback() {
  (
    _rb="$(wit_linear_lease_comments "$ISSUE_UUID")" || exit 0
    _wit_linear_other_live_lease "$_rb" && exit 0
    wit_linear_fetch_issue "$WIT_LINEAR_TEAM" "$WIT_ID_NUMBER"
    [[ "$(jq -r '.assignee.displayName // .assignee.email // ""' <<<"$WIT_LINEAR_ISSUE")" == "$HOLDER" ]] || exit 0
    wit_linear_set_assignee "$ISSUE_UUID" ""
  ) >/dev/null 2>&1 || true
}
trap _wit_linear_claim_rollback EXIT

NOW="$(wit_linear_now_iso)"
PROVISIONAL="$(jq -cn --arg sv "$WIT_SCHEMA_VERSION" --arg h "$HOLDER" --arg t "$NOW" \
  --argjson th "$TTL_HOURS" --argjson tm "$TTL_MINUTES" --arg s "$SESSION_ID" \
  '{schema_version: $sv, holder: $h, acquired_at: $t, renewed_at: $t,
    ttl_hours: $th, ttl_minutes: $tm}
   + (if ($s | length) > 0 then {session_id: $s} else {} end)')"
POSTED="$(wit_linear_post_comment "$ISSUE_UUID" "$(wit_linear_lease_marker "$PROVISIONAL")")" || exit "$?"
COMMENT_UUID="$(jq -r '.id' <<<"$POSTED")"
HANDLE="$(wit_linear_handle "$(jq -r '.createdAt' <<<"$POSTED")")"

LEASE="$(jq -c --argjson h "$HANDLE" '. + {lease_comment_id: $h}' <<<"$PROVISIONAL")"
wit_linear_update_comment "$COMMENT_UUID" "$(wit_linear_lease_marker "$LEASE")"

AFTER="$(wit_linear_lease_comments "$ISSUE_UUID")" || exit "$?"
LOSER=""
while IFS= read -r entry; do
  [[ -n "$entry" ]] || continue
  cid="$(jq -r '.comment_id' <<<"$entry")"
  [[ "$cid" != "$COMMENT_UUID" ]] || continue
  lease="$(jq -c '.lease' <<<"$entry")"
  wit_linear_lease_live "$lease" || continue
  ehandle="$(jq -r '.handle' <<<"$entry")"
  if ((ehandle < HANDLE)) || { ((ehandle == HANDLE)) && [[ "$cid" < "$COMMENT_UUID" ]]; }; then
    LOSER="$(jq -r '.holder // "another session"' <<<"$lease")"
    break
  fi
done < <(jq -c '.[]' <<<"$AFTER")

if [[ -n "$LOSER" ]]; then
  trap - EXIT
  SUPERSEDED="$(jq -c --arg t "$(wit_linear_now_iso)" '. + {superseded_at: $t}' <<<"$LEASE")"
  wit_linear_update_comment "$COMMENT_UUID" "$(wit_linear_lease_marker "$SUPERSEDED")"
  LOSER_LIVE=""
  wit_linear_fetch_issue "$WIT_LINEAR_TEAM" "$WIT_ID_NUMBER"
  if AFTER2="$(wit_linear_lease_comments "$ISSUE_UUID")"; then
    _wit_linear_other_live_lease "$AFTER2" && LOSER_LIVE="yes"
  else
    LOSER_LIVE="unknown"
    printf 'linear: could not re-read lease state on %s — leaving the assignee alone rather than risking a live claim\n' "$ID" >&2
  fi
  if [[ -z "$LOSER_LIVE" ]] &&
    [[ "$(jq -r '.assignee.displayName // .assignee.email // ""' <<<"$WIT_LINEAR_ISSUE")" == "$HOLDER" ]]; then
    wit_linear_set_assignee "$ISSUE_UUID" ""
  fi
  printf 'linear: lost the claim race on %s to %s — backed off\n' "$ID" "$LOSER" >&2
  exit "$EX_CONFLICT"
fi

trap - EXIT

jq -cn --arg sv "$WIT_SCHEMA_VERSION" --arg id "$ID" --argjson lease "$LEASE" \
  '{schema_version: $sv, id: $id, holder: $lease.holder,
    acquired_at: $lease.acquired_at, renewed_at: $lease.renewed_at,
    ttl_hours: $lease.ttl_hours, ttl_minutes: $lease.ttl_minutes,
    lease_comment_id: $lease.lease_comment_id,
    session_id: ($lease.session_id // null)}'
