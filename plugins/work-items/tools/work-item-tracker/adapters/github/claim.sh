#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

usage='usage: claim <id> [--ttl-hours <n>] [--ttl-minutes <n>] [--session-id <s>] [--holder <h>] [--lease-only] [--phase <kind>]
  --ttl-minutes (0-59) adds to --ttl-hours; for a sub-hour lease pass --ttl-hours 0
  --holder names the lease holder instead of the authenticated login
  --lease-only posts the lease comment and assigns no one
  --phase (triage, discovery or implementation) records the work the lease is for; absent means implementation'
wit_help_if_requested "$usage" "$@"

ttl="${WIT_LEASE_TTL_HOURS:-}" ttl_minutes="${WIT_LEASE_TTL_MINUTES:-0}" session_id="" holder="" lease_only=false phase=""
id="${1:-}"
[[ -n "$id" ]] || wit_usage_error "$usage"
shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ttl-hours)
      [[ $# -ge 2 ]] || wit_usage_error "--ttl-hours needs a value"
      ttl="$2"
      shift 2
      ;;
    --ttl-minutes)
      [[ $# -ge 2 ]] || wit_usage_error "--ttl-minutes needs a value"
      ttl_minutes="$2"
      shift 2
      ;;
    --session-id)
      [[ $# -ge 2 ]] || wit_usage_error "--session-id needs a value"
      session_id="$2"
      shift 2
      ;;
    --holder)
      [[ $# -ge 2 && -n "$2" ]] || wit_usage_error "--holder needs a value"
      holder="$2"
      shift 2
      ;;
    --lease-only)
      lease_only=true
      shift
      ;;
    --phase)
      [[ $# -ge 2 && -n "$2" ]] || wit_usage_error "--phase needs a value"
      phase="$2"
      shift 2
      ;;
    *) wit_usage_error "unknown argument: $1" ;;
  esac
done
wit_require_github_id "$id" || wit_usage_error "malformed or non-github id: $id"
[[ -z "$phase" ]] || wit_lease_phase_valid "$phase" || wit_usage_error "--phase must be triage, discovery or implementation"
[[ "$ttl" =~ ^[0-9]+$ ]] || wit_usage_error "--ttl-hours must be a non-negative integer (binding config.lease_ttl_hours supplies the default)"
if ! [[ "$ttl_minutes" =~ ^[0-9]{1,2}$ ]] || ((10#$ttl_minutes > 59)); then
  wit_usage_error "--ttl-minutes must be 0-59 (binding config.lease_ttl_minutes defaults to 0)"
fi
wit_lease_ttl_within_cap "$ttl" "$ttl_minutes" || wit_usage_error "--ttl-hours plus --ttl-minutes must not exceed the ${WIT_LEASE_MAX_TTL_HOURS} h lease cap; a longer lease is never live"

owner="$WIT_ID_OWNER" repo="$WIT_ID_REPO" number="$WIT_ID_NUMBER"

if [[ -n "$holder" ]]; then
  login="$holder"
else
  wit_run_gh read api user --jq .login
  login="$WIT_GH_OUT"
fi

if [[ "$lease_only" == false ]]; then
  _wit_claim_rollback() {
    wit_hand_back_assignee "$owner" "$repo" "$number" "$login" "${our_comment_id:-}"
  }
  trap _wit_claim_rollback EXIT

  wit_add_assignee read "$owner" "$repo" "$number" "$login"

  wit_read_assignees "$owner" "$repo" "$number"
  assignees="$WIT_GH_OUT"
  if ! jq -e --arg me "$login" 'any(.[]; . == $me)' <<<"$assignees" >/dev/null; then
    wit_add_assignee read "$owner" "$repo" "$number" "$login"
    wit_read_assignees "$owner" "$repo" "$number"
    assignees="$WIT_GH_OUT"
  fi
  if ! jq -e --arg me "$login" 'any(.[]; . == $me)' <<<"$assignees" >/dev/null; then
    printf 'claim: assignment of %s did not take effect (insufficient permission to self-assign on %s/%s)\n' \
      "$login" "$owner" "$repo" >&2
    exit "$EX_AUTH"
  fi
  other="$(jq -r --arg me "$login" '[.[] | select(. != $me)] | first // empty' <<<"$assignees")"
  if [[ -n "$other" ]]; then
    printf 'claim: item already claimed by %s\n' "$other" >&2
    exit "$EX_CONFLICT"
  fi
fi

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
lease="$(jq -cn --arg sv "$WIT_SCHEMA_VERSION" --arg holder "$login" --arg now "$now" \
  --arg ttl "$ttl" --arg ttl_minutes "$ttl_minutes" --arg sid "$session_id" --arg phase "$phase" \
  '{schema_version: $sv, holder: $holder, acquired_at: $now, renewed_at: $now,
    ttl_hours: ($ttl | tonumber)}
   + (if ($ttl_minutes | tonumber) > 0 then {ttl_minutes: ($ttl_minutes | tonumber)} else {} end)
   + (if $sid != "" then {session_id: $sid} else {} end)
   + (if $phase != "" then {phase: $phase} else {} end)')"
footer="" run_id="${session_id#run-}"
if [[ "$session_id" == "run-$run_id" && "$run_id" =~ ^[1-9][0-9]{0,19}$ && "${GITHUB_SERVER_URL:-}" =~ ^https://[A-Za-z0-9.-]+$ ]]; then
  footer=$'\n\n'"Claimed by [workflow run $run_id](${GITHUB_SERVER_URL}/$owner/$repo/actions/runs/$run_id)."
fi
wit_run_gh write api "repos/$owner/$repo/issues/$number/comments" \
  -f body="${WIT_LEASE_MARKER}${lease} -->${footer}" --jq '.id'
our_comment_id="$WIT_GH_OUT"

_wit_claim_abort() {
  wit_try_supersede_lease_comment "$owner" "$repo" "$our_comment_id" "$lease"
  [[ "$lease_only" == true ]] || _wit_claim_rollback
}
trap _wit_claim_abort EXIT

leases="$(wit_list_lease_comments "$owner" "$repo" "$number")" || exit "$?"
wit_lease_winner "$leases" "$(date -u +%s)" "$our_comment_id" wit_lease_released_by_run
winner_id="$WIT_WINNER_ID"
winner_holder=""
[[ -z "$WIT_WINNER_JSON" ]] || winner_holder="$(jq -r '.holder // empty' <<<"$WIT_WINNER_JSON")"

if [[ -n "$winner_id" && "$winner_id" != "$our_comment_id" ]]; then
  printf 'claim: live lease (comment %s, holder %s) wins — backing off\n' \
    "$winner_id" "$(tr -d '[:cntrl:]' <<<"${winner_holder:-unknown}")" >&2
  exit "$EX_CONFLICT"
fi

if [[ "$lease_only" == false ]]; then
  wit_read_assignees "$owner" "$repo" "$number"
  if ! jq -e --arg me "$login" 'any(.[]; . == $me)' <<<"$WIT_GH_OUT" >/dev/null; then
    wit_add_assignee read "$owner" "$repo" "$number" "$login"
  fi
fi

trap - EXIT
jq -cn --arg sv "$WIT_SCHEMA_VERSION" --arg id "$id" --arg holder "$login" \
  --arg now "$now" --arg ttl "$ttl" --arg cid "$our_comment_id" --arg sid "$session_id" \
  '{schema_version: $sv, id: $id, holder: $holder, acquired_at: $now, renewed_at: $now,
    ttl_hours: ($ttl | tonumber), lease_comment_id: ($cid | tonumber),
    session_id: (if $sid != "" then $sid else null end)}'
