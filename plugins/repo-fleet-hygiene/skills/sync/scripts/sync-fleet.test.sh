#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/sync-fleet.sh"
HELPER="$SCRIPT_DIR/../../../../source-control/scripts/worktree-create.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { FAILED=$((FAILED + 1)); printf 'FAIL: %s\n  %s\n' "$1" "$2" >&2; }

git_identity() {
  git -C "$1" config user.email t@t.t
  git -C "$1" config user.name t
  git -C "$1" config commit.gpgsign false
}

commit_file() {
  local repo="$1" name="$2"
  printf '%s\n' "$name" >"$repo/$name"
  git -C "$repo" add "$name"
  git -C "$repo" commit -q -m "$name"
}

bare="$TMP/remote.git"
git init -q --bare -b main "$bare"
seed="$TMP/seed"
git init -q -b main "$seed"
git_identity "$seed"
commit_file "$seed" README.md
git -C "$seed" remote add origin "$bare"
git -C "$seed" push -q origin main

clone="$TMP/clone"
git clone -q "$bare" "$clone"
git_identity "$clone"

if ( cd "$TMP" && REPO_FLEET_GHQ_BIN=/nonexistent bash "$SCRIPT" --project-dir "$TMP" >"$TMP/noscope.out" 2>"$TMP/noscope.err" ); then
  fail "no scope exits 3" "exit 0"
else
  code=$?
  if [[ "$code" -eq 3 ]]; then pass "no scope exits 3"; else fail "no scope exits 3" "exit $code"; fi
fi

# Advance origin, leave the clone behind.
commit_file "$seed" REMOTE_ONLY.md
git -C "$seed" push -q origin main
before="$(git -C "$clone" rev-parse HEAD)"
dry="$(bash "$SCRIPT" --repo "$clone")"
if [[ "$dry" == *$'ff-only\t'"$clone"* && "$(git -C "$clone" rev-parse HEAD)" == "$before" ]]; then
  pass "dry-run plans ff-only and does not move HEAD"
else
  fail "dry-run plans ff-only and does not move HEAD" "$dry"
fi

if bash "$SCRIPT" --repo "$clone" --apply >"$TMP/noyes.out" 2>"$TMP/noyes.err"; then
  fail "apply without --yes exits 3" "exit 0"
else
  code=$?
  if [[ "$code" -eq 3 && "$(git -C "$clone" rev-parse HEAD)" == "$before" ]]; then
    pass "apply without --yes changes nothing"
  else
    fail "apply without --yes changes nothing" "exit $code"
  fi
fi

applied="$(bash "$SCRIPT" --repo "$clone" --apply --yes)"
if [[ "$applied" == *$'applied\t'"$clone"* && "$(git -C "$clone" rev-parse HEAD)" == "$(git -C "$bare" rev-parse main)" ]]; then
  pass "apply --yes fast-forwards"
else
  fail "apply --yes fast-forwards" "$applied"
fi

dirty="$TMP/dirty"
git clone -q "$bare" "$dirty"
git_identity "$dirty"
git -C "$dirty" switch -q -c feature
printf 'park-me\n' >"$dirty/DIRTY.md"
wtroot="$TMP/worktrees"
mkdir -p "$wtroot"
parked="$(bash "$SCRIPT" --repo "$dirty" --apply --yes --worktree-root "$wtroot" --worktree-create "$HELPER")"
if [[ "$(git -C "$dirty" branch --show-current)" == "main" && "$parked" == *park-existing* ]]; then
  wt="$(printf '%s\n' "$parked" | awk -F '\t' '$1 == "applied" && $3 == "park-existing" { print $4 }')"
  if [[ -f "$wt/DIRTY.md" && "$(git -C "$wt" branch --show-current)" == "feature" ]]; then
    pass "dirty non-default branch is parked in a worktree"
  else
    fail "dirty non-default branch is parked in a worktree" "wt=$wt parked=$parked"
  fi
else
  fail "dirty non-default branch is parked in a worktree" "$parked"
fi

diverge="$TMP/diverge"
git clone -q "$bare" "$diverge"
git_identity "$diverge"
printf 'local\n' >"$diverge/LOCAL.md"
git -C "$diverge" add LOCAL.md
git -C "$diverge" commit -q -m local
commit_file "$seed" OTHER.md
git -C "$seed" push -q origin main
tip="$(git -C "$diverge" rev-parse HEAD)"
skipped="$(bash "$SCRIPT" --repo "$diverge" --apply --yes)"
if [[ "$skipped" == *non-fast-forward* && "$(git -C "$diverge" rev-parse HEAD)" == "$tip" ]]; then
  pass "non-fast-forward is skipped and the local commit stays"
else
  fail "non-fast-forward is skipped and the local commit stays" "$skipped"
fi

if [[ "$FAILED" -eq 0 ]]; then
  printf 'OK\n'
  exit 0
fi
printf '%s failed\n' "$FAILED" >&2
exit 1
