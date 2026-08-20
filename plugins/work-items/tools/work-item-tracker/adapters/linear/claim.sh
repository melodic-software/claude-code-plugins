#!/usr/bin/env bash
# claim — Linear adapter. Acquire the lease on one item.
#
# ── How this differs from the GitHub adapter, and why ────────────────────────────────
# The contract's claim sequence detects a race at step 2 by re-reading the ASSIGNEES and
# backing off when another login is present. That works because GitHub's assignee field
# is a LIST: both racers' assignments coexist, so both can see the collision.
#
# Linear's `Issue.assignee` is a SINGLE field. The second writer OVERWRITES the first and
# then re-reads only itself — the collision is invisible from the assignee alone, and a
# step-2 check would report "no race" to both racers.
#
# So arbitration rests on the lease COMMENT ordering instead, which the contract already
# specifies for the same-login case: post the lease, re-read every lease comment, and the
# earliest live one wins. Comments are durable and both racers see the same set, so this
# is real arbitration rather than an emulation of one. The assignee is still written —
# it is what makes the claim visible in Linear's own UI and what the frontier filter
# reads — but it is NOT the race detector here.
#
# Ordering is total: handles are millisecond timestamps and ties break on the comment
# UUID (see wit_linear_lease_comments). Without that tiebreak two same-millisecond
# racers could each read themselves as earliest.
#
# Contract: tools/work-item-tracker/CONTRACT.md "Lease protocol", "Exit codes".
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

USAGE='usage: claim.sh <id> [--ttl-hours <n>] [--ttl-minutes <n>] [--session-id <s>]'
wit_help_if_requested "$USAGE" "$@"

ID="${1:-}"
[[ -n "$ID" ]] || wit_usage_error "$USAGE"
shift
TTL_HOURS=""
TTL_MINUTES=""
SESSION_ID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --ttl-hours)
    [[ $# -ge 2 ]] || wit_usage_error "--ttl-hours needs a value"
    TTL_HOURS="$2"
    shift 2
    ;;
  --ttl-minutes)
    [[ $# -ge 2 ]] || wit_usage_error "--ttl-minutes needs a value"
    TTL_MINUTES="$2"
    shift 2
    ;;
  --session-id)
    [[ $# -ge 2 ]] || wit_usage_error "--session-id needs a value"
    SESSION_ID="$2"
    shift 2
    ;;
  *) wit_usage_error "unexpected argument: $1" ;;
  esac
done
wit_require_linear_id "$ID" || wit_usage_error "not a linear item id: $ID"
[[ -z "$TTL_HOURS" || "$TTL_HOURS" =~ ^[0-9]+$ ]] || wit_usage_error "--ttl-hours must be a non-negative integer"
[[ -z "$TTL_MINUTES" || "$TTL_MINUTES" =~ ^[0-9]+$ ]] || wit_usage_error "--ttl-minutes must be a non-negative integer"

wit_need_linear_config
wit_linear_require_scoped_id "$ID"

TTL_HOURS="${TTL_HOURS:-$WIT_LINEAR_LEASE_TTL_HOURS}"
TTL_MINUTES="${TTL_MINUTES:-$WIT_LINEAR_LEASE_TTL_MINUTES}"

wit_linear_resolve_viewer
HOLDER="$WIT_LINEAR_VIEWER"
wit_linear_fetch_issue "$WIT_LINEAR_TEAM" "$WIT_ID_NUMBER"
ISSUE_UUID="$(jq -r '.id' <<<"$WIT_LINEAR_ISSUE")"

# Step 1 — a live FOREIGN lease is refused before anything is written. Checking first
# costs one read and avoids the common case of assigning, posting, and then unwinding
# both against a holder who was never in doubt.
EXISTING="$(wit_linear_lease_comments "$ISSUE_UUID")" || exit "$?"
while IFS= read -r entry; do
  [[ -n "$entry" ]] || continue
  lease="$(jq -c '.lease' <<<"$entry")"
  wit_linear_lease_live "$lease" || continue
  other="$(jq -r '.holder // ""' <<<"$lease")"
  printf 'linear: %s is already claimed by %s (live lease) — not claiming\n' "$ID" "$other" >&2
  exit "$EX_CONFLICT"
done < <(jq -c '.[]' <<<"$EXISTING")

# Step 2 — assign the authenticated user. This is visibility and frontier state, NOT
# the race detector (see the header).
wit_linear_set_assignee "$ISSUE_UUID" "$WIT_LINEAR_VIEWER_ID"

# Guard the partial-claim window, exactly as the github adapter does. Any failure
# between this successful assignment and a settled lease (step 4's arbitration) would
# otherwise strand the issue ASSIGNED WITH NO LEASE — and that state is unrecoverable
# through the seam: list-frontier excludes assigned items, and reclaim refuses an item
# with no active lease, so nothing can hand it back. A transient API failure would park
# the item indefinitely.
#
# It must be an EXIT trap, not ERR: every wit_linear_* helper's failure path calls
# `exit` directly rather than returning, and an explicit `exit` inside a function does
# not run the caller's ERR trap — only its EXIT trap.
#
# The unassign itself runs in a SUBSHELL, because that same `exit` would otherwise fire
# from inside the trap: `|| true` does not contain an exit, only a subshell boundary
# does. Without it a failing rollback would abort the trap and overwrite the script's
# exit status, reporting a different failure than the one that actually happened.
_wit_linear_claim_rollback() {
  (wit_linear_set_assignee "$ISSUE_UUID" "") >/dev/null 2>&1 || true
}
trap _wit_linear_claim_rollback EXIT

# Step 3 — post the lease. The handle is minted from the comment's own createdAt, so it
# is ordered by construction rather than by anything this process chose.
NOW="$(wit_linear_now_iso)"
PROVISIONAL="$(jq -cn --arg sv "$WIT_SCHEMA_VERSION" --arg h "$HOLDER" --arg t "$NOW" \
  --argjson th "$TTL_HOURS" --argjson tm "$TTL_MINUTES" --arg s "$SESSION_ID" \
  '{schema_version: $sv, holder: $h, acquired_at: $t, renewed_at: $t,
    ttl_hours: $th, ttl_minutes: $tm}
   + (if ($s | length) > 0 then {session_id: $s} else {} end)')"
POSTED="$(wit_linear_post_comment "$ISSUE_UUID" "$(wit_linear_lease_marker "$PROVISIONAL")")" || exit "$?"
COMMENT_UUID="$(jq -r '.id' <<<"$POSTED")"
HANDLE="$(wit_linear_handle "$(jq -r '.createdAt' <<<"$POSTED")")"

# Write the minted handle back into the marker so later readers arbitrate on the same
# number this claim reports, rather than re-deriving it from a timestamp they might
# parse differently.
LEASE="$(jq -c --argjson h "$HANDLE" '. + {lease_comment_id: $h}' <<<"$PROVISIONAL")"
wit_linear_update_comment "$COMMENT_UUID" "$(wit_linear_lease_marker "$LEASE")"

# Step 4 — re-read and arbitrate. If any EARLIER live lease exists that is not our own
# comment, it wins: supersede ours and back off. The assignee is left alone on a
# same-holder race — it belongs to the winner either way.
AFTER="$(wit_linear_lease_comments "$ISSUE_UUID")" || exit "$?"
LOSER=""
while IFS= read -r entry; do
  [[ -n "$entry" ]] || continue
  cid="$(jq -r '.comment_id' <<<"$entry")"
  [[ "$cid" != "$COMMENT_UUID" ]] || continue
  lease="$(jq -c '.lease' <<<"$entry")"
  wit_linear_lease_live "$lease" || continue
  ehandle="$(jq -r '.handle' <<<"$entry")"
  # Strictly earlier by handle, or equal handle and lexically smaller comment id — the
  # same total order both racers compute.
  if ((ehandle < HANDLE)) || { ((ehandle == HANDLE)) && [[ "$cid" < "$COMMENT_UUID" ]]; }; then
    LOSER="$(jq -r '.holder // "another session"' <<<"$lease")"
    break
  fi
done < <(jq -c '.[]' <<<"$AFTER")

if [[ -n "$LOSER" ]]; then
  # Disarm before the branch's own unassign decision. From here the claim is SETTLED —
  # we lost — and this block already decides the assignee correctly by re-fetching and
  # comparing the holder. Leaving the trap armed would run a second, unconditional
  # unassign after that guarded one, stripping the winner's live claim: exactly the
  # failure the guarded check below exists to prevent.
  trap - EXIT
  SUPERSEDED="$(jq -c --arg t "$(wit_linear_now_iso)" '. + {superseded_at: $t}' <<<"$LEASE")"
  wit_linear_update_comment "$COMMENT_UUID" "$(wit_linear_lease_marker "$SUPERSEDED")"
  # Only unassign if we are still the assignee: the winner may already have taken it,
  # and clearing that would strip a live claim and hand the item back to the frontier.
  wit_linear_fetch_issue "$WIT_LINEAR_TEAM" "$WIT_ID_NUMBER"
  if [[ "$(jq -r '.assignee.displayName // .assignee.email // ""' <<<"$WIT_LINEAR_ISSUE")" == "$HOLDER" ]]; then
    wit_linear_set_assignee "$ISSUE_UUID" ""
  fi
  printf 'linear: lost the claim race on %s to %s — backed off\n' "$ID" "$LOSER" >&2
  exit "$EX_CONFLICT"
fi

# Arbitration confirms our lease is the winner — the claim is complete and the
# assignment is the one we intend to leave behind.
trap - EXIT

jq -cn --arg sv "$WIT_SCHEMA_VERSION" --arg id "$ID" --argjson lease "$LEASE" \
  '{schema_version: $sv, id: $id, holder: $lease.holder,
    acquired_at: $lease.acquired_at, renewed_at: $lease.renewed_at,
    ttl_hours: $lease.ttl_hours, ttl_minutes: $lease.ttl_minutes,
    lease_comment_id: $lease.lease_comment_id,
    session_id: ($lease.session_id // null)}'
