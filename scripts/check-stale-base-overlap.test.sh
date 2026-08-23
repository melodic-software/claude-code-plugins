#!/usr/bin/env bash
# Self-test for scripts/check-stale-base-overlap.sh
set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/check-stale-base-overlap.sh"
failures=0

ok() { printf 'ok - %s\n' "$1"; }
fail() {
  printf 'not ok - %s\n' "$1" >&2
  failures=$((failures + 1))
}

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

make_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name "test"
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

if [[ $failures -eq 0 ]]; then
  echo "ALL PASS"
  exit 0
fi
echo "$failures failure(s)" >&2
exit 1
