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
#   #42-hash                merged; a legal name that starts like a comment
#   feat/sym                merged; deleted through a symlinked capture
#   feat/win-b, feat/win-a1, feat/win-a2  merged; the two tip-move windows
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
merged_branch '#42-hash' hh
merged_branch feat/sym sy
merged_branch feat/win-b wb
merged_branch feat/win-a1 wa1
merged_branch feat/win-a2 wa2
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

# assert_branch <label> <present|absent> <branch>
assert_branch() {
  local label="$1" want="$2" branch="$3" got="absent"
  if branch_exists "$branch"; then got="present"; fi
  if [[ "$got" == "$want" ]]; then pass "$label"; else fail "$label" "$want" "$got"; fi
}

# assert_eq <label> <expected> <actual>
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}

# ---- No capture: refused, nothing deleted -----------------------------------
out="$(run_delete feat/safe1 2>&1)"
rc=$?
assert_exit "no --capture exits 3" 3 "$rc"
assert_contains "no --capture names what is missing" "$out" "Refused: no --capture given"
assert_contains "no --capture says how to produce it" "$out" "run git-branch-audit.sh and pass its TipCapture: path"
assert_not_contains "no --capture deletes nothing" "$out" "Deleted:"
assert_branch "no --capture: feat/safe1 still exists" present feat/safe1

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
# A branch name may begin with `#`. The capture must not mistake its row for a
# comment: the seal would then count one row short and fail the whole audit.
hash_tip="$(git -C "$REPO" rev-parse 'refs/heads/#42-hash')"
assert_not_contains "a #-leading branch does not break the seal" "$audit_out" "TipCaptureError:"
assert_contains "audit classifies #42-hash SAFE" "$audit_out" "Branch: #42-hash
Tip: $hash_tip
Tier: SAFE"
assert_contains "capture row for #42-hash" "$(cat "$CAP")" "#42-hash	$hash_tip	SAFE	"

# ---- Dry-run plans, deletes nothing ------------------------------------------
out="$(run_delete --capture "$CAP" feat/safe1 feat/safe2 feat/likely '#42-hash' 2>&1)"
rc=$?
assert_exit "dry-run exits 0" 0 "$rc"
assert_contains "dry-run plans safe1 with its tip" "$out" "Planned: feat/safe1 $safe1_tip (SAFE, safe delete)"
assert_contains "dry-run plans likely (gone upstream, merged) as a safe delete" "$out" "Planned: feat/likely $likely_tip (SAFE, safe delete)"
assert_contains "dry-run plans the #-leading branch from its captured row" "$out" "Planned: #42-hash $hash_tip (SAFE, safe delete)"
assert_contains "dry-run summary" "$out" "Summary: planned=4 refused=0 deleted=0"
assert_contains "dry-run tells how to restore" "$out" "Restore: git branch <branch> <tip>"
assert_not_contains "dry-run deletes nothing" "$out" "Deleted:"
assert_branch "dry-run: feat/safe1 intact" present feat/safe1
assert_branch "dry-run: feat/likely intact" present feat/likely
assert_file_absent "dry-run writes no ledger" "${CAP%.tsv}.deleted.tsv"

# ---- Tier gates ---------------------------------------------------------------
out="$(run_delete --capture "$CAP" feat/review 2>&1)"
rc=$?
assert_exit "REVIEW without --force-review exits 3" 3 "$rc"
assert_contains "REVIEW refused names the flag" "$out" "Refused: feat/review (tier REVIEW; pass --force-review"
out="$(run_delete --capture "$CAP" --force-review feat/review 2>&1)"
rc=$?
assert_exit "REVIEW with --force-review plans" 0 "$rc"
assert_contains "forced REVIEW is a force delete" "$out" "(REVIEW, force delete)"

# A SAFE-by-ancestry row whose tip is not merged (a forged or wrong capture) is
# refused up front: previously `git branch -d` discovered it only after the pin
# and a ledger row claiming deletion had been written.
awk -F'\t' -v OFS='\t' '$1 == "feat/review" { $3 = "SAFE" } 1' "$CAP" >"$TEST_TMPDIR/forged.tsv"
out="$(run_delete --capture "$TEST_TMPDIR/forged.tsv" --apply feat/review 2>&1)"
rc=$?
assert_exit "forged SAFE row exits 3" 3 "$rc"
assert_contains "forged SAFE row refused as unmerged" "$out" "Refused: feat/review (captured as SAFE by ancestry, but $(git -C "$REPO" rev-parse refs/heads/feat/review) is not merged into origin/main"
assert_not_contains "forged SAFE row: nothing deleted" "$out" "Deleted:"
assert_branch "forged SAFE row: feat/review untouched" present feat/review
assert_file_absent "forged SAFE row: no ledger written" "$TEST_TMPDIR/forged.deleted.tsv"
assert_eq "forged SAFE row: no pin written" "none" "$(git -C "$REPO" rev-parse --verify --quiet refs/repo-hygiene/deleted/feat/review || echo none)"

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
assert_branch "mixed batch: deletable feat/safe1 untouched" present feat/safe1

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
assert_branch "moved tip: unmoved sibling feat/still untouched" present feat/still
assert_branch "moved tip: feat/moved untouched" present feat/moved

# ---- Branch absent from the capture: refused --------------------------------
grep -v $'^feat/still\t' "$CAP" >"$TEST_TMPDIR/short.tsv"
out="$(run_delete --capture "$TEST_TMPDIR/short.tsv" --apply feat/still 2>&1)"
rc=$?
assert_exit "missing row exits 3" 3 "$rc"
assert_contains "missing row refused" "$out" "Refused: feat/still (no captured tip in"
assert_branch "missing row: feat/still untouched" present feat/still

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
out="$(run_delete --capture "$CAP" --apply feat/safe1 feat/safe2 feat/likely '#42-hash' 2>&1)"
rc=$?
assert_exit "apply exits 0" 0 "$rc"
assert_contains "apply reports safe1 with restore command" "$out" "Deleted: feat/safe1 $safe1_tip (was SAFE) restore: git branch feat/safe1 $safe1_tip"
assert_contains "apply reports likely" "$out" "Deleted: feat/likely $likely_tip (was SAFE)"
assert_contains "apply reports the #-leading branch" "$out" "Deleted: #42-hash $hash_tip (was SAFE)"
assert_contains "apply summary" "$out" "Summary: planned=4 refused=0 deleted=4 failed=0"
assert_contains "apply names the ledger" "$out" "Ledger: ${CAP%.tsv}.deleted.tsv"
assert_branch "apply: feat/safe1 deleted" absent feat/safe1
assert_branch "apply: feat/likely deleted" absent feat/likely
assert_branch "apply: #42-hash deleted" absent '#42-hash'
LEDGER="${CAP%.tsv}.deleted.tsv"
assert_file_exists "ledger written" "$LEDGER"
assert_contains "ledger row for safe1" "$(cat "$LEDGER")" "feat/safe1	$safe1_tip	"
assert_contains "ledger row for safe2" "$(cat "$LEDGER")" "feat/safe2	$safe2_tip	"
backup="$(git -C "$REPO" rev-parse --verify --quiet refs/repo-hygiene/deleted/feat/safe1)"
assert_eq "backup ref pins safe1 tip" "$safe1_tip" "${backup:-none}"

# The end-to-end property. Only the capture file is consulted: branch name in,
# tip out, `git branch <name> <tip>`. gc --prune=now first, so the restore also
# proves the pinned tip survived the prune the git tier runs after a deletion.
git -C "$REPO" gc -q --prune=now 2>/dev/null
for b in feat/safe1 feat/safe2 feat/likely '#42-hash'; do
  tip="$(awk -F'\t' -v b="$b" '$1 == b { print $2 }' "$CAP")"
  if [[ -n "$tip" ]] && git -C "$REPO" branch "$b" "$tip" 2>/dev/null &&
    [[ "$(git -C "$REPO" rev-parse "refs/heads/$b")" == "$tip" ]]; then
    pass "restored $b from the capture alone"
  else
    fail "restored $b from the capture alone" "$tip" "$(git -C "$REPO" rev-parse --verify --quiet "refs/heads/$b" || echo none)"
  fi
done
assert_eq "restored safe1 carries its content" "s1" "$(git -C "$REPO" show feat/safe1:s1 2>/dev/null || echo missing)"
assert_eq "restored #42-hash carries its content" "hh" "$(git -C "$REPO" show '#42-hash:hh' 2>/dev/null || echo missing)"

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
unpinned_state="pruned"
if git -C "$CTRL" cat-file -e "$unpinned_tip" 2>/dev/null; then unpinned_state="present"; fi
assert_eq "control: unpinned tip pruned by gc --prune=now" "pruned" "$unpinned_state"

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
assert_branch "abort: feat/blocked untouched" present feat/blocked
assert_branch "abort: feat/ok2 untouched" present feat/ok2
git -C "$REPO" update-ref -d refs/repo-hygiene/deleted/feat/blocked/child

# ---- Ledger unwritable: nothing deleted -------------------------------------
CAP3="$(cd "$REPO" && bash "$AUDIT" --capture-file "$TEST_TMPDIR/cap3.tsv" | sed -n 's/^TipCapture: //p')"
mkdir -p "$TEST_TMPDIR/cap3.deleted.tsv" # a directory where the ledger must go
out="$(run_delete --capture "$CAP3" --apply feat/ok2 2>&1)"
rc=$?
assert_exit "unwritable ledger exits 1" 1 "$rc"
assert_contains "unwritable ledger aborts" "$out" "Aborted: cannot write ledger"
assert_not_contains "unwritable ledger deletes nothing" "$out" "Deleted:"
assert_branch "unwritable ledger: feat/ok2 untouched" present feat/ok2

# ---- Ledger follows the capture's real location -----------------------------
mkdir -p "$TEST_TMPDIR/real" "$TEST_TMPDIR/lnk"
CAP_SYM="$(cd "$REPO" && bash "$AUDIT" --capture-file "$TEST_TMPDIR/real/cap-sym.tsv" | sed -n 's/^TipCapture: //p')"
ln -s "$CAP_SYM" "$TEST_TMPDIR/lnk/cap-sym.tsv"
out="$(run_delete --capture "$TEST_TMPDIR/lnk/cap-sym.tsv" --apply feat/sym 2>&1)"
rc=$?
assert_exit "symlinked capture applies" 0 "$rc"
assert_contains "ledger is derived from the real capture, not the symlink" "$out" "Ledger: $TEST_TMPDIR/real/cap-sym.deleted.tsv"
assert_file_exists "ledger written beside the real capture" "$TEST_TMPDIR/real/cap-sym.deleted.tsv"
assert_file_absent "no ledger beside the symlink" "$TEST_TMPDIR/lnk/cap-sym.deleted.tsv"

# ---- The two tip-move windows, opened deterministically ---------------------
# A FIFO at the ledger path parks the script, with no reader present, at the
# moment it opens the ledger to append a branch's row: after that branch's pin
# (step 2) and before its delete (step 4). The pin appearing is the signal that
# it is parked there. Window B moves the parked branch's own tip, so the move
# lands between pin and delete and only an atomic compare-and-delete can refuse
# it. Window A parks on a first branch and moves the SECOND branch's tip, so the
# move lands after the batch check and before that branch's per-branch re-check
# (step 1), which must then stop before writing a pin or a ledger row.
new_commit_on() { # <branch>: a commit on top of the branch's tip, referenced by nothing
  git -C "$REPO" commit-tree -p "refs/heads/$1" -m "moved $1" "refs/heads/$1^{tree}"
}
wait_for_ref() { # <ref>: poll (up to ~10s) until the ref exists
  local i
  for ((i = 0; i < 200; i++)); do
    git -C "$REPO" rev-parse --verify --quiet "$1" >/dev/null 2>&1 && return 0
    sleep 0.05
  done
  return 1
}
wait_pid() { # <pid>: reap it, killing it after ~30s so a regression cannot hang the suite
  local i
  for ((i = 0; i < 300; i++)); do
    kill -0 "$1" 2>/dev/null || break
    sleep 0.1
  done
  kill -0 "$1" 2>/dev/null && kill "$1" 2>/dev/null
  wait "$1"
}
drain_fd3() { # whatever the script appended after the FIFO reader left
  local line
  while IFS= read -r -t 1 line <&3; do printf '%s\n' "$line"; done
}
pin_of() { git -C "$REPO" rev-parse --verify --quiet "refs/repo-hygiene/deleted/$1" || echo none; }

if command -v mkfifo >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
  # Window B: the tip moves between the pin and the delete.
  CAP_B="$(cd "$REPO" && bash "$AUDIT" --capture-file "$TEST_TMPDIR/race-b.tsv" | sed -n 's/^TipCapture: //p')"
  FIFO_B="$TEST_TMPDIR/race-b.deleted.tsv"
  mkfifo "$FIFO_B"
  winb_tip="$(git -C "$REPO" rev-parse refs/heads/feat/win-b)"
  (cd "$REPO" && exec bash "$DELETE" --capture "$CAP_B" --apply feat/win-b) >"$TEST_TMPDIR/race-b.out" 2>&1 &
  pid=$!
  if wait_for_ref refs/repo-hygiene/deleted/feat/win-b; then
    winb_moved="$(new_commit_on feat/win-b)"
    git -C "$REPO" update-ref refs/heads/feat/win-b "$winb_moved" "$winb_tip"
    timeout 30 cat "$FIFO_B" >"$TEST_TMPDIR/race-b.row" # releases the parked row write
    exec 3<>"$FIFO_B"                                   # later appends never block
    wait_pid "$pid"
    rc=$?
    ledger_b="$(cat "$TEST_TMPDIR/race-b.row" && drain_fd3)"
    exec 3<&-
    out="$(cat "$TEST_TMPDIR/race-b.out")"
    assert_exit "window B: tip moved between pin and delete exits 1" 1 "$rc"
    assert_contains "window B: the delete itself refuses the moved tip" "$out" "Aborted: feat/win-b (tip moved between pin and delete: captured $winb_tip, now $winb_moved"
    assert_not_contains "window B: nothing reported deleted" "$out" "Deleted:"
    assert_branch "window B: feat/win-b intact" present feat/win-b
    assert_eq "window B: feat/win-b still at the moved tip" "$winb_moved" "$(git -C "$REPO" rev-parse refs/heads/feat/win-b)"
    assert_eq "window B: pin records the captured tip" "$winb_tip" "$(pin_of feat/win-b)"
    assert_contains "window B: ledger notes the branch was not deleted" "$ledger_b" "# not deleted: feat/win-b (tip moved between pin and delete"
    git -C "$REPO" reflog expire --expire=now --all
    git -C "$REPO" gc -q --prune=now 2>/dev/null
    moved_state="pruned"
    if git -C "$REPO" cat-file -e "$winb_moved" 2>/dev/null; then moved_state="present"; fi
    assert_eq "window B: the moved commit survives gc --prune=now" "present" "$moved_state"
  else
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    fail "window B: script pins feat/win-b before opening the ledger" "pin present" "no pin within 10s: $(cat "$TEST_TMPDIR/race-b.out")"
  fi

  # Window A: the tip moves after the batch check and before the per-branch re-check.
  CAP_A="$(cd "$REPO" && bash "$AUDIT" --capture-file "$TEST_TMPDIR/race-a.tsv" | sed -n 's/^TipCapture: //p')"
  FIFO_A="$TEST_TMPDIR/race-a.deleted.tsv"
  mkfifo "$FIFO_A"
  wina1_tip="$(git -C "$REPO" rev-parse refs/heads/feat/win-a1)"
  wina2_tip="$(git -C "$REPO" rev-parse refs/heads/feat/win-a2)"
  (cd "$REPO" && exec bash "$DELETE" --capture "$CAP_A" --apply feat/win-a1 feat/win-a2) >"$TEST_TMPDIR/race-a.out" 2>&1 &
  pid=$!
  if wait_for_ref refs/repo-hygiene/deleted/feat/win-a1; then
    wina2_moved="$(new_commit_on feat/win-a2)"
    git -C "$REPO" update-ref refs/heads/feat/win-a2 "$wina2_moved" "$wina2_tip"
    timeout 30 cat "$FIFO_A" >"$TEST_TMPDIR/race-a.row"
    exec 3<>"$FIFO_A"
    wait_pid "$pid"
    rc=$?
    ledger_a="$(cat "$TEST_TMPDIR/race-a.row" && drain_fd3)"
    exec 3<&-
    out="$(cat "$TEST_TMPDIR/race-a.out")"
    assert_exit "window A: tip moved before the re-check exits 1" 1 "$rc"
    assert_contains "window A: the parked branch was deleted" "$out" "Deleted: feat/win-a1 $wina1_tip"
    assert_contains "window A: the re-check stops the moved branch before the pin" "$out" "Aborted: feat/win-a2 (tip moved between check and delete: captured $wina2_tip, now $wina2_moved"
    assert_contains "window A: summary" "$out" "deleted=1 failed=0 aborted=1 untouched=1"
    assert_branch "window A: feat/win-a2 intact" present feat/win-a2
    assert_eq "window A: feat/win-a2 still at the moved tip" "$wina2_moved" "$(git -C "$REPO" rev-parse refs/heads/feat/win-a2)"
    assert_eq "window A: no pin written for the moved branch" "none" "$(pin_of feat/win-a2)"
    assert_contains "window A: ledger row for the deleted branch" "$ledger_a" "feat/win-a1	$wina1_tip	"
    assert_not_contains "window A: no ledger row for the moved branch" "$ledger_a" "feat/win-a2	"
  else
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    fail "window A: script pins feat/win-a1 before opening the ledger" "pin present" "no pin within 10s: $(cat "$TEST_TMPDIR/race-a.out")"
  fi
else
  skip_case "tip-move window cases need mkfifo and timeout"
fi

if [[ $FAILED -ne 0 ]]; then
  echo "FAILED: $FAILED test(s)"
  exit 1
fi
echo "OK: git-branch-delete.sh tests passed"
