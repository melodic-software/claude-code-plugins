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
#       the caller's or that an earlier live lease outranks;
#   (5) a lane's lease-only claim and release under a --holder override: a local
#       claim backs off while the lane lease is live and holds once it is
#       released, and a lane claim backs off on a live local lease;
#   (6) claim --phase writes the lease's phase and renew-lease keeps it;
#   (7) a lease held by a completed workflow run (session_id run-<id>) is
#       treated as released, while a live run, a non-run session or an
#       unreadable run status keeps the lease winning;
#   (8) release and renew act on the holder's lease under a newer lease not yet
#       arbitrated, release unassigns only when no other live lease of the login
#       remains, and a same-login loser leaves no assignee that outlives the leases.
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced lib
set -uo pipefail
# In a CI job the adapter wraps its gh calls and records into the job's
# RUNNER_TEMP; the stubs here answer the unwrapped calls. A run lease names its
# run only when GITHUB_SERVER_URL is set; the run-link case below sets it.
unset RUNNER_TEMP GITHUB_SERVER_URL

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../tests/lib.sh"
# shellcheck source=../../lib/lease.sh
source "$SCRIPT_DIR/../../lib/lease.sh"

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
# stub_hook <name>: run $d/hook-<name> once, if present, so a scenario can land another
# verb inside a given call: the n-th lease-list read (list-<n> before it answers,
# list-<n>-after after) or the k-th assignee read (assignees-<k>, after it answers).
stub_hook() {
  local h="${GH_STUB_DIR:?}/hook-$1"
  [[ -f "$h" ]] || return 0
  mv "$h" "$h.ran"
  bash "$h.ran" >/dev/null 2>&1
}
gh() {
  local d="${GH_STUB_DIR:?}" args="$*" a n cid body login
  case "$args" in
  *"--method PATCH"*)
    for a in "$@"; do
      case "$a" in repos/*/issues/comments/*) cid="${a##*/comments/}" ;; *) : ;; esac
    done
    printf 'PATCH %s\n' "$cid" >>"$d/calls.log"
    # The n-th PATCH: $d/patch-lost-<n> fails unapplied; $d/patch-fails-<n> lands but reports
    # failure, as on a timeout.
    n=$(($(cat "$d/patch.count" 2>/dev/null || printf '0') + 1))
    printf '%s\n' "$n" >"$d/patch.count"
    [[ ! -f "$d/patch-lost-$n" ]] || return 1
    if [[ -f "$d/stateful" ]]; then
      body="$(stub_body_arg "$@")"
      jq -c --argjson id "$cid" --arg b "$body" 'map(if .id == $id then .body = $b else . end)' \
        "$d/lease-comments" >"$d/lease-comments.tmp" && mv "$d/lease-comments.tmp" "$d/lease-comments"
    fi
    [[ ! -f "$d/patch-fails-$n" ]] || return 1
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
    # $d/assign-fails: the assignment lands but the call reports failure, as on a timeout.
    [[ ! -f "$d/assign-fails" ]] || return 1
    cat "$d/assignees" 2>/dev/null || printf '[]\n'
    ;;
  *".assignees[].login"*)
    n=$(($(cat "$d/assignees.count" 2>/dev/null || printf '0') + 1))
    printf '%s\n' "$n" >"$d/assignees.count"
    [[ ! -f "$d/assignees-fails-$n" ]] || return 1
    cat "$d/assignees"
    stub_hook "assignees-$n"
    ;;
  # A workflow run's status read; no $d/run-status file is an unreadable status.
  *"/actions/runs/"*)
    printf 'RUN_READ %s\n' "${args##*/actions/runs/}" >>"$d/calls.log"
    [[ -f "$d/run-status" ]] || return 1
    cat "$d/run-status"
    ;;
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
      stub_hook "list-$n"
      if [[ -f "$d/lease-comments-$n" ]]; then cat "$d/lease-comments-$n"; else cat "$d/lease-comments"; fi
      stub_hook "list-$n-after"
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
export -f gh stub_body_arg stub_login_arg stub_hook

# hook <name> <command…>: arm stub_hook <name> to run <command…>, writing its exit code to
# hook-<name>.rc. next_read <list|assignees> <offset>: the hook name for the read <offset>
# calls after the reads made so far.
hook() {
  local name="$1"
  shift
  {
    printf '%q ' "$@"
    printf '\nprintf "%%s\\n" "$?" >%q\n' "$GH_STUB_DIR/hook-$name.rc"
  } >"$GH_STUB_DIR/hook-$name"
}
hook_rc() { cat "$GH_STUB_DIR/hook-$1.rc" 2>/dev/null || printf 'hook did not run\n'; }
next_read() {
  local file=lease-comments.count
  [[ "$1" == list ]] || file=assignees.count
  printf '%s-%s' "$1" "$(($(cat "$GH_STUB_DIR/$file" 2>/dev/null || printf '0') + $2))"
}

# marker <holder> <renewed_at> <ttl> [session_id] — echo a lease marker comment body.
marker() {
  local json
  json="$(jq -cn --arg h "$1" --arg r "$2" --argjson t "$3" --arg s "${4:-}" \
    '{schema_version:"1.0", holder:$h, acquired_at:"2020-01-01T00:00:00Z", renewed_at:$r, ttl_hours:$t}
     + (if $s != "" then {session_id:$s} else {} end)')"
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
# conflict (7), and our own @me assignment is rolled back once, alice holding no lease.
new_scenario
printf 'alice\n' >"$GH_STUB_DIR/login"
jq -cn '["alice","bob"]' >"$GH_STUB_DIR/assignees"
printf '[]\n' >"$GH_STUB_DIR/lease-comments"
rc=0
bash "$CLAIM" "$ID" --ttl-hours 24 >/dev/null 2>&1 || rc=$?
assert_eq "claim returns conflict (7) when another login is assigned" "7" "$rc"
assert_eq "claim rolls its own assignment back once on conflict" "1" "$(grep -c '^REMOVE_ASSIGNEE alice' "$GH_STUB_DIR/calls.log")"
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

# [outranked] two live leases: the earlier one holds the item (claim step 4) and the
# newer one is a claimant that has not backed off. The newer handle is refused and
# superseded; the earlier one is released.
two_live_leases() {
  jq -cn --arg o "$(marker alice "$FUTURE" 24)" --arg n "$(marker alice "$FUTURE" 24)" \
    '[{id:100, node_id:"MDEx", body:$o, created_at:"2020-01-01T00:00:00Z", author_association:"MEMBER"},
      {id:200, node_id:"MDEx", body:$n, created_at:"2020-01-01T00:00:00Z", author_association:"MEMBER"}]' >"$GH_STUB_DIR/lease-comments"
  jq -cn --arg b "$(marker alice "$FUTURE" 24)" '{body:$b, issue:"1"}' >"$GH_STUB_DIR/comment"
}
new_scenario
printf 'alice\n' >"$GH_STUB_DIR/login"
two_live_leases
rc=0
bash "$RELEASE" "$ID" --lease-comment-id 200 >/dev/null 2>&1 || rc=$?
assert_eq "release refuses (7) a handle outranked by an earlier live lease" "7" "$rc"
assert_contains "release supersedes an outranked handle" "$(calls)" "PATCH 200"
assert_not_contains "release leaves the earlier live lease alone" "$(calls)" "PATCH 100"
cleanup_scenario
new_scenario
printf 'alice\n' >"$GH_STUB_DIR/login"
two_live_leases
rc=0
bash "$RELEASE" "$ID" --lease-comment-id 100 >/dev/null 2>&1 || rc=$?
assert_eq "release succeeds (0) for the holder's lease under a newer live lease" "0" "$rc"
assert_contains "release PATCHes the holder's lease under a newer live lease" "$(calls)" "PATCH 100"
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

# ===========================================================================
# Finding 7 — a live lease held by a completed workflow run (session_id run-<id>)
# is treated as released: one run read, the dead lease superseded in place, and
# the claim holds. A live run, a non-run session or an unreadable status still wins.
# ===========================================================================
# run_lease_case <label> <session_id> <run-status or "-" for unreadable>
# <expected-rc> <expected run reads>
run_lease_case() {
  local label="$1" sid="$2" status="$3" want_rc="$4" want_reads="$5" rc=0
  new_scenario
  : >"$GH_STUB_DIR/stateful"
  [[ "$status" == - ]] || printf '%s\n' "$status" >"$GH_STUB_DIR/run-status"
  lease_array 1 "$(marker "$LANE" "$FUTURE" 3 "$sid")" >"$GH_STUB_DIR/lease-comments"
  bash "$CLAIM" "$ID" --ttl-hours 2 --lease-only --holder "$LANE" --session-id run-200 >/dev/null 2>&1 || rc=$?
  assert_eq "$label: exit" "$want_rc" "$rc"
  assert_eq "$label: run status reads" "$want_reads" "$(grep -c '^RUN_READ' "$GH_STUB_DIR/calls.log")"
  assert_eq "$label: the earlier lease is superseded" "$([[ $want_rc == 0 ]] && echo true || echo false)" \
    "$(stored_lease 1 | jq -r 'has("superseded_at")')"
  assert_eq "$label: our own lease is superseded" "$([[ $want_rc == 7 ]] && echo true || echo false)" \
    "$(stored_lease 2 | jq -r 'has("superseded_at")')"
}
run_lease_case "a completed run's lease is taken over" run-100 completed 0 1
assert_contains "the takeover reads that run's status" "$(calls)" "RUN_READ 100"
assert_eq "the superseded lease keeps its session_id" "run-100" "$(stored_lease 1 | jq -r '.session_id')"
cleanup_scenario
run_lease_case "an in-progress run's lease is refused" run-100 in_progress 7 1
cleanup_scenario
run_lease_case "a queued run's lease is refused" run-100 queued 7 1
cleanup_scenario
run_lease_case "a lane-N session's lease is refused with no run read" lane-3 completed 7 0
cleanup_scenario
run_lease_case "a UUID session's lease is refused with no run read" 3f2b8c1e-9a4d-4e7f-8b1a-2c5d6e7f8a9b completed 7 0
cleanup_scenario
run_lease_case "an unreadable run status is refused" run-100 - 7 1
cleanup_scenario
# [unreadable status message] the back-off names the run whose status it could not read.
new_scenario
: >"$GH_STUB_DIR/stateful"
lease_array 1 "$(marker "$LANE" "$FUTURE" 3 run-100)" >"$GH_STUB_DIR/lease-comments"
rc=0
err="$(bash "$CLAIM" "$ID" --ttl-hours 2 --lease-only --holder "$LANE" --session-id run-200 2>&1 >/dev/null)" || rc=$?
assert_eq "an unreadable run status backs off (7)" "7" "$rc"
assert_contains "an unreadable run status says the lease is kept" "$err" "claim: could not read run 100 status; lease kept"
cleanup_scenario
# [shape boundary] only run-<positive integer without a leading zero> is a run lease.
for sid in run-0 run-0123 xrun-100 run-100x; do
  run_lease_case "a $sid session's lease is refused with no run read" "$sid" completed 7 0
  cleanup_scenario
done

# [run link] a workflow run's lease comment links its run after the marker, and the
# lease still reads; any other session, or a server URL of another shape, adds nothing.
link_case() {
  local label="$1" sid="$2" server="$3" want="$4" out
  new_scenario
  : >"$GH_STUB_DIR/stateful"
  printf '[]\n' >"$GH_STUB_DIR/lease-comments"
  out="$(GITHUB_SERVER_URL="$server" bash "$CLAIM" "$ID" --ttl-hours 2 --lease-only --holder "$LANE" --session-id "$sid" 2>/dev/null)"
  assert_eq "$label: the claim holds" "$LANE" "$(jq -r '.holder' <<<"$out")"
  local body
  body="$(jq -r '.[0].body' "$GH_STUB_DIR/lease-comments")"
  assert_eq "$label: the text after the marker" "$want" "${body#*-->}"
  assert_eq "$label: the lease reads past it" "$sid" "$(wit_lease_json "$body" | jq -r '.session_id')"
  cleanup_scenario
}
link_case "a run lease" run-200 https://github.com $'\n\nClaimed by [workflow run 200](https://github.com/acme/widgets/actions/runs/200).'
link_case "a session lease" lane-3 https://github.com ""
link_case "a run lease with no https server" run-200 'http://x) [y](https://z' ""

# three_lease_case <label> <first session_id> <second session_id> <expected-rc>
# <expected run reads>: two earlier live leases, then ours (id 3). Every run read
# answers completed, so the run-100 lease is a dead run's.
three_lease_case() {
  local label="$1" s1="$2" s2="$3" want_rc="$4" want_reads="$5" rc=0
  new_scenario
  : >"$GH_STUB_DIR/stateful"
  printf 'completed\n' >"$GH_STUB_DIR/run-status"
  jq -cn --arg a "$(marker "$LANE" "$FUTURE" 3 "$s1")" --arg b "$(marker "$LANE" "$FUTURE" 3 "$s2")" \
    '[{id:1, node_id:"MDEx", body:$a, created_at:"2020-01-01T00:00:00Z", author_association:"MEMBER"},
      {id:2, node_id:"MDEx", body:$b, created_at:"2020-01-01T00:00:00Z", author_association:"MEMBER"}]' \
    >"$GH_STUB_DIR/lease-comments"
  bash "$CLAIM" "$ID" --ttl-hours 2 --lease-only --holder "$LANE" --session-id run-200 >/dev/null 2>&1 || rc=$?
  assert_eq "$label: exit" "$want_rc" "$rc"
  assert_eq "$label: run status reads" "$want_reads" "$(grep -c '^RUN_READ' "$GH_STUB_DIR/calls.log")"
  cleanup_scenario
}
three_lease_case "a dead run's lease before a live lane lease: the lane lease wins" run-100 lane-3 7 1
three_lease_case "a live lane lease before a dead run's lease wins with no run read" lane-3 run-100 7 0

# ===========================================================================
# Finding 8 — the holder's release and renew act under a newer, not yet arbitrated
# lease; a same-login hand-back unassigns only when no other live lease of that login
# remains; a same-login loser does not strand an assignee the winner no longer holds.
# Each scenario starts with alice's attended claim holding lease 1.
# ===========================================================================
attended_scenario() {
  new_scenario
  : >"$GH_STUB_DIR/stateful"
  printf 'alice\n' >"$GH_STUB_DIR/login"
  printf '[]\n' >"$GH_STUB_DIR/assignees"
  printf '[]\n' >"$GH_STUB_DIR/lease-comments"
  bash "$CLAIM" "$ID" --ttl-hours 24 >/dev/null 2>&1
  assert_eq "attended claim holds lease 1 assigned to alice" '["alice"]' "$(jq -c . "$GH_STUB_DIR/assignees")"
}
assignees_now() { jq -c . "$GH_STUB_DIR/assignees"; }
superseded() { stored_lease "$1" | jq -r 'has("superseded_at")'; }

# [release under a lane lease] the lane has posted lease 2 and its re-read is next; the
# holder releases lease 1 in that window. The release ends lease 1 and unassigns alice,
# and the lane's arbitration then finds lease 2 earliest and holds.
attended_scenario
h="$(next_read list 1)"
hook "$h" bash "$RELEASE" "$ID" --lease-comment-id 1
rc=0
out="$(bash "$CLAIM" "$ID" --ttl-hours 2 --lease-only --holder "$LANE" 2>/dev/null)" || rc=$?
assert_eq "the holder's release under an unarbitrated lane lease succeeds (0)" "0" "$(hook_rc "$h")"
assert_contains "that release PATCHes the holder's own lease comment" "$(calls)" "PATCH 1"
assert_eq "the holder's lease is superseded" "true" "$(superseded 1)"
assert_eq "the lane's claim then wins (0)" "0" "$rc"
assert_eq "the lane holds lease 2" "2" "$(jq -r '.lease_comment_id' <<<"$out")"
assert_eq "the released holder is unassigned" "[]" "$(assignees_now)"
cleanup_scenario

# [renew under a lane lease] the same window with a renew: it renews lease 1, which keeps
# winning, so the lane backs off.
attended_scenario
sleep 1
h="$(next_read list 1)"
hook "$h" bash "$RENEW" "$ID" --lease-comment-id 1
rc=0
bash "$CLAIM" "$ID" --ttl-hours 2 --lease-only --holder "$LANE" >/dev/null 2>&1 || rc=$?
assert_eq "the holder's renew under an unarbitrated lane lease succeeds (0)" "0" "$(hook_rc "$h")"
assert_contains "that renew PATCHes the holder's own lease comment" "$(calls)" "PATCH 1"
assert_eq "the renewed lease moved renewed_at past acquired_at" "true" "$(stored_lease 1 | jq -r '.renewed_at > .acquired_at')"
assert_eq "the lane backs off (7) on the renewed lease" "7" "$rc"
assert_eq "the lane's lease is superseded" "true" "$(superseded 2)"
cleanup_scenario

# [hand-back after the other claim posts] a same-login triage claim has posted lease 2
# and its re-read is next when the attended session releases lease 1. The release sees
# lease 2 and leaves alice assigned, and triage holds lease 2 with alice assigned.
attended_scenario
h="$(next_read list 1)"
hook "$h" bash "$RELEASE" "$ID" --lease-comment-id 1
rc=0
out="$(bash "$CLAIM" "$ID" --ttl-hours 1 --phase triage 2>/dev/null)" || rc=$?
assert_eq "the attended release succeeds (0) while triage's lease is pending" "0" "$(hook_rc "$h")"
assert_eq "triage's claim holds (0)" "0" "$rc"
assert_eq "triage holds lease 2" "2" "$(jq -r '.lease_comment_id' <<<"$out")"
assert_eq "alice stays assigned for triage's live lease" '["alice"]' "$(assignees_now)"
assert_not_contains "the hand-back never removes alice" "$(calls)" "REMOVE_ASSIGNEE alice"
cleanup_scenario

# [hand-back before the other claim posts] the release lands after triage's assignee
# check and before its post, so it sees no other lease and unassigns alice; triage then
# wins and puts its assignee back.
attended_scenario
h="$(next_read assignees 1)"
hook "$h" bash "$RELEASE" "$ID" --lease-comment-id 1
rc=0
bash "$CLAIM" "$ID" --ttl-hours 1 --phase triage >/dev/null 2>&1 || rc=$?
assert_eq "the attended release succeeds (0) before triage posts" "0" "$(hook_rc "$h")"
assert_eq "triage's claim holds (0)" "0" "$rc"
assert_eq "triage's claim restores alice after the release removed her" '["alice"]' "$(assignees_now)"
cleanup_scenario

# [claim inside the release's unassign] triage posts and wins between the release's
# lease check and its unassign; the release's re-read finds triage's lease and puts
# alice back.
attended_scenario
h="$(next_read assignees 1)"
hook "$h" bash "$CLAIM" "$ID" --ttl-hours 1 --phase triage
out="$(bash "$RELEASE" "$ID" --lease-comment-id 1 2>/dev/null)"
rc=$?
assert_eq "the attended release succeeds (0)" "0" "$rc"
assert_eq "triage's claim inside the release holds (0)" "0" "$(hook_rc "$h")"
assert_eq "the release restores alice for triage's live lease" '["alice"]' "$(assignees_now)"
cleanup_scenario

# [stranded, caller cleared first] the attended caller clears alice before releasing; a
# same-login triage claim made in between loses to lease 1 and leaves alice assigned for
# that live lease; once lease 1 is released no assignee is left without a lease.
attended_scenario
gh api --method DELETE "repos/acme/widgets/issues/1/assignees" -f "assignees[]=alice" >/dev/null
rc=0
bash "$CLAIM" "$ID" --ttl-hours 1 --phase triage >/dev/null 2>&1 || rc=$?
assert_eq "triage backs off (7) on the attended lease" "7" "$rc"
assert_eq "the losing triage claim leaves alice assigned for live lease 1" '["alice"]' "$(assignees_now)"
bash "$RELEASE" "$ID" --lease-comment-id 1 >/dev/null 2>&1
assert_eq "after the release no assignee is left" "[]" "$(assignees_now)"
out="$(bash "$RECLAIM" "$ID" 2>/dev/null)"
assert_eq "reclaim finds no active lease" "no active lease record" "$(jq -r '.reason' <<<"$out")"
assert_eq "and no assignee to strand" "[]" "$(assignees_now)"
cleanup_scenario

# [stranded, release-only hand-back] triage loses to lease 1 while alice was already
# assigned, so it keeps her for the winner; the attended release then unassigns her,
# since no other live lease of alice's remains.
attended_scenario
rc=0
bash "$CLAIM" "$ID" --ttl-hours 1 --phase triage >/dev/null 2>&1 || rc=$?
assert_eq "triage backs off (7) on the attended lease" "7" "$rc"
assert_eq "the losing triage claim keeps the winner's assignee" '["alice"]' "$(assignees_now)"
bash "$RELEASE" "$ID" --lease-comment-id 1 >/dev/null 2>&1
assert_eq "the attended release unassigns alice" "[]" "$(assignees_now)"
out="$(bash "$RECLAIM" "$ID" 2>/dev/null)"
assert_eq "reclaim finds no active lease" "no active lease record" "$(jq -r '.reason' <<<"$out")"
assert_eq "and no assignee to strand" "[]" "$(assignees_now)"
cleanup_scenario

# [default claim dies after its post] a failed re-list supersedes the comment just posted
# and rolls back the assignment, as a lease-only claim does.
new_scenario
: >"$GH_STUB_DIR/stateful"
printf 'alice\n' >"$GH_STUB_DIR/login"
printf '[]\n' >"$GH_STUB_DIR/assignees"
printf '[]\n' >"$GH_STUB_DIR/lease-comments"
: >"$GH_STUB_DIR/list-fails-1"
rc=0
bash "$CLAIM" "$ID" --ttl-hours 24 >/dev/null 2>&1 || rc=$?
assert_eq "a default claim whose re-list fails exits non-zero" "true" "$([[ $rc -ne 0 ]] && echo true || echo false)"
assert_eq "the default claim supersedes its own comment on that failure" "true" "$(superseded 1)"
assert_eq "the default claim rolls back its assignment" "[]" "$(assignees_now)"
cleanup_scenario

# ===========================================================================
# Finding 9 — renew never revives a lease near expiry over a newer claimant, and the
# assignee hand-back decides on lease lists read after each side's own supersede.
# ===========================================================================
# put_lease <id> <body>: add lease comment <id>, or replace its body, in the stub's state.
put_lease() {
  jq -c --argjson id "$1" --arg b "$2" \
    'map(select(.id != $id)) + [{id: $id, node_id: "MDEx", body: $b, created_at: "2020-01-01T00:00:00Z", author_association: "MEMBER"}] | sort_by(.id)' \
    "$GH_STUB_DIR/lease-comments" >"$GH_STUB_DIR/lease-comments.tmp" && mv "$GH_STUB_DIR/lease-comments.tmp" "$GH_STUB_DIR/lease-comments"
}
export -f put_lease
superseded_marker() { printf '<!-- work-item-lease v1 %s -->' "$(jq -cn --arg h "$1" --arg r "$FUTURE" '{schema_version:"1.0", holder:$h, acquired_at:$r, renewed_at:$r, ttl_hours:1, superseded_at:$r}')"; }
# short_marker <holder>: a lease renewed now with a one-minute TTL, inside the skew margin.
short_marker() { printf '<!-- work-item-lease v1 %s -->' "$(jq -cn --arg h "$1" --arg r "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{schema_version:"1.0", holder:$h, acquired_at:$r, renewed_at:$r, ttl_hours:0, ttl_minutes:1}')"; }

# [renew near expiry, newer lease pending] lease 1 expires within the skew margin and a
# lane has posted lease 2. The lane may already have found lease 1 expired and started,
# so a renew that revived lease 1 would put two claimants on the item: refused.
new_scenario
SHORT_MARKER="$(short_marker alice)"
jq -cn --arg a "$SHORT_MARKER" --arg b "$(marker "$LANE" "$FUTURE" 2)" \
  '[{id:1, node_id:"MDEx", body:$a, created_at:"2020-01-01T00:00:00Z", author_association:"MEMBER"},
    {id:2, node_id:"MDEx", body:$b, created_at:"2020-01-01T00:00:00Z", author_association:"MEMBER"}]' >"$GH_STUB_DIR/lease-comments"
jq -cn --arg b "$SHORT_MARKER" '{body:$b, issue:"1"}' >"$GH_STUB_DIR/comment"
rc=0
err="$(bash "$RENEW" "$ID" --lease-comment-id 1 2>&1 >/dev/null)" || rc=$?
assert_eq "renew refuses (7) a lease within the skew margin under a newer lease" "7" "$rc"
assert_contains "the refusal names the skew margin, not expiry" "$err" "expires within 300 s"
assert_not_contains "that renew writes nothing" "$(calls)" "PATCH"
cleanup_scenario
# [renew near expiry, alone] the same lease with no newer one still renews.
new_scenario
SHORT_MARKER="$(short_marker alice)"
lease_array 1 "$SHORT_MARKER" >"$GH_STUB_DIR/lease-comments"
jq -cn --arg b "$SHORT_MARKER" '{body:$b, issue:"1"}' >"$GH_STUB_DIR/comment"
rc=0
bash "$RENEW" "$ID" --lease-comment-id 1 >/dev/null 2>&1 || rc=$?
assert_eq "renew within the skew margin succeeds (0) with no newer lease" "0" "$rc"
assert_contains "that renew PATCHes lease 1" "$(calls)" "PATCH 1"
cleanup_scenario

# [renew outranked] renewing the newer of two live leases is refused.
new_scenario
two_live_leases
rc=0
bash "$RENEW" "$ID" --lease-comment-id 200 >/dev/null 2>&1 || rc=$?
assert_eq "renew refuses (7) a handle outranked by an earlier live lease" "7" "$rc"
assert_not_contains "renew writes nothing for an outranked handle" "$(calls)" "PATCH"
cleanup_scenario

# [stale snapshot in the release] a same-login claim posts lease 2 before the release's
# first lease read and supersedes it, losing, right after that read. The release must not
# keep alice for lease 2 on the strength of that read.
attended_scenario
h="$(next_read list 1)"
hook "$h" put_lease 2 "$(marker alice "$FUTURE" 1)"
hook "$h-after" put_lease 2 "$(superseded_marker alice)"
bash "$RELEASE" "$ID" --lease-comment-id 1 >/dev/null 2>&1
assert_eq "the release succeeds with a lease 2 that was live in its first read" "true" "$(superseded 1)"
assert_eq "lease 2 is superseded by its losing claim" "true" "$(superseded 2)"
assert_eq "no assignee is left once every lease is superseded" "[]" "$(assignees_now)"
out="$(bash "$RECLAIM" "$ID" 2>/dev/null)"
assert_eq "reclaim finds no active lease" "no active lease record" "$(jq -r '.reason' <<<"$out")"
cleanup_scenario

# [stale snapshot in the loser] triage's arbitration read shows lease 1 live, but the
# attended release has superseded it by the time triage backs off. The release saw
# triage's lease 2 live and kept alice; triage's own read after its supersede finds no
# other live lease of alice's and removes her.
attended_scenario
h="$(next_read list 1)"
jq -c --arg b "$(marker alice "$FUTURE" 1)" \
  '. + [{id:2, node_id:"MDEx", body:$b, created_at:"2020-01-01T00:00:00Z", author_association:"MEMBER"}]' \
  "$GH_STUB_DIR/lease-comments" >"$GH_STUB_DIR/lease-comments-${h#list-}"
hook "$h" bash "$RELEASE" "$ID" --lease-comment-id 1
rc=0
bash "$CLAIM" "$ID" --ttl-hours 1 --phase triage >/dev/null 2>&1 || rc=$?
assert_eq "the attended release inside triage's arbitration succeeds (0)" "0" "$(hook_rc "$h")"
assert_eq "triage backs off (7) on the lease 1 its read showed" "7" "$rc"
assert_eq "every lease is superseded" "true true" "$(superseded 1) $(superseded 2)"
assert_eq "no assignee is left once every lease is superseded" "[]" "$(assignees_now)"
cleanup_scenario

# [two same-login claims, both unassigned] the winner's claim runs entirely inside the
# loser's, after the loser's assign; the loser must leave alice for the winner's lease,
# and the winner's release then leaves no assignee.
new_scenario
: >"$GH_STUB_DIR/stateful"
printf 'alice\n' >"$GH_STUB_DIR/login"
printf '[]\n' >"$GH_STUB_DIR/assignees"
printf '[]\n' >"$GH_STUB_DIR/lease-comments"
h="$(next_read assignees 1)"
hook "$h" bash "$CLAIM" "$ID" --ttl-hours 24
rc=0
bash "$CLAIM" "$ID" --ttl-hours 1 --phase triage >/dev/null 2>&1 || rc=$?
assert_eq "the inner claim wins (0)" "0" "$(hook_rc "$h")"
assert_eq "the outer claim backs off (7)" "7" "$rc"
assert_eq "the winner holds lease 1" "false" "$(superseded 1)"
assert_eq "alice stays assigned while the winner holds" '["alice"]' "$(assignees_now)"
bash "$RELEASE" "$ID" --lease-comment-id 1 >/dev/null 2>&1
assert_eq "after the winner's release no assignee is left" "[]" "$(assignees_now)"
cleanup_scenario

# ===========================================================================
# Finding 10 — a renew that lands near expiry yields to a newer claimant, a claim's
# failure path keeps a same-login holder's assignee, and a refused release hands back.
# ===========================================================================
# short_scenario: alice's lease 1 expires within the skew margin, alice assigned.
short_scenario() {
  new_scenario
  : >"$GH_STUB_DIR/stateful"
  printf 'alice\n' >"$GH_STUB_DIR/login"
  printf '["alice"]\n' >"$GH_STUB_DIR/assignees"
  lease_array 1 "$(short_marker alice)" >"$GH_STUB_DIR/lease-comments"
}

# [renew lands near expiry] the lane posts lease 2 after the renew's lease read, so every
# check before the PATCH passes; the lane may have found lease 1 expired, so the renew
# must not leave lease 1 live over it.
short_scenario
hook "$(next_read list 1)-after" put_lease 2 "$(marker "$LANE" "$FUTURE" 2)"
rc=0
err="$(bash "$RENEW" "$ID" --lease-comment-id 1 2>&1 >/dev/null)" || rc=$?
assert_eq "a renew landing near expiry under a newer lease exits conflict (7)" "7" "$rc"
assert_contains "the refusal says the renew landed too close to expiry" "$err" "too close to expiry"
assert_eq "the renewed lease 1 is superseded" "true" "$(superseded 1)"
assert_eq "the lane's lease 2 stays live" "false" "$(superseded 2)"
assert_eq "the backed-off renew hands back alice" "[]" "$(assignees_now)"
cleanup_scenario
# [renew lands near expiry, own newer lease] the newer lease is alice's, so the back-off
# keeps her assigned for it.
short_scenario
hook "$(next_read list 1)-after" put_lease 2 "$(marker alice "$FUTURE" 1)"
rc=0
bash "$RENEW" "$ID" --lease-comment-id 1 >/dev/null 2>&1 || rc=$?
assert_eq "a renew yielding to alice's own newer lease exits conflict (7)" "7" "$rc"
assert_eq "that back-off keeps alice for lease 2" '["alice"]' "$(assignees_now)"
cleanup_scenario

# [claim rollback re-adds] alice loses to a lane lease; between her rollback's lease read
# and its removal a same-login claim posts lease 3 and wins. The rollback's re-list after
# the removal sees lease 3 and puts alice back.
new_scenario
: >"$GH_STUB_DIR/stateful"
printf 'alice\n' >"$GH_STUB_DIR/login"
printf '[]\n' >"$GH_STUB_DIR/assignees"
lease_array 1 "$(marker "$LANE" "$FUTURE" 2)" >"$GH_STUB_DIR/lease-comments"
hook list-3 put_lease 3 "$(marker alice "$FUTURE" 1)"
rc=0
bash "$CLAIM" "$ID" --ttl-hours 24 >/dev/null 2>&1 || rc=$?
assert_eq "the claim losing to the lane backs off (7)" "7" "$rc"
assert_eq "its rollback removes alice, then adds her back" "REMOVE_ASSIGNEE alice ADD_ASSIGNEE alice" \
  "$(grep -E '^(REMOVE|ADD)_ASSIGNEE' "$GH_STUB_DIR/calls.log" | tail -n 2 | paste -sd ' ' -)"
assert_eq "alice stays assigned for the same-login winner's lease 3" '["alice"]' "$(assignees_now)"
cleanup_scenario

# [claim rollback re-add, then the lease ends] as above, but lease 3 is superseded before the
# rollback's check after its re-add; the re-add must not outlive every lease.
new_scenario
: >"$GH_STUB_DIR/stateful"
printf 'alice\n' >"$GH_STUB_DIR/login"
printf '[]\n' >"$GH_STUB_DIR/assignees"
lease_array 1 "$(marker "$LANE" "$FUTURE" 2)" >"$GH_STUB_DIR/lease-comments"
hook list-3 put_lease 3 "$(marker alice "$FUTURE" 1)"
hook list-4 put_lease 3 "$(superseded_marker alice)"
rc=0
bash "$CLAIM" "$ID" --ttl-hours 24 >/dev/null 2>&1 || rc=$?
assert_eq "the claim losing to the lane backs off (7)" "7" "$rc"
assert_eq "its rollback removes alice again after the re-add" "2" "$(grep -c '^REMOVE_ASSIGNEE alice' "$GH_STUB_DIR/calls.log")"
assert_eq "no assignee outlives every lease" "[]" "$(assignees_now)"
cleanup_scenario

# [hand-back, lease list fails once] a second alice session fails on its arbitration read
# and its rollback's first list fails too; the retry shows lease 1, so alice is never removed.
attended_scenario
: >"$GH_STUB_DIR/calls.log"
n="$(cat "$GH_STUB_DIR/lease-comments.count")"
: >"$GH_STUB_DIR/list-fails-$((n + 1))"
: >"$GH_STUB_DIR/list-fails-$((n + 2))"
bash "$CLAIM" "$ID" --ttl-hours 1 --phase triage >/dev/null 2>&1
assert_not_contains "the rollback never removes alice for live lease 1" "$(calls)" "REMOVE_ASSIGNEE alice"
assert_eq "alice stays assigned" '["alice"]' "$(assignees_now)"
cleanup_scenario

# [hand-back, assignee read fails] a release whose assignee read fails still removes
# alice, since an assignee no lease holds would block the item for good.
attended_scenario
: >"$GH_STUB_DIR/assignees-fails-$(($(cat "$GH_STUB_DIR/assignees.count") + 1))"
bash "$RELEASE" "$ID" --lease-comment-id 1 >/dev/null 2>&1
assert_contains "the release still removes alice" "$(calls)" "REMOVE_ASSIGNEE alice"
assert_eq "no assignee is left" "[]" "$(assignees_now)"
cleanup_scenario

# [renew near expiry, re-list fails twice] a failed read keeps the lease: the renew
# retries the list once, then keeps lease 1 and says so.
short_scenario
: >"$GH_STUB_DIR/list-fails-2"
: >"$GH_STUB_DIR/list-fails-3"
rc=0
err="$(bash "$RENEW" "$ID" --lease-comment-id 1 2>&1 >/dev/null)" || rc=$?
assert_eq "a renew near expiry whose re-lists fail succeeds (0)" "0" "$rc"
assert_contains "that renew says the lease is kept" "$err" "renew-lease: could not re-read the leases after the renew; lease kept"
assert_eq "that renew retries the list once" "3" "$(cat "$GH_STUB_DIR/lease-comments.count")"
assert_eq "that renew writes only its renew PATCH" "1" "$(grep -c '^PATCH 1' "$GH_STUB_DIR/calls.log")"
cleanup_scenario
# [renew near expiry, re-list fails once] the retry sees the newer lease and yields.
short_scenario
: >"$GH_STUB_DIR/list-fails-2"
hook "list-3" put_lease 2 "$(marker "$LANE" "$FUTURE" 2)"
rc=0
bash "$RENEW" "$ID" --lease-comment-id 1 >/dev/null 2>&1 || rc=$?
assert_eq "a renew whose retried re-list shows a newer lease exits conflict (7)" "7" "$rc"
assert_eq "that renew supersedes lease 1" "true" "$(superseded 1)"
cleanup_scenario

# [renew far from expiry] a normal renew reads the lease list once.
attended_scenario
sleep 1
printf '0\n' >"$GH_STUB_DIR/lease-comments.count"
bash "$RENEW" "$ID" --lease-comment-id 1 >/dev/null 2>&1
assert_eq "a renew far from expiry succeeds (0)" "0" "$?"
assert_eq "that renew reads the lease list once" "1" "$(cat "$GH_STUB_DIR/lease-comments.count")"
cleanup_scenario

# [same-login claim dies after its post] alice's attended lease 1 holds; a second alice
# session posts lease 2 and fails on its arbitration read. Its rollback must leave alice
# assigned for lease 1.
attended_scenario
: >"$GH_STUB_DIR/list-fails-$(($(cat "$GH_STUB_DIR/lease-comments.count") + 1))"
rc=0
bash "$CLAIM" "$ID" --ttl-hours 1 --phase triage >/dev/null 2>&1 || rc=$?
assert_eq "the second session's claim exits non-zero" "true" "$([[ $rc -ne 0 ]] && echo true || echo false)"
assert_eq "its lease 2 is superseded" "true" "$(superseded 2)"
assert_eq "alice stays assigned for live lease 1" '["alice"]' "$(assignees_now)"
cleanup_scenario

# [same-login step-2 conflict] bob was added by hand next to the attended alice; a second
# alice session backs off at step 2 and must leave alice assigned for lease 1.
attended_scenario
printf '["alice","bob"]\n' >"$GH_STUB_DIR/assignees"
rc=0
bash "$CLAIM" "$ID" --ttl-hours 1 --phase triage >/dev/null 2>&1 || rc=$?
assert_eq "the second session backs off (7) on bob" "7" "$rc"
assert_eq "alice stays assigned for live lease 1" '["alice","bob"]' "$(assignees_now)"
cleanup_scenario

# [assign lands but reports failure] the claim exits on the failed assign; the rollback
# removes the assignment that landed, since alice holds no lease.
new_scenario
: >"$GH_STUB_DIR/stateful"
printf 'alice\n' >"$GH_STUB_DIR/login"
printf '[]\n' >"$GH_STUB_DIR/assignees"
printf '[]\n' >"$GH_STUB_DIR/lease-comments"
: >"$GH_STUB_DIR/assign-fails"
rc=0
bash "$CLAIM" "$ID" --ttl-hours 24 >/dev/null 2>&1 || rc=$?
assert_eq "a claim whose assign reports failure exits non-zero" "true" "$([[ $rc -ne 0 ]] && echo true || echo false)"
assert_eq "the assignment that landed is rolled back" "[]" "$(assignees_now)"
cleanup_scenario

# [refused expired release] alice's lease 1 expired and a newer lease 2 is pending: the
# release is refused (7) and hands back alice unless lease 2 is alice's own.
refused_release_case() {
  new_scenario
  : >"$GH_STUB_DIR/stateful"
  printf 'alice\n' >"$GH_STUB_DIR/login"
  printf '["alice"]\n' >"$GH_STUB_DIR/assignees"
  jq -cn --arg a "$(marker alice "$PAST" 24)" --arg b "$(marker "$2" "$FUTURE" 2)" \
    '[{id:1, node_id:"MDEx", body:$a, created_at:"2020-01-01T00:00:00Z", author_association:"MEMBER"},
      {id:2, node_id:"MDEx", body:$b, created_at:"2020-01-01T00:00:00Z", author_association:"MEMBER"}]' >"$GH_STUB_DIR/lease-comments"
  rc=0
  bash "$RELEASE" "$ID" --lease-comment-id 1 >/dev/null 2>&1 || rc=$?
  assert_eq "$1: exit" "7" "$rc"
  assert_eq "$1: assignees" "$3" "$(assignees_now)"
  cleanup_scenario
}
refused_release_case "a refused release under a lane lease unassigns alice" "$LANE" '[]'
refused_release_case "a refused release under alice's own newer lease keeps her" alice '["alice"]'

# [outranked live release] alice's live lease 2 is outranked by an earlier live lease 1: the
# release is refused (7), supersedes lease 2 and hands back alice unless lease 1 is alice's own.
outranked_release_case() {
  new_scenario
  : >"$GH_STUB_DIR/stateful"
  printf 'alice\n' >"$GH_STUB_DIR/login"
  printf '%s\n' "$3" >"$GH_STUB_DIR/assignees"
  jq -cn --arg a "$(marker "$2" "$FUTURE" 24)" --arg b "$(marker alice "$FUTURE" 24)" \
    '[{id:1, node_id:"MDEx", body:$a, created_at:"2020-01-01T00:00:00Z", author_association:"MEMBER"},
      {id:2, node_id:"MDEx", body:$b, created_at:"2020-01-01T00:00:00Z", author_association:"MEMBER"}]' >"$GH_STUB_DIR/lease-comments"
  rc=0
  bash "$RELEASE" "$ID" --lease-comment-id 2 >/dev/null 2>&1 || rc=$?
  assert_eq "$1: exit" "7" "$rc"
  assert_eq "$1: own lease 2 superseded" "true" "$(superseded 2)"
  assert_eq "$1: earlier lease 1 left live" "false" "$(superseded 1)"
  assert_eq "$1: assignees" "$4" "$(assignees_now)"
  cleanup_scenario
}
outranked_release_case "an outranked release under bob's earlier lease unassigns alice" bob '["bob","alice"]' '["bob"]'
outranked_release_case "an outranked release under alice's own earlier lease keeps her" alice '["alice"]' '["alice"]'

# [outranked release, supersede fails twice] lease 2 may still be live, so alice stays.
new_scenario
: >"$GH_STUB_DIR/stateful"
printf 'alice\n' >"$GH_STUB_DIR/login"
printf '["bob","alice"]\n' >"$GH_STUB_DIR/assignees"
jq -cn --arg a "$(marker bob "$FUTURE" 24)" --arg b "$(marker alice "$FUTURE" 24)" \
  '[{id:1, node_id:"MDEx", body:$a, created_at:"2020-01-01T00:00:00Z", author_association:"MEMBER"},
    {id:2, node_id:"MDEx", body:$b, created_at:"2020-01-01T00:00:00Z", author_association:"MEMBER"}]' >"$GH_STUB_DIR/lease-comments"
: >"$GH_STUB_DIR/patch-lost-1"
: >"$GH_STUB_DIR/patch-lost-2"
rc=0
err="$(bash "$RELEASE" "$ID" --lease-comment-id 2 2>&1 >/dev/null)" || rc=$?
assert_eq "an outranked release whose supersede fails twice exits conflict (7)" "7" "$rc"
assert_eq "that release tries the supersede twice" "2" "$(grep -c '^PATCH 2' "$GH_STUB_DIR/calls.log")"
assert_eq "lease 2 is not superseded" "false" "$(superseded 2)"
assert_not_contains "that release never removes alice" "$(calls)" "REMOVE_ASSIGNEE alice"
assert_eq "alice stays assigned for lease 2" '["bob","alice"]' "$(assignees_now)"
assert_contains "the refusal says the assignee is kept" "$err" "could not supersede the lease, assignee kept"
cleanup_scenario

T0=1783828800
# date: `date -u +%s` answers the next line of $GH_STUB_DIR/clock, repeating the last.
# shellcheck disable=SC2329  # exported to the release.sh child
date() {
  if [[ "$*" == "-u +%s" && -f "${GH_STUB_DIR:?}/clock" ]]; then
    head -n 1 "$GH_STUB_DIR/clock"
    [[ "$(wc -l <"$GH_STUB_DIR/clock")" -le 1 ]] ||
      { tail -n +2 "$GH_STUB_DIR/clock" >"$GH_STUB_DIR/clock.tmp" && mv "$GH_STUB_DIR/clock.tmp" "$GH_STUB_DIR/clock"; }
  else
    command date "$@"
  fi
}
export -f date

# [hand-back clock] releasing lease 1, the hand-back lists alice's lease 2 (old expiry
# T0+3600); a same-login renew then extends it and the clock passes that old expiry before
# the judgment. Lease 2 was live at a clock read before the list, so alice is never removed.
new_scenario
: >"$GH_STUB_DIR/stateful"
printf 'alice\n' >"$GH_STUB_DIR/login"
printf '["alice"]\n' >"$GH_STUB_DIR/assignees"
jq -cn --arg a "$(marker alice "2026-07-12T04:00:00Z" 24)" --arg b "$(marker alice "2026-07-12T04:00:00Z" 1)" \
  '[{id:1, node_id:"MDEx", body:$a, created_at:"2020-01-01T00:00:00Z", author_association:"MEMBER"},
    {id:2, node_id:"MDEx", body:$b, created_at:"2020-01-01T00:00:00Z", author_association:"MEMBER"}]' >"$GH_STUB_DIR/lease-comments"
printf '%s\n' "$((T0 + 10))" >"$GH_STUB_DIR/clock"
h="$(next_read list 2)-after"
# shellcheck disable=SC2016  # expanded by the hook's bash
hook "$h" bash -c 'put_lease 2 "$1" && printf "%s\n" "$2" >"$GH_STUB_DIR/clock"' _ \
  "$(marker alice "2026-07-12T05:00:00Z" 1)" "$((T0 + 3600))"
rc=0
bash "$RELEASE" "$ID" --lease-comment-id 1 >/dev/null 2>&1 || rc=$?
assert_eq "the release of lease 1 succeeds (0)" "0" "$rc"
assert_eq "the renew landed after the hand-back's list" "0" "$(hook_rc "$h")"
assert_not_contains "the hand-back never removes alice for renewed lease 2" "$(calls)" "REMOVE_ASSIGNEE alice"
assert_eq "alice stays assigned" '["alice"]' "$(assignees_now)"
cleanup_scenario

# [hand-back clock, later lists] releasing lease 1, the hand-back's first list shows no
# lease 2, so it removes alice; lease 2 (old expiry T0+3600) is in every later list. On the
# named list a renew extends lease 2 and the clock passes its old expiry before the judgment;
# judged at a clock read before that list, alice ends assigned.
handback_clock_case() {
  new_scenario
  : >"$GH_STUB_DIR/stateful"
  printf 'alice\n' >"$GH_STUB_DIR/login"
  printf '["alice"]\n' >"$GH_STUB_DIR/assignees"
  jq -cn --arg a "$(marker alice "2026-07-12T04:00:00Z" 24)" --arg b "$(marker alice "2026-07-12T04:00:00Z" 1)" \
    '[{id:1, node_id:"MDEx", body:$a, created_at:"2020-01-01T00:00:00Z", author_association:"MEMBER"},
      {id:2, node_id:"MDEx", body:$b, created_at:"2020-01-01T00:00:00Z", author_association:"MEMBER"}]' >"$GH_STUB_DIR/lease-comments"
  lease_array 1 "$(superseded_marker alice)" >"$GH_STUB_DIR/lease-comments-2"
  printf '%s\n' "$((T0 + 10))" >"$GH_STUB_DIR/clock"
  # shellcheck disable=SC2016  # expanded by the hook's bash
  hook "list-$2-after" bash -c 'put_lease 2 "$1" && printf "%s\n" "$2" >"$GH_STUB_DIR/clock"' _ \
    "$(marker alice "2026-07-12T05:00:00Z" 1)" "$((T0 + 3600))"
  rc=0
  bash "$RELEASE" "$ID" --lease-comment-id 1 >/dev/null 2>&1 || rc=$?
  assert_eq "$1: release exit" "0" "$rc"
  assert_eq "$1: the renew landed after that list" "0" "$(hook_rc "list-$2-after")"
  assert_eq "$1: alice ends assigned" '["alice"]' "$(assignees_now)"
  cleanup_scenario
}
handback_clock_case "renew during the hand-back's re-list" 3
handback_clock_case "renew during the hand-back's confirm list" 4

# [hand-back clock, fast holder] releasing lease 1, the hand-back reads its clock (T0+10),
# then a same-login holder whose clock runs 300 s fast renews lease 2 two seconds into the
# list (renewed_at T0+312). That is past the skew bound at the earlier read and inside it at
# a read after the list, so alice is never removed.
new_scenario
: >"$GH_STUB_DIR/stateful"
printf 'alice\n' >"$GH_STUB_DIR/login"
printf '["alice"]\n' >"$GH_STUB_DIR/assignees"
jq -cn --arg a "$(marker alice "2026-07-12T04:00:00Z" 24)" --arg b "$(marker alice "2026-07-12T04:00:00Z" 1)" \
  '[{id:1, node_id:"MDEx", body:$a, created_at:"2020-01-01T00:00:00Z", author_association:"MEMBER"},
    {id:2, node_id:"MDEx", body:$b, created_at:"2020-01-01T00:00:00Z", author_association:"MEMBER"}]' >"$GH_STUB_DIR/lease-comments"
printf '%s\n' "$((T0 + 10))" >"$GH_STUB_DIR/clock"
h="$(next_read list 2)"
# shellcheck disable=SC2016  # expanded by the hook's bash
hook "$h" bash -c 'put_lease 2 "$1" && printf "%s\n" "$2" >"$GH_STUB_DIR/clock"' _ \
  "$(marker alice "2026-07-12T04:05:12Z" 1)" "$((T0 + 12))"
rc=0
bash "$RELEASE" "$ID" --lease-comment-id 1 >/dev/null 2>&1 || rc=$?
assert_eq "the release of lease 1 succeeds (0) beside a fast-clock holder" "0" "$rc"
assert_eq "the fast-clock renew landed during the hand-back's list" "0" "$(hook_rc "$h")"
assert_not_contains "the hand-back never removes alice for the fast-clock lease 2" "$(calls)" "REMOVE_ASSIGNEE alice"
assert_eq "alice stays assigned beside the fast-clock holder" '["alice"]' "$(assignees_now)"
cleanup_scenario

# [release clock] the lease expires between two clock reads; release decides on one read,
# so it releases the lease that was live at that read.
new_scenario
: >"$GH_STUB_DIR/stateful"
printf 'alice\n' >"$GH_STUB_DIR/login"
printf '["alice"]\n' >"$GH_STUB_DIR/assignees"
lease_array 1 "$(marker alice "2026-07-12T04:00:00Z" 1)" >"$GH_STUB_DIR/lease-comments"
printf '%s\n' "$((T0 + 3599))" "$((T0 + 3600))" >"$GH_STUB_DIR/clock"
rc=0
bash "$RELEASE" "$ID" --lease-comment-id 1 >/dev/null 2>&1 || rc=$?
assert_eq "release of a lease live at its clock read succeeds (0)" "0" "$rc"
assert_eq "that release supersedes lease 1" "true" "$(superseded 1)"
cleanup_scenario

# renew_clock_scenario <clock-reads…>: alice's lease 1 expires at T0 + 3600, alice assigned,
# and the renew's `date -u +%s` reads answer the given epochs, repeating the last.
renew_clock_scenario() {
  new_scenario
  : >"$GH_STUB_DIR/stateful"
  printf 'alice\n' >"$GH_STUB_DIR/login"
  printf '["alice"]\n' >"$GH_STUB_DIR/assignees"
  lease_array 1 "$(marker alice "2026-07-12T04:00:00Z" 1)" >"$GH_STUB_DIR/lease-comments"
  printf '%s\n' "$@" >"$GH_STUB_DIR/clock"
}
patches() { grep -c '^PATCH 1' "$GH_STUB_DIR/calls.log"; }

# [renew lands after expiry] the PATCH returns after lease 1's old expiry: a same-login
# claimant may have removed the shared assignee meanwhile, so the renew never keeps it.
renew_clock_scenario "$((T0 + 3590))" "$((T0 + 3590))" "$((T0 + 3600))"
rc=0
err="$(bash "$RENEW" "$ID" --lease-comment-id 1 2>&1 >/dev/null)" || rc=$?
assert_eq "a renew whose PATCH lands after the old expiry exits conflict (7)" "7" "$rc"
assert_contains "the refusal says the lease expired before the renew landed" "$err" "expired before the renew landed"
assert_eq "that renew PATCHes lease 1 twice, the second a supersede" "2" "$(patches)"
assert_eq "lease 1 ends superseded" "true" "$(superseded 1)"
assert_eq "alice is handed back" "[]" "$(assignees_now)"
cleanup_scenario

# [renew lands after expiry, same-login winner] a second alice session found lease 1 expired
# and won with lease 2 after the renew's lease read; the back-off keeps alice for lease 2.
renew_clock_scenario "$((T0 + 3590))" "$((T0 + 3590))" "$((T0 + 3600))"
hook list-1-after put_lease 2 "$(marker alice "2026-07-12T05:00:00Z" 1)"
rc=0
bash "$RENEW" "$ID" --lease-comment-id 1 >/dev/null 2>&1 || rc=$?
assert_eq "a renew landing after expiry under alice's newer lease exits conflict (7)" "7" "$rc"
assert_eq "that renew supersedes lease 1" "true" "$(superseded 1)"
assert_eq "alice's lease 2 stays live" "false" "$(superseded 2)"
assert_eq "the back-off keeps alice for lease 2" '["alice"]' "$(assignees_now)"
cleanup_scenario

# [renew PATCH lands but reports failure, after expiry] the renew may have revived lease 1,
# so it backs off as a late PATCH does.
renew_clock_scenario "$((T0 + 3590))" "$((T0 + 3590))" "$((T0 + 3600))"
: >"$GH_STUB_DIR/patch-fails-1"
rc=0
err="$(bash "$RENEW" "$ID" --lease-comment-id 1 2>&1 >/dev/null)" || rc=$?
assert_eq "a renew whose PATCH reports failure after the old expiry exits conflict (7)" "7" "$rc"
assert_contains "the refusal says the renew may have landed" "$err" "may have landed"
assert_eq "that renew supersedes lease 1" "true" "$(superseded 1)"
assert_eq "that renew hands back alice" "[]" "$(assignees_now)"
cleanup_scenario

# [renew PATCH fails within the margin] the same back-off runs before the old expiry.
renew_clock_scenario "$((T0 + 3590))"
: >"$GH_STUB_DIR/patch-lost-1"
rc=0
bash "$RENEW" "$ID" --lease-comment-id 1 >/dev/null 2>&1 || rc=$?
assert_eq "a renew whose PATCH fails within the margin exits conflict (7)" "7" "$rc"
assert_eq "that renew supersedes lease 1" "true" "$(superseded 1)"
assert_eq "that renew hands back alice" "[]" "$(assignees_now)"
cleanup_scenario

# [renew PATCH fails far from expiry] no back-off: the renew exits with the PATCH's error.
renew_clock_scenario "$((T0 + 100))"
: >"$GH_STUB_DIR/patch-lost-1"
rc=0
bash "$RENEW" "$ID" --lease-comment-id 1 >/dev/null 2>&1 || rc=$?
assert_eq "a renew whose PATCH fails far from expiry exits non-zero, not conflict" "true" \
  "$([[ $rc -ne 0 && $rc -ne 7 ]] && echo true || echo false)"
assert_eq "that renew writes only its renew PATCH" "1" "$(patches)"
assert_eq "that renew keeps alice" '["alice"]' "$(assignees_now)"
cleanup_scenario

# [back-off supersede fails twice] lease 1 may still be live, so alice stays assigned.
renew_clock_scenario "$((T0 + 3590))" "$((T0 + 3590))" "$((T0 + 3600))"
: >"$GH_STUB_DIR/patch-lost-2"
: >"$GH_STUB_DIR/patch-lost-3"
rc=0
err="$(bash "$RENEW" "$ID" --lease-comment-id 1 2>&1 >/dev/null)" || rc=$?
assert_eq "a back-off whose supersede fails twice exits conflict (7)" "7" "$rc"
assert_contains "that back-off says the assignee is kept" "$err" "could not supersede the lease, assignee kept"
assert_eq "that back-off tries the supersede twice" "3" "$(patches)"
assert_eq "lease 1 is not superseded" "false" "$(superseded 1)"
assert_eq "alice stays assigned for lease 1" '["alice"]' "$(assignees_now)"
cleanup_scenario

# [back-off supersede fails once] the retry supersedes lease 1, then the hand-back runs.
renew_clock_scenario "$((T0 + 3590))" "$((T0 + 3590))" "$((T0 + 3600))"
: >"$GH_STUB_DIR/patch-lost-2"
rc=0
bash "$RENEW" "$ID" --lease-comment-id 1 >/dev/null 2>&1 || rc=$?
assert_eq "a back-off whose retried supersede succeeds exits conflict (7)" "7" "$rc"
assert_eq "the retry supersedes lease 1" "true" "$(superseded 1)"
assert_eq "that back-off hands back alice" "[]" "$(assignees_now)"
cleanup_scenario
unset -f date

# [expired release, stale list] a same-login loser supersedes lease 2 right after the
# release's lease read; the refused release must not keep alice for lease 2.
new_scenario
: >"$GH_STUB_DIR/stateful"
printf 'alice\n' >"$GH_STUB_DIR/login"
printf '["alice"]\n' >"$GH_STUB_DIR/assignees"
jq -cn --arg a "$(marker alice "$PAST" 24)" --arg b "$(marker alice "$FUTURE" 1)" \
  '[{id:1, node_id:"MDEx", body:$a, created_at:"2020-01-01T00:00:00Z", author_association:"MEMBER"},
    {id:2, node_id:"MDEx", body:$b, created_at:"2020-01-01T00:00:00Z", author_association:"MEMBER"}]' >"$GH_STUB_DIR/lease-comments"
hook list-1-after put_lease 2 "$(superseded_marker alice)"
rc=0
bash "$RELEASE" "$ID" --lease-comment-id 1 >/dev/null 2>&1 || rc=$?
assert_eq "the release of an expired lease under lease 2 is refused (7)" "7" "$rc"
assert_eq "it hands back alice once lease 2 is superseded" "[]" "$(assignees_now)"
cleanup_scenario

[[ $FAILED -eq 0 ]] || exit 1
