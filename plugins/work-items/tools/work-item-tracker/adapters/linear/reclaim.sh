#!/usr/bin/env bash
# reclaim — Linear adapter. Release an EXPIRED lease, idempotently.
#
# Run at session start, not on a schedule. The invariant that matters: a LIVE lease is
# never the intended target. Everything below fails toward leaving a lease alone.
#
# Activity check: non-lease comments newer than the lease's renewed_at mean the holder
# is still working, so the lease is RENEWED in place and reclaimed is false. Only a
# silent expired lease is released.
#
# Ownership is revalidated immediately before the mutation, because the activity read
# opens a window in which a concurrent claimer can renew or supersede. That narrows the
# TOCTOU window; it does not close it — Linear's commentUpdate documents no compare-and-
# set — so this is intent, not a guarantee, exactly as the contract says for GitHub.
#
# Contract: tools/work-item-tracker/CONTRACT.md "Lease protocol", "Exit codes".
#
# shellcheck disable=SC2016  # single-quoted `$name` here is a GraphQL variable, not a shell one
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

USAGE='usage: reclaim.sh <id>'
wit_help_if_requested "$USAGE" "$@"

ID="${1:-}"
[[ -n "$ID" ]] || wit_usage_error "$USAGE"
shift
[[ $# -eq 0 ]] || wit_usage_error "unexpected argument: $1"
wit_require_linear_id "$ID" || wit_usage_error "not a linear item id: $ID"

wit_need_linear_config
wit_linear_require_scoped_id "$ID"

wit_linear_fetch_issue "$WIT_LINEAR_TEAM" "$WIT_ID_NUMBER"
ISSUE_UUID="$(jq -r '.id' <<<"$WIT_LINEAR_ISSUE")"

emit() {
  jq -cn --arg sv "$WIT_SCHEMA_VERSION" --arg id "$ID" --argjson r "$1" --arg reason "$2" \
    '{schema_version: $sv, id: $id, reclaimed: $r, reason: $reason}'
  exit 0
}

ENTRIES="$(wit_linear_lease_comments "$ISSUE_UUID")"
# The LATEST non-superseded lease is the active one — the same ordering arbitration uses.
ACTIVE="$(jq -c '[.[] | select(.lease.superseded_at == null)] | last // empty' <<<"$ENTRIES")"
[[ -n "$ACTIVE" ]] || emit false "no active lease"

LEASE="$(jq -c '.lease' <<<"$ACTIVE")"
COMMENT_UUID="$(jq -r '.comment_id' <<<"$ACTIVE")"
HANDLE="$(jq -r '.handle' <<<"$ACTIVE")"
HOLDER="$(jq -r '.lease.holder // ""' <<<"$ACTIVE")"
RENEWED_AT="$(jq -r '.lease.renewed_at // ""' <<<"$ACTIVE")"

wit_linear_lease_live "$LEASE" && emit false "lease is still live"

# Activity: any comment newer than renewed_at that is NOT itself a lease marker. A lease
# marker would count its own renewal as activity and keep the lease alive forever.
RENEWED_EPOCH="$(wit_linear_epoch "$RENEWED_AT")"
ACTIVITY="no"
if [[ -n "$RENEWED_EPOCH" ]]; then
  wit_linear_gql \
    'query($id: String!) { issue(id: $id) { comments(first: 50) { nodes { body createdAt } } } }' \
    "$(jq -cn --arg id "$ISSUE_UUID" '{id: $id}')" \
    "checking activity on $ID"
  while IFS= read -r node; do
    [[ -n "$node" ]] || continue
    body="$(jq -r '.body // ""' <<<"$node")"
    [[ "$body" != *"$WIT_LINEAR_LEASE_PREFIX"* ]] || continue
    cepoch="$(wit_linear_epoch "$(jq -r '.createdAt' <<<"$node")")"
    [[ -n "$cepoch" ]] || continue
    if ((cepoch > RENEWED_EPOCH)); then
      ACTIVITY="yes"
      break
    fi
  done < <(jq -c '.issue.comments.nodes[]?' <<<"$WIT_LINEAR_DATA")
fi

# Revalidate before EITHER mutation: the activity read above round-tripped, and a
# concurrent claimer may have renewed or superseded this lease meanwhile.
revalidate() {
  local now active
  now="$(wit_linear_lease_comments "$ISSUE_UUID")"
  active="$(jq -c --argjson h "$HANDLE" '[.[] | select(.handle == $h)][0] // empty' <<<"$now")"
  [[ -n "$active" ]] || return 1
  [[ -z "$(jq -r '.lease.superseded_at // empty' <<<"$active")" ]] || return 1
  ! wit_linear_lease_live "$(jq -c '.lease' <<<"$active")"
}

if [[ "$ACTIVITY" == "yes" ]]; then
  revalidate || emit false "lease changed while checking activity"
  RENEWED="$(jq -c --arg t "$(wit_linear_now_iso)" '. + {renewed_at: $t}' <<<"$LEASE")"
  wit_linear_update_comment "$COMMENT_UUID" "$(wit_linear_lease_marker "$RENEWED")"
  emit false "activity since renewed_at — lease renewed instead of reclaimed"
fi

revalidate || emit false "lease changed before reclaim"

SUPERSEDED="$(jq -c --arg t "$(wit_linear_now_iso)" '. + {superseded_at: $t}' <<<"$LEASE")"
wit_linear_update_comment "$COMMENT_UUID" "$(wit_linear_lease_marker "$SUPERSEDED")"

# Unassign ONLY the expired lease's holder. Someone else in the assignee slot is a live
# claim taken after this lease expired; clearing it would strip that claim and hand the
# item back to the frontier while another session works it.
CURRENT_ASSIGNEE="$(jq -r '.assignee.displayName // .assignee.email // ""' <<<"$WIT_LINEAR_ISSUE")"
if [[ -n "$HOLDER" && "$CURRENT_ASSIGNEE" == "$HOLDER" ]]; then
  wit_linear_set_assignee "$ISSUE_UUID" ""
fi

wit_linear_post_comment "$ISSUE_UUID" \
  "Reclaimed: the lease held by ${HOLDER:-an earlier session} expired at ${RENEWED_AT} with no activity since. The item is available again." >/dev/null

emit true "expired lease with no activity"
