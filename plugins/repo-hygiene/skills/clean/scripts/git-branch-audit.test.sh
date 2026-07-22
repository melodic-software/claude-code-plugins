#!/usr/bin/env bash
# Tests for git-branch-audit.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"

AUDIT="$SCRIPT_DIR/git-branch-audit.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
FAILED=0

rc=0
bash "$AUDIT" --help >/dev/null 2>&1 || rc=$?
assert_exit "--help exits 0" 0 "$rc"

git init "$TEST_TMPDIR/repo" >/dev/null 2>&1
git -C "$TEST_TMPDIR/repo" config user.email "t@example.com"
git -C "$TEST_TMPDIR/repo" config user.name "Test"
echo x >"$TEST_TMPDIR/repo/x"
git -C "$TEST_TMPDIR/repo" add x
git -C "$TEST_TMPDIR/repo" commit -m "init" >/dev/null

out="$(GIT_DIR="$TEST_TMPDIR/repo/.git" GIT_WORK_TREE="$TEST_TMPDIR/repo" bash -c "cd '$TEST_TMPDIR/repo' && bash '$AUDIT'")"
assert_contains "lists branch" "$out" "Branch:"
assert_contains "protects current" "$out" "Tier: PROTECTED"
assert_contains "summary line" "$out" "Summary:"
assert_not_contains "no deletion" "$out" "Deleted:"

# Default branch: gh repo view path (no literal {owner}/{repo})
assert_not_contains "no placeholder owner/repo" "$out" "{owner}"

# CLOSED PR → REVIEW (mock gh + jq when available)
if command -v jq >/dev/null 2>&1; then
  fake_bin="$TEST_TMPDIR/fake-bin"
  mkdir -p "$fake_bin"
  cat >"$fake_bin/gh" <<'FAKEGH'
#!/usr/bin/env bash
case "$*" in
  *pr\ list*)
    printf '%s\n' '[{"headRefName":"feat/closed","state":"CLOSED","number":99,"headRefOid":"abc"}]'
    ;;
  *) exit 1 ;;
esac
FAKEGH
  chmod +x "$fake_bin/gh"
  git -C "$TEST_TMPDIR/repo" checkout -b feat/closed >/dev/null 2>&1 || true
  git -C "$TEST_TMPDIR/repo" checkout main >/dev/null 2>&1 || git -C "$TEST_TMPDIR/repo" checkout -b main >/dev/null 2>&1
  closed_out="$(PATH="$fake_bin:$PATH" GIT_DIR="$TEST_TMPDIR/repo/.git" GIT_WORK_TREE="$TEST_TMPDIR/repo" bash -c "cd '$TEST_TMPDIR/repo' && bash '$AUDIT'")"
  assert_contains "closed pr review tier" "$closed_out" "Tier: REVIEW"
  assert_contains "closed pr reason" "$closed_out" "PR closed without merge"
fi

# A no-op gh stub keeps the worktree / no-upstream cases below deterministic and
# offline (the real gh would hit the network for its PR map).
STUB_BIN="$TEST_TMPDIR/stub-bin"
mkdir -p "$STUB_BIN"
printf '#!/usr/bin/env bash\nexit 1\n' >"$STUB_BIN/gh"
chmod +x "$STUB_BIN/gh"

# Worktree exclusion: a branch checked out in a linked worktree is its own
# WORKTREE bucket — never a deletion candidate lumped under PROTECTED, and never
# offered for `git branch -d` (which would break the worktree).
WT_REPO="$TEST_TMPDIR/wt-repo"
git init -q "$WT_REPO"
git -C "$WT_REPO" config user.email "t@example.com"
git -C "$WT_REPO" config user.name "Test"
echo x >"$WT_REPO/x"
git -C "$WT_REPO" add x
git -C "$WT_REPO" commit -qm init
git -C "$WT_REPO" branch feat/parked
git -C "$WT_REPO" worktree add -q "$TEST_TMPDIR/wt-linked" feat/parked
wt_out="$(PATH="$STUB_BIN:$PATH" bash -c "cd '$WT_REPO' && bash '$AUDIT'")"
assert_contains "worktree branch own tier" "$wt_out" "Tier: WORKTREE"
assert_contains "worktree branch reason" "$wt_out" "clean up the worktree first"
assert_contains "summary counts worktree bucket" "$wt_out" "worktree=1"

# No-upstream classification: a never-pushed branch with commits not on
# origin/<default> is surfaced as its own class and Unpushed line, not left
# invisible behind @{upstream}-only ahead reporting.
NU_REPO="$TEST_TMPDIR/nu-repo"
git init -q --bare "$TEST_TMPDIR/nu-origin.git"
git init -q "$NU_REPO"
git -C "$NU_REPO" config user.email "t@example.com"
git -C "$NU_REPO" config user.name "Test"
echo a >"$NU_REPO/a"
git -C "$NU_REPO" add a
git -C "$NU_REPO" commit -qm init
git -C "$NU_REPO" remote add origin "$TEST_TMPDIR/nu-origin.git"
git -C "$NU_REPO" push -q origin HEAD:main
git -C "$NU_REPO" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
git -C "$NU_REPO" checkout -q -b feat/never-pushed
echo b >"$NU_REPO/b"
git -C "$NU_REPO" add b
git -C "$NU_REPO" commit -qm b
git -C "$NU_REPO" checkout -q main
nu_out="$(PATH="$STUB_BIN:$PATH" bash -c "cd '$NU_REPO' && bash '$AUDIT'")"
assert_contains "no-upstream unpushed line" "$nu_out" "no upstream, 1 commits not on origin/main"
assert_contains "no-upstream own review class" "$nu_out" "Reason: no upstream, 1 commits not on origin/main"

# A configured upstream whose tracking ref is unfetched still counts as no-upstream:
# `rev-parse --abbrev-ref` echoes the literal input on failure, which must not be
# mistaken for a real upstream (it would print `<branch>@{upstream}` as the ahead
# base). Configure tracking, then delete the remote-tracking ref to simulate it.
git -C "$NU_REPO" checkout -q -b feat/tracked-unfetched
echo c >"$NU_REPO/c"
git -C "$NU_REPO" add c
git -C "$NU_REPO" commit -qm c
git -C "$NU_REPO" config branch.feat/tracked-unfetched.remote origin
git -C "$NU_REPO" config branch.feat/tracked-unfetched.merge refs/heads/feat/tracked-unfetched
git -C "$NU_REPO" checkout -q main
uf_out="$(PATH="$STUB_BIN:$PATH" bash -c "cd '$NU_REPO' && bash '$AUDIT'")"
assert_not_contains "unfetched upstream not echoed literally" "$uf_out" "@{upstream}"
assert_contains "unfetched upstream falls to no-upstream count" "$uf_out" "no upstream, 1 commits not on origin/main"

if [[ $FAILED -ne 0 ]]; then
  echo "FAILED: $FAILED test(s)"
  exit 1
fi
echo "OK: git-branch-audit.sh tests passed"
