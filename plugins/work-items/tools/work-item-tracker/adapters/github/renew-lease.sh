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

# Non-superseded is not enough: an expired lease can coexist with a newer claim, and
# renewing it would leave two live leases. Require the newest non-superseded lease.
leases="$(wit_list_lease_comments "$owner" "$repo" "$number")" || exit "$?"
wit_select_active_lease "$leases"
if [[ "$WIT_ACTIVE_LEASE_ID" != "$lease_comment_id" ]]; then
  printf 'renew-lease: comment %s is not the active lease (superseded by a newer claim, comment %s)\n' \
    "$lease_comment_id" "${WIT_ACTIVE_LEASE_ID:-none}" >&2
  exit "$EX_CONFLICT"
fi

# The active lease can still be expired, e.g. a crashed or delayed holder that never
# backed off. Reviving it would undo a handoff another worker made on expiry;
# recovery is a fresh claim or reclaim.
if ! wit_lease_is_live "$lease_json" "$(date -u +%s)"; then
  printf 'renew-lease: lease %s is expired (renewed_at + ttl_hours elapsed); not renewing\n' \
    "$lease_comment_id" >&2
  exit "$EX_CONFLICT"
fi

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
renewed="$(jq -c --arg ts "$now" '. + {renewed_at: $ts}' <<<"$lease_json")"
wit_patch_lease_comment "$owner" "$repo" "$lease_comment_id" "$renewed"

jq -c --arg sv "$WIT_SCHEMA_VERSION" --arg id "$id" --arg cid "$lease_comment_id" \
  '{schema_version: $sv, id: $id, holder: .holder, acquired_at: .acquired_at,
    renewed_at: .renewed_at, ttl_hours: .ttl_hours,
    lease_comment_id: ($cid | tonumber), session_id: (.session_id // null)}' <<<"$renewed"
