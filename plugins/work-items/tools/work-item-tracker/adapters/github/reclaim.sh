#!/usr/bin/env bash
# reclaim <id> — CONTRACT.md "Lease protocol". Idempotent session-start reclaim:
# expired lease + no activity → clear assignees, supersede lease, note; activity →
# renew in place. Never touches a live lease or a manual (lease-less) assignment.
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

# Select the ACTIVE lease = newest NON-superseded lease comment. Not blind
# `last`: a claim that backs off supersedes its own newer comment, so the
# highest-id comment can be a superseded back-off while an earlier comment is
# the still-active lease — picking `last` there would falsely report "already
# superseded" and never reclaim the genuinely expired active lease.
lease_comment_id=""
lease_json=""
while IFS= read -r row; do
  [[ -n "$row" ]] || continue
  cand="$(wit_lease_json "$(jq -r '.body' <<<"$row")")"
  [[ -n "$cand" ]] || continue
  [[ "$(jq -r '.superseded_at // empty' <<<"$cand")" == "" ]] || continue
  lease_comment_id="$(jq -r '.id' <<<"$row")"
  lease_json="$cand"
  break
done < <(jq -c 'sort_by(.id) | reverse | .[]' <<<"$leases")

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

# Expired + inactive: clear assignees, supersede, note.
wit_run_gh read issue view "$number" -R "$owner/$repo" --json assignees --jq '[.assignees[].login]'
while IFS= read -r assignee; do
  [[ -n "$assignee" ]] || continue
  wit_run_gh write issue edit "$number" -R "$owner/$repo" --remove-assignee "$assignee"
done < <(jq -r '.[]' <<<"$WIT_GH_OUT")

superseded="$(jq -c --arg ts "$now" '. + {superseded_at: $ts}' <<<"$lease_json")"
wit_run_gh write api --method PATCH "repos/$owner/$repo/issues/comments/$lease_comment_id" \
  -f body="${WIT_LEASE_MARKER}${superseded} -->" --jq '.id'
wit_run_gh write api "repos/$owner/$repo/issues/$number/comments" \
  -f body="work-item-lease reclaimed: lease expired (renewed_at $renewed_at) with no activity." --jq '.id'

emit true "lease expired; no activity"
