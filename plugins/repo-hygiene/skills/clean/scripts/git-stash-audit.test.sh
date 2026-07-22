#!/usr/bin/env bash
# Tests for git-stash-audit.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"

AUDIT="$SCRIPT_DIR/git-stash-audit.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
FAILED=0

rc=0
bash "$AUDIT" --help >/dev/null 2>&1 || rc=$?
assert_exit "--help exits 0" 0 "$rc"

# A no-op gh stub keeps the audit deterministic and offline.
STUB_BIN="$TEST_TMPDIR/stub-bin"
mkdir -p "$STUB_BIN"
printf '#!/usr/bin/env bash\nexit 1\n' >"$STUB_BIN/gh"
chmod +x "$STUB_BIN/gh"

# Empty repo: no stashes → count 0, never an error, exit 0.
# `-b main` pins the initial branch so the assertions below hold on machines where
# `git init` still defaults to `master`.
git init -q -b main "$TEST_TMPDIR/empty"
git -C "$TEST_TMPDIR/empty" config user.email "t@example.com"
git -C "$TEST_TMPDIR/empty" config user.name "Test"
echo x >"$TEST_TMPDIR/empty/x"
git -C "$TEST_TMPDIR/empty" add x
git -C "$TEST_TMPDIR/empty" commit -qm init
empty_out="$(PATH="$STUB_BIN:$PATH" bash -c "cd '$TEST_TMPDIR/empty' && bash '$AUDIT'")"
assert_contains "emits stash store key" "$empty_out" "StashStore:"
assert_contains "zero stash count" "$empty_out" "Stash count: 0"
assert_contains "summary line" "$empty_out" "Summary: stashes=0"

# Populated repo: a stash on the default branch is live WIP (never superseded),
# a stash whose source branch merged into origin/<default> is flagged possibly
# superseded — but only ever as advisory, never dropped.
REPO="$TEST_TMPDIR/repo"
git init -q --bare "$TEST_TMPDIR/origin.git"
git init -q -b main "$REPO"
git -C "$REPO" config user.email "t@example.com"
git -C "$REPO" config user.name "Test"
echo a >"$REPO/a"
git -C "$REPO" add a
git -C "$REPO" commit -qm init
git -C "$REPO" remote add origin "$TEST_TMPDIR/origin.git"
git -C "$REPO" push -q origin HEAD:main
git -C "$REPO" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
echo change >"$REPO/a"
git -C "$REPO" stash push -q -m "live wip on main"
git -C "$REPO" checkout -q -b feat/done
echo b >"$REPO/b"
git -C "$REPO" add b
git -C "$REPO" commit -qm b
git -C "$REPO" checkout -q main
git -C "$REPO" merge -q feat/done
git -C "$REPO" push -q origin main
git -C "$REPO" checkout -q feat/done
echo edit >>"$REPO/b"
git -C "$REPO" stash push -q -m "pre-merge backup"
git -C "$REPO" checkout -q main
out="$(PATH="$STUB_BIN:$PATH" bash -c "cd '$REPO' && bash '$AUDIT'")"
assert_contains "counts both stashes" "$out" "Stash count: 2"
assert_contains "emits diffstat" "$out" "Diffstat:"
assert_contains "attributes source branch" "$out" "Source branch: feat/done"
assert_contains "merged source flagged superseded" "$out" "possibly superseded"
# A stash on the default branch is live WIP, never flagged superseded.
assert_contains "main stash stays review" "$out" "review — confirm with the user"
assert_contains "never auto-dropped disclaimer" "$out" "never auto-dropped"
# Each stash carries its stable commit id — the safe handle for multi-drop, since
# the stash@{n} selector renumbers after every drop.
sha0="$(git -C "$REPO" rev-parse "stash@{0}" 2>/dev/null)"
assert_contains "emits stable stash commit id" "$out" "Commit: $sha0"

if [[ $FAILED -ne 0 ]]; then
  echo "FAILED: $FAILED test(s)"
  exit 1
fi
echo "OK: git-stash-audit.sh tests passed"
