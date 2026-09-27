#!/usr/bin/env bash
# release <id> --lease-comment-id <n> — CONTRACT.md "Lease protocol". Ends the
# caller's own live lease early by adding superseded_at in place. The assignee is
# left alone; the caller clears it through the adapter's assignee edit. The PATCH
# routes through the same writer that posted the lease comment (bot).
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

usage='usage: release <id> --lease-comment-id <n>'
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
if [[ -n "$(jq -r '.superseded_at // empty' <<<"$lease_json")" ]]; then
  emit false "lease already superseded"
  exit 0
fi

# Comment ids are public, so the handle alone would let any session end another
# login's lease. Same-login sessions are told apart by the handle, as for renew-lease.
wit_run_gh read api user --jq .login
login="$WIT_GH_OUT"
holder="$(jq -r '.holder // empty' <<<"$lease_json")"
if [[ "$holder" != "$login" ]]; then
  printf 'release: lease %s is held by %s, not %s\n' \
    "$lease_comment_id" "${holder:-unknown}" "$login" >&2
  exit "$EX_CONFLICT"
fi

leases="$(wit_list_lease_comments "$owner" "$repo" "$number")" || exit "$?"
wit_select_active_lease "$leases"
if [[ "$WIT_ACTIVE_LEASE_ID" != "$lease_comment_id" ]]; then
  printf 'release: comment %s is not the active lease (active: comment %s)\n' \
    "$lease_comment_id" "${WIT_ACTIVE_LEASE_ID:-none}" >&2
  exit "$EX_CONFLICT"
fi

# An expired lease already blocks nobody; superseding it is reclaim's business,
# together with the assignee it strands.
if ! wit_lease_is_live "$lease_json" "$(date -u +%s)"; then
  emit false "lease already expired"
  exit 0
fi

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
released="$(jq -c --arg ts "$now" '. + {superseded_at: $ts}' <<<"$lease_json")"
wit_patch_lease_comment "$owner" "$repo" "$lease_comment_id" "$released"
emit true "live lease released"
