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

git init -b main "$TEST_TMPDIR/repo" >/dev/null 2>&1
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
  assert_contains "complete map reports its size" "$closed_out" "PRCount: 1"
  assert_not_contains "complete map is not flagged truncated" "$closed_out" "PRDataTruncated:"
  assert_not_contains "complete map is not flagged unavailable" "$closed_out" "PRDataUnavailable:"

  # --- PR map: truncation is detected and announced -----------------------------
  # The lookup is the ONLY mechanism that sees a squash merge, so a short map
  # does not soften a verdict, it inverts it: a landed branch reports as needing
  # review. `gh pr list` has no unlimited sentinel and rejects `--limit 0`, so
  # truncation can only be inferred from returned-count == requested-limit.
  # CLEAN_PR_LIST_LIMIT makes that boundary reachable without 100000 fixtures.
  trunc_out="$(PATH="$fake_bin:$PATH" CLEAN_PR_LIST_LIMIT=1 GIT_DIR="$TEST_TMPDIR/repo/.git" GIT_WORK_TREE="$TEST_TMPDIR/repo" bash -c "cd '$TEST_TMPDIR/repo' && bash '$AUDIT'")"
  assert_contains "truncated map is announced" "$trunc_out" "PRDataTruncated:"
  assert_contains "truncated map still reports its count" "$trunc_out" "PRCount: 1"

  # --- PR map: empty is NOT the same as unavailable -----------------------------
  empty_bin="$TEST_TMPDIR/empty-pr-bin"
  mkdir -p "$empty_bin"
  cat >"$empty_bin/gh" <<'EMPTYGH'
#!/usr/bin/env bash
case "$*" in
  *pr\ list*) printf '%s\n' '[]' ;;
  *) exit 1 ;;
esac
EMPTYGH
  chmod +x "$empty_bin/gh"
  empty_pr_out="$(PATH="$empty_bin:$PATH" GIT_DIR="$TEST_TMPDIR/repo/.git" GIT_WORK_TREE="$TEST_TMPDIR/repo" bash -c "cd '$TEST_TMPDIR/repo' && bash '$AUDIT'")"
  assert_contains "a repo with no PRs reports a real count" "$empty_pr_out" "PRCount: 0"
  assert_not_contains "a repo with no PRs is not called unavailable" "$empty_pr_out" "PRDataUnavailable:"

  # A `gh` that exits 0 with output that is not a PR array must not be counted.
  junk_bin="$TEST_TMPDIR/junk-pr-bin"
  mkdir -p "$junk_bin"
  cat >"$junk_bin/gh" <<'JUNKGH'
#!/usr/bin/env bash
case "$*" in
  *pr\ list*) printf '%s\n' 'not json at all' ;;
  *) exit 1 ;;
esac
JUNKGH
  chmod +x "$junk_bin/gh"
  junk_out="$(PATH="$junk_bin:$PATH" GIT_DIR="$TEST_TMPDIR/repo/.git" GIT_WORK_TREE="$TEST_TMPDIR/repo" bash -c "cd '$TEST_TMPDIR/repo' && bash '$AUDIT'")"
  assert_contains "unparsable gh output is unavailable" "$junk_out" "PRDataUnavailable:"
  assert_not_contains "unparsable gh output fabricates no count" "$junk_out" "PRCount:"

  # --- PR map: cannot create the outfile is unavailable, not a count ----------
  # A successful gh lookup used to emit PRCount even when the map file was never
  # created (ignored `: >"$outfile"`), so the audit looked complete while loading
  # no rows. Failure to create the file is the same class as a missing lookup.
  helper_out="$(
    PATH="$fake_bin:$PATH" bash -c '
      source "$1"
      clean_pr_map "$2" "headRefName,state,number,headRefOid"
    ' bash "$SCRIPT_DIR/lib/clean-common.sh" "$TEST_TMPDIR/no-such-dir/pr-map"
  )"
  assert_contains "helper: missing map file is unavailable" "$helper_out" "PRDataUnavailable:"
  assert_not_contains "helper: missing map file reports no count" "$helper_out" "PRCount:"

  # mktemp fails when TMPDIR is not a directory; both audits then fall back to
  # ${TMPDIR}/clean-pr-map.$$ in that same unusable directory. Capture stderr
  # so a missing-file redirect would show up as a regression.
  mapfail_out="$(
    PATH="$fake_bin:$PATH" TMPDIR="$TEST_TMPDIR/no-such-tmpdir" \
      GIT_DIR="$TEST_TMPDIR/repo/.git" GIT_WORK_TREE="$TEST_TMPDIR/repo" \
      bash -c "cd '$TEST_TMPDIR/repo' && bash '$AUDIT'" 2>&1
  )"
  assert_contains "unwritable TMPDIR is unavailable" "$mapfail_out" "PRDataUnavailable:"
  assert_not_contains "unwritable TMPDIR reports no count" "$mapfail_out" "PRCount:"
fi

# --- PR map: a failed lookup is distinguishable from an empty one ---------------
FAILGH_BIN="$TEST_TMPDIR/failgh-bin"
mkdir -p "$FAILGH_BIN"
printf '#!/usr/bin/env bash\nexit 1\n' >"$FAILGH_BIN/gh"
chmod +x "$FAILGH_BIN/gh"
failed_out="$(PATH="$FAILGH_BIN:$PATH" GIT_DIR="$TEST_TMPDIR/repo/.git" GIT_WORK_TREE="$TEST_TMPDIR/repo" bash -c "cd '$TEST_TMPDIR/repo' && bash '$AUDIT'")"
assert_contains "failed lookup says so" "$failed_out" "PRDataUnavailable:"
assert_not_contains "failed lookup reports no count" "$failed_out" "PRCount:"

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
git init -q -b main "$WT_REPO"
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
git init -q -b main "$NU_REPO"
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

# A branch whose upstream is GONE but that still carries commits not on
# origin/<default> is unmerged local work — it must be REVIEW, not the LIKELY-SAFE
# deletion candidate the bare `gone` check would assign (deleting it loses those
# commits).
git -C "$NU_REPO" checkout -q -b feat/gone
echo g >"$NU_REPO/g"
git -C "$NU_REPO" add g
git -C "$NU_REPO" commit -qm g
git -C "$NU_REPO" push -q -u origin feat/gone
echo g2 >>"$NU_REPO/g"
git -C "$NU_REPO" add g
git -C "$NU_REPO" commit -qm g2
git -C "$NU_REPO" push -q origin --delete feat/gone
git -C "$NU_REPO" fetch -q --prune origin
git -C "$NU_REPO" checkout -q main
gone_out="$(PATH="$STUB_BIN:$PATH" bash -c "cd '$NU_REPO' && bash '$AUDIT'")"
assert_contains "gone+unpushed is review not likely-safe" "$gone_out" "Reason: upstream gone, 2 commits not on origin/main"
assert_contains "gone+unpushed is LOSSY (deletable, loses work), never LIKELY-SAFE" "$gone_out" "Tier: LOSSY
Age days: 0
PR: none
Unpushed: no upstream, 2 commits not on origin/main
Loss: 2 commits only on this branch
Reason: upstream gone, 2 commits not on origin/main"

# Gone upstream with NO origin/<default> to compare against (feature-only clone /
# unfetched remote HEAD): the script cannot prove the branch is merged, so it must
# fail closed to REVIEW, not offer it as a deletable LIKELY-SAFE candidate.
GC_REPO="$TEST_TMPDIR/gc-repo"
git init -q --bare "$TEST_TMPDIR/gc-origin.git"
git init -q -b main "$GC_REPO"
git -C "$GC_REPO" config user.email "t@example.com"
git -C "$GC_REPO" config user.name "Test"
echo a >"$GC_REPO/a"
git -C "$GC_REPO" add a
git -C "$GC_REPO" commit -qm init
git -C "$GC_REPO" remote add origin "$TEST_TMPDIR/gc-origin.git"
git -C "$GC_REPO" checkout -q -b feat/gone-nocmp
echo g >"$GC_REPO/g"
git -C "$GC_REPO" add g
git -C "$GC_REPO" commit -qm g
git -C "$GC_REPO" push -q -u origin feat/gone-nocmp
git -C "$GC_REPO" push -q origin --delete feat/gone-nocmp
git -C "$GC_REPO" fetch -q --prune origin
git -C "$GC_REPO" checkout -q main
gc_out="$(PATH="$STUB_BIN:$PATH" bash -c "cd '$GC_REPO' && bash '$AUDIT'")"
assert_contains "gone + no default to compare fails closed to review" "$gc_out" "Reason: upstream gone, cannot compare against origin/main"
assert_not_contains "gone + no default is never likely-safe" "$gc_out" "Tier: LIKELY-SAFE"
# The same missing signal keeps the branch out of LOSSY too: a loss that cannot
# be measured is reported as undetermined, and the branch stays REVIEW.
assert_contains "gone + no default: loss undetermined, stays REVIEW" "$gc_out" "Tier: REVIEW
Age days: 0
PR: none
Unpushed: no upstream (no origin/main to compare)
Loss: undetermined (no origin/main to compare against)
Reason: upstream gone, cannot compare against origin/main"
assert_not_contains "gone + no default is never LOSSY" "$gc_out" "Tier: LOSSY"
assert_contains "gone + no default: empty loss block" "$gc_out" "LossBlock: 0 branches lose work if deleted
LossBlockEnd: 0"

# Tip capture: every branch carries its tip as a structured field, and the same
# facts land in a durable TSV under the common git dir whose path the audit
# prints. That file is what git-branch-delete.sh requires before any deletion.
rc=0
bash "$AUDIT" --bogus >/dev/null 2>&1 || rc=$?
assert_exit "unknown arg exits 2" 2 "$rc"

git -C "$NU_REPO" checkout -q -b feat/tracked
echo t1 >"$NU_REPO/t1"
git -C "$NU_REPO" add t1
git -C "$NU_REPO" commit -qm t1
echo t2 >"$NU_REPO/t2"
git -C "$NU_REPO" add t2
git -C "$NU_REPO" commit -qm t2
git -C "$NU_REPO" push -q -u origin feat/tracked
git -C "$NU_REPO" reset -q --hard HEAD~1
echo t3 >"$NU_REPO/t3"
git -C "$NU_REPO" add t3
git -C "$NU_REPO" commit -qm t3
git -C "$NU_REPO" checkout -q main
git -C "$NU_REPO" branch '#7-lead' # a legal name that starts like a comment line
tracked_tip="$(git -C "$NU_REPO" rev-parse refs/heads/feat/tracked)"
never_tip="$(git -C "$NU_REPO" rev-parse refs/heads/feat/never-pushed)"
lead_tip="$(git -C "$NU_REPO" rev-parse 'refs/heads/#7-lead')"
tip_out="$(PATH="$STUB_BIN:$PATH" bash -c "cd '$NU_REPO' && bash '$AUDIT'")"
assert_contains "Tip line follows Branch line" "$tip_out" "Branch: feat/never-pushed
Tip: $never_tip
Tier: LOSSY"
assert_contains "Tip line for the tracked branch" "$tip_out" "Tip: $tracked_tip"
assert_not_contains "no branch is left without a resolved tip" "$tip_out" "Tip: unresolved"
cap="$(printf '%s\n' "$tip_out" | sed -n 's/^TipCapture: //p')"
assert_file_exists "TipCapture path exists" "$cap"
assert_contains "capture is under <common-dir>/repo-hygiene/branch-tips/" "$cap" "$NU_REPO/.git/repo-hygiene/branch-tips/"
assert_file_absent "no .part left behind" "$cap.part"
cap_body="$(cat "$cap")"
assert_contains "capture header" "$cap_body" "# repo-hygiene branch tip capture v1"
assert_contains "capture names the restore command" "$cap_body" "# restore: git branch <branch> <tip>"
assert_contains "capture row: never-pushed (no upstream, 1 not on default) carries LOSSY" "$cap_body" "feat/never-pushed	$never_tip	LOSSY	none	none	-	-	1	"
assert_contains "capture row: tracked (ahead 1, behind 1) carries LOSSY" "$cap_body" "feat/tracked	$tracked_tip	LOSSY	none	origin/feat/tracked	1	1	"
assert_not_contains "a #-leading branch name does not fail the seal" "$tip_out" "TipCaptureError:"
assert_contains "capture row: #-leading branch is a row, not a comment" "$cap_body" "#7-lead	$lead_tip	"
# Rows are counted by shape (nine columns, a commit id second), as the seal does.
rows="$(awk -F'\t' 'NF == 9 && $2 ~ /^[0-9a-f]+$/ && length($2) >= 40 { n++ } END { print n + 0 }' "$cap")"
heads="$(git -C "$NU_REPO" for-each-ref refs/heads/ | wc -l | tr -d ' ')"
if [[ "$rows" == "$heads" ]]; then
  pass "capture has one row per local branch ($rows)"
else
  fail "capture has one row per local branch" "$heads" "$rows"
fi

# Explicit capture path honoured.
explicit_out="$(PATH="$STUB_BIN:$PATH" bash -c "cd '$NU_REPO' && bash '$AUDIT' --capture-file '$TEST_TMPDIR/explicit.tsv'")"
assert_contains "--capture-file path reported" "$explicit_out" "TipCapture: $TEST_TMPDIR/explicit.tsv"
assert_file_exists "--capture-file written" "$TEST_TMPDIR/explicit.tsv"

# Capture failure is reported as such, never as a path: a directory component
# that is a regular file cannot be created, so the audit has nowhere to write.
printf 'x\n' >"$TEST_TMPDIR/blocker"
err_rc=0
err_out="$(PATH="$STUB_BIN:$PATH" bash -c "cd '$NU_REPO' && bash '$AUDIT' --capture-file '$TEST_TMPDIR/blocker/cap.tsv'")" || err_rc=$?
assert_exit "capture failure keeps exit 0 (audit is read-only)" 0 "$err_rc"
assert_contains "capture failure reported" "$err_out" "TipCaptureError: cannot create $TEST_TMPDIR/blocker"
assert_not_contains "capture failure prints no TipCapture path" "$err_out" "TipCapture: "
assert_contains "capture failure still reports every tip" "$err_out" "Tip: $tracked_tip"

# A `.part` that already exists belongs to another run (a stamp-pid collision
# or an interrupted audit): it is refused and left alone, never appended to.
printf 'x\n' >"$TEST_TMPDIR/busy.tsv.part"
busy_out="$(PATH="$STUB_BIN:$PATH" bash -c "cd '$NU_REPO' && bash '$AUDIT' --capture-file '$TEST_TMPDIR/busy.tsv'")"
assert_contains "pre-existing .part is refused" "$busy_out" "TipCaptureError: refusing to reuse existing $TEST_TMPDIR/busy.tsv.part"
assert_not_contains "pre-existing .part yields no capture path" "$busy_out" "TipCapture: "
assert_file_absent "pre-existing .part: nothing sealed" "$TEST_TMPDIR/busy.tsv"
if [[ "$(cat "$TEST_TMPDIR/busy.tsv.part")" == "x" ]]; then
  pass "pre-existing .part left untouched"
else
  fail "pre-existing .part left untouched" "x" "$(cat "$TEST_TMPDIR/busy.tsv.part")"
fi

# ---- LOSSY: deletable, and deleting it loses work --------------------------------
# The classifier's boundary, stated as record-level rules over the output and
# checked mechanically on every audit output this suite produces:
#   - PROTECTED / WORKTREE / SAFE / LIKELY-SAFE always carry `Loss: not assessed`,
#     so a branch the chain deemed safe is never re-described as losing work
#     (a squash-merged SAFE branch has unreachable commits and must not be);
#   - LOSSY always carries a bare positive `Loss: N commits only on this branch`;
#   - REVIEW never carries a bare positive count: its loss is `none`,
#     `undetermined (...)`, or a count annotated with why it stays REVIEW;
#   - the loss block lists exactly the LOSSY records, and LossBlockEnd agrees.
check_loss_invariants() {
  local label="$1" out="$2" bad
  bad="$(printf '%s\n' "$out" | awk '
    /^Branch: / { branch = substr($0, 9); tier = ""; loss = "" }
    /^Tier: /   { tier = substr($0, 7) }
    /^Loss: /   { loss = substr($0, 7) }
    /^Reason: / {
      if (tier == "PROTECTED" || tier == "WORKTREE" || tier == "SAFE" || tier == "LIKELY-SAFE") {
        if (loss !~ /^not assessed \(/) print "tier " tier " with loss [" loss "] on " branch
      } else if (tier == "LOSSY") {
        if (loss !~ /^[1-9][0-9]* commits only on this branch$/) print "LOSSY with loss [" loss "] on " branch
        lossy[branch] = 1; nl++
      } else if (tier == "REVIEW") {
        if (loss ~ /^[1-9][0-9]* commits only on this branch$/) print "REVIEW with bare positive loss on " branch
        if (loss !~ /^(none \(|undetermined \(|[1-9][0-9]* commits only on this branch \()/) print "REVIEW with unexpected loss [" loss "] on " branch
      } else print "unknown tier [" tier "] on " branch
      records++
    }
    /^LossBranch: / { split(substr($0, 13), f, " "); if (!(f[1] in lossy)) print "LossBranch for non-LOSSY " f[1]; nb++ }
    /^LossBlockEnd: / { end = substr($0, 15); seen_end++ }
    END {
      if (records == 0) print "no branch records parsed"
      if (seen_end != 1) print "LossBlockEnd lines: " seen_end + 0
      if (nl + 0 != nb + 0) print "LOSSY records " nl + 0 " != LossBranch lines " nb + 0
      if (end + 0 != nl + 0) print "LossBlockEnd " end " != LOSSY records " nl + 0
    }
  ')"
  if [[ -z "$bad" ]]; then
    pass "$label: loss invariants hold"
  else
    fail "$label: loss invariants hold" "no violations" "$bad"
  fi
}
check_loss_invariants "single-branch repo" "$out"
check_loss_invariants "worktree repo" "$wt_out"
check_loss_invariants "no-upstream repo" "$nu_out"
check_loss_invariants "unfetched-upstream repo" "$uf_out"
check_loss_invariants "gone-upstream repo" "$gone_out"
check_loss_invariants "gone + no default repo" "$gc_out"
check_loss_invariants "tip-capture repo" "$tip_out"

# One branch per boundary case. main is pushed to a bare origin with origin/HEAD
# set, so "landed" is measurable everywhere in this repository.
LR="$TEST_TMPDIR/loss-repo"
git init -q --bare "$TEST_TMPDIR/loss-origin.git"
git init -q -b main "$LR"
git -C "$LR" config user.email "t@example.com"
git -C "$LR" config user.name "Test"
echo a >"$LR/a"
git -C "$LR" add a
git -C "$LR" commit -qm init
git -C "$LR" remote add origin "$TEST_TMPDIR/loss-origin.git"
git -C "$LR" push -q origin HEAD:main
git -C "$LR" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
lr_commit() { # <file> <message>: one commit on the checked-out branch
  echo "$1" >"$LR/$1"
  git -C "$LR" add "$1"
  git -C "$LR" commit -qm "$2"
}
# never pushed, two commits                                  -> LOSSY, both listed
git -C "$LR" checkout -q -b feat/never
lr_commit n1 "never one"
lr_commit n2 "never two"
git -C "$LR" checkout -q main
# pushed, two more commits, then deleted on origin: the remote copy is gone, so
# all three commits exist only here                            -> LOSSY (gone)
git -C "$LR" checkout -q -b feat/gone
lr_commit g1 "gone one"
git -C "$LR" push -q -u origin feat/gone
lr_commit g2 "gone two"
lr_commit g3 "gone three"
git -C "$LR" push -q origin --delete feat/gone
git -C "$LR" checkout -q main
# live upstream, one commit past it                            -> LOSSY (ahead)
git -C "$LR" checkout -q -b feat/ahead
lr_commit h1 "ahead pushed"
git -C "$LR" push -q -u origin feat/ahead
lr_commit h2 "ahead local"
git -C "$LR" checkout -q main
# live upstream, nothing local-only                            -> REVIEW, loss none
git -C "$LR" checkout -q -b feat/pushed
lr_commit p1 "pushed"
git -C "$LR" push -q -u origin feat/pushed
git -C "$LR" checkout -q main
# never pushed, but a tag pins the tip: a tag persists          -> REVIEW, loss none
git -C "$LR" checkout -q -b feat/tagged
lr_commit tg "tagged"
git -C "$LR" tag keep/tagged
git -C "$LR" checkout -q main
# never pushed under its own name, tip on origin under another  -> REVIEW, loss none
git -C "$LR" checkout -q -b feat/alias
lr_commit al "alias"
git -C "$LR" push -q origin feat/alias:refs/heads/other-name
git -C "$LR" checkout -q main
# stacked, both never pushed: a local sibling is not "elsewhere" -> both LOSSY
git -C "$LR" checkout -q -b feat/stack-base
lr_commit sb "stack base"
git -C "$LR" checkout -q -b feat/stack-top
lr_commit st "stack top"
git -C "$LR" checkout -q main
# twelve never-pushed commits: the listing is capped, the rest counted -> LOSSY
git -C "$LR" checkout -q -b feat/many
for ((i = 1; i <= 12; i++)); do
  lr_commit "m$i" "many $i"
done
git -C "$LR" checkout -q main
# merged by ancestry                                            -> SAFE, not assessed
git -C "$LR" checkout -q -b feat/merged
lr_commit mg "merged"
git -C "$LR" checkout -q main
git -C "$LR" merge -q --no-ff -m "merge feat/merged" feat/merged
git -C "$LR" push -q origin main
git -C "$LR" fetch -q --prune origin

lr_tip() { git -C "$LR" rev-parse "refs/heads/$1"; }
lr_short() { git -C "$LR" rev-parse --short "refs/heads/$1${2:-}"; }
lr_out="$(PATH="$STUB_BIN:$PATH" bash -c "cd '$LR' && bash '$AUDIT'")"
check_loss_invariants "loss repo" "$lr_out"
# assert_no_line <label> <haystack> <ERE>: no whole line matches. Used where a
# substring needle is ambiguous (a branch named `many` followed by a short SHA
# that happens to begin with `2` also contains "many 2").
assert_no_line() {
  local label="$1" haystack="$2" ere="$3" hits
  hits="$(printf '%s\n' "$haystack" | grep -c -E "$ere")"
  if [[ "$hits" == "0" ]]; then
    pass "$label"
  else
    fail "$label" "0 lines matching $ere" "$hits"
  fi
}

assert_contains "never pushed: LOSSY with the count and the chain's reason" "$lr_out" "Branch: feat/never
Tip: $(lr_tip feat/never)
Tier: LOSSY
Age days: 0
PR: none
Unpushed: no upstream, 2 commits not on origin/main
Loss: 2 commits only on this branch
Reason: no upstream, 2 commits not on origin/main"
assert_contains "upstream gone: LOSSY counting the commits whose remote copy is gone" "$lr_out" "Branch: feat/gone
Tip: $(lr_tip feat/gone)
Tier: LOSSY
Age days: 0
PR: none
Unpushed: no upstream, 3 commits not on origin/main
Loss: 3 commits only on this branch
Reason: upstream gone, 3 commits not on origin/main"
assert_contains "ahead of a live upstream: LOSSY counting only the unpushed commit" "$lr_out" "Branch: feat/ahead
Tip: $(lr_tip feat/ahead)
Tier: LOSSY
Age days: 0
PR: none
Unpushed: 1 ahead of origin/feat/ahead
Loss: 1 commits only on this branch
Reason: orphaned or needs review"
assert_contains "fully pushed: REVIEW, nothing lost" "$lr_out" "Branch: feat/pushed
Tip: $(lr_tip feat/pushed)
Tier: REVIEW
Age days: 0
PR: none
Unpushed: 0 ahead of origin/feat/pushed
Loss: none (every commit is on a remote ref or a tag)
Reason: orphaned or needs review"
assert_contains "tag-pinned: a tag is elsewhere, so REVIEW with nothing lost" "$lr_out" "Branch: feat/tagged
Tip: $(lr_tip feat/tagged)
Tier: REVIEW
Age days: 0
PR: none
Unpushed: no upstream, 1 commits not on origin/main
Loss: none (every commit is on a remote ref or a tag)
Reason: no upstream, 1 commits not on origin/main"
assert_contains "pushed under another name: a remote ref is elsewhere, so REVIEW" "$lr_out" "Branch: feat/alias
Tip: $(lr_tip feat/alias)
Tier: REVIEW
Age days: 0
PR: none
Unpushed: no upstream, 1 commits not on origin/main
Loss: none (every commit is on a remote ref or a tag)
Reason: no upstream, 1 commits not on origin/main"
assert_contains "stack base: LOSSY although a local sibling holds its commit" "$lr_out" "Branch: feat/stack-base
Tip: $(lr_tip feat/stack-base)
Tier: LOSSY
Age days: 0
PR: none
Unpushed: no upstream, 1 commits not on origin/main
Loss: 1 commits only on this branch"
assert_contains "stack top: LOSSY with both commits" "$lr_out" "Branch: feat/stack-top
Tip: $(lr_tip feat/stack-top)
Tier: LOSSY
Age days: 0
PR: none
Unpushed: no upstream, 2 commits not on origin/main
Loss: 2 commits only on this branch"
assert_contains "ancestry-merged: SAFE, loss not assessed" "$lr_out" "Branch: feat/merged
Tip: $(lr_tip feat/merged)
Tier: SAFE
Age days: 0
PR: none
Unpushed: no upstream, 0 commits not on origin/main
Loss: not assessed (SAFE)
Reason: merged (git ancestry)"
assert_contains "default branch: PROTECTED, loss not assessed" "$lr_out" "Tier: PROTECTED
Age days: 0
PR: none
Unpushed: no upstream, 0 commits not on origin/main
Loss: not assessed (PROTECTED)
Reason: current branch"
assert_contains "summary counts the lossy bucket" "$lr_out" "Summary: protected=1 worktree=0 safe=1 likely-safe=0 lossy=6 review=3"

# The block: its own surface, after the records, one LossBranch per LOSSY branch
# with the commits that would be lost (newest first, subjects included).
assert_contains "loss block header names the count and the separate decision" "$lr_out" "LossBlock: 6 branches lose work if deleted; confirm them as their own decision, never with the SAFE/LIKELY-SAFE set"
assert_contains "loss block: never-pushed branch with both commits" "$lr_out" "LossBranch: feat/never 2 commits only on this branch (no upstream, 2 commits not on origin/main) tip $(lr_tip feat/never)
LossCommit: feat/never $(lr_short feat/never) never two
LossCommit: feat/never $(lr_short feat/never ~1) never one"
assert_contains "loss block: gone branch with all three commits" "$lr_out" "LossBranch: feat/gone 3 commits only on this branch (upstream gone, 3 commits not on origin/main) tip $(lr_tip feat/gone)
LossCommit: feat/gone $(lr_short feat/gone) gone three
LossCommit: feat/gone $(lr_short feat/gone ~1) gone two
LossCommit: feat/gone $(lr_short feat/gone ~2) gone one"
assert_contains "loss block: ahead branch lists only the unpushed commit" "$lr_out" "LossBranch: feat/ahead 1 commits only on this branch (orphaned or needs review) tip $(lr_tip feat/ahead)
LossCommit: feat/ahead $(lr_short feat/ahead) ahead local
LossBranch: feat/gone"
assert_contains "loss block: capped listing counts the remainder" "$lr_out" "LossCommit: feat/many $(lr_short feat/many ~9) many 3
LossCommit: feat/many and 2 more
LossBranch: feat/never"
assert_no_line "loss block: the eleventh commit is not listed" "$lr_out" '^LossCommit: feat/many [0-9a-f]+ many 2$'
assert_no_line "loss block: the twelfth commit is not listed" "$lr_out" '^LossCommit: feat/many [0-9a-f]+ many 1$'
assert_not_contains "loss block never lists a REVIEW branch" "$lr_out" "LossBranch: feat/pushed"
assert_not_contains "loss block never lists a tag-pinned branch" "$lr_out" "LossBranch: feat/tagged"
assert_not_contains "loss block never lists a SAFE branch" "$lr_out" "LossBranch: feat/merged"
assert_contains "loss block end agrees with the header" "$lr_out" "LossBlockEnd: 6"
# The block sits after every branch record and before the capture line.
block_pos="$(printf '%s\n' "$lr_out" | grep -n '^LossBlock: ' | cut -d: -f1)"
last_record="$(printf '%s\n' "$lr_out" | grep -n '^Reason: ' | tail -n1 | cut -d: -f1)"
capture_pos="$(printf '%s\n' "$lr_out" | grep -n '^TipCapture: ' | cut -d: -f1)"
if [[ -n "$block_pos" && -n "$last_record" && -n "$capture_pos" && "$block_pos" -gt "$last_record" && "$block_pos" -lt "$capture_pos" ]]; then
  pass "loss block is printed after the records and before the capture line"
else
  fail "loss block is printed after the records and before the capture line" "records < block < capture" "record=$last_record block=$block_pos capture=$capture_pos"
fi
assert_contains "capture row carries LOSSY" "$(cat "$(printf '%s\n' "$lr_out" | sed -n 's/^TipCapture: //p')")" "feat/never	$(lr_tip feat/never)	LOSSY	none	none	-	-	2	"

cap3_out="$(PATH="$STUB_BIN:$PATH" CLEAN_LOSS_COMMITS_SHOWN=3 bash -c "cd '$LR' && bash '$AUDIT'")"
assert_contains "CLEAN_LOSS_COMMITS_SHOWN caps the listing" "$cap3_out" "LossCommit: feat/many $(lr_short feat/many ~2) many 10
LossCommit: feat/many and 9 more"
assert_no_line "CLEAN_LOSS_COMMITS_SHOWN: the fourth commit is not listed" "$cap3_out" '^LossCommit: feat/many [0-9a-f]+ many 9$'

# PR state as a competing signal. An OPEN PR is an active claim on the branch and
# a MERGED PR means the count overstates the loss (a squash lands the work under a
# new SHA); both stay REVIEW with the count still shown and annotated. A CLOSED PR
# is abandoned work and is LOSSY. A MERGED PR whose head is the local tip is SAFE
# with the loss deliberately not assessed, even though its commits are on no
# remote ref: the work landed.
if command -v jq >/dev/null 2>&1; then
  for b in feat/pr-open feat/pr-closed feat/pr-drift feat/pr-squashed; do
    git -C "$LR" checkout -q -b "$b"
    lr_commit "${b#feat/}-1" "${b#feat/} one"
    [[ "$b" == feat/pr-drift ]] && lr_commit "${b#feat/}-2" "${b#feat/} two"
    git -C "$LR" checkout -q main
  done
  pr_bin="$TEST_TMPDIR/pr-state-bin"
  mkdir -p "$pr_bin"
  printf '[{"headRefName":"feat/pr-open","state":"OPEN","number":1,"headRefOid":"%s"},{"headRefName":"feat/pr-closed","state":"CLOSED","number":2,"headRefOid":"%s"},{"headRefName":"feat/pr-drift","state":"MERGED","number":3,"headRefOid":"%s"},{"headRefName":"feat/pr-squashed","state":"MERGED","number":4,"headRefOid":"%s"}]\n' \
    "$(lr_tip feat/pr-open)" "$(lr_tip feat/pr-closed)" "$(git -C "$LR" rev-parse refs/heads/feat/pr-drift~1)" "$(lr_tip feat/pr-squashed)" >"$pr_bin/prs.json"
  cat >"$pr_bin/gh" <<FAKEGH
#!/usr/bin/env bash
case "\$*" in
  *pr\ list*) cat "$pr_bin/prs.json" ;;
  *) exit 1 ;;
esac
FAKEGH
  chmod +x "$pr_bin/gh"
  pr_out="$(PATH="$pr_bin:$PATH" bash -c "cd '$LR' && bash '$AUDIT'")"
  check_loss_invariants "PR-state repo" "$pr_out"
  assert_contains "OPEN PR: stays REVIEW, count shown and annotated" "$pr_out" "Branch: feat/pr-open
Tip: $(lr_tip feat/pr-open)
Tier: REVIEW
Age days: 0
PR: #1 OPEN
Unpushed: no upstream, 1 commits not on origin/main
Loss: 1 commits only on this branch (PR open, stays REVIEW)
Reason: no upstream, 1 commits not on origin/main"
  assert_contains "CLOSED PR: LOSSY" "$pr_out" "Branch: feat/pr-closed
Tip: $(lr_tip feat/pr-closed)
Tier: LOSSY
Age days: 0
PR: #2 CLOSED
Unpushed: no upstream, 1 commits not on origin/main
Loss: 1 commits only on this branch
Reason: PR closed without merge"
  assert_contains "MERGED PR with tip drift: stays REVIEW, count annotated as unreliable" "$pr_out" "Branch: feat/pr-drift
Tip: $(lr_tip feat/pr-drift)
Tier: REVIEW
Age days: 0
PR: #3 MERGED (tip drift)
Unpushed: no upstream, 2 commits not on origin/main
Loss: 2 commits only on this branch (PR merged; count unreliable after a squash, stays REVIEW)
Reason: PR merged but branch has commits since merge"
  assert_contains "MERGED PR at the tip: SAFE, loss not assessed despite unreachable commits" "$pr_out" "Branch: feat/pr-squashed
Tip: $(lr_tip feat/pr-squashed)
Tier: SAFE
Age days: 0
PR: #4 MERGED
Unpushed: no upstream, 1 commits not on origin/main
Loss: not assessed (SAFE)
Reason: PR merged"
  assert_contains "loss block lists the CLOSED-PR branch" "$pr_out" "LossBranch: feat/pr-closed 1 commits only on this branch (PR closed without merge) tip $(lr_tip feat/pr-closed)"
  assert_not_contains "loss block omits the OPEN-PR branch" "$pr_out" "LossBranch: feat/pr-open"
  assert_not_contains "loss block omits the drifted MERGED-PR branch" "$pr_out" "LossBranch: feat/pr-drift"
  assert_not_contains "loss block omits the squash-merged SAFE branch" "$pr_out" "LossBranch: feat/pr-squashed"
  assert_contains "summary with PR states" "$pr_out" "Summary: protected=1 worktree=0 safe=2 likely-safe=0 lossy=7 review=5"
else
  skip_case "PR-state cases need jq"
fi

# Missing signals resolve to REVIEW with the loss undetermined, never to LOSSY
# and never to SAFE. Three distinct absences:
#   1. no origin/<default> at all (a repository with no remote),
#   2. the count itself fails (git cannot answer),
#   3. upstream gone with no origin/<default> (asserted on GC_REPO above).
NR="$TEST_TMPDIR/no-remote"
git init -q -b main "$NR"
git -C "$NR" config user.email "t@example.com"
git -C "$NR" config user.name "Test"
echo a >"$NR/a"
git -C "$NR" add a
git -C "$NR" commit -qm init
git -C "$NR" checkout -q -b feat/local-only
echo b >"$NR/b"
git -C "$NR" add b
git -C "$NR" commit -qm b
git -C "$NR" checkout -q main
nr_out="$(PATH="$STUB_BIN:$PATH" bash -c "cd '$NR' && bash '$AUDIT'")"
check_loss_invariants "no-remote repo" "$nr_out"
assert_contains "no remote: loss undetermined, stays REVIEW" "$nr_out" "Branch: feat/local-only
Tip: $(git -C "$NR" rev-parse refs/heads/feat/local-only)
Tier: REVIEW
Age days: 0
PR: none
Unpushed: no upstream (no origin/main to compare)
Loss: undetermined (no origin/main to compare against)
Reason: orphaned or needs review"
assert_not_contains "no remote: never LOSSY" "$nr_out" "Tier: LOSSY"
assert_not_contains "no remote: never SAFE" "$nr_out" "Tier: SAFE"
assert_contains "no remote: empty loss block" "$nr_out" "LossBlock: 0 branches lose work if deleted
LossBlockEnd: 0"

# A git that cannot count: a wrapper that fails exactly the `--remotes` form the
# loss count uses and passes everything else through. Every branch that was
# LOSSY above must fall back to REVIEW with the failure named; SAFE and
# PROTECTED verdicts are untouched.
REAL_GIT="$(command -v git)"
BROKEN_BIN="$TEST_TMPDIR/broken-git-bin"
mkdir -p "$BROKEN_BIN"
cat >"$BROKEN_BIN/git" <<BROKENGIT
#!/usr/bin/env bash
for a in "\$@"; do [[ "\$a" == "--remotes" ]] && exit 128; done
exec "$REAL_GIT" "\$@"
BROKENGIT
chmod +x "$BROKEN_BIN/git"
printf '#!/usr/bin/env bash\nexit 1\n' >"$BROKEN_BIN/gh"
chmod +x "$BROKEN_BIN/gh"
broken_out="$(PATH="$BROKEN_BIN:$PATH" bash -c "cd '$LR' && bash '$AUDIT'")"
check_loss_invariants "count-failure repo" "$broken_out"
assert_contains "count failure: never-pushed branch stays REVIEW with the failure named" "$broken_out" "Branch: feat/never
Tip: $(lr_tip feat/never)
Tier: REVIEW
Age days: 0
PR: none
Unpushed: no upstream, 2 commits not on origin/main
Loss: undetermined (could not count commits absent from every remote ref and tag)
Reason: no upstream, 2 commits not on origin/main"
assert_not_contains "count failure: nothing is LOSSY" "$broken_out" "Tier: LOSSY"
assert_contains "count failure: SAFE and PROTECTED are untouched, everything else is REVIEW" "$broken_out" "Summary: protected=1 worktree=0 safe=1 likely-safe=0 lossy=0 review="
assert_contains "count failure: empty loss block" "$broken_out" "LossBlock: 0 branches lose work if deleted
LossBlockEnd: 0"

if [[ $FAILED -ne 0 ]]; then
  echo "FAILED: $FAILED test(s)"
  exit 1
fi
echo "OK: git-branch-audit.sh tests passed"
