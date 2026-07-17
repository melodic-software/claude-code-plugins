#!/usr/bin/env bash
# Tests for remove-path.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"

REMOVE="$SCRIPT_DIR/remove-path.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
FAILED=0

ROOT="$TEST_TMPDIR/ghq-root"
mkdir -p "$ROOT"

git_quiet() { git "$@" >/dev/null 2>&1; }

make_repo() {
  local path="$1"
  git_quiet init "$path"
  git -C "$path" config user.email test@example.com
  git -C "$path" config user.name Test
  printf 'x\n' >"$path/file.txt"
  git_quiet -C "$path" add file.txt
  git_quiet -C "$path" commit -m init
}

# Push everything to a local bare "remote" so the repo reads as fully pushed.
make_pushed_repo() {
  local path="$1" bare="$2"
  make_repo "$path"
  git_quiet init --bare "$bare"
  git_quiet -C "$path" remote add origin "$bare"
  git_quiet -C "$path" push -u origin HEAD
}

rc=0
bash "$REMOVE" --help >/dev/null 2>&1 || rc=$?
assert_exit "--help exits 0" 0 "$rc"

rc=0
bash "$REMOVE" --root "$ROOT" >/dev/null 2>&1 || rc=$?
assert_exit "no target exits 2" 2 "$rc"

rc=0
bash "$REMOVE" "$ROOT" --root "$ROOT" >/dev/null 2>&1 || rc=$?
assert_exit "root itself refused" 2 "$rc"

rc=0
bash "$REMOVE" "$TEST_TMPDIR/elsewhere" --root "$ROOT" >/dev/null 2>&1 || rc=$?
mkdir -p "$TEST_TMPDIR/elsewhere"
bash "$REMOVE" "$TEST_TMPDIR/elsewhere" --root "$ROOT" >/dev/null 2>&1 || rc=$?
assert_exit "outside root refused" 2 "$rc"

rc=0
bash "$REMOVE" "$ROOT/missing" --root "$ROOT" >/dev/null 2>&1 || rc=$?
assert_exit "missing target exits 1" 1 "$rc"

mkdir -p "$ROOT/plain-dir/sub"
out="$(bash "$REMOVE" "$ROOT/plain-dir" --root "$ROOT")"
rc=$?
assert_exit "plain dir dry-run exits 0" 0 "$rc"
assert_contains "plain dir dry-run plans removal" "$out" "Planned: rm -rf"
assert_contains "plain dir kind" "$out" "Kind: dir"
if [[ -d "$ROOT/plain-dir" ]]; then
  pass "dry-run leaves target in place"
else
  fail "dry-run leaves target in place" "present" "absent"
fi

out="$(bash "$REMOVE" "$ROOT/plain-dir" --root "$ROOT" --apply)"
rc=$?
assert_exit "plain dir apply exits 0" 0 "$rc"
assert_contains "apply reports removal" "$out" "Applied: rm -rf"
assert_file_absent "apply removed the dir" "$ROOT/plain-dir/sub"

make_pushed_repo "$ROOT/pushed-repo" "$TEST_TMPDIR/pushed-remote.git"
out="$(bash "$REMOVE" "$ROOT/pushed-repo" --root "$ROOT")"
rc=$?
assert_exit "clean pushed repo dry-run exits 0" 0 "$rc"
assert_contains "repo kind detected" "$out" "Kind: repo"
assert_contains "clean pushed repo not blocked" "$out" "Blocked: none"

make_pushed_repo "$ROOT/dirty-repo" "$TEST_TMPDIR/dirty-remote.git"
printf 'y\n' >>"$ROOT/dirty-repo/file.txt"
rc=0
out="$(bash "$REMOVE" "$ROOT/dirty-repo" --root "$ROOT")" || rc=$?
assert_exit "dirty repo blocked exits 3" 3 "$rc"
assert_contains "dirty repo blocked reason" "$out" "Blocked: dirty"

make_repo "$ROOT/unpushed-repo"
rc=0
out="$(bash "$REMOVE" "$ROOT/unpushed-repo" --root "$ROOT")" || rc=$?
assert_exit "unpushed repo blocked exits 4" 4 "$rc"
assert_contains "unpushed repo blocked reason" "$out" "Blocked: unpushed"

out="$(bash "$REMOVE" "$ROOT/unpushed-repo" --root "$ROOT" --allow-unpushed)"
rc=$?
assert_exit "--allow-unpushed clears the block" 0 "$rc"
assert_contains "--allow-unpushed plans removal" "$out" "Planned: rm -rf"

make_pushed_repo "$ROOT/secret-repo" "$TEST_TMPDIR/secret-remote.git"
printf '.env\n' >"$ROOT/secret-repo/.gitignore"
git_quiet -C "$ROOT/secret-repo" add .gitignore
git_quiet -C "$ROOT/secret-repo" commit -m gitignore
git_quiet -C "$ROOT/secret-repo" push
printf 'TOKEN=x\n' >"$ROOT/secret-repo/.env"
rc=0
out="$(bash "$REMOVE" "$ROOT/secret-repo" --root "$ROOT")" || rc=$?
assert_exit "ignored secret blocks exits 3" 3 "$rc"
assert_contains "secret block reason" "$out" "Blocked: secrets"

out="$(bash "$REMOVE" "$ROOT/secret-repo" --root "$ROOT" --include-secrets)"
rc=$?
assert_exit "--include-secrets clears the block" 0 "$rc"

make_pushed_repo "$ROOT/wt-repo" "$TEST_TMPDIR/wt-remote.git"
git_quiet -C "$ROOT/wt-repo" worktree add "$ROOT/wt-repo-linked" -b linked
rc=0
out="$(bash "$REMOVE" "$ROOT/wt-repo" --root "$ROOT")" || rc=$?
assert_exit "repo with linked worktree blocked exits 3" 3 "$rc"
assert_contains "linked worktree block reason" "$out" "Blocked: linked-worktrees"

rc=0
bash "$REMOVE" "$ROOT/wt-repo-linked" --root "$ROOT" >/dev/null 2>&1 || rc=$?
assert_exit "linked worktree target refused" 2 "$rc"

if ln -s "$ROOT/pushed-repo" "$ROOT/link-target" 2>/dev/null && [[ -L "$ROOT/link-target" ]]; then
  rc=0
  bash "$REMOVE" "$ROOT/link-target" --root "$ROOT" >/dev/null 2>&1 || rc=$?
  assert_exit "symlink target refused" 2 "$rc"
else
  skip_case "symlink creation unavailable on this platform"
fi

if [[ $FAILED -ne 0 ]]; then
  echo "FAILED: $FAILED test(s)"
  exit 1
fi
echo "OK: remove-path.sh tests passed"
