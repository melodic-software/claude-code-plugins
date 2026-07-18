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

mkdir -p "$TEST_TMPDIR/elsewhere"
rc=0
bash "$REMOVE" "$TEST_TMPDIR/elsewhere" --root "$ROOT" >/dev/null 2>&1 || rc=$?
assert_exit "outside root refused" 2 "$rc"

rc=0
bash "$REMOVE" "$ROOT" --bogus-flag --root "$ROOT" >/dev/null 2>&1 || rc=$?
assert_exit "unknown flag exits 2" 2 "$rc"

rc=0
bash "$REMOVE" "$ROOT/a" "$ROOT/b" --root "$ROOT" >/dev/null 2>&1 || rc=$?
assert_exit "multiple targets exits 2" 2 "$rc"

rc=0
bash "$REMOVE" "$ROOT/a" --root >/dev/null 2>&1 || rc=$?
assert_exit "--root without value exits 2" 2 "$rc"

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

# Reparse-point refusal — prefer a real Windows junction (creatable without
# elevation and the exact traversal hazard); fall back to a POSIX symlink.
# Whichever the platform can create MUST be refused — no silent skip.
REPARSE_MADE=""
if command -v cmd >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1; then
  cmd //c "mklink /J $(cygpath -w "$ROOT/reparse-target") $(cygpath -w "$ROOT/pushed-repo")" >/dev/null 2>&1 && REPARSE_MADE=junction
fi
if [[ -z "$REPARSE_MADE" ]]; then
  ln -s "$ROOT/pushed-repo" "$ROOT/reparse-target" 2>/dev/null && [[ -L "$ROOT/reparse-target" ]] && REPARSE_MADE=symlink
fi
if [[ -n "$REPARSE_MADE" ]]; then
  rc=0
  bash "$REMOVE" "$ROOT/reparse-target" --root "$ROOT" >/dev/null 2>&1 || rc=$?
  assert_exit "reparse-point target ($REPARSE_MADE) refused" 2 "$rc"
  assert_file_exists "reparse traversal did not delete linked contents" "$ROOT/pushed-repo/file.txt"
else
  skip_case "no reparse-point mechanism available on this platform"
fi

git_quiet init --bare "$ROOT/bare-repo"
rc=0
out="$(bash "$REMOVE" "$ROOT/bare-repo" --root "$ROOT" --allow-unpushed)" || rc=$?
assert_exit "empty bare repo dry-run exits 0" 0 "$rc"
assert_contains "bare repo kind detected" "$out" "Kind: bare-repo"

make_pushed_repo "$ROOT/aws-repo" "$TEST_TMPDIR/aws-remote.git"
printf '.aws/\n' >"$ROOT/aws-repo/.gitignore"
git_quiet -C "$ROOT/aws-repo" add .gitignore
git_quiet -C "$ROOT/aws-repo" commit -m gitignore
git_quiet -C "$ROOT/aws-repo" push
mkdir -p "$ROOT/aws-repo/.aws"
printf 'key\n' >"$ROOT/aws-repo/.aws/credentials"
rc=0
out="$(bash "$REMOVE" "$ROOT/aws-repo" --root "$ROOT")" || rc=$?
assert_exit "ignored .aws credentials block exits 3" 3 "$rc"
assert_contains "SSOT secret-class block reason" "$out" "Blocked: secrets"

# Default root resolution (no --root): first chain link is `git config ghq.root`
# from the (test-scoped) global config.
FAKE_HOME="$TEST_TMPDIR/fake-home"
mkdir -p "$FAKE_HOME" "$ROOT/default-root-dir"
HOME="$FAKE_HOME" git config --global ghq.root "$ROOT"
out="$(HOME="$FAKE_HOME" bash "$REMOVE" "$ROOT/default-root-dir")"
rc=$?
assert_exit "default ghq.root resolution exits 0" 0 "$rc"
# The script resolves paths physically (pwd -P), so the reported Root is the
# physical form of $ROOT — mirror that here so the assertion holds wherever the
# tmpdir sits under a symlink (macOS /var -> /private/var, etc.).
ROOT_PHYS="$(cd "$ROOT" && pwd -P)"
ROOT_PHYS="${ROOT_PHYS//\\//}"
assert_contains "default root resolved from git config" "$out" "Root: $ROOT_PHYS"

# Nested git repos inside a plain-dir target are refused (exit 2) so a leftover
# owner dir cannot take child clones' state down with it.
mkdir -p "$ROOT/owner-dir"
make_repo "$ROOT/owner-dir/child-clone"
rc=0
out="$(bash "$REMOVE" "$ROOT/owner-dir" --root "$ROOT")" || rc=$?
assert_exit "plain dir with nested git repo refused exits 2" 2 "$rc"
assert_file_exists "nested child repo left intact by refusal" "$ROOT/owner-dir/child-clone/file.txt"

# A nested *bare* repo (HEAD + objects/ + refs/, no .git entry) is caught by the
# structural scan, not the .git-name scan.
mkdir -p "$ROOT/mirror-owner"
git_quiet init --bare "$ROOT/mirror-owner/project.git"
rc=0
out="$(bash "$REMOVE" "$ROOT/mirror-owner" --root "$ROOT")" || rc=$?
assert_exit "plain dir with nested bare repo refused exits 2" 2 "$rc"
assert_file_exists "nested bare repo left intact by refusal" "$ROOT/mirror-owner/project.git/HEAD"

# Plain leftover directory holding a secret-class file blocks like a repo does,
# and --include-secrets clears it.
mkdir -p "$ROOT/leftover-dir"
printf 'TOKEN=x\n' >"$ROOT/leftover-dir/.env"
rc=0
out="$(bash "$REMOVE" "$ROOT/leftover-dir" --root "$ROOT")" || rc=$?
assert_exit "plain dir with .env blocked exits 3" 3 "$rc"
assert_contains "plain dir secret block reason" "$out" "Blocked: secrets"
out="$(bash "$REMOVE" "$ROOT/leftover-dir" --root "$ROOT" --include-secrets)"
rc=$?
assert_exit "--include-secrets clears plain dir secret block" 0 "$rc"

# Skill-owned data/ is irreplaceable — blocked with NO override, in a plain dir.
mkdir -p "$ROOT/synth-dir/.claude/skills/notes/data"
printf 'synthesis\n' >"$ROOT/synth-dir/.claude/skills/notes/data/corpus.md"
rc=0
out="$(bash "$REMOVE" "$ROOT/synth-dir" --root "$ROOT")" || rc=$?
assert_exit "plain dir with skill data blocked exits 3" 3 "$rc"
assert_contains "plain dir skill-data block reason" "$out" "Blocked: skill-data"
rc=0
out="$(bash "$REMOVE" "$ROOT/synth-dir" --root "$ROOT" --include-secrets)" || rc=$?
assert_exit "--include-secrets does NOT clear skill-data block" 3 "$rc"

# Gitignored skill data in an otherwise-clean pushed repo blocks: it is neither
# dirty (ignored) nor secret-class, so only the skill-data scan catches it.
make_pushed_repo "$ROOT/skill-repo" "$TEST_TMPDIR/skill-remote.git"
printf '.claude/skills/*/data/\n' >"$ROOT/skill-repo/.gitignore"
git_quiet -C "$ROOT/skill-repo" add .gitignore
git_quiet -C "$ROOT/skill-repo" commit -m gitignore
git_quiet -C "$ROOT/skill-repo" push
mkdir -p "$ROOT/skill-repo/.claude/skills/notes/data"
printf 'synthesis\n' >"$ROOT/skill-repo/.claude/skills/notes/data/corpus.md"
rc=0
out="$(bash "$REMOVE" "$ROOT/skill-repo" --root "$ROOT")" || rc=$?
assert_exit "repo with gitignored skill data blocked exits 3" 3 "$rc"
assert_contains "repo skill-data block reason" "$out" "Blocked: skill-data"

# A local-only (never-pushed) tag counts as unpushed work: the branch is pushed
# but the annotated tag has no upstream.
make_pushed_repo "$ROOT/tag-repo" "$TEST_TMPDIR/tag-remote.git"
git_quiet -C "$ROOT/tag-repo" tag -a v1.0.0-rc1 -m rc
rc=0
out="$(bash "$REMOVE" "$ROOT/tag-repo" --root "$ROOT")" || rc=$?
assert_exit "local-only tag blocks exits 4" 4 "$rc"
assert_contains "local tag unpushed reason" "$out" "Blocked: unpushed"

# Stash guard: a clean-tree repo with a stash entry blocks.
make_pushed_repo "$ROOT/stash-repo" "$TEST_TMPDIR/stash-remote.git"
printf 'z\n' >>"$ROOT/stash-repo/file.txt"
git_quiet -C "$ROOT/stash-repo" stash push -m wip
rc=0
out="$(bash "$REMOVE" "$ROOT/stash-repo" --root "$ROOT")" || rc=$?
assert_exit "stash entry blocks exits 3" 3 "$rc"
assert_contains "stash block reason" "$out" "Blocked: stash"

# Pruned upstream fails closed as unpushed: the branch keeps its upstream config
# but the remote-tracking ref is gone (as after fetch --prune on an orphan clone).
make_pushed_repo "$ROOT/pruned-repo" "$TEST_TMPDIR/pruned-remote.git"
pruned_branch="$(git -C "$ROOT/pruned-repo" branch --show-current | tr -d '\r')"
git_quiet -C "$ROOT/pruned-repo" update-ref -d "refs/remotes/origin/$pruned_branch"
rc=0
out="$(bash "$REMOVE" "$ROOT/pruned-repo" --root "$ROOT")" || rc=$?
assert_exit "pruned upstream ref blocks exits 4" 4 "$rc"
assert_contains "pruned upstream unpushed reason" "$out" "Blocked: unpushed"

# Symlinked intermediate component must not bypass physical containment: pwd -P
# resolves it to the physical path outside the root, so the target is refused and
# rm -rf never traverses the link. POSIX symlink only (Windows-junction pwd -P
# resolution is platform-uncertain); skip where symlinks cannot be created.
OUTSIDE="$TEST_TMPDIR/outside-root"
mkdir -p "$OUTSIDE/victim"
printf 'keep\n' >"$OUTSIDE/victim/.keep"
if ln -s "$OUTSIDE" "$ROOT/escape-link" 2>/dev/null && [[ -L "$ROOT/escape-link" ]]; then
  rc=0
  bash "$REMOVE" "$ROOT/escape-link/victim" --root "$ROOT" --apply >/dev/null 2>&1 || rc=$?
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
