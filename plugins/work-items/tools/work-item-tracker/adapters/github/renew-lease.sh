#!/usr/bin/env bash
# renew-lease <id> --lease-comment-id <n> — CONTRACT.md "Lease protocol". Edits the
# lease comment in place (renewed_at bump). The PATCH identity must match the comment
# author, so it routes through the same writer that posted it (bot).
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

usage='usage: renew-lease <id> --lease-comment-id <n>'
wit_help_if_requested "$usage" "$@"

id="${1:-}"
[[ -n "$id" ]] || wit_usage_error "$usage"
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
wit_require_github_id "$id" || wit_usage_error "malformed or non-github id: $id"
[[ "$lease_comment_id" =~ ^[0-9]+$ ]] || wit_usage_error "--lease-comment-id must be numeric"

owner="$WIT_ID_OWNER" repo="$WIT_ID_REPO" number="$WIT_ID_NUMBER"

# The comment REST path is repo + comment id, not issue-scoped, so a stale or
# cross-issue handle would otherwise renew a different item's lease and report
# success for $id.
wit_run_gh read api "repos/$owner/$repo/issues/comments/$lease_comment_id" \
  --jq '{body, issue: (.issue_url | capture("/issues/(?<n>[0-9]+)$") | .n)}'
comment_issue="$(jq -r '.issue // empty' <<<"$WIT_GH_OUT")"
if [[ "$comment_issue" != "$number" ]]; then
  printf 'renew-lease: comment %s belongs to issue #%s, not #%s\n' \
    "$lease_comment_id" "${comment_issue:-unknown}" "$number" >&2
  exit "$EX_CONFLICT"
fi
lease_json="$(wit_lease_json "$(jq -r '.body' <<<"$WIT_GH_OUT")")"
if [[ -z "$lease_json" ]]; then
  printf 'renew-lease: comment %s is not a work-item lease\n' "$lease_comment_id" >&2
  exit "$EX_CONFLICT"
fi
if [[ -n "$(jq -r '.superseded_at // empty' <<<"$lease_json")" ]]; then
  printf 'renew-lease: lease %s is superseded\n' "$lease_comment_id" >&2
  exit "$EX_CONFLICT"
fi

# An expired lease is never revived, e.g. a crashed or delayed holder that never
# backed off: that would undo a handoff another worker made on expiry; recovery is a
# fresh claim or reclaim.
if ! wit_lease_is_live "$lease_json" "$(date -u +%s)"; then
  printf 'renew-lease: lease %s is expired (renewed_at + ttl_hours elapsed); not renewing\n' \
    "$lease_comment_id" >&2
  exit "$EX_CONFLICT"
fi

# Live is not enough: the holder is the earliest live lease (claim step 4). A newer
# live lease is a claimant that has not backed off yet and does not stop the renew.
leases="$(wit_list_lease_comments "$owner" "$repo" "$number")" || exit "$?"
now_epoch="$(date -u +%s)"
wit_lease_winner "$leases" "$now_epoch" "$lease_comment_id" wit_lease_released_by_run
if [[ "$WIT_WINNER_ID" != "$lease_comment_id" ]]; then
  printf 'renew-lease: comment %s is outranked by the earlier live lease, comment %s\n' \
    "$lease_comment_id" "${WIT_WINNER_ID:-none}" >&2
  exit "$EX_CONFLICT"
fi

# Within the skew margin of expiry, a newer claimant may already have found this lease
# expired and started; renewing would then revive the lease that outranks it. There the
# lease must also be the newest non-superseded one.
expires_epoch=$(($(wit_iso_to_epoch "$(jq -r '.renewed_at' <<<"$lease_json")") + $(wit_lease_ttl_seconds "$lease_json")))
if ((expires_epoch - now_epoch <= WIT_LEASE_SKEW_SECONDS)); then
  wit_select_active_lease "$leases"
  if [[ "$WIT_ACTIVE_LEASE_ID" != "$lease_comment_id" ]]; then
    printf 'renew-lease: lease %s expires within %s s and a newer lease (comment %s) is pending; not renewing\n' \
      "$lease_comment_id" "$WIT_LEASE_SKEW_SECONDS" "$WIT_ACTIVE_LEASE_ID" >&2
    exit "$EX_CONFLICT"
  fi
fi

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
renewed="$(jq -c --arg ts "$now" '. + {renewed_at: $ts}' <<<"$lease_json")"
wit_patch_lease_comment "$owner" "$repo" "$lease_comment_id" "$renewed"

# A superseded lease is out of reclaim's reach, so a back-off hands its holder's assignee back.
back_off() {
  wit_try_supersede_lease_comment "$owner" "$repo" "$lease_comment_id" "$renewed"
  wit_hand_back_assignee "$owner" "$repo" "$number" "$(jq -r '.holder // empty' <<<"$renewed")" "$lease_comment_id"
  printf 'renew-lease: lease %s: %s; lease superseded\n' "$lease_comment_id" "$1" >&2
  exit "$EX_CONFLICT"
}

# A PATCH that returns after the old expiry may have revived an expired lease, and a
# same-login claimant that lost to it meanwhile removes the shared assignee: never kept.
# Within the margin the checks above saw only leases posted before their read; a claimant
# that found this lease expired before the PATCH landed posted before it, so a list read
# now shows it, and one posting later sees the renewed lease and backs off. Earlier than
# that nobody can have found the lease expired. A failed read keeps the lease, as
# wit_lease_released_by_run does.
after_epoch="$(date -u +%s)"
if ((after_epoch >= expires_epoch)); then
  back_off "it expired before the renew landed"
elif ((after_epoch >= expires_epoch - WIT_LEASE_SKEW_SECONDS)); then
  if leases="$(wit_list_lease_comments "$owner" "$repo" "$number")" ||
    leases="$(wit_list_lease_comments "$owner" "$repo" "$number")"; then
    ! wit_newer_live_lease "$leases" "$after_epoch" "$lease_comment_id" ||
      back_off "the renew landed too close to expiry and a newer claimant holds"
  else
    printf 'renew-lease: could not re-read the leases after the renew; lease kept\n' >&2
  fi
fi

jq -c --arg sv "$WIT_SCHEMA_VERSION" --arg id "$id" --arg cid "$lease_comment_id" \
  '{schema_version: $sv, id: $id, holder: .holder, acquired_at: .acquired_at,
    renewed_at: .renewed_at, ttl_hours: .ttl_hours,
    lease_comment_id: ($cid | tonumber), session_id: (.session_id // null)}' <<<"$renewed"
