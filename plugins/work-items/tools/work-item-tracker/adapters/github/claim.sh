#!/usr/bin/env bash
# claim <id> [--ttl-hours <n>] [--session-id <s>] — CONTRACT.md "Lease protocol".
# Assignment is bare gh (@me = session identity); the lease comment goes through the
# bot. Race arbitration is by lease-comment identity, not session_id.
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

wit_help_if_requested "usage: claim <id> [--ttl-hours <n>] [--session-id <s>]" "$@"

id="" ttl="${WIT_LEASE_TTL_HOURS:-}" session_id=""
id="${1:-}"
[[ -n "$id" ]] || wit_usage_error "usage: claim <id> [--ttl-hours <n>] [--session-id <s>]"
shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ttl-hours)
      [[ $# -ge 2 ]] || wit_usage_error "--ttl-hours needs a value"
      ttl="$2"
      shift 2
      ;;
    --session-id)
      [[ $# -ge 2 ]] || wit_usage_error "--session-id needs a value"
      session_id="$2"
      shift 2
      ;;
    *) wit_usage_error "unknown argument: $1" ;;
  esac
done
wit_require_github_id "$id" || wit_usage_error "malformed or non-github id: $id"
[[ "$ttl" =~ ^[0-9]+$ ]] || wit_usage_error "--ttl-hours must be a non-negative integer (binding config.lease_ttl_hours supplies the default)"

owner="$WIT_ID_OWNER" repo="$WIT_ID_REPO" number="$WIT_ID_NUMBER"

wit_run_gh read api user --jq .login
login="$WIT_GH_OUT"

# 1. Assign the session identity.
wit_run_gh read issue edit "$number" -R "$owner/$repo" --add-assignee "@me"

# 2. Sole-assignee check — a different login present means an established claim.
wit_run_gh read issue view "$number" -R "$owner/$repo" --json assignees --jq '[.assignees[].login]'
assignees="$WIT_GH_OUT"
other="$(jq -r --arg me "$login" '[.[] | select(. != $me)] | first // empty' <<<"$assignees")"
if [[ -n "$other" ]]; then
  gh issue edit "$number" -R "$owner/$repo" --remove-assignee "@me" >/dev/null 2>&1 || true
  printf 'claim: item already claimed by %s\n' "$other" >&2
  exit "$EX_CONFLICT"
fi

# 3. Post our lease comment.
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
lease="$(jq -cn --arg sv "$WIT_SCHEMA_VERSION" --arg holder "$login" --arg now "$now" \
  --arg ttl "$ttl" --arg sid "$session_id" \
  '{schema_version: $sv, holder: $holder, acquired_at: $now, renewed_at: $now,
    ttl_hours: ($ttl | tonumber)}
   + (if $sid != "" then {session_id: $sid} else {} end)')"
wit_run_gh write api "repos/$owner/$repo/issues/$number/comments" \
  -f body="${WIT_LEASE_MARKER}${lease} -->" --jq '.id'
our_comment_id="$WIT_GH_OUT"

# 4. Re-read all lease comments; the EARLIEST live lease wins.
now_epoch="$(date -u +%s)"
# $() swallows wit_run_gh's exit-on-error; propagate so a read failure here does
# not silently arbitrate the claim against an empty lease set.
leases="$(wit_list_lease_comments "$owner" "$repo" "$number")" || exit "$?"
winner_id=""
winner_holder=""
while IFS= read -r row; do
  [[ -n "$row" ]] || continue
  cid="$(jq -r '.id' <<<"$row")"
  lease_json="$(wit_lease_json "$(jq -r '.body' <<<"$row")")"
  [[ -n "$lease_json" ]] || continue
  if wit_lease_is_live "$lease_json" "$now_epoch"; then
    winner_id="$cid"
    winner_holder="$(jq -r '.holder // empty' <<<"$lease_json")"
    break
  fi
done < <(jq -c 'sort_by(.id) | .[]' <<<"$leases")

# Earliest LIVE lease wins. No live lease at all (e.g. ttl 0) → our claim stands;
# expiry is reclaim's concern.
if [[ -n "$winner_id" && "$winner_id" != "$our_comment_id" ]]; then
  superseded="$(jq -c --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '. + {superseded_at: $ts}' <<<"$lease")"
  gh_write api --method PATCH "repos/$owner/$repo/issues/comments/$our_comment_id" \
    -f body="${WIT_LEASE_MARKER}${superseded} -->" >/dev/null 2>&1 || true
  # Keep the @me assignment only on a SAME-login race (the winner shares our
  # login, so the assignee still matches the holder). If the winning lease
  # belongs to a different holder, our @me would leave the item assigned to the
  # loser while the holder no longer matches — drop it.
  if [[ "$winner_holder" != "$login" ]]; then
    gh issue edit "$number" -R "$owner/$repo" --remove-assignee "@me" >/dev/null 2>&1 || true
  fi
  printf 'claim: live lease (comment %s, holder %s) wins — backing off\n' \
    "$winner_id" "${winner_holder:-unknown}" >&2
  exit "$EX_CONFLICT"
fi

jq -cn --arg sv "$WIT_SCHEMA_VERSION" --arg id "$id" --arg holder "$login" \
  --arg now "$now" --arg ttl "$ttl" --arg cid "$our_comment_id" --arg sid "$session_id" \
  '{schema_version: $sv, id: $id, holder: $holder, acquired_at: $now, renewed_at: $now,
    ttl_hours: ($ttl | tonumber), lease_comment_id: ($cid | tonumber),
    session_id: (if $sid != "" then $sid else null end)}'
