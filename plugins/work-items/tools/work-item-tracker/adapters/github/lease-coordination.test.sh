#!/usr/bin/env bash
# GitHub-adapter lease-coordination correctness that the abstract conformance
# suite cannot assert (that suite needs a live GitHub target; these cases drive
# specific renew-lease/reclaim decision paths deterministically against a stubbed
# gh). Covers two lease-coordination findings:
#   (1) renew-lease REFUSES an expired lease even when it is still the active
#       (non-superseded) lease whose handle matches — no revive, exit 7, no PATCH;
#   (2) reclaim removes ONLY the expired lease's holder, leaving a co-assignee
#       (manual or concurrent claimer) in place; and revalidates ownership before
#       mutating, so a concurrent claim during the activity window aborts cleanly.
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced lib
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../tests/lib.sh"

RENEW="$SCRIPT_DIR/renew-lease.sh"
RECLAIM="$SCRIPT_DIR/reclaim.sh"
ID="github:acme/widgets#1"

# --- gh stub: a bash function (always wins over the external gh, and is inherited
# by the `bash <verb>.sh` child via `export -f`). It reads canned responses from
# $GH_STUB_DIR and appends write ops to calls.log, dispatching on the flags/paths
# each call carries — the two reads of the same /comments endpoint are told apart
# by --jq (`length` = activity count) vs (lease list), and successive lease-list
# reads pick lease-comments-<n> when present so a revalidation read can differ. ---
gh() {
  local d="${GH_STUB_DIR:?}" args="$*" a prev n
  case "$args" in
    *"--method PATCH"*)
      for a in "$@"; do
        case "$a" in repos/*/issues/comments/*) printf 'PATCH %s\n' "${a##*/comments/}" >>"$d/calls.log" ;; *) : ;; esac
      done
      printf '1\n'
      ;;
    *"--remove-assignee"*)
      prev=""
      for a in "$@"; do
        [[ "$prev" == "--remove-assignee" ]] && printf 'REMOVE_ASSIGNEE %s\n' "$a" >>"$d/calls.log"
        prev="$a"
      done
      ;;
    *"--json assignees"*) cat "$d/assignees" ;;
    # The timeline read also carries --paginate, so it must be matched by its path
    # BEFORE the generic --paginate (/comments) branch below — order is load-bearing.
    *"/timeline"*) cat "$d/pr-activity" 2>/dev/null || printf '0\n' ;;
    *"--paginate"*)
      case "$args" in
        *length*) cat "$d/comment-activity" 2>/dev/null || printf '0\n' ;;
        *)
          n=$(( $(cat "$d/lease-comments.count" 2>/dev/null || printf '0') + 1 ))
          printf '%s\n' "$n" >"$d/lease-comments.count"
          if [[ -f "$d/lease-comments-$n" ]]; then cat "$d/lease-comments-$n"; else cat "$d/lease-comments"; fi
          ;;
      esac
      ;;
    *"issues/comments/"*) cat "$d/comment" ;;
    *"-f body="*) printf 'POST_COMMENT\n' >>"$d/calls.log"; printf '1\n' ;;
    *) printf 'gh-stub: unhandled: %s\n' "$args" >&2; return 90 ;;
  esac
}
export -f gh

# marker <holder> <renewed_at> <ttl> — echo a lease marker comment body.
marker() {
  local json
  json="$(jq -cn --arg h "$1" --arg r "$2" --argjson t "$3" \
    '{schema_version:"1.0", holder:$h, acquired_at:"2020-01-01T00:00:00Z", renewed_at:$r, ttl_hours:$t}')"
  printf '<!-- work-item-lease v1 %s -->' "$json"
}

lease_array() { jq -cn --argjson id "$1" --arg body "$2" '[{id:$id, node_id:"MDEx", body:$body, created_at:"2020-01-01T00:00:00Z"}]'; }

new_scenario() { GH_STUB_DIR="$(mktemp -d)"; export GH_STUB_DIR; : >"$GH_STUB_DIR/calls.log"; }
calls() { cat "$GH_STUB_DIR/calls.log"; }
cleanup_scenario() { rm -rf "$GH_STUB_DIR"; }

PAST="2020-01-01T00:00:00Z"   # renewed_at + ttl long elapsed → expired
FUTURE="2099-01-01T00:00:00Z" # renewed_at in the future → unambiguously live

# ===========================================================================
# Finding 1 — renew-lease must refuse an expired active lease (no revive).
# ===========================================================================

# [expired] active lease matches the handle but has elapsed its TTL.
new_scenario
EXP_MARKER="$(marker alice "$PAST" 24)"
lease_array 123 "$EXP_MARKER" >"$GH_STUB_DIR/lease-comments"
jq -cn --arg b "$EXP_MARKER" '{body:$b, issue:"1"}' >"$GH_STUB_DIR/comment"
set +e
bash "$RENEW" "$ID" --lease-comment-id 123 >/dev/null 2>&1
rc=$?
set -e 2>/dev/null || true
assert_eq "renew-lease returns conflict (7) for an expired active lease" "7" "$rc"
if grep -q '^PATCH' "$GH_STUB_DIR/calls.log"; then
  fail "renew-lease does NOT revive the expired lease (no PATCH)" "no PATCH logged" "PATCH logged"
else
  pass "renew-lease does NOT revive the expired lease (no PATCH)"
fi
cleanup_scenario

# [live control] the same flow on a LIVE active lease must still renew (guards the
# fix against refusing a legitimate renewal).
new_scenario
LIVE_MARKER="$(marker alice "$FUTURE" 24)"
lease_array 123 "$LIVE_MARKER" >"$GH_STUB_DIR/lease-comments"
jq -cn --arg b "$LIVE_MARKER" '{body:$b, issue:"1"}' >"$GH_STUB_DIR/comment"
out="$(bash "$RENEW" "$ID" --lease-comment-id 123 2>/dev/null)"; rc=$?
assert_eq "renew-lease succeeds (0) for a live active lease" "0" "$rc"
assert_eq "renew-lease emits the renewed lease record" "$ID" "$(jq -r '.id' <<<"$out")"
assert_contains "renew-lease PATCHes the live lease comment" "$(calls)" "PATCH 123"
cleanup_scenario

# ===========================================================================
# Finding 2 — reclaim removes ONLY the expired lease's holder.
# ===========================================================================

# [holder-only] expired lease held by alice; bob is a co-assignee (manual add or a
# concurrent claimer). No activity → reclaim must unassign alice ONLY.
new_scenario
EXP_MARKER="$(marker alice "$PAST" 24)"
lease_array 123 "$EXP_MARKER" >"$GH_STUB_DIR/lease-comments"
jq -cn '["alice","bob"]' >"$GH_STUB_DIR/assignees"
out="$(bash "$RECLAIM" "$ID" 2>/dev/null)"; rc=$?
assert_eq "reclaim succeeds (0)" "0" "$rc"
assert_eq "reclaim reports reclaimed:true" "true" "$(jq -r '.reclaimed' <<<"$out")"
assert_contains "reclaim removes the expired lease holder (alice)" "$(calls)" "REMOVE_ASSIGNEE alice"
assert_not_contains "reclaim leaves the co-assignee (bob) untouched" "$(calls)" "REMOVE_ASSIGNEE bob"
cleanup_scenario

# [revalidation] a concurrent claimer supersedes the lease during the activity
# window: the revalidation read (lease-comments-2) shows a different active lease.
# reclaim must abort as a no-op (reclaimed:false) and mutate NOTHING.
new_scenario
EXP_MARKER="$(marker alice "$PAST" 24)"
CONCURRENT_MARKER="$(marker carol "$FUTURE" 24)"
lease_array 123 "$EXP_MARKER" >"$GH_STUB_DIR/lease-comments-1"
lease_array 200 "$CONCURRENT_MARKER" >"$GH_STUB_DIR/lease-comments-2"
jq -cn '["alice","carol"]' >"$GH_STUB_DIR/assignees"
out="$(bash "$RECLAIM" "$ID" 2>/dev/null)"; rc=$?
assert_eq "reclaim succeeds (0) on a concurrent-claim revalidation" "0" "$rc"
assert_eq "reclaim reports reclaimed:false when the lease changed under it" "false" "$(jq -r '.reclaimed' <<<"$out")"
assert_not_contains "reclaim removes NO assignee when revalidation fails" "$(calls)" "REMOVE_ASSIGNEE"
assert_not_contains "reclaim does not supersede when revalidation fails" "$(calls)" "PATCH"
cleanup_scenario

[[ $FAILED -eq 0 ]] || exit 1
