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

if [[ $FAILED -ne 0 ]]; then
  echo "FAILED: $FAILED test(s)"
  exit 1
fi
echo "OK: git-branch-audit.sh tests passed"
