#!/usr/bin/env bash
# reclaim <id> — CONTRACT.md "Lease protocol". Idempotent session-start reclaim:
# expired lease + no activity → unassign the lease holder only, supersede lease,
# note; activity → renew in place. Never touches a live lease, a co-assignee that
# does not hold the expired lease, or a manual (lease-less) assignment.
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

wit_help_if_requested "usage: reclaim <id>" "$@"

id="${1:-}"
[[ -n "$id" && $# -eq 1 ]] || wit_usage_error "usage: reclaim <id>"
wit_require_github_id "$id" || wit_usage_error "malformed or non-github id: $id"
owner="$WIT_ID_OWNER" repo="$WIT_ID_REPO" number="$WIT_ID_NUMBER"

emit() {
  jq -cn --arg sv "$WIT_SCHEMA_VERSION" --arg id "$id" --argjson reclaimed "$1" --arg reason "$2" \
    '{schema_version: $sv, id: $id, reclaimed: $reclaimed, reason: $reason}'
  exit 0
}

# $() swallows wit_run_gh's exit-on-error; propagate so a transient API failure
# is not misreported as "no lease record" (which would let reclaim proceed).
leases="$(wit_list_lease_comments "$owner" "$repo" "$number")" || exit "$?"

# Select the ACTIVE lease = newest NON-superseded lease comment (not blind `last`:
# a back-off supersedes its own newer comment, so the highest-id comment can be a
# superseded back-off while an earlier comment is the still-active lease — picking
# `last` there would falsely report "already superseded" and never reclaim the
# genuinely expired active lease).
wit_select_active_lease "$leases"
lease_comment_id="$WIT_ACTIVE_LEASE_ID"
lease_json="$WIT_ACTIVE_LEASE_JSON"

[[ -n "$lease_json" ]] || emit false "no active lease record"

now_epoch="$(date -u +%s)"
if wit_lease_is_live "$lease_json" "$now_epoch"; then
  emit false "lease live"
fi

renewed_at="$(jq -r '.renewed_at' <<<"$lease_json")"

# Activity check: non-lease comments since renewed_at, or open cross-referenced PRs.
wit_run_gh read api --paginate "repos/$owner/$repo/issues/$number/comments" \
  --jq "[.[] | select((.body | startswith(\"<!-- work-item-lease v1\") | not) and .created_at > \"$renewed_at\")] | length"
comment_activity="$(printf '%s\n' "$WIT_GH_OUT" | jq -s 'add // 0')"

wit_run_gh read api --paginate "repos/$owner/$repo/issues/$number/timeline" \
  --jq '[.[] | select(.event == "cross-referenced" and (.source.issue.pull_request // null) != null and .source.issue.state == "open")] | length'
pr_activity="$(printf '%s\n' "$WIT_GH_OUT" | jq -s 'add // 0')"

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if ((comment_activity > 0 || pr_activity > 0)); then
  renewed="$(jq -c --arg ts "$now" '. + {renewed_at: $ts}' <<<"$lease_json")"
  wit_run_gh write api --method PATCH "repos/$owner/$repo/issues/comments/$lease_comment_id" \
    -f body="${WIT_LEASE_MARKER}${renewed} -->" --jq '.id'
  emit false "activity detected; lease renewed"
fi

# Expired + inactive → reclaim. Revalidate first: the lease was selected before
# the two activity round-trips above, a TOCTOU window in which a concurrent
# claimer can renew or supersede it. Re-read leases and confirm THIS is still the
# active lease and still expired; if another worker won the item in that window,
# reclaim is a no-op for this idempotent session-start sweep (reclaimed:false) —
# not a conflict, and emphatically not a mutation that would strip the new owner.
leases="$(wit_list_lease_comments "$owner" "$repo" "$number")" || exit "$?"
wit_select_active_lease "$leases"
if [[ "$WIT_ACTIVE_LEASE_ID" != "$lease_comment_id" ]]; then
  emit false "lease superseded by a concurrent claim during reclaim"
fi
if wit_lease_is_live "$WIT_ACTIVE_LEASE_JSON" "$(date -u +%s)"; then
  emit false "lease renewed during reclaim"
fi

# Remove ONLY the expired lease's holder — never a co-assignee a human added after
# the lease or a concurrent claimer added before this snapshot. Removing all
# assignees would strip a live claim and leave the frontier treating the item as
# unassigned while that lease stays live: two workers on one item. Guard on a
# fresh assignee read so a holder already unassigned (idempotent re-run) is a no-op.
holder="$(jq -r '.holder' <<<"$lease_json")"
wit_run_gh read issue view "$number" -R "$owner/$repo" --json assignees --jq '[.assignees[].login]'
if jq -e --arg h "$holder" 'any(.[]; . == $h)' <<<"$WIT_GH_OUT" >/dev/null; then
  wit_run_gh write issue edit "$number" -R "$owner/$repo" --remove-assignee "$holder"
fi

superseded="$(jq -c --arg ts "$now" '. + {superseded_at: $ts}' <<<"$lease_json")"
wit_run_gh write api --method PATCH "repos/$owner/$repo/issues/comments/$lease_comment_id" \
  -f body="${WIT_LEASE_MARKER}${superseded} -->" --jq '.id'
wit_run_gh write api "repos/$owner/$repo/issues/$number/comments" \
  -f body="work-item-lease reclaimed: lease expired (renewed_at $renewed_at) with no activity." --jq '.id'

emit true "lease expired; no activity"
