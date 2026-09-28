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

rc=0
bash "$SCRIPT" --apply --repo "$ROOT/repo" >/dev/null 2>"$ROOT/apply.err" || rc=$?
assert_exit "--apply is refused" 2 "$rc"
assert_contains "--apply names the refusal" "$(cat "$ROOT/apply.err")" "refused"
if [[ -d "$ROOT/repo/.git" ]]; then
  pass "refused --apply left the repository"
else
  fail "--apply removed the repository"
fi

FAKE="$(mktemp -d)"
cat >"$FAKE/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' '[{"headRefName":"feature","state":"MERGED","headRefOid":"$FEATURE_SHA"}]'
EOF
chmod +x "$FAKE/gh"
# The merged branch lives in a linked worktree. The primary checkout stays held.
git -C "$ROOT/repo" checkout -q main
git -C "$ROOT/repo" worktree add -q "$ROOT/linked" feature
out="$(PATH="$FAKE:$PATH" bash "$SCRIPT" --repo "$ROOT/repo")"
assert_contains "merged matching tip is review-remove" "$out" "Proposed: review-remove"
assert_contains "report counts one review-remove" "$out" "review-remove=1"
assert_contains "primary checkout is held" "$out" "Proposed: hold-primary"
if [[ -d "$ROOT/linked" && -d "$ROOT/repo/.git" ]]; then
  pass "linked worktree and primary checkout still present"
else
  fail "a worktree directory was removed"
fi

# A later unpushed commit is not review-remove.
git -C "$ROOT/linked" commit -q --allow-empty -m later
out="$(PATH="$FAKE:$PATH" bash "$SCRIPT" --repo "$ROOT/repo")"
assert_contains "unpushed tip is a sha mismatch" "$out" "Proposed: hold-sha-mismatch"

# Built-in carve-out, even with no --hold.
git -C "$ROOT/repo" worktree add -q "$ROOT/spike" -b spike-lane
out="$(PATH="$FAKE:$PATH" bash "$SCRIPT" --repo "$ROOT/repo")"
assert_contains "spike basename is a built-in carve-out" "$out" "built-in carve-out spike"
if [[ -d "$ROOT/spike" ]]; then
  pass "spike worktree still present"
else
  fail "spike worktree was removed"
fi

if [[ "$FAILED" -eq 0 ]]; then
  echo "worktree-reconcile.test.sh: all passed"
  exit 0
fi
exit 1
