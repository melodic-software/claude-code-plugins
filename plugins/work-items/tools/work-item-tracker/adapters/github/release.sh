#!/usr/bin/env bash
# release <id> --lease-comment-id <n> [--holder <h>] — CONTRACT.md "Lease protocol". Ends the
# caller's own live lease early by adding superseded_at in place, then unassigns the
# holder unless another live lease of that holder remains. The PATCH routes through the
# same writer that posted the lease comment (bot).
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

usage='usage: release <id> --lease-comment-id <n> [--holder <h>]
  --holder names the lease holder instead of the authenticated login'
wit_help_if_requested "$usage" "$@"

id="${1:-}"
[[ -n "$id" ]] || wit_usage_error "$usage"
shift
lease_comment_id="" holder_override=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --lease-comment-id)
      [[ $# -ge 2 ]] || wit_usage_error "--lease-comment-id needs a value"
      lease_comment_id="$2"
      shift 2
      ;;
    --holder)
      [[ $# -ge 2 && -n "$2" ]] || wit_usage_error "--holder needs a value"
      holder_override="$2"
      shift 2
      ;;
    *) wit_usage_error "unknown argument: $1" ;;
  esac
done
wit_require_github_id "$id" || wit_usage_error "malformed or non-github id: $id"
[[ "$lease_comment_id" =~ ^[0-9]+$ ]] || wit_usage_error "--lease-comment-id must be numeric"

owner="$WIT_ID_OWNER" repo="$WIT_ID_REPO" number="$WIT_ID_NUMBER"

emit() {
  jq -cn --arg sv "$WIT_SCHEMA_VERSION" --arg id "$id" --arg cid "$lease_comment_id" \
    --argjson released "$1" --arg reason "$2" \
    '{schema_version: $sv, id: $id, lease_comment_id: ($cid | tonumber),
      released: $released, reason: $reason}'
}

# The comment REST path is repo + comment id, not issue-scoped, so a stale or
# cross-issue handle would otherwise supersede a different item's lease.
wit_run_gh read api "repos/$owner/$repo/issues/comments/$lease_comment_id" \
  --jq '{body, issue: (.issue_url | capture("/issues/(?<n>[0-9]+)$") | .n)}'
comment_issue="$(jq -r '.issue // empty' <<<"$WIT_GH_OUT")"
if [[ "$comment_issue" != "$number" ]]; then
  printf 'release: comment %s belongs to issue #%s, not #%s\n' \
    "$lease_comment_id" "${comment_issue:-unknown}" "$number" >&2
  exit "$EX_CONFLICT"
fi
lease_json="$(wit_lease_json "$(jq -r '.body' <<<"$WIT_GH_OUT")")"
if [[ -z "$lease_json" ]]; then
  printf 'release: comment %s is not a work-item lease\n' "$lease_comment_id" >&2
  exit "$EX_CONFLICT"
fi

# Comment ids are public, so the handle alone would let any session end another
# login's lease. Same-login sessions are told apart by the handle, as for renew-lease.
# --holder stands in for the login where `gh api user` cannot run (an installation token).
if [[ -n "$holder_override" ]]; then
  login="$holder_override"
else
  wit_run_gh read api user --jq .login
  login="$WIT_GH_OUT"
fi
holder="$(jq -r '.holder // empty' <<<"$lease_json")"

# Every exit-0 path for the caller's own lease hands the assignee back too, since the caller
# relies on release for it; another login's superseded lease exits 0 with no write.
hand_back() {
  [[ "$holder" == "$login" ]] && wit_hand_back_assignee "$owner" "$repo" "$number" "$login" "$lease_comment_id"
  emit "$1" "$2"
  exit 0
}

if [[ -n "$(jq -r '.superseded_at // empty' <<<"$lease_json")" ]]; then
  [[ "$holder" == "$login" ]] || {
    emit false "lease already superseded"
    exit 0
  }
  hand_back false "lease already superseded"
fi

if [[ "$holder" != "$login" ]]; then
  printf 'release: lease %s is held by %s, not %s\n' \
    "$lease_comment_id" "${holder:-unknown}" "$login" >&2
  exit "$EX_CONFLICT"
fi

leases="$(wit_list_lease_comments "$owner" "$repo" "$number")" || exit "$?"
now_epoch="$(date -u +%s)"

# An expired lease already blocks nobody; superseding it is reclaim's business. It is
# still refused under a newer non-superseded lease, as a stale handle, and the assignee
# goes back unless that lease or another live one is this login's.
if ! wit_lease_is_live "$lease_json" "$now_epoch"; then
  wit_select_active_lease "$leases"
  if [[ "$WIT_ACTIVE_LEASE_ID" != "$lease_comment_id" ]]; then
    wit_hand_back_assignee "$owner" "$repo" "$number" "$login" "$lease_comment_id"
    printf 'release: comment %s is not the active lease (active: comment %s)\n' \
      "$lease_comment_id" "${WIT_ACTIVE_LEASE_ID:-none}" >&2
    exit "$EX_CONFLICT"
  fi
  hand_back false "lease already expired"
fi

# The holder is the earliest live lease (claim step 4); a newer live lease is a claimant
# that has not backed off yet and does not stop the holder's release.
wit_lease_winner "$leases" "$now_epoch" "$lease_comment_id" wit_lease_released_by_run
if [[ "$WIT_WINNER_ID" != "$lease_comment_id" ]]; then
  printf 'release: comment %s is outranked by the earlier live lease, comment %s\n' \
    "$lease_comment_id" "${WIT_WINNER_ID:-none}" >&2
  exit "$EX_CONFLICT"
fi

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
released="$(jq -c --arg ts "$now" '. + {superseded_at: $ts}' <<<"$lease_json")"
wit_patch_lease_comment "$owner" "$repo" "$lease_comment_id" "$released"
hand_back true "live lease released"
