#!/usr/bin/env bash
# Self-test for scripts/check-stale-base-overlap.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/check-stale-base-overlap.sh"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"
# The builder clears the inherited git environment for the whole suite: an
# inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would redirect `git init` and
# `git config` into the caller's repository.
# shellcheck source=lib/fixture-tree.sh
. "$ROOT/scripts/lib/fixture-tree.sh"

# The builder assigns through a nameref, which shellcheck cannot follow;
# declaring the out-var here is what tells it (SC2154) the name is written.
scratch=""
fixture_tree::build scratch --label stale-base-overlap

make_repo() {
  local dir="$1"
  mkdir -p "$dir"
  # git_init_test_repo owns the throwaway identity: user.email, user.name,
  # commit.gpgsign=false and core.autocrlf=false, so a signing-enabled or
  # CRLF-converting machine runs these cases the same way CI does.
  git_init_test_repo "$dir"
  # The cases below diff a feature branch against `main` by name.
  git -C "$dir" symbolic-ref HEAD refs/heads/main
  printf 'a\n' >"$dir/shared.txt"
  printf 'x\n' >"$dir/only-main.txt"
  git -C "$dir" add -A
  git -C "$dir" commit -qm 'initial'
}

# --- usage / missing ref ---
out="$(bash "$SCRIPT" 2>&1)" && rc=0 || rc=$?
if [[ $rc -eq 2 && "$out" == *"usage:"* ]]; then
  ok "bare invocation exits 2 with usage"
else
  fail "bare invocation: rc=$rc out='$out'"
fi

# --- fresh base ---
repo="$scratch/fresh"
make_repo "$repo"
cd "$repo" || exit 1
git checkout -qb feature
printf 'b\n' >feature-only.txt
git add -A && git commit -qm 'feature'
out="$(bash "$SCRIPT" --check main 2>&1)" && rc=0 || rc=$?
if [[ $rc -eq 0 && "$out" == *"up to date"* ]]; then
  ok "fresh base exits 0"
else
  fail "fresh base: rc=$rc out='$out'"
fi

# --- behind with overlapping path ---
repo="$scratch/overlap"
make_repo "$repo"
cd "$repo" || exit 1
git checkout -qb feature
printf 'feature-edit\n' >shared.txt
git add -A && git commit -qm 'feature edits shared'
git checkout -q main
printf 'main-edit\n' >shared.txt
git add -A && git commit -qm 'main also edits shared'
git checkout -q feature
out="$(bash "$SCRIPT" --check main 2>&1)" && rc=0 || rc=$?
if [[ $rc -eq 1 && "$out" == *"STALE BASE"* && "$out" == *"shared.txt"* ]]; then
  ok "overlapping behind-base fails"
else
  fail "overlapping behind-base: rc=$rc out='$out'"
fi

# --- behind with disjoint paths ---
repo="$scratch/disjoint"
make_repo "$repo"
cd "$repo" || exit 1
git checkout -qb feature
printf 'feature\n' >feature-only.txt
git add -A && git commit -qm 'feature file'
git checkout -q main
printf 'main\n' >main-later.txt
git add -A && git commit -qm 'main file'
git checkout -q feature
out="$(bash "$SCRIPT" --check main 2>&1)" && rc=0 || rc=$?
if [[ $rc -eq 0 && "$out" == *"no overlapping paths"* ]]; then
  ok "disjoint behind-base exits 0"
else
  fail "disjoint behind-base: rc=$rc out='$out'"
fi

# --- a rename on the base still overlaps an edit to the pre-rename path ---
# The overlap set must carry BOTH sides of a move. Seeing only the destination
# would report "no overlapping paths" for a PR editing the file the base just
# renamed away, which is the squash-reverts-a-fix shape this gate exists for.
repo="$scratch/rename"
make_repo "$repo"
cd "$repo" || exit 1
git checkout -qb feature
printf 'feature-edit\n' >shared.txt
git add -A && git commit -qm 'feature edits shared'
git checkout -q main
git mv shared.txt renamed.txt
git commit -qm 'main renames shared'
git checkout -q feature
out="$(bash "$SCRIPT" --check main 2>&1)" && rc=0 || rc=$?
if [[ $rc -eq 1 && "$out" == *"shared.txt"* ]]; then
  ok "a rename on the base overlaps an edit to the pre-rename path"
else
  fail "rename overlap: rc=$rc out='$out'"
fi

# --- unresolvable base ---
repo="$scratch/badref"
make_repo "$repo"
cd "$repo" || exit 1
out="$(bash "$SCRIPT" --check does-not-exist 2>&1)" && rc=0 || rc=$?
if [[ $rc -eq 2 && "$out" == *"not resolvable"* ]]; then
  ok "missing base ref exits 2"
else
  fail "missing base ref: rc=$rc out='$out'"
fi

test_harness::report
