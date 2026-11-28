#!/usr/bin/env bash
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

if [[ -n "$holder_override" ]]; then
  login="$holder_override"
else
  wit_run_gh read api user --jq .login
  login="$WIT_GH_OUT"
fi
holder="$(jq -r '.holder // empty' <<<"$lease_json")"

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

wit_lease_winner "$leases" "$now_epoch" "$lease_comment_id" wit_lease_released_by_run
if [[ "$WIT_WINNER_ID" != "$lease_comment_id" ]]; then
  outcome="lease superseded"
  if wit_try_supersede_lease_comment "$owner" "$repo" "$lease_comment_id" "$lease_json" ||
    wit_try_supersede_lease_comment "$owner" "$repo" "$lease_comment_id" "$lease_json"; then
    wit_hand_back_assignee "$owner" "$repo" "$number" "$login" "$lease_comment_id"
  else
    outcome="could not supersede the lease, assignee kept"
  fi
  printf 'release: comment %s is outranked by the earlier live lease, comment %s; %s\n' \
    "$lease_comment_id" "${WIT_WINNER_ID:-none}" "$outcome" >&2
  exit "$EX_CONFLICT"
fi

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
released="$(jq -c --arg ts "$now" '. + {superseded_at: $ts}' <<<"$lease_json")"
wit_patch_lease_comment "$owner" "$repo" "$lease_comment_id" "$released"
hand_back true "live lease released"
