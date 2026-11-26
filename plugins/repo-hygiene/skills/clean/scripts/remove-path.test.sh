#!/usr/bin/env bash
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

run_remove() {
  rc=0
  out="$(bash "$REMOVE" "$@")" || rc=$?
}

run_remove_quiet() {
  rc=0
  bash "$REMOVE" "$@" >/dev/null 2>&1 || rc=$?
}

make_repo() {
  local path="$1"
  git_quiet init "$path"
  git -C "$path" config user.email test@example.com
  git -C "$path" config user.name Test
  printf 'x\n' >"$path/file.txt"
  git_quiet -C "$path" add file.txt
  git_quiet -C "$path" commit -m init
}

make_pushed_repo() {
  local path="$1" bare="$2"
  make_repo "$path"
  git_quiet init --bare "$bare"
  git_quiet -C "$path" remote add origin "$bare"
  git_quiet -C "$path" push -u origin HEAD
}

make_ignoring_repo() {
  local path="$1" bare="$2" pattern="$3"
  make_pushed_repo "$path" "$bare"
  printf '%s\n' "$pattern" >"$path/.gitignore"
  git_quiet -C "$path" add .gitignore
  git_quiet -C "$path" commit -m gitignore
  git_quiet -C "$path" push
}

run_remove_quiet --help
assert_exit "--help exits 0" 0 "$rc"

run_remove_quiet --root "$ROOT"
assert_exit "no target exits 2" 2 "$rc"

run_remove_quiet "$ROOT" --root "$ROOT"
assert_exit "root itself refused" 2 "$rc"

mkdir -p "$TEST_TMPDIR/elsewhere"
run_remove_quiet "$TEST_TMPDIR/elsewhere" --root "$ROOT"
assert_exit "outside root refused" 2 "$rc"

run_remove_quiet "$ROOT" --bogus-flag --root "$ROOT"
assert_exit "unknown flag exits 2" 2 "$rc"

run_remove_quiet "$ROOT/a" "$ROOT/b" --root "$ROOT"
assert_exit "multiple targets exits 2" 2 "$rc"

run_remove_quiet "$ROOT/a" --root
assert_exit "--root without value exits 2" 2 "$rc"

run_remove_quiet "$ROOT/missing" --root "$ROOT"
assert_exit "missing target exits 1" 1 "$rc"

mkdir -p "$ROOT/plain-dir/sub"
run_remove "$ROOT/plain-dir" --root "$ROOT"
assert_exit "plain dir dry-run exits 0" 0 "$rc"
assert_contains "plain dir dry-run plans removal" "$out" "Planned: rm -rf"
assert_contains "plain dir kind" "$out" "Kind: dir"
if [[ -d "$ROOT/plain-dir" ]]; then
  pass "dry-run leaves target in place"
else
  fail "dry-run leaves target in place" "present" "absent"
fi

run_remove "$ROOT/plain-dir" --root "$ROOT" --apply
assert_exit "plain dir apply exits 0" 0 "$rc"
assert_contains "apply reports removal" "$out" "Applied: rm -rf"
assert_file_absent "apply removed the dir" "$ROOT/plain-dir/sub"

make_pushed_repo "$ROOT/pushed-repo" "$TEST_TMPDIR/pushed-remote.git"
run_remove "$ROOT/pushed-repo" --root "$ROOT"
assert_exit "clean pushed repo dry-run exits 0" 0 "$rc"
assert_contains "repo kind detected" "$out" "Kind: repo"
assert_contains "clean pushed repo not blocked" "$out" "Blocked: none"

make_pushed_repo "$ROOT/dirty-repo" "$TEST_TMPDIR/dirty-remote.git"
printf 'y\n' >>"$ROOT/dirty-repo/file.txt"
run_remove "$ROOT/dirty-repo" --root "$ROOT"
assert_exit "dirty repo blocked exits 3" 3 "$rc"
assert_contains "dirty repo blocked reason" "$out" "Blocked: dirty"

make_repo "$ROOT/unpushed-repo"
run_remove "$ROOT/unpushed-repo" --root "$ROOT"
assert_exit "unpushed repo blocked exits 4" 4 "$rc"
assert_contains "unpushed repo blocked reason" "$out" "Blocked: unpushed"

make_pushed_repo "$ROOT/hidden-untracked-repo" "$TEST_TMPDIR/hidden-untracked-remote.git"
git_quiet -C "$ROOT/hidden-untracked-repo" config status.showUntrackedFiles no
printf 'local\n' >"$ROOT/hidden-untracked-repo/untracked.txt"
run_remove "$ROOT/hidden-untracked-repo" --root "$ROOT"
assert_exit "showUntrackedFiles=no hidden untracked still blocks exits 3" 3 "$rc"
assert_contains "hidden untracked dirty block reason" "$out" "Blocked: dirty"

run_remove "$ROOT/unpushed-repo" --root "$ROOT" --allow-unpushed
assert_exit "--allow-unpushed clears the block" 0 "$rc"
assert_contains "--allow-unpushed plans removal" "$out" "Planned: rm -rf"

make_ignoring_repo "$ROOT/secret-repo" "$TEST_TMPDIR/secret-remote.git" '.env'
printf 'TOKEN=x\n' >"$ROOT/secret-repo/.env"
run_remove "$ROOT/secret-repo" --root "$ROOT"
assert_exit "ignored secret blocks exits 3" 3 "$rc"
assert_contains "secret block reason" "$out" "Blocked: secrets"

run_remove "$ROOT/secret-repo" --root "$ROOT" --include-secrets
assert_exit "--include-secrets clears the block" 0 "$rc"

make_pushed_repo "$ROOT/wt-repo" "$TEST_TMPDIR/wt-remote.git"
git_quiet -C "$ROOT/wt-repo" worktree add "$ROOT/wt-repo-linked" -b linked
run_remove "$ROOT/wt-repo" --root "$ROOT"
assert_exit "repo with linked worktree blocked exits 3" 3 "$rc"
assert_contains "linked worktree block reason" "$out" "Blocked: linked-worktrees"

run_remove_quiet "$ROOT/wt-repo-linked" --root "$ROOT"
assert_exit "linked worktree target refused" 2 "$rc"

REPARSE_MADE=""
if command -v cmd >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1; then
  cmd //c "mklink /J $(cygpath -w "$ROOT/reparse-target") $(cygpath -w "$ROOT/pushed-repo")" >/dev/null 2>&1 && REPARSE_MADE=junction
fi
if [[ -z "$REPARSE_MADE" ]]; then
  ln -s "$ROOT/pushed-repo" "$ROOT/reparse-target" 2>/dev/null && [[ -L "$ROOT/reparse-target" ]] && REPARSE_MADE=symlink
fi
if [[ -n "$REPARSE_MADE" ]]; then
  run_remove_quiet "$ROOT/reparse-target" --root "$ROOT"
  assert_exit "reparse-point target ($REPARSE_MADE) refused" 2 "$rc"
  assert_file_exists "reparse traversal did not delete linked contents" "$ROOT/pushed-repo/file.txt"
else
  skip_case "no reparse-point mechanism available on this platform"
fi

git_quiet init --bare "$ROOT/bare-repo"
run_remove "$ROOT/bare-repo" --root "$ROOT" --allow-unpushed
assert_exit "empty bare repo dry-run exits 0" 0 "$rc"
assert_contains "bare repo kind detected" "$out" "Kind: bare-repo"

make_ignoring_repo "$ROOT/aws-repo" "$TEST_TMPDIR/aws-remote.git" '.aws/'
mkdir -p "$ROOT/aws-repo/.aws"
printf 'key\n' >"$ROOT/aws-repo/.aws/credentials"
run_remove "$ROOT/aws-repo" --root "$ROOT"
assert_exit "ignored .aws credentials block exits 3" 3 "$rc"
assert_contains "SSOT secret-class block reason" "$out" "Blocked: secrets"

FAKE_HOME="$TEST_TMPDIR/fake-home"
mkdir -p "$FAKE_HOME" "$ROOT/default-root-dir"
HOME="$FAKE_HOME" GIT_CONFIG_GLOBAL="$FAKE_HOME/.gitconfig" git config --global ghq.root "$ROOT"
out="$(HOME="$FAKE_HOME" GIT_CONFIG_GLOBAL="$FAKE_HOME/.gitconfig" bash "$REMOVE" "$ROOT/default-root-dir")"
rc=$?
assert_exit "default ghq.root resolution exits 0" 0 "$rc"
ROOT_PHYS="$(cd "$ROOT" && pwd -P)"
ROOT_PHYS="${ROOT_PHYS//\\//}"
assert_contains "default root resolved from git config" "$out" "Root: $ROOT_PHYS"

mkdir -p "$ROOT/owner-dir"
make_repo "$ROOT/owner-dir/child-clone"
run_remove "$ROOT/owner-dir" --root "$ROOT"
assert_exit "plain dir with nested git repo refused exits 2" 2 "$rc"
assert_file_exists "nested child repo left intact by refusal" "$ROOT/owner-dir/child-clone/file.txt"

mkdir -p "$ROOT/mirror-owner"
git_quiet init --bare "$ROOT/mirror-owner/project.git"
run_remove "$ROOT/mirror-owner" --root "$ROOT"
assert_exit "plain dir with nested bare repo refused exits 2" 2 "$rc"
assert_file_exists "nested bare repo left intact by refusal" "$ROOT/mirror-owner/project.git/HEAD"

mkdir -p "$ROOT/leftover-dir"
printf 'TOKEN=x\n' >"$ROOT/leftover-dir/.env"
run_remove "$ROOT/leftover-dir" --root "$ROOT"
assert_exit "plain dir with .env blocked exits 3" 3 "$rc"
assert_contains "plain dir secret block reason" "$out" "Blocked: secrets"
run_remove "$ROOT/leftover-dir" --root "$ROOT" --include-secrets
assert_exit "--include-secrets clears plain dir secret block" 0 "$rc"

mkdir -p "$ROOT/synth-dir/.claude/skills/notes/data"
printf 'synthesis\n' >"$ROOT/synth-dir/.claude/skills/notes/data/corpus.md"
run_remove "$ROOT/synth-dir" --root "$ROOT"
assert_exit "plain dir with skill data blocked exits 3" 3 "$rc"
assert_contains "plain dir skill-data block reason" "$out" "Blocked: skill-data"
run_remove "$ROOT/synth-dir" --root "$ROOT" --include-secrets
assert_exit "--include-secrets does NOT clear skill-data block" 3 "$rc"

make_ignoring_repo "$ROOT/skill-repo" "$TEST_TMPDIR/skill-remote.git" '.claude/skills/*/data/'
mkdir -p "$ROOT/skill-repo/.claude/skills/notes/data"
printf 'synthesis\n' >"$ROOT/skill-repo/.claude/skills/notes/data/corpus.md"
run_remove "$ROOT/skill-repo" --root "$ROOT"
assert_exit "repo with gitignored skill data blocked exits 3" 3 "$rc"
assert_contains "repo skill-data block reason" "$out" "Blocked: skill-data"

make_pushed_repo "$ROOT/tag-repo" "$TEST_TMPDIR/tag-remote.git"
git_quiet -C "$ROOT/tag-repo" tag -a v1.0.0-rc1 -m rc
run_remove "$ROOT/tag-repo" --root "$ROOT"
assert_exit "local-only tag blocks exits 4" 4 "$rc"
assert_contains "local tag unpushed reason" "$out" "Blocked: unpushed"

make_pushed_repo "$ROOT/stash-repo" "$TEST_TMPDIR/stash-remote.git"
printf 'z\n' >>"$ROOT/stash-repo/file.txt"
git_quiet -C "$ROOT/stash-repo" stash push -m wip
run_remove "$ROOT/stash-repo" --root "$ROOT"
assert_exit "stash entry blocks exits 3" 3 "$rc"
assert_contains "stash block reason" "$out" "Blocked: stash"

make_pushed_repo "$ROOT/pruned-repo" "$TEST_TMPDIR/pruned-remote.git"
pruned_branch="$(git -C "$ROOT/pruned-repo" branch --show-current | tr -d '\r')"
git_quiet -C "$ROOT/pruned-repo" update-ref -d "refs/remotes/origin/$pruned_branch"
run_remove "$ROOT/pruned-repo" --root "$ROOT"
assert_exit "pruned upstream ref blocks exits 4" 4 "$rc"
assert_contains "pruned upstream unpushed reason" "$out" "Blocked: unpushed"

OUTSIDE="$TEST_TMPDIR/outside-root"
mkdir -p "$OUTSIDE/victim"
printf 'keep\n' >"$OUTSIDE/victim/.keep"
if ln -s "$OUTSIDE" "$ROOT/escape-link" 2>/dev/null && [[ -L "$ROOT/escape-link" ]]; then
  run_remove_quiet "$ROOT/escape-link/victim" --root "$ROOT" --apply
  assert_exit "symlinked-intermediate target refused (physical containment) exits 2" 2 "$rc"
  assert_file_exists "outside victim survives (rm -rf never traversed the link)" "$OUTSIDE/victim/.keep"
else
  skip_case "no POSIX symlink available for physical-containment test"
fi

if [[ $FAILED -ne 0 ]]; then
  echo "FAILED: $FAILED test(s)"
  exit 1
fi
echo "OK: remove-path.sh tests passed"
