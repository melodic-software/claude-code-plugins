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
#       the caller's active one;
#   (5) a lane's lease-only claim and release under a --holder override: a local
#       claim backs off while the lane lease is live and holds once it is
#       released, and a lane claim backs off on a live local lease;
#   (6) claim --phase writes the lease's phase and renew-lease keeps it.
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
      [[ ! -f "$d/list-fails-$n" ]] || exit 1
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
  *"api user"*)
    printf 'API_USER\n' >>"$d/calls.log"
    cat "$d/login" 2>/dev/null || printf 'alice\n'
    ;;
  *"-f body="*)
    printf 'POST_COMMENT\n' >>"$d/calls.log"
    if [[ -f "$d/stateful" ]]; then
      cid="$(jq -r '(map(.id) | max // 0) + 1' "$d/lease-comments")"
      body="$(stub_body_arg "$@")"
      jq -c --argjson id "$cid" --arg b "$body" \
        '. + [{id: $id, node_id: "MDEx", body: $b, created_at: "2020-01-01T00:00:00Z", author_association: "MEMBER"}]' \
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

lease_array() { jq -cn --argjson id "$1" --arg body "$2" '[{id:$id, node_id:"MDEx", body:$body, created_at:"2020-01-01T00:00:00Z", author_association:"MEMBER"}]'; }

new_scenario() {
  GH_STUB_DIR="$(mktemp -d "$TMP_ROOT/d.XXXXXX")"
  export GH_STUB_DIR
  : >"$GH_STUB_DIR/calls.log"
}
calls() { cat "$GH_STUB_DIR/calls.log"; }
cleanup_scenario() { rm -rf "$GH_STUB_DIR"; }

PAST="2020-01-01T00:00:00Z"   # renewed_at + ttl long elapsed → expired
FUTURE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" # renewed now → live for its TTL

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
  '[{id:100, node_id:"MDEx", body:$o, created_at:"2020-01-01T00:00:00Z", author_association:"MEMBER"},
    {id:200, node_id:"MDEx", body:$n, created_at:"2020-01-01T00:00:00Z", author_association:"MEMBER"}]' >"$GH_STUB_DIR/lease-comments"
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

# ===========================================================================
# Finding 5 — a lane claims lease-only under a --holder override (an
# installation token cannot call `gh api user`), and arbitration is by
# lease-comment order against local claims.
# ===========================================================================
LANE=987654

# [lane lease live, then released] the lane posts its lease with no assignment;
# a local claim made while it is live backs off and drops its own assignment;
# after the lane's release the same local claim holds.
new_scenario
: >"$GH_STUB_DIR/stateful"
printf 'alice\n' >"$GH_STUB_DIR/login"
printf '[]\n' >"$GH_STUB_DIR/assignees"
printf '[]\n' >"$GH_STUB_DIR/lease-comments"
out="$(bash "$CLAIM" "$ID" --ttl-hours 2 --lease-only --holder "$LANE" 2>/dev/null)"
rc=$?
assert_eq "lane lease-only claim succeeds (0)" "0" "$rc"
assert_eq "lane claim names the override holder" "$LANE" "$(jq -r '.holder' <<<"$out")"
LANE_CID="$(jq -r '.lease_comment_id' <<<"$out")"
assert_not_contains "lane claim assigns no one" "$(calls)" "ADD_ASSIGNEE"
assert_not_contains "lane claim never calls gh api user" "$(calls)" "API_USER"
assert_eq "lane lease names the holder in its comment" "$LANE" \
  "$(jq -r '.[0].body | ltrimstr("<!-- work-item-lease v1 ") | rtrimstr(" -->") | fromjson | .holder' "$GH_STUB_DIR/lease-comments")"
rc=0
bash "$CLAIM" "$ID" --ttl-hours 24 >/dev/null 2>&1 || rc=$?
assert_eq "a local claim backs off (7) while the lane lease is live" "7" "$rc"
assert_contains "the backed-off local claim drops its own assignment" "$(calls)" "REMOVE_ASSIGNEE alice"
assert_eq "no assignee is left after the back-off" "[]" "$(jq -c . "$GH_STUB_DIR/assignees")"
: >"$GH_STUB_DIR/calls.log"
out="$(bash "$RELEASE" "$ID" --lease-comment-id "$LANE_CID" --holder "$LANE" 2>/dev/null)"
rc=$?
assert_eq "lane release under --holder succeeds (0)" "0" "$rc"
assert_eq "lane release reports released:true" "true" "$(jq -r '.released' <<<"$out")"
assert_not_contains "lane release never calls gh api user" "$(calls)" "API_USER"
out="$(bash "$CLAIM" "$ID" --ttl-hours 24 2>/dev/null)"
rc=$?
assert_eq "after the lane release, the local claim succeeds (0)" "0" "$rc"
assert_eq "the local claim holds as alice" "alice" "$(jq -r '.holder' <<<"$out")"
cleanup_scenario

# [live local lease] a lane run finding a live local lease backs off (7), touches
# no assignee, and supersedes its own lease so it blocks nobody.
new_scenario
: >"$GH_STUB_DIR/stateful"
printf '["alice"]\n' >"$GH_STUB_DIR/assignees"
lease_array 1 "$(marker alice "$FUTURE" 24)" >"$GH_STUB_DIR/lease-comments"
rc=0
bash "$CLAIM" "$ID" --ttl-hours 2 --lease-only --holder "$LANE" >/dev/null 2>&1 || rc=$?
assert_eq "a lane claim backs off (7) on a live local lease" "7" "$rc"
assert_not_contains "the lane back-off touches no assignee" "$(calls)" "ASSIGNEE"
assert_eq "the lane's own lease is superseded" "true" \
  "$(jq -r '.[] | select(.id == 2) | .body | ltrimstr("<!-- work-item-lease v1 ") | rtrimstr(" -->") | fromjson | has("superseded_at")' "$GH_STUB_DIR/lease-comments")"
cleanup_scenario

# [foreign holder under override] --holder does not let a lane release a local lease.
new_scenario
LOCAL_MARKER="$(marker alice "$FUTURE" 24)"
lease_array 123 "$LOCAL_MARKER" >"$GH_STUB_DIR/lease-comments"
jq -cn --arg b "$LOCAL_MARKER" '{body:$b, issue:"1"}' >"$GH_STUB_DIR/comment"
rc=0
bash "$RELEASE" "$ID" --lease-comment-id 123 --holder "$LANE" >/dev/null 2>&1 || rc=$?
assert_eq "release under --holder refuses (7) another holder's lease" "7" "$rc"
assert_not_contains "release under --holder does not supersede a local lease" "$(calls)" "PATCH"
cleanup_scenario

# [lease author] a lease comment counts only from a member, collaborator or owner,
# or from a bot (an App installed on the repository, association NONE): the lane's
# github-actions[bot] or a consumer's gh-bot.sh App. author_case <label> <association>
# <login> <expected-rc> [user-type]
author_case() {
  new_scenario
  : >"$GH_STUB_DIR/stateful"
  printf 'alice\n' >"$GH_STUB_DIR/login"
  printf '[]\n' >"$GH_STUB_DIR/assignees"
  jq -cn --arg b "$(marker "$3" "$FUTURE" 24)" --arg a "$2" --arg u "$3" --arg t "${5:-User}" \
    '[{id:1, node_id:"MDEx", body:$b, created_at:"2020-01-01T00:00:00Z", author_association:$a, user:{login:$u, type:$t}}]' \
    >"$GH_STUB_DIR/lease-comments"
  rc=0
  bash "$CLAIM" "$ID" --ttl-hours 24 >/dev/null 2>&1 || rc=$?
  assert_eq "$1" "$4" "$rc"
  cleanup_scenario
}
author_case "an outsider-planted lease is ignored: the local claim succeeds (0)" NONE mallory 0
author_case "a github-actions[bot] lease wins: the local claim backs off (7)" NONE "github-actions[bot]" 7 Bot
author_case "a gh-bot.sh App's lease wins: the local claim backs off (7)" NONE "acme-agent[bot]" 7 Bot
author_case "a member's lease wins: the local claim backs off (7)" MEMBER bob 7
author_case "a collaborator's lease wins: the local claim backs off (7)" COLLABORATOR bob 7

# [lease-only failure after the POST] a failed re-list supersedes the comment just
# posted, so no lease nobody holds a handle to blocks the item for its TTL.
new_scenario
: >"$GH_STUB_DIR/stateful"
printf '[]\n' >"$GH_STUB_DIR/lease-comments"
: >"$GH_STUB_DIR/list-fails-1"
rc=0
bash "$CLAIM" "$ID" --ttl-hours 2 --lease-only --holder "$LANE" >/dev/null 2>&1 || rc=$?
assert_eq "a lease-only claim whose re-list fails exits non-zero" "true" "$([[ $rc -ne 0 ]] && echo true || echo false)"
assert_eq "the lease-only claim supersedes its own comment on that failure" "true" \
  "$(jq -r '.[0].body | ltrimstr("<!-- work-item-lease v1 ") | rtrimstr(" -->") | fromjson | has("superseded_at")' "$GH_STUB_DIR/lease-comments")"
cleanup_scenario

# [log injection] a winner's holder is printed with its control characters removed.
new_scenario
: >"$GH_STUB_DIR/stateful"
printf '[]\n' >"$GH_STUB_DIR/assignees"
lease_array 1 "$(marker "$(printf 'bob\n::error::forged')" "$FUTURE" 24)" >"$GH_STUB_DIR/lease-comments"
err="$(bash "$CLAIM" "$ID" --ttl-hours 2 --lease-only --holder "$LANE" 2>&1 >/dev/null)"
assert_eq "the backed-off claim prints no line break from the holder" "false" \
  "$(grep -q '^::error::forged' <<<"$err" && echo true || echo false)"
assert_contains "the backed-off claim still names the holder" "$err" "bob::error::forged"
cleanup_scenario

# [TTL cap] a TTL over the lease cap is refused before any write, since every
# reader treats such a lease as not live; the cap itself is accepted.
ttl_case() {
  local label="$1" want_rc="$2" want_posts="$3" rc=0
  shift 3
  new_scenario
  : >"$GH_STUB_DIR/stateful"
  printf '[]\n' >"$GH_STUB_DIR/lease-comments"
  bash "$CLAIM" "$ID" --lease-only --holder "$LANE" "$@" >/dev/null 2>&1 || rc=$?
  assert_eq "$label: exit" "$want_rc" "$rc"
  assert_eq "$label: lease comments posted" "$want_posts" "$(grep -c POST_COMMENT "$GH_STUB_DIR/calls.log" 2>/dev/null)"
  cleanup_scenario
}
ttl_case "a 169 h claim is refused" 2 0 --ttl-hours 169
ttl_case "a 168 h 1 m claim is refused" 2 0 --ttl-hours 168 --ttl-minutes 1
ttl_case "a 168 h claim is accepted" 0 1 --ttl-hours 168

# [phase] claim --phase writes the field into the lease comment and renew-lease keeps
# it; no --phase writes no field (an implementation claim); an unknown phase is
# refused before any write.
stored_lease() { jq -r --argjson id "$1" '.[] | select(.id == $id) | .body | ltrimstr("<!-- work-item-lease v1 ") | rtrimstr(" -->")' "$GH_STUB_DIR/lease-comments"; }
new_scenario
: >"$GH_STUB_DIR/stateful"
printf 'alice\n' >"$GH_STUB_DIR/login"
printf '[]\n' >"$GH_STUB_DIR/assignees"
printf '[]\n' >"$GH_STUB_DIR/lease-comments"
out="$(bash "$CLAIM" "$ID" --ttl-hours 24 --phase triage 2>/dev/null)"
assert_eq "claim --phase triage succeeds (0)" "0" "$?"
PHASE_CID="$(jq -r '.lease_comment_id' <<<"$out")"
assert_eq "claim --phase triage writes phase into the lease comment" "triage" "$(stored_lease "$PHASE_CID" | jq -r '.phase')"
sleep 1
bash "$RENEW" "$ID" --lease-comment-id "$PHASE_CID" >/dev/null 2>&1
assert_eq "renew-lease on the triage lease succeeds (0)" "0" "$?"
assert_eq "renew-lease keeps the phase" "triage" "$(stored_lease "$PHASE_CID" | jq -r '.phase')"
assert_eq "renew-lease bumped renewed_at past acquired_at" "true" \
  "$(stored_lease "$PHASE_CID" | jq -r '.renewed_at > .acquired_at')"
cleanup_scenario

new_scenario
: >"$GH_STUB_DIR/stateful"
printf 'alice\n' >"$GH_STUB_DIR/login"
printf '[]\n' >"$GH_STUB_DIR/assignees"
printf '[]\n' >"$GH_STUB_DIR/lease-comments"
out="$(bash "$CLAIM" "$ID" --ttl-hours 24 2>/dev/null)"
assert_eq "a claim with no --phase writes no phase field" "false" \
  "$(stored_lease "$(jq -r '.lease_comment_id' <<<"$out")" | jq -r 'has("phase")')"
cleanup_scenario

new_scenario
: >"$GH_STUB_DIR/stateful"
printf '[]\n' >"$GH_STUB_DIR/lease-comments"
rc=0
bash "$CLAIM" "$ID" --ttl-hours 24 --lease-only --holder "$LANE" --phase review >/dev/null 2>&1 || rc=$?
assert_eq "claim refuses an unknown phase (2)" "2" "$rc"
assert_not_contains "a refused phase posts no lease" "$(calls)" "POST_COMMENT"
cleanup_scenario

[[ $FAILED -eq 0 ]] || exit 1
