#!/usr/bin/env bash
# renew-lease <id> --lease-comment-id <n> — CONTRACT.md "Lease protocol". Edits the
# lease comment in place (renewed_at bump). The PATCH identity must match the comment
# author, so it routes through the same writer that posted it (bot).
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
wit_require_github_id "$id" || wit_usage_error "malformed or non-github id: $id"
[[ "$lease_comment_id" =~ ^[0-9]+$ ]] || wit_usage_error "--lease-comment-id must be numeric"

owner="$WIT_ID_OWNER" repo="$WIT_ID_REPO" number="$WIT_ID_NUMBER"

# The comment REST path is repo + comment id, NOT issue-scoped: a stale or
# cross-issue --lease-comment-id would otherwise patch a DIFFERENT item's lease
# and report success for $id. Verify the comment's own issue number matches the
# requested item before touching it.
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
if [[ "$(jq -r '.superseded_at // empty' <<<"$lease_json")" != "" ]]; then
  printf 'renew-lease: lease %s is superseded\n' "$lease_comment_id" >&2
  exit "$EX_CONFLICT"
fi

# The comment being non-superseded is not enough: an EXPIRED-but-not-superseded
# lease can coexist with a newer active claim. Renewing it would produce two live
# lease records and let a stale session keep work it no longer owns. Require this
# comment to BE the current active lease = the newest non-superseded lease.
leases="$(wit_list_lease_comments "$owner" "$repo" "$number")" || exit "$?"
active_id=""
while IFS= read -r row; do
  [[ -n "$row" ]] || continue
  cand="$(wit_lease_json "$(jq -r '.body' <<<"$row")")"
  [[ -n "$cand" ]] || continue
  [[ "$(jq -r '.superseded_at // empty' <<<"$cand")" == "" ]] || continue
  active_id="$(jq -r '.id' <<<"$row")"
  break
done < <(jq -c 'sort_by(.id) | reverse | .[]' <<<"$leases")
if [[ "$active_id" != "$lease_comment_id" ]]; then
  printf 'renew-lease: comment %s is not the active lease (superseded by a newer claim, comment %s)\n' \
    "$lease_comment_id" "${active_id:-none}" >&2
  exit "$EX_CONFLICT"
fi

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
renewed="$(jq -c --arg ts "$now" '. + {renewed_at: $ts}' <<<"$lease_json")"
wit_run_gh write api --method PATCH "repos/$owner/$repo/issues/comments/$lease_comment_id" \
  -f body="${WIT_LEASE_MARKER}${renewed} -->" --jq '.id'

jq -c --arg sv "$WIT_SCHEMA_VERSION" --arg id "$id" --arg cid "$lease_comment_id" \
  '{schema_version: $sv, id: $id, holder: .holder, acquired_at: .acquired_at,
    renewed_at: .renewed_at, ttl_hours: .ttl_hours,
    lease_comment_id: ($cid | tonumber), session_id: (.session_id // null)}' <<<"$renewed"
