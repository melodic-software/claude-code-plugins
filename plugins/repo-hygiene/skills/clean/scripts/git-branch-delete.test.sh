#!/usr/bin/env bash
# Tests for git-branch-delete.sh: the tip-capture precondition, the fail-closed
# batch semantics, and the end-to-end property that a branch deleted through
# this path is restorable from the artifact the audit produced, with no other
# information.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"

AUDIT="$SCRIPT_DIR/git-branch-audit.sh"
DELETE="$SCRIPT_DIR/git-branch-delete.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
FAILED=0

# A no-op gh stub keeps every case offline and deterministic (the real gh would
# hit the network for the audit's PR map).
STUB_BIN="$TEST_TMPDIR/stub-bin"
mkdir -p "$STUB_BIN"
printf '#!/usr/bin/env bash\nexit 1\n' >"$STUB_BIN/gh"
chmod +x "$STUB_BIN/gh"
export PATH="$STUB_BIN:$PATH"

rc=0
bash "$DELETE" --help >/dev/null 2>&1 || rc=$?
assert_exit "--help exits 0" 0 "$rc"

# ---- Fixture -----------------------------------------------------------------
# main pushed to a bare origin (so ancestry-merged branches classify SAFE), plus:
#   feat/safe1, feat/safe2  merged into main with --no-ff  -> SAFE, distinct tips
#   feat/likely             merged, pushed, then deleted on origin -> SAFE
#                           (ancestry, priority 6, outranks the gone upstream)
#   feat/still, feat/moved  merged; feat/moved gains a commit after the audit
#   feat/review             unmerged local work             -> REVIEW
#   feat/parked             checked out in a linked worktree -> WORKTREE
#   release/1               protected pattern
REPO="$TEST_TMPDIR/repo"
git init -q --bare "$TEST_TMPDIR/origin.git"
git init -q -b main "$REPO"
git -C "$REPO" config user.email "t@example.com"
git -C "$REPO" config user.name "Test"
echo base >"$REPO/base"
git -C "$REPO" add base
git -C "$REPO" commit -qm base
git -C "$REPO" remote add origin "$TEST_TMPDIR/origin.git"

merged_branch() { # <name> <file>: branch with one commit, merged --no-ff into main
  git -C "$REPO" checkout -q -b "$1"
  echo "$2" >"$REPO/$2"
  git -C "$REPO" add "$2"
  git -C "$REPO" commit -qm "$2"
  git -C "$REPO" checkout -q main
  git -C "$REPO" merge -q --no-ff -m "merge $1" "$1"
}
merged_branch feat/safe1 s1
merged_branch feat/safe2 s2
merged_branch feat/still st
merged_branch feat/moved mv
merged_branch feat/ok1 o1
merged_branch feat/blocked bl
merged_branch feat/ok2 o2
git -C "$REPO" push -q -u origin main
git -C "$REPO" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

git -C "$REPO" checkout -q -b feat/likely
echo l >"$REPO/l"
git -C "$REPO" add l
git -C "$REPO" commit -qm l
git -C "$REPO" checkout -q main
git -C "$REPO" merge -q --no-ff -m "merge likely" feat/likely
git -C "$REPO" push -q origin main
git -C "$REPO" push -q -u origin feat/likely
git -C "$REPO" push -q origin --delete feat/likely
git -C "$REPO" fetch -q --prune origin

git -C "$REPO" checkout -q -b feat/review
echo r >"$REPO/r"
git -C "$REPO" add r
git -C "$REPO" commit -qm r
git -C "$REPO" checkout -q main

git -C "$REPO" branch feat/parked
git -C "$REPO" worktree add -q "$TEST_TMPDIR/wt-parked" feat/parked
git -C "$REPO" branch release/1

branch_exists() { git -C "$REPO" rev-parse --verify --quiet "refs/heads/$1" >/dev/null 2>&1; }
run_delete() { (cd "$REPO" && bash "$DELETE" "$@"); }

# ---- No capture: refused, nothing deleted -----------------------------------
out="$(run_delete feat/safe1 2>&1)"
rc=$?
assert_exit "no --capture exits 3" 3 "$rc"
assert_contains "no --capture names what is missing" "$out" "Refused: no --capture given"
assert_contains "no --capture says how to produce it" "$out" "run git-branch-audit.sh and pass its TipCapture: path"
assert_not_contains "no --capture deletes nothing" "$out" "Deleted:"
branch_exists feat/safe1 && pass "no --capture: feat/safe1 still exists" || fail "no --capture: feat/safe1 still exists" "exists" "gone"

out="$(run_delete --capture "$TEST_TMPDIR/does-not-exist.tsv" feat/safe1 2>&1)"
rc=$?
assert_exit "unreadable capture exits 3" 3 "$rc"
assert_contains "unreadable capture refused" "$out" "Refused: capture not readable"

printf 'not a capture\n' >"$TEST_TMPDIR/bogus.tsv"
out="$(run_delete --capture "$TEST_TMPDIR/bogus.tsv" feat/safe1 2>&1)"
rc=$?
assert_exit "bad header exits 3" 3 "$rc"
assert_contains "bad header refused" "$out" "bad header"

# ---- Audit produces the capture --------------------------------------------
audit_out="$(cd "$REPO" && bash "$AUDIT")"
CAP="$(printf '%s\n' "$audit_out" | sed -n 's/^TipCapture: //p')"
assert_file_exists "audit wrote a capture" "$CAP"
assert_contains "capture lives under the common git dir" "$CAP" "$REPO/.git/repo-hygiene/branch-tips/"
safe1_tip="$(git -C "$REPO" rev-parse refs/heads/feat/safe1)"
safe2_tip="$(git -C "$REPO" rev-parse refs/heads/feat/safe2)"
likely_tip="$(git -C "$REPO" rev-parse refs/heads/feat/likely)"
assert_contains "audit classifies feat/safe1 SAFE" "$audit_out" "Branch: feat/safe1
Tip: $safe1_tip
Tier: SAFE"
assert_contains "audit reports feat/likely tip with its verdict" "$audit_out" "Branch: feat/likely
Tip: $likely_tip
Tier: SAFE"

# ---- Dry-run plans, deletes nothing ------------------------------------------
out="$(run_delete --capture "$CAP" feat/safe1 feat/safe2 feat/likely 2>&1)"
rc=$?
assert_exit "dry-run exits 0" 0 "$rc"
assert_contains "dry-run plans safe1 with its tip" "$out" "Planned: feat/safe1 $safe1_tip (SAFE, git branch -d)"
assert_contains "dry-run plans likely (gone upstream, merged) with -d" "$out" "Planned: feat/likely $likely_tip (SAFE, git branch -d)"
assert_contains "dry-run summary" "$out" "Summary: planned=3 refused=0 deleted=0"
assert_contains "dry-run tells how to restore" "$out" "Restore: git branch <branch> <tip>"
assert_not_contains "dry-run deletes nothing" "$out" "Deleted:"
branch_exists feat/safe1 && branch_exists feat/likely && pass "dry-run: branches intact" || fail "dry-run: branches intact" "intact" "deleted"
assert_file_absent "dry-run writes no ledger" "${CAP%.tsv}.deleted.tsv"

# ---- Tier gates ---------------------------------------------------------------
out="$(run_delete --capture "$CAP" feat/review 2>&1)"
rc=$?
assert_exit "REVIEW without --force-review exits 3" 3 "$rc"
assert_contains "REVIEW refused names the flag" "$out" "Refused: feat/review (tier REVIEW; pass --force-review"
out="$(run_delete --capture "$CAP" --force-review feat/review 2>&1)"
rc=$?
assert_exit "REVIEW with --force-review plans" 0 "$rc"
assert_contains "forced REVIEW uses -D" "$out" "(REVIEW, git branch -D)"

out="$(run_delete --capture "$CAP" --force-review release/1 main feat/parked 2>&1)"
rc=$?
assert_exit "protected/current/worktree exit 3 even forced" 3 "$rc"
assert_contains "protected pattern refused" "$out" "Refused: release/1 (protected pattern)"
assert_contains "current branch refused" "$out" "Refused: main (current branch)"
assert_contains "worktree branch refused" "$out" "Refused: feat/parked (checked out in a linked worktree"

# ---- One bad branch refuses the whole batch ---------------------------------
out="$(run_delete --capture "$CAP" --apply feat/safe1 feat/review 2>&1)"
rc=$?
assert_exit "mixed batch exits 3" 3 "$rc"
assert_not_contains "mixed batch deletes nothing" "$out" "Deleted:"
branch_exists feat/safe1 && pass "mixed batch: deletable feat/safe1 untouched" || fail "mixed batch: deletable feat/safe1 untouched" "exists" "gone"

# ---- Tip moved between capture and delete: batch stops ----------------------
git -C "$REPO" checkout -q feat/moved
echo more >>"$REPO/mv"
git -C "$REPO" add mv
git -C "$REPO" commit -qm "moved after audit"
git -C "$REPO" checkout -q main
moved_tip_now="$(git -C "$REPO" rev-parse refs/heads/feat/moved)"
out="$(run_delete --capture "$CAP" --apply feat/still feat/moved 2>&1)"
rc=$?
assert_exit "moved tip exits 3" 3 "$rc"
assert_contains "moved tip refused names both shas" "$out" "Refused: feat/moved (tip moved since capture: captured"
assert_contains "moved tip refused names current sha" "$out" "now $moved_tip_now"
assert_not_contains "moved tip: nothing deleted" "$out" "Deleted:"
branch_exists feat/still && pass "moved tip: unmoved sibling feat/still untouched" || fail "moved tip: unmoved sibling feat/still untouched" "exists" "gone"
branch_exists feat/moved && pass "moved tip: feat/moved untouched" || fail "moved tip: feat/moved untouched" "exists" "gone"

# ---- Branch absent from the capture: refused --------------------------------
grep -v $'^feat/still\t' "$CAP" >"$TEST_TMPDIR/short.tsv"
out="$(run_delete --capture "$TEST_TMPDIR/short.tsv" --apply feat/still 2>&1)"
rc=$?
assert_exit "missing row exits 3" 3 "$rc"
assert_contains "missing row refused" "$out" "Refused: feat/still (no captured tip in"
branch_exists feat/still && pass "missing row: feat/still untouched" || fail "missing row: feat/still untouched" "exists" "gone"

# ---- Capture from another repository: refused -------------------------------
OTHER="$TEST_TMPDIR/other"
git init -q -b main "$OTHER"
git -C "$OTHER" config user.email "t@example.com"
git -C "$OTHER" config user.name "Test"
echo o >"$OTHER/o"
git -C "$OTHER" add o
git -C "$OTHER" commit -qm o
git -C "$OTHER" branch feat/still
other_cap="$(cd "$OTHER" && bash "$AUDIT" | sed -n 's/^TipCapture: //p')"
out="$(run_delete --capture "$other_cap" --apply feat/still 2>&1)"
rc=$?
assert_exit "foreign capture exits 3" 3 "$rc"
assert_contains "foreign capture refused" "$out" "different repository"

# ---- Apply: capture before delete, ledger, backup ref, restore --------------
out="$(run_delete --capture "$CAP" --apply feat/safe1 feat/safe2 feat/likely 2>&1)"
rc=$?
assert_exit "apply exits 0" 0 "$rc"
assert_contains "apply reports safe1 with restore command" "$out" "Deleted: feat/safe1 $safe1_tip (was SAFE) restore: git branch feat/safe1 $safe1_tip"
assert_contains "apply reports likely" "$out" "Deleted: feat/likely $likely_tip (was SAFE)"
assert_contains "apply summary" "$out" "Summary: planned=3 refused=0 deleted=3 failed=0"
assert_contains "apply names the ledger" "$out" "Ledger: ${CAP%.tsv}.deleted.tsv"
branch_exists feat/safe1 && fail "apply: feat/safe1 deleted" "gone" "exists" || pass "apply: feat/safe1 deleted"
branch_exists feat/likely && fail "apply: feat/likely deleted" "gone" "exists" || pass "apply: feat/likely deleted"
LEDGER="${CAP%.tsv}.deleted.tsv"
assert_file_exists "ledger written" "$LEDGER"
assert_contains "ledger row for safe1" "$(cat "$LEDGER")" "feat/safe1	$safe1_tip	"
assert_contains "ledger row for safe2" "$(cat "$LEDGER")" "feat/safe2	$safe2_tip	"
backup="$(git -C "$REPO" rev-parse --verify --quiet refs/repo-hygiene/deleted/feat/safe1)"
[[ "$backup" == "$safe1_tip" ]] && pass "backup ref pins safe1 tip" || fail "backup ref pins safe1 tip" "$safe1_tip" "${backup:-none}"

# The end-to-end property. Only the capture file is consulted: branch name in,
# tip out, `git branch <name> <tip>`. gc --prune=now first, so the restore also
# proves the pinned tip survived the prune the git tier runs after a deletion.
git -C "$REPO" gc -q --prune=now 2>/dev/null
for b in feat/safe1 feat/safe2 feat/likely; do
  tip="$(awk -F'\t' -v b="$b" '!/^#/ && $1==b {print $2}' "$CAP")"
  if [[ -n "$tip" ]] && git -C "$REPO" branch "$b" "$tip" 2>/dev/null &&
    [[ "$(git -C "$REPO" rev-parse "refs/heads/$b")" == "$tip" ]]; then
    pass "restored $b from the capture alone"
  else
    fail "restored $b from the capture alone" "$tip" "$(git -C "$REPO" rev-parse --verify --quiet "refs/heads/$b" || echo none)"
  fi
done
[[ "$(git -C "$REPO" show feat/safe1:s1 2>/dev/null)" == "s1" ]] && pass "restored safe1 carries its content" || fail "restored safe1 carries its content" "s1" "missing"

# Control for the pin: the same deletion without the backup ref loses the commit
# to the same prune, which is why step 2 precedes the delete.
CTRL="$TEST_TMPDIR/ctrl"
git init -q -b main "$CTRL"
git -C "$CTRL" config user.email "t@example.com"
git -C "$CTRL" config user.name "Test"
echo c >"$CTRL/c"
git -C "$CTRL" add c
git -C "$CTRL" commit -qm c
git -C "$CTRL" checkout -q -b feat/unpinned
echo u >"$CTRL/u"
git -C "$CTRL" add u
git -C "$CTRL" commit -qm u
unpinned_tip="$(git -C "$CTRL" rev-parse HEAD)"
git -C "$CTRL" checkout -q main
git -C "$CTRL" branch -D feat/unpinned >/dev/null
git -C "$CTRL" reflog expire --expire=now --all
git -C "$CTRL" gc -q --prune=now 2>/dev/null
git -C "$CTRL" cat-file -e "$unpinned_tip" 2>/dev/null && fail "control: unpinned tip pruned" "pruned" "present" || pass "control: unpinned tip pruned by gc --prune=now"

# ---- Apply aborts mid-batch, before touching the blocked branch -------------
# A ref nested under the backup name makes update-ref fail for feat/blocked
# (directory/file conflict). Fresh capture: feat/safe* were recreated above.
CAP2="$(cd "$REPO" && bash "$AUDIT" | sed -n 's/^TipCapture: //p')"
git -C "$REPO" update-ref refs/repo-hygiene/deleted/feat/blocked/child HEAD
out="$(run_delete --capture "$CAP2" --apply feat/ok1 feat/blocked feat/ok2 2>&1)"
rc=$?
assert_exit "backup-ref failure exits 1" 1 "$rc"
assert_contains "ok1 deleted before the abort" "$out" "Deleted: feat/ok1 "
assert_contains "abort names the backup ref" "$out" "Aborted: feat/blocked (could not write backup ref"
assert_contains "abort summary counts untouched (blocked + ok2)" "$out" "deleted=1 failed=0 aborted=1 untouched=2"
branch_exists feat/blocked && pass "abort: feat/blocked untouched" || fail "abort: feat/blocked untouched" "exists" "gone"
branch_exists feat/ok2 && pass "abort: feat/ok2 untouched" || fail "abort: feat/ok2 untouched" "exists" "gone"
git -C "$REPO" update-ref -d refs/repo-hygiene/deleted/feat/blocked/child

# ---- Ledger unwritable: nothing deleted -------------------------------------
CAP3="$(cd "$REPO" && bash "$AUDIT" --capture-file "$TEST_TMPDIR/cap3.tsv" | sed -n 's/^TipCapture: //p')"
mkdir -p "$TEST_TMPDIR/cap3.deleted.tsv" # a directory where the ledger must go
out="$(run_delete --capture "$CAP3" --apply feat/ok2 2>&1)"
rc=$?
assert_exit "unwritable ledger exits 1" 1 "$rc"
assert_contains "unwritable ledger aborts" "$out" "Aborted: cannot write ledger"
assert_not_contains "unwritable ledger deletes nothing" "$out" "Deleted:"
branch_exists feat/ok2 && pass "unwritable ledger: feat/ok2 untouched" || fail "unwritable ledger: feat/ok2 untouched" "exists" "gone"

if [[ $FAILED -ne 0 ]]; then
  echo "FAILED: $FAILED test(s)"
  exit 1
fi
echo "OK: git-branch-delete.sh tests passed"
