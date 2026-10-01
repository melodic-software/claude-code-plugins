#!/usr/bin/env bash
# GitHub-adapter lease-coordination correctness that the abstract conformance
# suite cannot assert (that suite needs a live GitHub target; these cases drive
# specific claim/renew-lease/reclaim decision paths deterministically against a
# stubbed gh). Covers three lease-coordination findings:
#   (1) renew-lease REFUSES an expired lease even when it is still the active
#       (non-superseded) lease whose handle matches — no revive, exit 7, no PATCH;
#   (2) reclaim removes ONLY the expired lease's holder, leaving a co-assignee
#       (manual or concurrent claimer) in place; and revalidates ownership before
#       mutating, so a concurrent claim during the activity window aborts cleanly;
#   (3) claim's own protocol path (assign, sole-assignee check, lease post,
#       arbitration), which claim.test.sh does not reach;
#   (4) release ends the caller's own live lease, so a same-login claim that
#       backed off on it succeeds afterwards, and refuses any lease that is not
#       the caller's active one.
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced lib
set -uo pipefail

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../tests/lib.sh"

RENEW="$SCRIPT_DIR/renew-lease.sh"
RECLAIM="$SCRIPT_DIR/reclaim.sh"
RELEASE="$SCRIPT_DIR/release.sh"
CLAIM="$SCRIPT_DIR/claim.sh"
ID="github:acme/widgets#1"

# --- gh stub: a bash function (always wins over the external gh, and is inherited
# by the `bash <verb>.sh` child via `export -f`). It reads canned responses from
# $GH_STUB_DIR and appends write ops to calls.log, dispatching on the flags/paths
# each call carries — the two reads of the same /comments endpoint are told apart
# by --jq (`length` = activity count) vs (lease list), and successive lease-list
# reads pick lease-comments-<n> when present so a revalidation read can differ. ---
# A scenario that creates $d/stateful makes lease comments and assignees persist:
# a POSTed comment is appended to lease-comments with the next id, a PATCH rewrites
# that comment's body, and assignee POST/DELETE edit $d/assignees, so one scenario
# can chain claim → release → claim against what earlier calls wrote.
stub_body_arg() {
  local a
  for a in "$@"; do
    case "$a" in body=*) printf '%s' "${a#body=}" ;; *) : ;; esac
  done
}
stub_login_arg() {
  local a
  for a in "$@"; do
    case "$a" in "assignees[]="*) printf '%s' "${a#assignees[]=}" ;; *) : ;; esac
  done
}
gh() {
  local d="${GH_STUB_DIR:?}" args="$*" a n cid body login
  case "$args" in
  *"--method PATCH"*)
    for a in "$@"; do
      case "$a" in repos/*/issues/comments/*) cid="${a##*/comments/}" ;; *) : ;; esac
    done
    printf 'PATCH %s\n' "$cid" >>"$d/calls.log"
    if [[ -f "$d/stateful" ]]; then
      body="$(stub_body_arg "$@")"
      jq -c --argjson id "$cid" --arg b "$body" 'map(if .id == $id then .body = $b else . end)' \
        "$d/lease-comments" >"$d/lease-comments.tmp" && mv "$d/lease-comments.tmp" "$d/lease-comments"
    fi
    printf '%s\n' "${cid:-1}"
    ;;
  # Assignee ops are REST (`gh api …/issues/<n>/assignees`), not `gh issue edit`
  # — the gh subcommands route through GraphQL, which sandboxed sessions refuse.
  # The login rides in an `assignees[]=<login>` -f field, so it is read off that
  # field rather than off a positional flag argument. Both must be matched
  # BEFORE the generic --paginate/-f branches below.
  *"--method DELETE"*"/assignees"*)
    login="$(stub_login_arg "$@")"
    printf 'REMOVE_ASSIGNEE %s\n' "$login" >>"$d/calls.log"
    if [[ -f "$d/stateful" ]]; then
      jq -c --arg l "$login" 'map(select(. != $l))' "$d/assignees" >"$d/assignees.tmp" &&
        mv "$d/assignees.tmp" "$d/assignees"
    fi
    cat "$d/assignees" 2>/dev/null || printf '[]\n'
    ;;
  *"--method POST"*"/assignees"*)
    login="$(stub_login_arg "$@")"
    printf 'ADD_ASSIGNEE %s\n' "$login" >>"$d/calls.log"
    if [[ -f "$d/stateful" ]]; then
      jq -c --arg l "$login" 'if index($l) then . else . + [$l] end' "$d/assignees" >"$d/assignees.tmp" &&
        mv "$d/assignees.tmp" "$d/assignees"
    fi
    cat "$d/assignees" 2>/dev/null || printf '[]\n'
    ;;
  *".assignees[].login"*) cat "$d/assignees" ;;
  # The timeline read also carries --paginate, so it must be matched by its path
  # BEFORE the generic --paginate (/comments) branch below — order is load-bearing.
  *"/timeline"*) cat "$d/pr-activity" 2>/dev/null || printf '0\n' ;;
  *"--paginate"*)
    case "$args" in
    *length*) cat "$d/comment-activity" 2>/dev/null || printf '0\n' ;;
    *)
      n=$(($(cat "$d/lease-comments.count" 2>/dev/null || printf '0') + 1))
      printf '%s\n' "$n" >"$d/lease-comments.count"
      if [[ -f "$d/lease-comments-$n" ]]; then cat "$d/lease-comments-$n"; else cat "$d/lease-comments"; fi
      ;;
    esac
    ;;
  *"issues/comments/"*)
    if [[ -f "$d/stateful" ]]; then
      for a in "$@"; do
        case "$a" in repos/*/issues/comments/*) cid="${a##*/comments/}" ;; *) : ;; esac
      done
      jq -c --argjson id "$cid" '.[] | select(.id == $id) | {body, issue: "1"}' "$d/lease-comments"
    else
      cat "$d/comment"
    fi
    ;;
  # claim resolves the session identity before assigning; $d/login lets a scenario
  # choose whose claim it is.
  *"api user"*) cat "$d/login" 2>/dev/null || printf 'alice\n' ;;
  *"-f body="*)
    printf 'POST_COMMENT\n' >>"$d/calls.log"
    if [[ -f "$d/stateful" ]]; then
      cid="$(jq -r '(map(.id) | max // 0) + 1' "$d/lease-comments")"
      body="$(stub_body_arg "$@")"
      jq -c --argjson id "$cid" --arg b "$body" \
        '. + [{id: $id, node_id: "MDEx", body: $b, created_at: "2020-01-01T00:00:00Z"}]' \
        "$d/lease-comments" >"$d/lease-comments.tmp" && mv "$d/lease-comments.tmp" "$d/lease-comments"
      printf '%s\n' "$cid"
    else
      printf '1\n'
    fi
    ;;
  *)
    printf 'gh-stub: unhandled: %s\n' "$args" >&2
    return 90
    ;;
  esac
}
export -f gh stub_body_arg stub_login_arg

# marker <holder> <renewed_at> <ttl> — echo a lease marker comment body.
marker() {
  local json
  json="$(jq -cn --arg h "$1" --arg r "$2" --argjson t "$3" \
    '{schema_version:"1.0", holder:$h, acquired_at:"2020-01-01T00:00:00Z", renewed_at:$r, ttl_hours:$t}')"
  printf '<!-- work-item-lease v1 %s -->' "$json"
}

lease_array() { jq -cn --argjson id "$1" --arg body "$2" '[{id:$id, node_id:"MDEx", body:$body, created_at:"2020-01-01T00:00:00Z"}]'; }

new_scenario() {
  GH_STUB_DIR="$(mktemp -d "$TMP_ROOT/d.XXXXXX")"
  export GH_STUB_DIR
  : >"$GH_STUB_DIR/calls.log"
}
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
# `|| rc=$?` rather than a `set +e` / `set -e` pair: this file runs under
# `set -uo pipefail` with errexit deliberately OFF, and such a pair would
# ENABLE errexit rather than restore the prior state, aborting every later
# case that expects a non-zero exit instead of letting it assert.
rc=0
bash "$RENEW" "$ID" --lease-comment-id 123 >/dev/null 2>&1 || rc=$?
assert_eq "renew-lease returns conflict (7) for an expired active lease" "7" "$rc"
assert_fails "renew-lease does NOT revive the expired lease (no PATCH)" "no PATCH logged" "PATCH logged" \
  grep -q '^PATCH' "$GH_STUB_DIR/calls.log"
cleanup_scenario

# [live control] the same flow on a LIVE active lease must still renew (guards the
# fix against refusing a legitimate renewal).
new_scenario
LIVE_MARKER="$(marker alice "$FUTURE" 24)"
lease_array 123 "$LIVE_MARKER" >"$GH_STUB_DIR/lease-comments"
jq -cn --arg b "$LIVE_MARKER" '{body:$b, issue:"1"}' >"$GH_STUB_DIR/comment"
out="$(bash "$RENEW" "$ID" --lease-comment-id 123 2>/dev/null)"
rc=$?
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
out="$(bash "$RECLAIM" "$ID" 2>/dev/null)"
rc=$?
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
out="$(bash "$RECLAIM" "$ID" 2>/dev/null)"
rc=$?
assert_eq "reclaim succeeds (0) on a concurrent-claim revalidation" "0" "$rc"
assert_eq "reclaim reports reclaimed:false when the lease changed under it" "false" "$(jq -r '.reclaimed' <<<"$out")"
assert_not_contains "reclaim removes NO assignee when revalidation fails" "$(calls)" "REMOVE_ASSIGNEE"
assert_not_contains "reclaim does not supersede when revalidation fails" "$(calls)" "PATCH"
cleanup_scenario

# [revalidation, same id renewed] the OTHER revalidation branch: a concurrent
# renew-lease completes IN PLACE during the activity window — same active id (123),
# but renewed_at now in the future (live). reclaim must abort as a no-op too, never
# unassigning the holder whose lease was just legitimately renewed.
new_scenario
EXP_MARKER="$(marker alice "$PAST" 24)"
RENEWED_MARKER="$(marker alice "$FUTURE" 24)"
lease_array 123 "$EXP_MARKER" >"$GH_STUB_DIR/lease-comments-1"
lease_array 123 "$RENEWED_MARKER" >"$GH_STUB_DIR/lease-comments-2"
jq -cn '["alice"]' >"$GH_STUB_DIR/assignees"
out="$(bash "$RECLAIM" "$ID" 2>/dev/null)"
rc=$?
assert_eq "reclaim succeeds (0) when the lease was renewed in place during the window" "0" "$rc"
assert_eq "reclaim reports reclaimed:false when the lease was renewed in place" "false" "$(jq -r '.reclaimed' <<<"$out")"
assert_not_contains "reclaim removes NO assignee when the lease was renewed in place" "$(calls)" "REMOVE_ASSIGNEE"
assert_not_contains "reclaim does not supersede when the lease was renewed in place" "$(calls)" "PATCH"
cleanup_scenario

# ===========================================================================
# Finding 3 — claim's assignment path. `claim.test.sh` covers only --help and
# usage errors, so the protocol itself (assign → sole-assignee check → lease →
# arbitration) had no coverage; these drive it against the stub.
# ===========================================================================

# [happy path] nobody else assigned, our lease is the only live one → claim holds.
new_scenario
printf 'alice\n' >"$GH_STUB_DIR/login"
jq -cn '["alice"]' >"$GH_STUB_DIR/assignees"
lease_array 1 "$(marker alice "$FUTURE" 24)" >"$GH_STUB_DIR/lease-comments"
out="$(bash "$CLAIM" "$ID" --ttl-hours 24 2>/dev/null)"
rc=$?
assert_eq "claim succeeds (0) on an unclaimed item" "0" "$rc"
assert_eq "claim assigns the session identity" "alice" "$(jq -r '.holder' <<<"$out")"
assert_eq "claim returns the lease comment handle" "1" "$(jq -r '.lease_comment_id' <<<"$out")"
assert_contains "claim assigns via REST" "$(calls)" "ADD_ASSIGNEE alice"
cleanup_scenario

# [foreign assignee] our assignment lands, but bob already holds the item →
# conflict (7), and our own @me assignment is rolled back.
new_scenario
printf 'alice\n' >"$GH_STUB_DIR/login"
jq -cn '["alice","bob"]' >"$GH_STUB_DIR/assignees"
lease_array 1 "$(marker alice "$FUTURE" 24)" >"$GH_STUB_DIR/lease-comments"
rc=0
bash "$CLAIM" "$ID" --ttl-hours 24 >/dev/null 2>&1 || rc=$?
assert_eq "claim returns conflict (7) when another login is assigned" "7" "$rc"
assert_contains "claim rolls its own assignment back on conflict" "$(calls)" "REMOVE_ASSIGNEE alice"
cleanup_scenario

# [silently dropped assignment] REST POST /assignees returns 201 but drops a login
# that cannot be assigned. Without an explicit landed-check claim would report a
# held lease while list-frontier still saw the item unassigned — two workers on one
# item. Must fail auth (4) instead, and never post a lease comment.
new_scenario
printf 'alice\n' >"$GH_STUB_DIR/login"
jq -cn '[]' >"$GH_STUB_DIR/assignees"
lease_array 1 "$(marker alice "$FUTURE" 24)" >"$GH_STUB_DIR/lease-comments"
rc=0
bash "$CLAIM" "$ID" --ttl-hours 24 >/dev/null 2>&1 || rc=$?
assert_eq "claim fails auth (4) when the assignment is silently dropped" "4" "$rc"
assert_not_contains "claim posts no lease when the assignment never landed" "$(calls)" "POST_COMMENT"
cleanup_scenario

# ===========================================================================
# Finding 4 — release ends the caller's own live lease early.
# ===========================================================================

# [attended claim, flip, release, same-login claim] the attend-queue row sequence
# against persistent stub state. Before the release, a same-login claim backs off on
# the attended session's still-live lease; after it, the same claim holds.
new_scenario
: >"$GH_STUB_DIR/stateful"
printf 'alice\n' >"$GH_STUB_DIR/login"
printf '[]\n' >"$GH_STUB_DIR/assignees"
printf '[]\n' >"$GH_STUB_DIR/lease-comments"
out="$(bash "$CLAIM" "$ID" --ttl-hours 24 2>/dev/null)"
rc=$?
assert_eq "attended claim succeeds (0)" "0" "$rc"
ATTENDED_CID="$(jq -r '.lease_comment_id' <<<"$out")"
assert_eq "attended claim returns lease handle 1" "1" "$ATTENDED_CID"
# The role-label flip is a label edit outside the seam; the assignee clear after it
# is the adapter's REST assignee edit.
gh api --method DELETE "repos/acme/widgets/issues/1/assignees" -f "assignees[]=alice" >/dev/null
assert_eq "flip clears the attended assignee" "[]" "$(jq -c . "$GH_STUB_DIR/assignees")"
rc=0
bash "$CLAIM" "$ID" --ttl-hours 24 >/dev/null 2>&1 || rc=$?
assert_eq "without release, a same-login claim backs off (7) on the live lease" "7" "$rc"
out="$(bash "$RELEASE" "$ID" --lease-comment-id "$ATTENDED_CID" 2>/dev/null)"
rc=$?
assert_eq "release succeeds (0) on the caller's live lease" "0" "$rc"
assert_eq "release reports released:true" "true" "$(jq -r '.released' <<<"$out")"
assert_eq "release emits schema_version" "1.0" "$(jq -r '.schema_version' <<<"$out")"
assert_contains "release PATCHes the attended lease comment" "$(calls)" "PATCH $ATTENDED_CID"
released_body="$(jq -r --argjson id "$ATTENDED_CID" '.[] | select(.id == $id) | .body' "$GH_STUB_DIR/lease-comments")"
released_body="${released_body#<!-- work-item-lease v1 }"
assert_eq "released lease carries superseded_at" "true" \
  "$(jq -r 'has("superseded_at")' <<<"${released_body% -->}")"
patches_before="$(grep -c '^PATCH' "$GH_STUB_DIR/calls.log")"
out="$(bash "$RELEASE" "$ID" --lease-comment-id "$ATTENDED_CID" 2>/dev/null)"
rc=$?
assert_eq "re-release is an idempotent no-op (0)" "0" "$rc"
assert_eq "re-release reports released:false" "false" "$(jq -r '.released' <<<"$out")"
assert_eq "re-release writes nothing" "$patches_before" "$(grep -c '^PATCH' "$GH_STUB_DIR/calls.log")"
out="$(bash "$CLAIM" "$ID" --ttl-hours 24 2>/dev/null)"
rc=$?
assert_eq "after release, a same-login claim succeeds (0)" "0" "$rc"
assert_eq "the lane's claim holds a new lease handle" "3" "$(jq -r '.lease_comment_id' <<<"$out")"
cleanup_scenario

# [foreign holder] a live lease held by another login is refused, never superseded.
new_scenario
printf 'alice\n' >"$GH_STUB_DIR/login"
BOB_MARKER="$(marker bob "$FUTURE" 24)"
lease_array 123 "$BOB_MARKER" >"$GH_STUB_DIR/lease-comments"
jq -cn --arg b "$BOB_MARKER" '{body:$b, issue:"1"}' >"$GH_STUB_DIR/comment"
rc=0
bash "$RELEASE" "$ID" --lease-comment-id 123 >/dev/null 2>&1 || rc=$?
assert_eq "release refuses (7) a lease another login holds" "7" "$rc"
assert_not_contains "release does not supersede a foreign lease" "$(calls)" "PATCH"
cleanup_scenario

# [not the active lease] an older non-superseded lease under a newer claim.
new_scenario
printf 'alice\n' >"$GH_STUB_DIR/login"
OLD_MARKER="$(marker alice "$FUTURE" 24)"
NEW_MARKER="$(marker alice "$FUTURE" 24)"
jq -cn --arg o "$OLD_MARKER" --arg n "$NEW_MARKER" \
  '[{id:100, node_id:"MDEx", body:$o, created_at:"2020-01-01T00:00:00Z"},
    {id:200, node_id:"MDEx", body:$n, created_at:"2020-01-01T00:00:00Z"}]' >"$GH_STUB_DIR/lease-comments"
jq -cn --arg b "$OLD_MARKER" '{body:$b, issue:"1"}' >"$GH_STUB_DIR/comment"
rc=0
bash "$RELEASE" "$ID" --lease-comment-id 100 >/dev/null 2>&1 || rc=$?
assert_eq "release refuses (7) a handle that is not the active lease" "7" "$rc"
assert_not_contains "release writes nothing for a stale handle" "$(calls)" "PATCH"
cleanup_scenario

# [cross-issue handle] the comment belongs to a different issue.
new_scenario
printf 'alice\n' >"$GH_STUB_DIR/login"
jq -cn --arg b "$(marker alice "$FUTURE" 24)" '{body:$b, issue:"2"}' >"$GH_STUB_DIR/comment"
rc=0
bash "$RELEASE" "$ID" --lease-comment-id 123 >/dev/null 2>&1 || rc=$?
assert_eq "release refuses (7) another issue's lease comment" "7" "$rc"
assert_not_contains "release writes nothing for a cross-issue handle" "$(calls)" "PATCH"
cleanup_scenario

# [expired] an expired active lease blocks nobody: no-op, no write.
new_scenario
printf 'alice\n' >"$GH_STUB_DIR/login"
EXP_MARKER="$(marker alice "$PAST" 24)"
lease_array 123 "$EXP_MARKER" >"$GH_STUB_DIR/lease-comments"
jq -cn --arg b "$EXP_MARKER" '{body:$b, issue:"1"}' >"$GH_STUB_DIR/comment"
out="$(bash "$RELEASE" "$ID" --lease-comment-id 123 2>/dev/null)"
rc=$?
assert_eq "release on an expired lease is a no-op (0)" "0" "$rc"
assert_eq "expired release reports released:false" "false" "$(jq -r '.released' <<<"$out")"
assert_not_contains "release writes nothing for an expired lease" "$(calls)" "PATCH"
cleanup_scenario

[[ $FAILED -eq 0 ]] || exit 1
