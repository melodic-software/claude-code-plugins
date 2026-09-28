#!/usr/bin/env bash
# Dry-run reconcile: proposes labels and deletes nothing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/worktree-reconcile.sh"
# shellcheck source=../../clean/scripts/lib/test-helpers.sh
source "$SCRIPT_DIR/../../clean/scripts/lib/test-helpers.sh"

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
FAILED=0

git init -q "$ROOT/origin" --bare
git init -q "$ROOT/repo"
git -C "$ROOT/repo" config user.email t@example.com
git -C "$ROOT/repo" config user.name Test
git -C "$ROOT/repo" commit -q --allow-empty -m init
git -C "$ROOT/repo" branch -M main
git -C "$ROOT/repo" remote add origin "$ROOT/origin"
git -C "$ROOT/repo" push -q origin main
git -C "$ROOT/repo" checkout -q -b feature
git -C "$ROOT/repo" commit -q --allow-empty -m feature
git -C "$ROOT/repo" push -q origin feature
FEATURE_SHA="$(git -C "$ROOT/repo" rev-parse HEAD)"

rc=0
help_out="$(bash "$SCRIPT" --help 2>&1)" || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help says it never deletes" "$help_out" "never deletes"

rc=0
bash "$SCRIPT" --repo "$ROOT" >/dev/null 2>&1 || rc=$?
assert_exit "a non-repo exits 2" 2 "$rc"

# Dirty main worktree is a hold, and the dirty file survives.
printf 'keep me\n' >"$ROOT/repo/note.txt"
out="$(bash "$SCRIPT" --repo "$ROOT/repo" --hold "$ROOT/repo")"
assert_contains "carve-out wins over dirty" "$out" "Proposed: hold-carve-out"
assert_contains "dry-run note" "$out" "no worktree, branch, stash, or file was deleted"
if [[ -f "$ROOT/repo/note.txt" ]]; then
  pass "dirty file still exists"
else
  fail "the dry-run deleted note.txt"
fi

rm -f "$ROOT/repo/note.txt"
# No gh: insufficient evidence, not review-remove.
out="$(bash "$SCRIPT" --repo "$ROOT/repo")"
assert_contains "missing gh is announced" "$out" "PRDataUnavailable:"
assert_not_contains "missing gh does not propose removal" "$out" "Proposed: review-remove"

FAKE="$(mktemp -d)"
cat >"$FAKE/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' '[{"headRefName":"feature","state":"MERGED","headRefOid":"$FEATURE_SHA"}]'
EOF
chmod +x "$FAKE/gh"
# The feature branch is checked out in the primary worktree and is clean.
git -C "$ROOT/repo" checkout -q feature
out="$(PATH="$FAKE:$PATH" bash "$SCRIPT" --repo "$ROOT/repo")"
assert_contains "merged matching tip is review-remove" "$out" "Proposed: review-remove"
assert_contains "report counts one review-remove" "$out" "review-remove=1"
if [[ -d "$ROOT/repo/.git" || -f "$ROOT/repo/.git" ]]; then
  pass "worktree still present after review-remove"
else
  fail "worktree directory was removed"
fi

# A later unpushed commit is not review-remove.
git -C "$ROOT/repo" commit -q --allow-empty -m later
out="$(PATH="$FAKE:$PATH" bash "$SCRIPT" --repo "$ROOT/repo")"
assert_contains "unpushed tip is a sha mismatch" "$out" "Proposed: hold-sha-mismatch"

if [[ "$FAILED" -eq 0 ]]; then
  echo "worktree-reconcile.test.sh: all passed"
  exit 0
fi
exit 1
