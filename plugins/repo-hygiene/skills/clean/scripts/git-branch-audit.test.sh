#!/usr/bin/env bash
# Tests for git-branch-audit.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"

AUDIT="$SCRIPT_DIR/git-branch-audit.sh"
# The capture path the script reports comes from `clean_git_common_dir`, which
# ends in `cd` plus `pwd -P`. The fixture root is resolved the same way so the
# two spellings of one directory are comparable: `mktemp -d` can hand back a
# path that is not the physical one (under MSYS `/tmp` is a mount of the
# Windows temp directory). Identity wherever the temp root is already physical.
TEST_TMPDIR="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
FAILED=0

rc=0
bash "$AUDIT" --help >/dev/null 2>&1 || rc=$?
assert_exit "--help exits 0" 0 "$rc"

# check_facts <label> <repo> <audit output>: the audit reads every branch's tip,
# upstream, ahead/behind counts, commits not on origin/main and loss count in
# bulk. For each branch the capture holds a row for, those must equal what one
# git call per branch prints: this is that per-branch read, taken from the repo
# as it stands, so call it straight after the audit run it checks. The default
# branch in every fixture is main.
check_facts() {
  local label="$1" repo="$2" out="$3" cap b tip up ahead behind nod at
  local w_tip w_up w_ahead w_behind w_nod n want bad="" rows=0 has_default=0
  cap="$(printf '%s\n' "$out" | sed -n 's/^TipCapture: //p')"
  if [[ ! -f "$cap" ]]; then
    fail "$label: per-branch facts need a capture" "a capture file" "none"
    return
  fi
  git -C "$repo" rev-parse --verify --quiet refs/remotes/origin/main >/dev/null 2>&1 && has_default=1
  while IFS=$'\t' read -r b tip _ _ up ahead behind nod at; do
    [[ "$tip" =~ ^[0-9a-f]{40,}$ && -n "$at" ]] || continue
    rows=$((rows + 1))
    w_tip="$(git -C "$repo" rev-parse --verify --quiet "refs/heads/$b")"
    if w_up="$(git -C "$repo" rev-parse --abbrev-ref "$b@{upstream}" 2>/dev/null)"; then
      w_ahead="$(git -C "$repo" rev-list --count "$b@{upstream}..refs/heads/$b" 2>/dev/null)"
      w_behind="$(git -C "$repo" rev-list --count "refs/heads/$b..$b@{upstream}" 2>/dev/null)"
    else
      w_up=none w_ahead=- w_behind=-
    fi
    w_nod=-
    ((has_default)) && w_nod="$(git -C "$repo" rev-list --count "origin/main..refs/heads/$b" 2>/dev/null)"
    want="$w_tip|$w_up|$w_ahead|$w_behind|$w_nod"
    [[ "$tip|$up|$ahead|$behind|$nod" == "$want" ]] || bad+="$b: capture $tip|$up|$ahead|$behind|$nod, per-branch $want"$'\n'
  done <"$cap"
  # Loss lines that carry a count (a bare positive one, or `none`) against the
  # per-branch `rev-list <branch> --not --remotes --tags`.
  while read -r b n; do
    want="$(git -C "$repo" rev-list --count "refs/heads/$b" --not --remotes --tags 2>/dev/null)"
    [[ "$n" == "$want" ]] || bad+="$b: loss $n, per-branch $want"$'\n'
  done < <(printf '%s\n' "$out" | awk '/^Branch: /{b=substr($0,9)} /^Loss: none \(/{print b, 0} /^Loss: [0-9]+ commits only on this branch/{print b, $2}')
  if [[ "$rows" -eq 0 ]]; then
    fail "$label: per-branch facts" "at least one capture row" "none"
  elif [[ -z "$bad" ]]; then
    pass "$label: bulk facts equal the per-branch reads ($rows branches)"
  else
    fail "$label: bulk facts equal the per-branch reads" "no difference" "$bad"
  fi
}

git init -b main "$TEST_TMPDIR/repo" >/dev/null 2>&1
git -C "$TEST_TMPDIR/repo" config user.email "t@example.com"
git -C "$TEST_TMPDIR/repo" config user.name "Test"
echo x >"$TEST_TMPDIR/repo/x"
git -C "$TEST_TMPDIR/repo" add x
git -C "$TEST_TMPDIR/repo" commit -m "init" >/dev/null

out="$(GIT_DIR="$TEST_TMPDIR/repo/.git" GIT_WORK_TREE="$TEST_TMPDIR/repo" bash -c "cd '$TEST_TMPDIR/repo' && bash '$AUDIT'")"
check_facts "base repo" "$TEST_TMPDIR/repo" "$out"
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
check_facts "worktree repo" "$WT_REPO" "$wt_out"
assert_contains "worktree branch own tier" "$wt_out" "Tier: WORKTREE"
assert_contains "worktree branch reason" "$wt_out" "clean up the worktree first"
assert_contains "summary counts worktree bucket" "$wt_out" "worktree=1"
wt_real="$(cd "$TEST_TMPDIR/wt-linked" && pwd -P)"
assert_contains "worktree branch reports its linked worktree path" "$wt_out" "Worktree: $wt_real"
assert_not_contains "only WORKTREE branches carry a Worktree line" "$(printf '%s\n' "$wt_out" | awk '/^Tier: /{t=$2} /^Worktree: /&&t!="WORKTREE"{print}')" "Worktree:"

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
check_facts "no-upstream repo" "$NU_REPO" "$nu_out"
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
check_facts "unfetched-upstream repo" "$NU_REPO" "$uf_out"
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
check_facts "gone-upstream repo" "$NU_REPO" "$gone_out"
assert_contains "gone+unpushed is review not likely-safe" "$gone_out" "Reason: upstream gone, 2 commits not on origin/main"
assert_contains "gone+unpushed is LOSSY (deletable, loses work), never LIKELY-SAFE" "$gone_out" "Tier: LOSSY
Age days: 0
PR: none
Unpushed: no upstream, 2 commits not on origin/main
Loss: 2 commits only on this branch
Reason: upstream gone, 2 commits not on origin/main"
assert_contains "MainCheckout names the branch" "$gone_out" "MainCheckout: main"
assert_contains "MainCheckout reports the dirty count" "$gone_out" "MainCheckoutDirty: 0"
assert_not_contains "no operation, no OperationInProgress line" "$gone_out" "OperationInProgress:"

# An operation in progress demotes every deletable tier to REVIEW and names the file.
op_file="$(git -C "$NU_REPO" rev-parse --path-format=absolute --git-path MERGE_HEAD)"
git -C "$NU_REPO" rev-parse HEAD >"$op_file"
op_out="$(PATH="$STUB_BIN:$PATH" bash -c "cd '$NU_REPO' && bash '$AUDIT'")"
rm -f "$op_file"
assert_contains "operation in progress is announced" "$op_out" "OperationInProgress: $op_file"
assert_contains "operation is named in the MainCheckout block" "$op_out" "MainCheckoutOperation: MERGE_HEAD $op_file"
assert_contains "operation demotes LOSSY to REVIEW with the reason" "$op_out" "Reason: operation in progress: $op_file"
assert_not_contains "no LOSSY tier while an operation is in progress" "$op_out" "Tier: LOSSY"
assert_not_contains "no SAFE tier while an operation is in progress" "$op_out" "Tier: SAFE"
assert_not_contains "no LIKELY-SAFE tier while an operation is in progress" "$op_out" "Tier: LIKELY-SAFE"

# Detached HEAD is reported and does not block.
git -C "$NU_REPO" checkout -q --detach
det_out="$(PATH="$STUB_BIN:$PATH" bash -c "cd '$NU_REPO' && bash '$AUDIT'")"
git -C "$NU_REPO" checkout -q main
assert_contains "detached HEAD is reported" "$det_out" "MainCheckout: detached at "
assert_not_contains "detached HEAD is not an operation" "$det_out" "OperationInProgress:"

# A real conflicted merge writes MERGE_HEAD itself; the conflicted and untracked
# files count toward the dirty total.
CM="$TEST_TMPDIR/cm-repo"
git init -q -b main "$CM"
git -C "$CM" config user.email "t@example.com"
git -C "$CM" config user.name "Test"
echo base >"$CM/f"
git -C "$CM" add f
git -C "$CM" commit -qm base
git -C "$CM" branch feat/conflict
echo main-side >"$CM/f"
git -C "$CM" commit -qam main-side
git -C "$CM" checkout -q feat/conflict
echo feat-side >"$CM/f"
git -C "$CM" commit -qam feat-side
git -C "$CM" checkout -q main
git -C "$CM" merge feat/conflict >/dev/null 2>&1 || true
echo scratch >"$CM/untracked"
mkdir "$CM/newdir"
echo a >"$CM/newdir/a"
echo b >"$CM/newdir/b"
cm_out="$(PATH="$STUB_BIN:$PATH" bash -c "cd '$CM' && bash '$AUDIT'")"
check_facts "conflicted-merge repo" "$CM" "$cm_out"
assert_contains "conflicted merge is named in the MainCheckout block" "$cm_out" "MainCheckoutOperation: MERGE_HEAD "
assert_contains "dirty count covers the conflicted file, an untracked file and each file in an untracked directory" "$cm_out" "MainCheckoutDirty: 4"
assert_not_contains "no SAFE tier mid-merge" "$cm_out" "Tier: SAFE"
assert_not_contains "no LIKELY-SAFE tier mid-merge" "$cm_out" "Tier: LIKELY-SAFE"
assert_not_contains "no LOSSY tier mid-merge" "$cm_out" "Tier: LOSSY"

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
check_facts "gone + no default repo" "$GC_REPO" "$gc_out"
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
check_facts "tip-capture repo" "$NU_REPO" "$tip_out"
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
# Rows are counted by shape (ten columns, a commit id second), as the seal does.
rows="$(awk -F'\t' 'NF == 10 && $2 ~ /^[0-9a-f]+$/ && length($2) >= 40 { n++ } END { print n + 0 }' "$cap")"
heads="$(git -C "$NU_REPO" for-each-ref refs/heads/ | wc -l | tr -d ' ')"
if [[ "$rows" == "$heads" ]]; then
  pass "capture has one row per local branch ($rows)"
else
  fail "capture has one row per local branch" "$heads" "$rows"
fi

# Explicit capture path honored.
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
git -C "$LR" tag --no-sign keep/tagged
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
check_facts "loss repo" "$LR" "$lr_out"
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

# Landed proof. Work that origin/main already holds under other SHAs, with no PR
# data to say so: a rebase or cherry-pick merge is found by patch-id, a squash by
# the patch-id of the branch's whole diff. Either is LIKELY-SAFE with a Landed
# line and never LOSSY. Work only partly on main, an empty branch, and a landed
# branch whose PR is OPEN keep their verdicts.
LP="$TEST_TMPDIR/landed-repo"
git init -q --bare "$TEST_TMPDIR/landed-origin.git"
git init -q -b main "$LP"
git -C "$LP" config user.email "t@example.com"
git -C "$LP" config user.name "Test"
lp_commit() { # <file> <message>
  echo "$1" >"$LP/$1"
  git -C "$LP" add "$1"
  git -C "$LP" commit -qm "$2"
}
lp_commit a init
git -C "$LP" remote add origin "$TEST_TMPDIR/landed-origin.git"
git -C "$LP" push -q origin HEAD:main
git -C "$LP" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
for b in rebased squashed partial empty open; do
  git -C "$LP" checkout -q -b "feat/$b" main
  case "$b" in
  rebased) lp_commit r1 "rebased one" ;;
  squashed)
    lp_commit s1 "squashed one"
    lp_commit s2 "squashed two"
    ;;
  partial)
    lp_commit p1 "partial one"
    lp_commit p2 "partial two"
    ;;
  empty) git -C "$LP" commit -q --allow-empty -m "empty marker" ;;
  open) lp_commit o1 "open one" ;;
  *) ;;
  esac
  git -C "$LP" checkout -q main
done
lp_commit m1 "main moves on"
git -C "$LP" cherry-pick feat/rebased >/dev/null
git -C "$LP" merge -q --squash feat/squashed
git -C "$LP" commit -qm "squash feat/squashed"
git -C "$LP" cherry-pick feat/partial~1 >/dev/null
git -C "$LP" cherry-pick feat/open >/dev/null
git -C "$LP" commit -q --allow-empty -m "empty marker"
git -C "$LP" push -q origin main
git -C "$LP" fetch -q --prune origin
lp_tip() { git -C "$LP" rev-parse "refs/heads/$1"; }
lp_refs_before="$(git -C "$LP" for-each-ref | wc -l | tr -d ' ')"
# --read-only writes nothing under the git dir, objects included: the squash step's
# commit-tree runs in a throwaway object directory. A copy of the fixture that no
# audit has touched, because a second run would find the same synthetic commit
# already stored and write nothing, and the probe is checked against a normal run.
LPRO="$TEST_TMPDIR/landed-ro"
cp -a "$LP" "$LPRO"
ro_mark="$TEST_TMPDIR/ro-mark"
: >"$ro_mark"
lpro_out="$(PATH="$STUB_BIN:$PATH" bash -c "cd '$LPRO' && bash '$AUDIT' --read-only")"
assert_contains "--read-only: a squash-merged branch is still LIKELY-SAFE with its proof" "$lpro_out" "Landed: landed as a squash (tree patch-id)"
ro_touched="$(find "$LPRO/.git" -newer "$ro_mark")"
if [[ -z "$ro_touched" ]]; then pass "--read-only writes nothing under the git dir (no object, no file, no index refresh)"; else fail "--read-only writes nothing under the git dir" none "$ro_touched"; fi
PATH="$STUB_BIN:$PATH" bash -c "cd '$LPRO' && bash '$AUDIT'" >/dev/null
if [[ -n "$(find "$LPRO/.git/objects" -type f -newer "$ro_mark")" ]]; then pass "a normal audit writes objects there (the read-only probe can see a write)"; else fail "a normal audit writes objects there" "a new object" none; fi
# Without a throwaway directory (mktemp fails) the whole landed proof is skipped.
lpro_nt="$(TMPDIR="$TEST_TMPDIR/no-such-dir" PATH="$STUB_BIN:$PATH" bash -c "cd '$LPRO' && bash '$AUDIT' --read-only")"
assert_not_contains "--read-only without a throwaway directory gives no landed proof" "$lpro_nt" "Landed:"
assert_contains "--read-only without a throwaway directory still audits the branches" "$lpro_nt" "Branch: feat/squashed"
lp_out="$(PATH="$STUB_BIN:$PATH" bash -c "cd '$LP' && bash '$AUDIT'")"
check_facts "landed repo" "$LP" "$lp_out"
check_loss_invariants "landed repo" "$lp_out"
assert_contains "cherry-picked branch: LIKELY-SAFE by patch-id, loss not assessed" "$lp_out" "Branch: feat/rebased
Tip: $(lp_tip feat/rebased)
Tier: LIKELY-SAFE
Age days: 0
PR: none
Unpushed: no upstream, 1 commits not on origin/main
Loss: not assessed (LIKELY-SAFE)
Reason: landed by patch-id (git cherry)
Landed: landed by patch-id (git cherry)"
assert_contains "squash-merged branch: LIKELY-SAFE by tree patch-id" "$lp_out" "Branch: feat/squashed
Tip: $(lp_tip feat/squashed)
Tier: LIKELY-SAFE
Age days: 0
PR: none
Unpushed: no upstream, 2 commits not on origin/main
Loss: not assessed (LIKELY-SAFE)
Reason: landed as a squash (tree patch-id)
Landed: landed as a squash (tree patch-id)"
assert_contains "half-landed branch: still LOSSY, no Landed line" "$lp_out" "Branch: feat/partial
Tip: $(lp_tip feat/partial)
Tier: LOSSY
Age days: 0
PR: none
Unpushed: no upstream, 2 commits not on origin/main
Loss: 2 commits only on this branch
Reason: no upstream, 2 commits not on origin/main"
assert_contains "branch with no net change proves nothing: still LOSSY" "$lp_out" "Branch: feat/empty
Tip: $(lp_tip feat/empty)
Tier: LOSSY"
assert_contains "only the half-landed and empty branches are in the loss block" "$lp_out" "LossBlockEnd: 2"
assert_not_contains "no LossBranch for a landed branch" "$lp_out" "LossBranch: feat/rebased"
assert_not_contains "no LossBranch for a squashed branch" "$lp_out" "LossBranch: feat/squashed"
assert_contains "summary counts the landed branches as likely-safe" "$lp_out" "likely-safe=3"
assert_no_line "only landed branches carry a Landed line" "$(printf '%s\n' "$lp_out" | awk '/^Tier: /{t=$2} /^Landed: /&&t!="LIKELY-SAFE"{print}')" '.'
lp_refs_after="$(git -C "$LP" for-each-ref | wc -l | tr -d ' ')"
if [[ "$lp_refs_before" == "$lp_refs_after" ]]; then
  pass "landed proof creates no ref"
else
  fail "landed proof creates no ref" "$lp_refs_before refs" "$lp_refs_after"
fi
if command -v jq >/dev/null 2>&1; then
  lp_bin="$TEST_TMPDIR/landed-pr-bin"
  mkdir -p "$lp_bin"
  printf '[{"headRefName":"feat/open","state":"OPEN","number":9,"headRefOid":"%s"}]\n' "$(lp_tip feat/open)" >"$lp_bin/prs.json"
  cat >"$lp_bin/gh" <<FAKEGH
#!/usr/bin/env bash
case "\$*" in
  *pr\ list*) cat "$lp_bin/prs.json" ;;
  *) exit 1 ;;
esac
FAKEGH
  chmod +x "$lp_bin/gh"
  lp_pr_out="$(PATH="$lp_bin:$PATH" bash -c "cd '$LP' && bash '$AUDIT'")"
  assert_contains "landed branch with an OPEN PR keeps its verdict" "$lp_pr_out" "Branch: feat/open
Tip: $(lp_tip feat/open)
Tier: REVIEW"
  assert_not_contains "an OPEN PR gets no Landed line" "$(printf '%s\n' "$lp_pr_out" | awk '/^Branch: feat\/open$/{p=1} p{print} /^Reason: /{if(p)exit}')" "Landed:"
else
  skip_case "landed proof against an OPEN PR needs jq"
fi

# The proof is recorded in the capture's landed column (`-` on every branch that
# is not landed), and dropped with the tier when an operation in progress demotes
# the branch.
tsv() { local IFS=$'\t' && printf '%s\t' "$*"; }
capture_of() { cat "$(printf '%s\n' "$1" | sed -n 's/^TipCapture: //p')"; }
lp_cap="$(capture_of "$lp_out")"
assert_contains "capture row: a cherry-picked branch records its proof" "$lp_cap" "$(tsv feat/rebased "$(lp_tip feat/rebased)" LIKELY-SAFE none none - - 1 'landed by patch-id (git cherry)')"
assert_contains "capture row: a squashed branch records its proof" "$lp_cap" "$(tsv feat/squashed "$(lp_tip feat/squashed)" LIKELY-SAFE none none - - 2 'landed as a squash (tree patch-id)')"
assert_contains "capture row: an unlanded branch records none" "$lp_cap" "$(tsv feat/partial "$(lp_tip feat/partial)" LOSSY none none - - 2 -)"
lp_op="$(git -C "$LP" rev-parse --path-format=absolute --git-path MERGE_HEAD)"
git -C "$LP" rev-parse HEAD >"$lp_op"
lp_op_out="$(PATH="$STUB_BIN:$PATH" bash -c "cd '$LP' && bash '$AUDIT'")"
rm -f "$lp_op"
assert_not_contains "an operation in progress drops the Landed line with the tier" "$lp_op_out" "Landed:"
assert_contains "an operation in progress records no proof" "$(capture_of "$lp_op_out")" "$(tsv feat/rebased "$(lp_tip feat/rebased)" REVIEW none none - - 1 -)"

# Tree equality. Work that landed as commits split differently from the branch's,
# with nothing since on origin/main: no commit's patch-id matches and the branch's
# whole diff matches no single commit, yet the branch's tree is main's tree.
TE="$TEST_TMPDIR/tree-repo"
git init -q --bare "$TEST_TMPDIR/tree-origin.git"
git init -q -b main "$TE"
git -C "$TE" config user.email "t@example.com"
git -C "$TE" config user.name "Test"
te_commit() { # <message> <file>...
  local msg="$1" f
  shift
  for f in "$@"; do echo "$f" >"$TE/$f"; done
  git -C "$TE" add "$@"
  git -C "$TE" commit -qm "$msg"
}
te_commit init a
git -C "$TE" remote add origin "$TEST_TMPDIR/tree-origin.git"
git -C "$TE" push -q origin HEAD:main
git -C "$TE" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
git -C "$TE" checkout -q -b feat/split main
te_commit "branch one" p q
te_commit "branch two" r
git -C "$TE" checkout -q main
te_commit "main one" p
te_commit "main two" q r
git -C "$TE" push -q origin main
git -C "$TE" fetch -q --prune origin
assert_no_line "tree fixture premise: git cherry finds no landed commit" "$(git -C "$TE" cherry origin/main feat/split)" '^-'
te_out="$(PATH="$STUB_BIN:$PATH" bash -c "cd '$TE' && bash '$AUDIT'")"
check_facts "tree-equality repo" "$TE" "$te_out"
check_loss_invariants "tree-equality repo" "$te_out"
assert_contains "differently split commits, same final tree: LIKELY-SAFE by tree equality" "$te_out" "Branch: feat/split
Tip: $(git -C "$TE" rev-parse refs/heads/feat/split)
Tier: LIKELY-SAFE
Age days: 0
PR: none
Unpushed: no upstream, 2 commits not on origin/main
Loss: not assessed (LIKELY-SAFE)
Reason: landed as identical content (tree equals origin/main)
Landed: landed as identical content (tree equals origin/main)"
git -C "$TE" checkout -q feat/split
te_more="$(te_commit "branch three" s && git -C "$TE" rev-parse HEAD)"
git -C "$TE" checkout -q main
te_more_out="$(PATH="$STUB_BIN:$PATH" bash -c "cd '$TE' && bash '$AUDIT'")"
assert_contains "one more commit on the branch breaks the equality: LOSSY" "$te_more_out" "Branch: feat/split
Tip: $te_more
Tier: LOSSY"

# A merge commit is not listed by git cherry, so a branch whose merge carries
# content no commit on origin/main holds would read as fully landed by patch-id.
# A branch with a merge gets no cherry proof, and the whole-diff checks then find
# the extra content missing.
MG="$TEST_TMPDIR/merge-repo"
git init -q --bare "$TEST_TMPDIR/merge-origin.git"
git init -q -b main "$MG"
git -C "$MG" config user.email "t@example.com"
git -C "$MG" config user.name "Test"
mg_commit() { # <file> <message>
  echo "$1" >"$MG/$1"
  git -C "$MG" add "$1"
  git -C "$MG" commit -qm "$2"
}
mg_commit a init
git -C "$MG" remote add origin "$TEST_TMPDIR/merge-origin.git"
git -C "$MG" push -q origin HEAD:main
git -C "$MG" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
git -C "$MG" checkout -q -b side main
mg_commit s "side one"
git -C "$MG" checkout -q -b feat/evil main
mg_commit x "branch one"
git -C "$MG" merge -q --no-ff --no-commit side >/dev/null 2>&1
echo evil >"$MG/extra"
git -C "$MG" add extra
git -C "$MG" commit -qm "merge side with extra content"
git -C "$MG" checkout -q main
git -C "$MG" cherry-pick side feat/evil^1 >/dev/null
git -C "$MG" branch -q -D side
git -C "$MG" push -q origin main
git -C "$MG" fetch -q --prune origin
mg_cherry="$(git -C "$MG" cherry origin/main feat/evil)"
assert_no_line "merge fixture premise: git cherry calls every listed commit landed" "$mg_cherry" '^\+'
assert_contains "merge fixture premise: git cherry lists the branch's own commits" "$mg_cherry" "- "
mg_out="$(PATH="$STUB_BIN:$PATH" bash -c "cd '$MG' && bash '$AUDIT'")"
check_facts "merge-commit repo" "$MG" "$mg_out"
check_loss_invariants "merge-commit repo" "$mg_out"
assert_contains "a merge with unlanded content is not a landed proof: LOSSY" "$mg_out" "Branch: feat/evil
Tip: $(git -C "$MG" rev-parse refs/heads/feat/evil)
Tier: LOSSY"
assert_not_contains "a merge with unlanded content gets no Landed line" "$mg_out" "Landed:"

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
  check_facts "PR-state repo" "$LR" "$pr_out"
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
check_facts "no-remote repo" "$NR" "$nr_out"
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
check_facts "count-failure repo" "$LR" "$broken_out"
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

# --- bulk reads: a fixed number of git calls, the answers the per-branch calls give ---
# The audit reads the branch list, upstreams and ahead/behind counts in one
# for-each-ref, and the two counts for-each-ref cannot give (commits not on
# origin/<default>, and the loss count) in one ancestry pass each. A branch the
# bulk records cannot describe exactly, and any pass that fails, takes the
# per-branch commands, so a verdict never depends on which path answered. This
# section holds that to a fixture of 242 branches: the facts equal the
# per-branch reads (check_facts), the number of git calls does not grow with the
# branch count, and a failed pass gives the same output as a working one.
declare -A FX_MARK=()
FX_STREAM=""
FX_N=0
FX_CFG=""
FX_PRS=()
FX_TS=0

fx_commit() { # <name> <ts> [<parent-name>...]: a commit whose message is its name
  local name="$1" ts="$2" p
  shift 2
  FX_N=$((FX_N + 1))
  FX_MARK[$name]=$FX_N
  FX_STREAM+="commit refs/fixture/scratch"$'\n'"mark :$FX_N"$'\n'"committer T <t@example.com> $ts +0000"$'\n'"data ${#name}"$'\n'"$name"$'\n'
  if (($# > 0)); then
    FX_STREAM+="from :${FX_MARK[$1]}"$'\n'
    shift
    for p in "$@"; do FX_STREAM+="merge :${FX_MARK[$p]}"$'\n'; done
  fi
  FX_STREAM+=$'\n'
}
fx_ref() { # <full ref> <commit name>
  FX_STREAM+="reset $1"$'\n'"from :${FX_MARK[$2]}"$'\n\n'
}
fx_track() { # <branch> [remote] [merge ref]: configure the branch's upstream
  FX_CFG+="[branch \"$1\"]"$'\n\tremote = '"${2:-origin}"$'\n\tmerge = '"${3:-refs/heads/$1}"$'\n'
}
fx_pr() { # <branch> <state> <number> <commit name>: a PR whose head was that commit
  FX_PRS+=("$1 $2 $3 $4")
}
fx_now() { # a fresh commit time within the last hour
  FX_TS=$((FX_TS + 1))
  NOWTS=$((FX_NOW - 3600 + FX_TS))
}
fx_rnd() { # next value of a fixed-seed generator, so the random ancestry is the same on every run
  FX_SEED=$(((FX_SEED * 1103515245 + 12345) & 0x7fffffff))
  RND=$((FX_SEED >> 8))
}

# build_audit_fixture <dir> <percent>: <dir>/repo, a repository whose local
# branches span every tier and every way the audit reads one, and
# <dir>/prs.json, the gh stub's payload. <percent> scales the bulk classes: 100
# gives 242 branches. Every commit is built by one fast-import, so the size of the
# fixture costs no git calls.
build_audit_fixture() {
  local d="$1" pct="$2" r i k j n v s
  r="$d/repo"
  FX_MARK=() FX_STREAM="" FX_N=0 FX_CFG="" FX_PRS=() FX_TS=0 FX_SEED=20260929
  FX_NOW="$(date +%s)"
  git init -q -b main "$r"
  git -C "$r" config user.email "t@example.com"
  git -C "$r" config user.name "Test"
  git -C "$r" remote add origin "$d/nowhere.git"
  git -C "$r" remote add fork "$d/nowhere.git"

  # main: six commits, ten days old
  fx_commit main1 $((FX_NOW - 863000))
  for i in 2 3 4 5 6; do fx_commit "main$i" $((FX_NOW - 864000 + i * 3600)) "main$((i - 1))"; done
  fx_ref refs/heads/main main6
  fx_ref refs/remotes/origin/main main6

  # merged by ancestry; half of them have an upstream at the same tip
  n=$((50 * pct / 100))
  for ((i = 1; i <= n; i++)); do
    fx_ref "refs/heads/chore/merged-$i" "main$((i % 5 + 1))"
    if ((i % 2)); then
      fx_ref "refs/remotes/origin/chore/merged-$i" "main$((i % 5 + 1))"
      fx_track "chore/merged-$i"
    fi
  done
  # PR merged at the tip, work unpushed (SAFE by PR); PR merged with the tip moved on (REVIEW)
  n=$((20 * pct / 100))
  for ((i = 1; i <= n; i++)); do
    fx_now
    fx_commit "prm$i.a" "$NOWTS" main6
    fx_now
    fx_commit "prm$i.b" "$NOWTS" "prm$i.a"
    fx_ref "refs/heads/feat/pr-merged-$i" "prm$i.b"
    fx_pr "feat/pr-merged-$i" MERGED $((1000 + i)) "prm$i.b"
  done
  # (at least one of each at every scale, so both fixtures run the ancestor pass)
  n=$((5 * pct / 100))
  ((n > 0)) || n=1
  for ((i = 1; i <= n; i++)); do
    fx_now
    fx_commit "drift$i.a" "$NOWTS" main6
    fx_now
    fx_commit "drift$i.b" "$NOWTS" "drift$i.a"
    fx_ref "refs/heads/feat/drift-$i" "drift$i.b"
    fx_pr "feat/drift-$i" MERGED $((1100 + i)) "drift$i.a"
    fx_ref "refs/heads/feat/drift-ancestor-$i" "drift$i.a"
    fx_pr "feat/drift-ancestor-$i" MERGED $((1150 + i)) "drift$i.b"
  done
  # PR closed: unpushed (LOSSY) and pushed (REVIEW); PR open
  n=$((10 * pct / 100))
  for ((i = 1; i <= n; i++)); do
    fx_now
    fx_commit "closed$i" "$NOWTS" main6
    fx_ref "refs/heads/feat/closed-$i" "closed$i"
    fx_pr "feat/closed-$i" CLOSED $((1200 + i)) "closed$i"
  done
  n=$((3 * pct / 100))
  for ((i = 1; i <= n; i++)); do
    fx_now
    fx_commit "closedp$i" "$NOWTS" main6
    fx_ref "refs/heads/feat/closed-pushed-$i" "closedp$i"
    fx_ref "refs/remotes/origin/feat/closed-pushed-$i" "closedp$i"
    fx_track "feat/closed-pushed-$i"
    fx_pr "feat/closed-pushed-$i" CLOSED $((1300 + i)) "closedp$i"
  done
  n=$((5 * pct / 100))
  for ((i = 1; i <= n; i++)); do
    fx_now
    fx_commit "open$i" "$NOWTS" main6
    fx_ref "refs/heads/feat/open-$i" "open$i"
    fx_pr "feat/open-$i" OPEN $((1400 + i)) "open$i"
  done
  # upstream gone, commits unpushed
  n=$((10 * pct / 100))
  for ((i = 1; i <= n; i++)); do
    fx_now
    fx_commit "gone$i.a" "$NOWTS" main6
    fx_now
    fx_commit "gone$i.b" "$NOWTS" "gone$i.a"
    fx_ref "refs/heads/feat/gone-$i" "gone$i.b"
    fx_track "feat/gone-$i"
  done
  # never pushed; some pinned by a tag, some pushed under another name
  n=$((20 * pct / 100))
  for ((i = 1; i <= n; i++)); do
    fx_now
    fx_commit "local$i" "$NOWTS" main6
    fx_ref "refs/heads/wip/local-$i" "local$i"
    ((i % 5 == 0)) && fx_ref "refs/tags/keep-local-$i" "local$i"
    ((i % 7 == 0)) && fx_ref "refs/remotes/origin/elsewhere-$i" "local$i"
  done
  # stale (two hundred days), pushed
  n=$((10 * pct / 100))
  for ((i = 1; i <= n; i++)); do
    fx_commit "stale$i" $((FX_NOW - 17280000 - 7200 + i)) main1
    fx_ref "refs/heads/old/stale-$i" "stale$i"
    fx_ref "refs/remotes/origin/old/stale-$i" "stale$i"
    fx_track "old/stale-$i"
  done
  # pushed and level with the upstream
  n=$((30 * pct / 100))
  for ((i = 1; i <= n; i++)); do
    fx_now
    fx_commit "pushed$i" "$NOWTS" main6
    fx_ref "refs/heads/feat/pushed-$i" "pushed$i"
    fx_ref "refs/remotes/origin/feat/pushed-$i" "pushed$i"
    fx_track "feat/pushed-$i"
  done
  # ahead 2 and behind 1 of the upstream
  n=$((10 * pct / 100))
  for ((i = 1; i <= n; i++)); do
    fx_now
    fx_commit "div$i.base" "$NOWTS" main6
    fx_now
    fx_commit "div$i.a1" "$NOWTS" "div$i.base"
    fx_now
    fx_commit "div$i.a2" "$NOWTS" "div$i.a1"
    fx_now
    fx_commit "div$i.theirs" "$NOWTS" "div$i.base"
    fx_ref "refs/heads/feat/diverged-$i" "div$i.a2"
    fx_ref "refs/remotes/origin/feat/diverged-$i" "div$i.theirs"
    fx_track "feat/diverged-$i"
  done
  fx_now
  fx_commit behind.base "$NOWTS" main6
  fx_now
  fx_commit behind.theirs "$NOWTS" behind.base
  fx_ref refs/heads/feat/behind-only behind.base
  fx_ref refs/remotes/origin/feat/behind-only behind.theirs
  fx_track feat/behind-only
  fx_now
  fx_commit ahead.base "$NOWTS" main6
  fx_now
  fx_commit ahead.mine "$NOWTS" ahead.base
  fx_ref refs/heads/feat/ahead-only ahead.mine
  fx_ref refs/remotes/origin/feat/ahead-only ahead.base
  fx_track feat/ahead-only
  # eight worktrees (checked out after the import)
  for ((i = 1; i <= 8; i++)); do
    fx_now
    fx_commit "wt$i" "$NOWTS" main6
    fx_ref "refs/heads/feat/wt-$i" "wt$i"
  done
  # protected by pattern or name
  for s in release/1.0 release/2.0 hotfix/urgent develop; do
    fx_now
    fx_commit "prot-$s" "$NOWTS" main6
    fx_ref "refs/heads/$s" "prot-$s"
  done
  # odd names
  for s in '#7-lead' 'feat/dot.name' 'a/b/c/deep' 'feat/UPPER' 'feat/at@sign'; do
    fx_now
    fx_commit "odd-$s" "$NOWTS" main6
    fx_ref "refs/heads/$s" "odd-$s"
  done
  # a tag with the branch's name: its short name is `heads/<name>`
  for s in v1 v2 v3; do
    fx_now
    fx_commit "amb-$s" "$NOWTS" main6
    fx_ref "refs/heads/$s" "amb-$s"
    fx_ref "refs/tags/$s" "amb-$s"
  done
  fx_ref refs/remotes/origin/v2 amb-v2
  fx_track v2
  # upstream is a local branch, and a local branch of a local branch
  fx_now
  fx_commit localup "$NOWTS" main6
  fx_ref refs/heads/feat/local-upstream localup
  fx_track feat/local-upstream . refs/heads/main
  fx_now
  fx_commit localup2 "$NOWTS" main4
  fx_ref refs/heads/feat/local-upstream-2 localup2
  fx_track feat/local-upstream-2 . refs/heads/feat/local-upstream
  # stacked, never pushed
  for ((i = 1; i <= 2; i++)); do
    fx_now
    fx_commit "stack$i.base" "$NOWTS" main6
    fx_now
    fx_commit "stack$i.top" "$NOWTS" "stack$i.base"
    fx_ref "refs/heads/stack/base-$i" "stack$i.base"
    fx_ref "refs/heads/stack/top-$i" "stack$i.top"
  done
  # a merge, an octopus, and a criss-cross
  for ((i = 1; i <= 2; i++)); do
    fx_now
    fx_commit "mx$i" "$NOWTS" main6
    fx_now
    fx_commit "my$i" "$NOWTS" main6
    fx_now
    fx_commit "mz$i" "$NOWTS" main5
    fx_now
    fx_commit "merge$i" "$NOWTS" "mx$i" "my$i"
    fx_now
    fx_commit "octopus$i" "$NOWTS" "merge$i" "mz$i" main4
    fx_ref "refs/heads/topo/x-$i" "mx$i"
    fx_ref "refs/heads/topo/merge-$i" "merge$i"
    fx_ref "refs/heads/topo/octopus-$i" "octopus$i"
    fx_ref "refs/remotes/origin/topo/y-$i" "my$i"
  done
  fx_now
  fx_commit cx.a "$NOWTS" main6
  fx_now
  fx_commit cy.a "$NOWTS" main6
  fx_now
  fx_commit cx.m "$NOWTS" cx.a cy.a
  fx_now
  fx_commit cy.m "$NOWTS" cy.a cx.a
  fx_ref refs/heads/topo/crossx cx.m
  fx_ref refs/heads/topo/crossy cy.m
  # an upstream on a second remote
  for ((i = 1; i <= 3; i++)); do
    fx_now
    fx_commit "fork$i" "$NOWTS" main6
    fx_ref "refs/heads/feat/fork-$i" "fork$i"
    fx_ref "refs/remotes/fork/feat-$i" "fork$i"
    fx_track "feat/fork-$i" fork "refs/heads/feat-$i"
  done
  # tips equal to origin/main and to its first commit
  fx_ref refs/heads/at-main main6
  fx_ref refs/heads/at-root main1
  # a parent dated after its child
  fx_commit skew.parent $((FX_NOW - 100)) main6
  fx_commit skew.child $((FX_NOW - 5000)) skew.parent
  fx_ref refs/heads/skew/child skew.child
  fx_ref refs/heads/skew/parent-only skew.parent
  # a seeded random ancestry: 48 commits with one to three parents each, then
  # branches on random commits with a different upstream state each. Remote refs
  # and tags sit on early commits only, so most branches carry commits that no
  # remote ref and no tag reaches.
  fx_now
  fx_commit rd0 "$NOWTS" main3
  for ((i = 1; i < 48; i++)); do
    fx_rnd
    v=$((1 + RND % 3))
    ((v > i)) && v=$i
    s="rd$((i - 1))"
    for ((k = 1; k < v; k++)); do
      fx_rnd
      j="rd$((i - 1 - RND % (i > 8 ? 8 : i)))"
      [[ " $s " == *" $j "* ]] || s+=" $j"
    done
    fx_now
    # shellcheck disable=SC2086
    fx_commit "rd$i" "$NOWTS" $s
  done
  for ((k = 1; k <= 24; k++)); do
    fx_rnd
    j="rd$((RND % 48))"
    ((k % 8 == 0)) && j="rd$((RND % 16))"
    fx_ref "refs/heads/dag/b$k" "$j"
    case $((k % 8)) in
    0)
      fx_ref "refs/remotes/origin/dag/b$k" "$j"
      fx_track "dag/b$k"
      ;;
    1)
      fx_rnd
      fx_ref "refs/remotes/origin/dag/b$k" "rd$((RND % 16))"
      fx_track "dag/b$k"
      ;;
    2 | 7) fx_track "dag/b$k" ;;
    6)
      fx_rnd
      fx_ref "refs/tags/dag-$k" "rd$((RND % 16))"
      ;;
    *) ;;
    esac
  done
  # an upstream that exists but is no commit: the branch is not "gone"
  fx_commit nc.tip $((FX_NOW - 90)) main6
  fx_ref refs/heads/feat/nc nc.tip
  fx_track feat/nc

  printf '%s' "$FX_STREAM" | git -C "$r" fast-import --force --quiet --export-marks="$d/marks"
  git -C "$r" update-ref -d refs/fixture/scratch
  printf '%s' "$FX_CFG" >>"$r/.git/config"
  git -C "$r" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  git -C "$r" update-ref refs/remotes/origin/feat/nc "$(git -C "$r" hash-object -w --stdin <<<"blob")"
  for ((i = 1; i <= 8; i++)); do git -C "$r" worktree add -q "$d/wt-$i" "feat/wt-$i"; done
  git -C "$r" symbolic-ref HEAD refs/heads/feat/pushed-1

  # the gh stub's payload: each PR with the commit its head was
  local -A oid_of_mark=()
  local m o pr_json="" b st num cn
  while read -r m o; do oid_of_mark[${m#:}]=$o; done <"$d/marks"
  for v in "${FX_PRS[@]}"; do
    read -r b st num cn <<<"$v"
    pr_json+="${pr_json:+,}{\"headRefName\":\"$b\",\"state\":\"$st\",\"number\":$num,\"headRefOid\":\"${oid_of_mark[${FX_MARK[$cn]}]}\"}"
  done
  printf '[%s]\n' "$pr_json" >"$d/prs.json"
}

# A git shim that logs every call and, when SHIM_FAIL_ON is set, fails the calls
# whose arguments contain it; a gh stub that serves SHIM_PRS.
FIXTURES="$TEST_TMPDIR/audit-fixtures"
SPAWN_LOG="$TEST_TMPDIR/git-spawns.log"
export SPAWN_LOG
SHIM_BIN="$TEST_TMPDIR/shim-bin"
mkdir -p "$FIXTURES/big" "$FIXTURES/small" "$SHIM_BIN"
cat >"$SHIM_BIN/git" <<SHIMGIT
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"\$SPAWN_LOG"
if [[ -n "\${SHIM_FAIL_ON:-}" && " \$* " == *"\$SHIM_FAIL_ON"* ]]; then exit 128; fi
exec "$REAL_GIT" "\$@"
SHIMGIT
cat >"$SHIM_BIN/gh" <<'SHIMGH'
#!/usr/bin/env bash
case "$*" in *pr\ list*) cat "$SHIM_PRS" ;; *) exit 1 ;; esac
SHIMGH
chmod +x "$SHIM_BIN/git" "$SHIM_BIN/gh"
# run_audit_shimmed <fixture dir> <capture file>: the audit's stdout; the git calls it made are in SPAWN_LOG
run_audit_shimmed() {
  : >"$SPAWN_LOG"
  (cd "$1/repo" && PATH="$SHIM_BIN:$PATH" SHIM_PRS="$1/prs.json" bash "$AUDIT" --capture-file "$2")
}
spawn_count() { wc -l <"$SPAWN_LOG" | tr -d ' '; }
# audit_view <stdout> <capture file>: what the audit reported, less the capture's own path and timestamp
audit_view() {
  printf '%s\n' "$1" | sed 's|^TipCapture: .*|TipCapture: <path>|'
  grep -v '^# captured_at:' "$2" | cut -f1-8
}

build_audit_fixture "$FIXTURES/big" 100
build_audit_fixture "$FIXTURES/small" 10
big_heads="$(git -C "$FIXTURES/big/repo" for-each-ref refs/heads/ | wc -l | tr -d ' ')"
small_heads="$(git -C "$FIXTURES/small/repo" for-each-ref refs/heads/ | wc -l | tr -d ' ')"
if [[ "$big_heads" -ge 200 && $((big_heads - small_heads)) -ge 100 ]]; then
  pass "fixtures: $big_heads branches against $small_heads"
else
  fail "fixtures: at least 200 branches, and 100 more than the small one" "200+" "$big_heads and $small_heads"
fi

# The git calls the landed proof makes, counted per branch that reaches it.
PROOF_CALLS=' (merge-base|diff --quiet|rev-list --merges|rev-parse [^ ]*\^\{tree\}|cherry|commit-tree) '
big_out="$(run_audit_shimmed "$FIXTURES/big" "$FIXTURES/big.tsv")"
big_spawns="$(spawn_count)"
big_logs="$(grep -c ' log --format=' "$SPAWN_LOG")"
big_proof="$(grep -c -E "$PROOF_CALLS" "$SPAWN_LOG")"
big_mb="$(grep -c ' merge-base ' "$SPAWN_LOG")"
small_out="$(run_audit_shimmed "$FIXTURES/small" "$FIXTURES/small.tsv")"
small_spawns="$(spawn_count)"
small_logs="$(grep -c ' log --format=' "$SPAWN_LOG")"
small_proof="$(grep -c -E "$PROOF_CALLS" "$SPAWN_LOG")"
small_mb="$(grep -c ' merge-base ' "$SPAWN_LOG")"

check_loss_invariants "big fixture" "$big_out"
check_facts "big fixture" "$FIXTURES/big/repo" "$big_out"
check_facts "small fixture" "$FIXTURES/small/repo" "$small_out"
assert_not_contains "big fixture: the capture is sealed" "$big_out" "TipCaptureError:"
if command -v jq >/dev/null 2>&1; then
  # The tallies the per-branch implementation printed for this fixture: the
  # classification is unchanged, not merely internally consistent.
  assert_contains "big fixture: every tier, as classified before the bulk reads" "$big_out" "Summary: protected=6 worktree=8 safe=77 likely-safe=0 lossy=83 review=73"
  assert_contains "big fixture: the PR map" "$big_out" "PRCount: 48"
  assert_contains "big fixture: the loss block" "$big_out" "LossBlock: 83 branches lose work if deleted"
else
  skip_case "big fixture tallies need jq"
fi

# A branch named like a tag has the short name `heads/<name>`. The per-branch
# commands cannot resolve it, so it reports no tip and gets no capture row, which
# leaves it undeletable through git-branch-delete.sh; the bulk path must not
# resolve it either.
assert_contains "ambiguous short name: no tip, loss undetermined" "$big_out" "Branch: heads/v1
Tip: unresolved
Tier: REVIEW
Age days: 0
PR: none
Unpushed: no upstream (no origin/main to compare)
Loss: undetermined (tip unresolved)"
unresolved="$(grep -c '^Tip: unresolved$' <<<"$big_out")"
capture_rows="$(awk -F'\t' 'NF == 10 && $2 ~ /^[0-9a-f]+$/ && length($2) >= 40 { n++ } END { print n + 0 }' "$FIXTURES/big.tsv")"
if [[ "$unresolved" == 3 && "$capture_rows" == $((big_heads - 3)) ]]; then
  pass "ambiguous short names: 3 unresolved tips, and they alone have no capture row"
else
  fail "ambiguous short names: 3 unresolved tips, and they alone have no capture row" "3 and $((big_heads - 3))" "$unresolved and $capture_rows"
fi
assert_contains "an upstream that exists but is no commit is still an upstream" "$(awk '/^Branch: feat\/nc$/ { p = 1 } p { print } /^Reason: / { if (p) exit }' <<<"$big_out")" "ahead of origin/feat/nc"

for ((i = 1; i <= 8; i++)); do
  want="$(bash -c 'source "$1" && clean_worktree_path "$2" "$3"' bash "$SCRIPT_DIR/lib/clean-common.sh" "$FIXTURES/big/repo" "feat/wt-$i")"
  have="$(awk -v b="Branch: feat/wt-$i" '$0 == b { p = 1 } p && /^Worktree: / { print substr($0, 11); exit }' <<<"$big_out")"
  if [[ -n "$want" && "$have" == "$want" ]]; then
    pass "worktree branch feat/wt-$i reports the path clean_worktree_path gives"
  else
    fail "worktree branch feat/wt-$i reports the path clean_worktree_path gives" "$want" "$have"
  fi
done

# The number of git calls is a constant plus one `git log` per LOSSY branch (the
# LossCommit listing is walked per branch: a shared walk can reorder it when
# commit dates tie or skew). Everything else, including the ambiguous-name
# branches that take the per-branch commands, is the same at 242 branches as at 85.
# The landed-proof step is the other per-branch work: one merge-base call and at
# most six more (diff, merge listing, cherry, tree ids, commit-tree, cherry) for
# each branch that reaches it.
big_fixed=$((big_spawns - big_logs - big_proof))
small_fixed=$((small_spawns - small_logs - small_proof))
if [[ "$big_proof" -le $((7 * big_mb)) && "$small_proof" -le $((7 * small_mb)) ]]; then
  pass "landed-proof calls are at most seven per branch that reaches it ($big_proof for $big_mb, $small_proof for $small_mb)"
else
  fail "landed-proof calls are at most seven per branch that reaches it" "$((7 * big_mb)) and $((7 * small_mb))" "$big_proof and $small_proof"
fi
big_lossy="$(grep -c '^LossBranch: ' <<<"$big_out")"
small_lossy="$(grep -c '^LossBranch: ' <<<"$small_out")"
if [[ "$big_logs" == "$big_lossy" && "$small_logs" == "$small_lossy" ]]; then
  pass "one git log per LOSSY branch, and no other per-branch call ($big_logs and $small_logs)"
else
  fail "one git log per LOSSY branch" "$big_lossy and $small_lossy" "$big_logs and $small_logs"
fi
if [[ "$big_fixed" == "$small_fixed" && "$big_fixed" -le 40 ]]; then
  pass "git calls beyond the LOSSY listings do not grow with the branch count ($big_fixed at $big_heads branches, $small_fixed at $small_heads)"
else
  fail "git calls beyond the LOSSY listings are a constant of at most 40" "$small_fixed at $small_heads branches" "$big_fixed at $big_heads"
fi

# A pass that fails is answered by the per-branch commands: same report, more calls.
big_view="$(audit_view "$big_out" "$FIXTURES/big.tsv")"
for fail_on in " --parents " " cat-file "; do
  fb_out="$(SHIM_FAIL_ON="$fail_on" run_audit_shimmed "$FIXTURES/big" "$FIXTURES/big-fallback.tsv")"
  fb_spawns="$(spawn_count)"
  fb_view="$(audit_view "$fb_out" "$FIXTURES/big-fallback.tsv")"
  if [[ "$fb_view" == "$big_view" ]]; then
    pass "a failing${fail_on}pass gives the same report and capture"
  else
    fail "a failing${fail_on}pass gives the same report and capture" "no difference" "$(diff <(printf '%s\n' "$big_view") <(printf '%s\n' "$fb_view") | head -10)"
  fi
  if [[ "$fb_spawns" -gt "$big_spawns" ]]; then
    pass "a failing${fail_on}pass falls back to per-branch calls ($fb_spawns against $big_spawns)"
  else
    fail "a failing${fail_on}pass falls back to per-branch calls" "more than $big_spawns" "$fb_spawns"
  fi
done

# --- merged PR, tip moved: ancestor of the merged head, and the branch family ---------
# A MERGED PR whose headRefOid differs from the local tip is SAFE when the head
# object is here and the tip is an ancestor of it, REVIEW otherwise. The family is
# read from the branch name and no tier depends on it. Each verdict is the same
# whether the bulk pass or the per-branch commands answered.
if command -v jq >/dev/null 2>&1; then
  AN="$TEST_TMPDIR/ancestor-repo"
  git init -q --bare "$TEST_TMPDIR/ancestor-origin.git"
  git init -q -b main "$AN"
  git -C "$AN" config user.email "t@example.com"
  git -C "$AN" config user.name "Test"
  git -C "$AN" commit -q --allow-empty -m init
  git -C "$AN" remote add origin "$TEST_TMPDIR/ancestor-origin.git"
  git -C "$AN" push -q origin HEAD:main
  git -C "$AN" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  an_branch() { # <branch> <commits>: a branch with that many commits off main
    git -C "$AN" checkout -q -b "$1" main
    for ((k = 1; k <= $2; k++)); do git -C "$AN" commit -q --allow-empty -m "$1 $k"; done
    git -C "$AN" checkout -q main
  }
  an_branch feat/ancestor 2
  ancestor_head="$(git -C "$AN" rev-parse refs/heads/feat/ancestor)"
  git -C "$AN" branch -q -f feat/ancestor "$ancestor_head~1"
  an_branch feat/ahead 2
  ahead_head="$(git -C "$AN" rev-parse refs/heads/feat/ahead~1)"
  an_branch feat/diverged 1
  an_branch feat/diverged-head 1
  diverged_head="$(git -C "$AN" rev-parse refs/heads/feat/diverged-head)"
  git -C "$AN" branch -q -D feat/diverged-head
  an_branch feat/missing 1
  missing_head=dddddddddddddddddddddddddddddddddddddddd
  for b in agent-a1b2c3 agent-xyz claude/web1 plan/p stranded/s pre-wipe/w feat/plain; do an_branch "$b" 1; done
  an_bin="$TEST_TMPDIR/ancestor-bin"
  mkdir -p "$an_bin"
  printf '[{"headRefName":"feat/ancestor","state":"MERGED","number":1,"headRefOid":"%s"},{"headRefName":"feat/ahead","state":"MERGED","number":2,"headRefOid":"%s"},{"headRefName":"feat/diverged","state":"MERGED","number":3,"headRefOid":"%s"},{"headRefName":"feat/missing","state":"MERGED","number":4,"headRefOid":"%s"}]\n' \
    "$ancestor_head" "$ahead_head" "$diverged_head" "$missing_head" >"$an_bin/prs.json"
  printf '#!/usr/bin/env bash\ncase "$*" in *pr\\ list*) cat "%s" ;; *) exit 1 ;; esac\n' "$an_bin/prs.json" >"$an_bin/gh"
  chmod +x "$an_bin/gh"
  # field <audit output> <branch> <field>: the value of one line of a branch's record
  field() { awk -v b="Branch: $2" -v f="$3: " '$0 == b { p = 1; next } /^Branch: / { p = 0 } p && index($0, f) == 1 { print substr($0, length(f) + 1); exit }' <<<"$1"; }

  an_views=()
  for fail_on in "" " --parents " " cat-file "; do
    an_out="$(cd "$AN" && SHIM_FAIL_ON="$fail_on" PATH="$SHIM_BIN:$PATH" SHIM_PRS="$an_bin/prs.json" bash "$AUDIT" --capture-file "$TEST_TMPDIR/an${fail_on// /}.tsv")"
    an_views+=("$(printf '%s\n' "$an_out" | sed 's|^TipCapture: .*|TipCapture: <path>|')")
    lbl="${fail_on:+ (failing$fail_on)}"
    assert_contains "tip is an ancestor of the merged head: SAFE$lbl" "$an_out" "Branch: feat/ancestor
Tip: $(git -C "$AN" rev-parse refs/heads/feat/ancestor)
Tier: SAFE
Age days: 0
PR: #1 MERGED (tip drift)
Unpushed: no upstream, 1 commits not on origin/main
Loss: not assessed (SAFE)
Reason: PR merged (tip is an ancestor of the merged head)
Family: none"
    assert_contains "tip ahead of the merged head: REVIEW, 5b$lbl" "$an_out" "Branch: feat/ahead
Tip: $(git -C "$AN" rev-parse refs/heads/feat/ahead)
Tier: REVIEW"
    assert_contains "tip ahead of the merged head keeps the 5b reason$lbl" "$(field "$an_out" feat/ahead Reason)" "PR merged but branch has commits since merge"
    assert_contains "tip not an ancestor of the merged head: REVIEW$lbl" "$(field "$an_out" feat/diverged Tier) $(field "$an_out" feat/diverged Reason)" "REVIEW PR merged but branch has commits since merge"
    assert_contains "merged head object missing here: REVIEW$lbl" "$(field "$an_out" feat/missing Tier) $(field "$an_out" feat/missing Reason)" "REVIEW PR merged but branch has commits since merge"
  done
  if [[ "${an_views[0]}" == "${an_views[1]}" && "${an_views[0]}" == "${an_views[2]}" ]]; then
    pass "ancestor verdicts do not depend on which path answered"
  else
    fail "ancestor verdicts do not depend on which path answered" "no difference" "$(diff <(printf '%s\n' "${an_views[0]}") <(printf '%s\n' "${an_views[1]}") | head -10)"
  fi
  an_op="$(git -C "$AN" rev-parse --path-format=absolute --git-path MERGE_HEAD)"
  git -C "$AN" rev-parse HEAD >"$an_op"
  an_op_out="$(cd "$AN" && PATH="$SHIM_BIN:$PATH" SHIM_PRS="$an_bin/prs.json" bash "$AUDIT" --capture-file "$TEST_TMPDIR/an-op.tsv")"
  rm -f "$an_op"
  assert_contains "an operation in progress demotes the ancestor SAFE to REVIEW" "$(field "$an_op_out" feat/ancestor Tier) $(field "$an_op_out" feat/ancestor Reason)" "REVIEW operation in progress: $an_op"
  an_out="${an_views[0]}"
  for pair in agent-a1b2c3:agent agent-xyz:none claude/web1:claude plan/p:plan stranded/s:stranded pre-wipe/w:pre-wipe feat/plain:none main:none; do
    assert_contains "family of ${pair%%:*} is ${pair#*:}" "$(field "$an_out" "${pair%%:*}" Family)" "${pair#*:}"
    [[ "${pair%%:*}" == main ]] || assert_contains "family does not change the tier of ${pair%%:*}" "$(field "$an_out" "${pair%%:*}" Tier)" "$(field "$an_out" feat/plain Tier)"
  done
else
  skip_case "ancestor and family cases need jq"
fi

# clean_unreached_counts against the per-id rev-list, on tips whose ancestry has a
# merge, an octopus, a criss-cross and a tip already on origin/main.
counts() { bash -c 'source "$1" && shift && clean_unreached_counts "$@"' bash "$SCRIPT_DIR/lib/clean-common.sh" "$@"; }
count_ids=""
for b in topo/octopus-1 topo/crossx topo/crossy at-main at-root dag/b10 dag/b10; do
  count_ids+="$(git -C "$FIXTURES/big/repo" rev-parse "refs/heads/$b")"$'\n'
done
count_bad=""
declare -A COUNTED=()
while read -r o n; do COUNTED[$o]=$n; done < <(printf '%s' "$count_ids" | counts "$FIXTURES/big/repo" origin/main)
while read -r o; do
  want="$(git -C "$FIXTURES/big/repo" rev-list --count "origin/main..$o")"
  [[ "${COUNTED[$o]:-missing}" == "$want" ]] || count_bad+="$o: ${COUNTED[$o]:-missing}, rev-list $want"$'\n'
done <<<"${count_ids%$'\n'}"
if [[ -z "$count_bad" && "${#COUNTED[@]}" == 6 ]]; then
  pass "clean_unreached_counts equals rev-list --count for each id, once per distinct id"
else
  fail "clean_unreached_counts equals rev-list --count for each id" "6 ids, no difference" "${#COUNTED[@]} ids: $count_bad"
fi
rc=0
printf '' | counts "$FIXTURES/big/repo" origin/main >/dev/null || rc=$?
assert_exit "clean_unreached_counts: no ids is not a failure" 0 "$rc"
rc=0
printf '%s\n' "$(git -C "$FIXTURES/big/repo" rev-parse main)" | counts "$FIXTURES/big/repo" origin/no-such-ref >/dev/null 2>&1 || rc=$?
if [[ "$rc" -ne 0 ]]; then pass "clean_unreached_counts: a rev git cannot resolve is a failure"; else fail "clean_unreached_counts: a rev git cannot resolve is a failure" "non-zero" "$rc"; fi

# --- fleet form: --repo / --repos-from / --skip / --skip-from -------------------
# Two repositories plus a linked worktree of the first. The audit of the worktree
# would repeat the first repository's branches, so it is reported skipped.
FL="$TEST_TMPDIR/fleet"
mkdir -p "$FL"
for r in one two; do
  git init -q -b main "$FL/$r"
  git -C "$FL/$r" config user.email "t@example.com"
  git -C "$FL/$r" config user.name "Test"
  git -C "$FL/$r" commit -q --allow-empty -m init
done
git -C "$FL/one" worktree add -q -b feat/linked "$FL/one-linked"
FL_BIN="$TEST_TMPDIR/fleet-bin"
mkdir -p "$FL_BIN"
printf '#!/usr/bin/env bash\nexit 1\n' >"$FL_BIN/gh"
chmod +x "$FL_BIN/gh"
fleet_audit() { PATH="$FL_BIN:$PATH" bash "$AUDIT" "$@" 2>/dev/null; }

plain_out="$(PATH="$FL_BIN:$PATH" bash -c "cd '$FL/one' && bash '$AUDIT'")"
check_facts "fleet repo" "$FL/one" "$plain_out"
assert_not_contains "no selection flag: no Repo block" "$plain_out" "Repo: "
assert_not_contains "no selection flag: no fleet summary" "$plain_out" "FleetSummary:"

fleet_out="$(fleet_audit --repo "$FL/one" "$FL/one-linked" "$FL/two")"
assert_contains "fleet: first repo is a block" "$fleet_out" "Repo: $FL/one
"
assert_contains "fleet: second repo is a block" "$fleet_out" "Repo: $FL/two
"
assert_contains "fleet: a linked worktree of an audited repo is skipped once" "$fleet_out" "Repo: $FL/one-linked
Outcome: skipped
Reason: shares a git common dir with an audited repo"
assert_contains "fleet: summary counts" "$fleet_out" "FleetSummary: repos=3 audited=2 skipped=0 duplicate=1 blocked=0 failed=0"
assert_exit "fleet: exit 0" 0 "$(fleet_audit --repo "$FL/one" "$FL/two" >/dev/null && echo 0 || echo $?)"
tip_lines="$(grep -c '^TipCapture: ' <<<"$fleet_out")"
if [[ "$tip_lines" == 2 ]]; then pass "fleet: each audited repo prints its own TipCapture"; else fail "fleet: each audited repo prints its own TipCapture" 2 "$tip_lines"; fi
assert_contains "fleet: first capture lives in the first repo" "$fleet_out" "TipCapture: $FL/one/.git/repo-hygiene/branch-tips/"
assert_contains "fleet: second capture lives in the second repo" "$fleet_out" "TipCapture: $FL/two/.git/repo-hygiene/branch-tips/"

# A repo's block is its single-repo output, unchanged (the capture path carries a
# per-run stamp and pid, so that one line is set aside).
block_one="$(awk -v r="Repo: $FL/one" '$0 == r { on = 1; next } on && $0 == "---" { exit } on' <<<"$fleet_out" | grep -v '^TipCapture: ')"
plain_nc="$(grep -v '^TipCapture: ' <<<"$plain_out")"
if [[ "$block_one" == "$plain_nc" ]]; then pass "fleet: a repo's block equals its single-repo output"; else fail "fleet: a repo's block equals its single-repo output" "$plain_nc" "$block_one"; fi

# Selection: --repos-from (file and stdin), --skip, --skip-from.
printf '%s\r\n%s\n\n' "$FL/one" "$FL/two" >"$FL/list.txt"
from_file_out="$(fleet_audit --repos-from "$FL/list.txt")"
assert_contains "repos-from FILE audits both" "$from_file_out" "audited=2"
from_stdin_out="$(printf '%s\n' "$FL/two" | fleet_audit --repos-from -)"
assert_contains "repos-from - audits stdin" "$from_stdin_out" "audited=1"

skip_out="$(fleet_audit --repo "$FL/one" "$FL/two" --skip two --skip nowhere)"
assert_contains "skip list reports the skipped repo" "$skip_out" "Repo: $FL/two
Outcome: skipped
Reason: skip-list (two)"
assert_contains "skip list leaves the other repo audited" "$skip_out" "Repo: $FL/one
"
assert_contains "an entry that matched nothing is reported" "$skip_out" "UnmatchedSkip: nowhere"
assert_contains "skip summary" "$skip_out" "audited=1 skipped=1"
printf '%s\n' "$FL/one" >"$FL/skips.txt"
skip_from_out="$(fleet_audit --repo "$FL/one" "$FL/two" --skip-from "$FL/skips.txt")"
assert_contains "skip-from FILE skips the listed repo" "$skip_from_out" "Reason: skip-list ($FL/one)"
# A skipped worktree does not hide its sibling: the second one is audited instead.
sib_out="$(fleet_audit --repo "$FL/one" "$FL/one-linked" --skip one)"
assert_contains "skipping one worktree audits the other" "$sib_out" "Branch: feat/linked
Tip: "
assert_contains "the audited sibling is its own block" "$sib_out" "Repo: $FL/one-linked
"

# An unusable input and a missing path are reported; the rest of the fleet runs.
mkdir -p "$FL/plain-dir"
bad_out="$(fleet_audit --repo "$FL/missing" "$FL/plain-dir" "$FL/two")"
assert_contains "missing path is blocked" "$bad_out" "Repo: $FL/missing
Outcome: blocked
Reason: not-a-directory"
assert_contains "non-repo directory is blocked" "$bad_out" "Reason: not-a-git-repo"
assert_contains "the fleet continues past blocked repos" "$bad_out" "Repo: $FL/two
"
assert_contains "blocked summary" "$bad_out" "audited=1 skipped=0 duplicate=0 blocked=2 failed=0"

# --capture-file names one file: fine for one repo, a usage error for several.
rc=0
cap_err="$(PATH="$FL_BIN:$PATH" bash "$AUDIT" --repo "$FL/one" "$FL/two" --capture-file "$FL/shared.tsv" 2>&1 >/dev/null)" || rc=$?
assert_exit "--capture-file with two repos exits 2" 2 "$rc"
assert_contains "--capture-file rejection says why" "$cap_err" "cannot serve 2 repos"
if [[ ! -e "$FL/shared.tsv" && ! -e "$FL/shared.tsv.part" ]]; then pass "--capture-file rejection writes nothing"; else fail "--capture-file rejection writes nothing" absent present; fi
one_cap_out="$(fleet_audit --repo "$FL/one" --capture-file "$FL/one.tsv")"
assert_contains "--capture-file with one repo is honored" "$one_cap_out" "TipCapture: $FL/one.tsv"

# Usage errors.
for bad in "--repo" "--repos-from" "--skip two" "--repos-from $FL/no-such-list.txt"; do
  rc=0
  # shellcheck disable=SC2086
  PATH="$FL_BIN:$PATH" bash "$AUDIT" $bad >/dev/null 2>&1 || rc=$?
  assert_exit "usage error exits 2: $bad" 2 "$rc"
done
: >"$FL/empty.txt"
rc=0
PATH="$FL_BIN:$PATH" bash "$AUDIT" --repos-from "$FL/empty.txt" >/dev/null 2>&1 || rc=$?
assert_exit "an empty repo list exits 2" 2 "$rc"
help_out="$(bash "$AUDIT" --help)"
assert_contains "--help documents --repo" "$help_out" "--repo DIR..."
assert_contains "--help documents the capture rule" "$help_out" "--capture-file with more than one repo"

# --- --read-only: no capture file, no .part, no directory ----------------------
# capture_state prints every path under the repository's git dir that belongs to
# the capture location, so a before/after comparison catches a file, a `.part`,
# or a directory.
capture_state() { find "$1/.git" -path '*repo-hygiene*' 2>/dev/null | sort; }
normal_out="$(fleet_audit --repo "$FL/two")"
assert_contains "read-only setup: a normal audit writes a capture" "$normal_out" "TipCapture: $FL/two/.git/repo-hygiene/branch-tips/"
before_state="$(capture_state "$FL/two")"
ro_out="$(PATH="$FL_BIN:$PATH" bash -c "cd '$FL/two' && bash '$AUDIT' --read-only")"
assert_contains "--read-only says no capture was written" "$ro_out" "TipCaptureSkipped: --read-only, no capture was written"
assert_not_contains "--read-only prints no capture path" "$ro_out" "TipCapture: "
assert_not_contains "--read-only reports no capture error" "$ro_out" "TipCaptureError:"
assert_contains "--read-only still reports every branch" "$ro_out" "Branch: main"
assert_contains "--read-only still prints the summary" "$ro_out" "Summary:"
after_state="$(capture_state "$FL/two")"
if [[ -n "$before_state" && "$before_state" == "$after_state" ]]; then pass "--read-only leaves the capture dir unchanged"; else fail "--read-only leaves the capture dir unchanged" "$before_state" "$after_state"; fi
if ! find "$FL/two/.git" -name '*.part' | grep -q .; then pass "--read-only leaves no .part file"; else fail "--read-only leaves no .part file" none present; fi
# A repo that has never been audited gains no capture directory either.
git init -q -b main "$FL/fresh"
git -C "$FL/fresh" config user.email "t@example.com"
git -C "$FL/fresh" config user.name "Test"
git -C "$FL/fresh" commit -q --allow-empty -m init
PATH="$FL_BIN:$PATH" bash -c "cd '$FL/fresh' && bash '$AUDIT' --read-only" >/dev/null
if [[ -z "$(capture_state "$FL/fresh")" ]]; then pass "--read-only creates no capture dir in a never-audited repo"; else fail "--read-only creates no capture dir in a never-audited repo" none "$(capture_state "$FL/fresh")"; fi
# Deletion still needs a capture: nothing here produced one.
git -C "$FL/fresh" branch feat/orphan
rc=0
del_out="$(PATH="$FL_BIN:$PATH" bash -c "cd '$FL/fresh' && bash '$SCRIPT_DIR/git-branch-delete.sh' --dry-run feat/orphan" 2>&1)" || rc=$?
assert_exit "delete after a --read-only audit exits 3" 3 "$rc"
assert_contains "delete after a --read-only audit names the missing capture" "$del_out" "Refused: no --capture given"
# Fleet form forwards --read-only to every repo.
ro_fleet="$(fleet_audit --repo "$FL/one" "$FL/two" --read-only)"
skipped_lines="$(grep -c '^TipCaptureSkipped: ' <<<"$ro_fleet")"
if [[ "$skipped_lines" == 2 ]]; then pass "fleet --read-only: every audited repo skips its capture"; else fail "fleet --read-only: every audited repo skips its capture" 2 "$skipped_lines"; fi
assert_not_contains "fleet --read-only: no capture path anywhere" "$ro_fleet" "TipCapture: "
# --read-only and --remote take no capture path.
rc=0
PATH="$FL_BIN:$PATH" bash -c "cd '$FL/two' && bash '$AUDIT' --read-only --capture-file '$FL/x.tsv'" >/dev/null 2>&1 || rc=$?
assert_exit "--read-only with --capture-file exits 2" 2 "$rc"
rc=0
PATH="$FL_BIN:$PATH" bash -c "cd '$FL/two' && bash '$AUDIT' --remote --capture-file '$FL/x.tsv'" >/dev/null 2>&1 || rc=$?
assert_exit "--remote with --capture-file exits 2" 2 "$rc"
rc=0
PATH="$FL_BIN:$PATH" bash -c "cd '$FL/two' && bash '$AUDIT' --remote --remote-families" >/dev/null 2>&1 || rc=$?
assert_exit "--remote with --remote-families exits 2" 2 "$rc"

# --- --remote: the live origin branch list against merged PRs ------------------
# A bare origin, a working clone, and a second clone that pushes a branch the
# first never fetches. The gh shim answers only `pr list --state merged --head X`.
if command -v jq >/dev/null 2>&1; then
  RM="$TEST_TMPDIR/remote"
  mkdir -p "$RM"
  git init -q --bare -b main "$RM/origin.git"
  git clone -q "$RM/origin.git" "$RM/work" 2>/dev/null
  git clone -q "$RM/origin.git" "$RM/other" 2>/dev/null
  for c in work other; do
    git -C "$RM/$c" config user.email "t@example.com"
    git -C "$RM/$c" config user.name "Test"
  done
  git -C "$RM/work" commit -q --allow-empty -m init
  git -C "$RM/work" push -q origin main 2>/dev/null
  push_branch() { # <branch> <n commits> from work
    git -C "$RM/work" checkout -q -b "$1" main
    for ((k = 1; k <= $2; k++)); do git -C "$RM/work" commit -q --allow-empty -m "$1 c$k"; done
    git -C "$RM/work" push -q origin "$1" 2>/dev/null
    git -C "$RM/work" checkout -q main
  }
  push_branch feat/current 1
  push_branch feat/nopr 1
  push_branch release/1 1
  push_branch feat/drift 1
  drift_old="$(git -C "$RM/work" rev-parse feat/drift)"
  git -C "$RM/work" checkout -q feat/drift
  git -C "$RM/work" commit -q --allow-empty -m "after the merge 1"
  git -C "$RM/work" commit -q --allow-empty -m "after the merge 2"
  git -C "$RM/work" push -q origin feat/drift 2>/dev/null
  git -C "$RM/work" checkout -q main
  drift_tip="$(git -C "$RM/work" rev-parse feat/drift)"
  # The tracking ref goes stale: it still says the PR head is the tip.
  git -C "$RM/work" update-ref refs/remotes/origin/feat/drift "$drift_old"
  # A branch pushed by another clone: no tracking ref and no objects here.
  git -C "$RM/other" checkout -q -b feat/unfetched
  git -C "$RM/other" commit -q --allow-empty -m "unfetched"
  git -C "$RM/other" push -q origin feat/unfetched 2>/dev/null
  unfetched_tip="$(git -C "$RM/other" rev-parse feat/unfetched)"
  if ! git -C "$RM/work" rev-parse --verify --quiet refs/remotes/origin/feat/unfetched >/dev/null; then pass "remote setup: the unfetched branch has no tracking ref"; else fail "remote setup: the unfetched branch has no tracking ref" absent present; fi
  current_tip="$(git -C "$RM/work" rev-parse feat/current)"
  release_tip="$(git -C "$RM/work" rev-parse release/1)"

  RM_BIN="$TEST_TMPDIR/remote-bin"
  mkdir -p "$RM_BIN"
  cat >"$RM_BIN/gh" <<GH
#!/usr/bin/env bash
[[ "\$*" == *"pr list"* && "\$*" == *"--state merged"* ]] || exit 1
head="" prev=""
for a in "\$@"; do [[ "\$prev" == --head ]] && head="\$a"; [[ "\$prev" == --repo ]] && echo "\$a" >>"$RM/gh-repos.log"; prev="\$a"; done
echo "\$head" >>"$RM/gh-heads.log"
case "\$head" in
  feat/current) printf '[{"number":11,"headRefOid":"$current_tip"}]\n' ;;
  feat/drift) printf '[{"number":5,"headRefOid":"0000000000000000000000000000000000000005"},{"number":7,"headRefOid":"$drift_old"}]\n' ;;
  feat/unfetched) printf '[{"number":9,"headRefOid":"1111111111111111111111111111111111111111"}]\n' ;;
  *) printf '[]\n' ;;
esac
GH
  chmod +x "$RM_BIN/gh"
  remote_run() { PATH="$RM_BIN:$PATH" bash -c "cd '$RM/work' && bash '$AUDIT' --remote" 2>/dev/null; }
  # rec <output> <branch> <key>: one RemoteBranch record's field.
  rec() { awk -v b="$2" -v k="$3" '$0 == "RemoteBranch: " b { on = 1; next } /^RemoteBranch: / { on = 0 } on && index($0, k ": ") == 1 { print substr($0, length(k) + 3) }' <<<"$1"; }

  before_remote="$(capture_state "$RM/work")"
  rout="$(remote_run)"
  assert_contains "remote: counts the live branches" "$rout" "RemoteBranches: 6"
  assert_no_line "remote: no local records" "$rout" "^Branch: "
  assert_not_contains "remote: no capture line" "$rout" "TipCapture"
  assert_contains "remote: summary counts each tier" "$rout" "RemoteSummary: protected=2 merged=1 merged-drift=2 no-merged-pr=1 unknown=0"
  if [[ "$(rec "$rout" feat/current RemoteTier)" == MERGED ]]; then pass "remote: tip equal to the merged PR head is MERGED"; else fail "remote: tip equal to the merged PR head is MERGED" MERGED "$(rec "$rout" feat/current RemoteTier)"; fi
  if [[ "$(rec "$rout" feat/current RemotePR)" == "#11 MERGED" ]]; then pass "remote: MERGED names its PR"; else fail "remote: MERGED names its PR" "#11 MERGED" "$(rec "$rout" feat/current RemotePR)"; fi
  # The stale tracking ref says feat/drift is at the PR head; the live tip is two commits past it.
  if [[ "$(rec "$rout" feat/drift RemoteTier)" == MERGED-DRIFT ]]; then pass "remote: a tip that differs from the merged PR head is flagged MERGED-DRIFT"; else fail "remote: a tip that differs from the merged PR head is flagged MERGED-DRIFT" MERGED-DRIFT "$(rec "$rout" feat/drift RemoteTier)"; fi
  if [[ "$(rec "$rout" feat/drift RemoteTip)" == "$drift_tip" ]]; then pass "remote: the tip is the live one, not the stale tracking ref"; else fail "remote: the tip is the live one, not the stale tracking ref" "$drift_tip" "$(rec "$rout" feat/drift RemoteTip)"; fi
  if [[ "$(rec "$rout" feat/drift RemoteAhead)" == "2 commits past the PR head" ]]; then pass "remote: drift reports the commits past the PR head"; else fail "remote: drift reports the commits past the PR head" "2 commits past the PR head" "$(rec "$rout" feat/drift RemoteAhead)"; fi
  if [[ "$(rec "$rout" feat/drift RemotePR)" == "#7 MERGED (head $drift_old)" ]]; then pass "remote: drift compares with the merged PR whose head the branch had"; else fail "remote: drift compares with the merged PR whose head the branch had" "#7 MERGED (head $drift_old)" "$(rec "$rout" feat/drift RemotePR)"; fi
  if [[ "$(rec "$rout" feat/unfetched RemoteTier)" == MERGED-DRIFT && "$(rec "$rout" feat/unfetched RemoteTip)" == "$unfetched_tip" ]]; then pass "remote: a never-fetched branch is judged against its live tip"; else fail "remote: a never-fetched branch is judged against its live tip" "MERGED-DRIFT $unfetched_tip" "$(rec "$rout" feat/unfetched RemoteTier) $(rec "$rout" feat/unfetched RemoteTip)"; fi
  assert_contains "remote: an unfetched tip has no computable ahead count" "$(rec "$rout" feat/unfetched RemoteAhead)" "not computable"
  if [[ "$(rec "$rout" feat/nopr RemoteTier)" == NO-MERGED-PR ]]; then pass "remote: no merged PR is NO-MERGED-PR"; else fail "remote: no merged PR is NO-MERGED-PR" NO-MERGED-PR "$(rec "$rout" feat/nopr RemoteTier)"; fi
  if [[ "$(rec "$rout" main RemoteTier)" == PROTECTED && "$(rec "$rout" release/1 RemoteTier)" == PROTECTED && "$(rec "$rout" release/1 RemoteTip)" == "$release_tip" ]]; then pass "remote: default and protected-pattern branches are PROTECTED"; else fail "remote: default and protected-pattern branches are PROTECTED" PROTECTED "$(rec "$rout" main RemoteTier) $(rec "$rout" release/1 RemoteTier)"; fi
  if ! grep -qx 'main\|release/1' "$RM/gh-heads.log"; then pass "remote: protected branches trigger no PR lookup"; else fail "remote: protected branches trigger no PR lookup" none "$(cat "$RM/gh-heads.log")"; fi
  # The lookup names origin's repository, so an `upstream` remote cannot redirect it.
  if [[ "$(sort -u "$RM/gh-repos.log")" == "$RM/origin.git" && "$(wc -l <"$RM/gh-repos.log")" -eq "$(wc -l <"$RM/gh-heads.log")" ]]; then pass "remote: every PR lookup targets origin's repository"; else fail "remote: every PR lookup targets origin's repository" "$RM/origin.git on each lookup" "$(sort -u "$RM/gh-repos.log")"; fi
  if [[ "$(capture_state "$RM/work")" == "$before_remote" ]]; then pass "remote: writes no capture"; else fail "remote: writes no capture" "$before_remote" "$(capture_state "$RM/work")"; fi

  # gh absent: still listed with the live tip, every checked branch UNKNOWN.
  # PATH holds only the tools the script needs (no gh).
  NOGH_BIN="$TEST_TMPDIR/nogh-bin"
  mkdir -p "$NOGH_BIN"
  for t in git jq awk grep sed tr cat mktemp date dirname rm mv mkdir sort find basename head tail cut wc uname ls; do
    src="$(command -v "$t" 2>/dev/null)" && ln -sf "$src" "$NOGH_BIN/$t"
  done
  nogh_out="$(PATH="$NOGH_BIN" "$BASH" -c "cd '$RM/work' && \"$BASH\" '$AUDIT' --remote" 2>/dev/null)"
  assert_contains "remote without gh: says why" "$nogh_out" "merged-PR lookup unavailable (gh not on PATH)"
  assert_contains "remote without gh: still lists the live tip" "$nogh_out" "RemoteTip: $unfetched_tip"
  assert_contains "remote without gh: summary" "$nogh_out" "RemoteSummary: protected=2 merged=0 merged-drift=0 no-merged-pr=0 unknown=4"

  # A failing gh is UNKNOWN too, and a remote that cannot be read is an error.
  printf '#!/usr/bin/env bash\nexit 1\n' >"$RM/failgh"
  mkdir -p "$RM/fail-bin"
  cp "$RM/failgh" "$RM/fail-bin/gh"
  chmod +x "$RM/fail-bin/gh"
  fail_out="$(PATH="$RM/fail-bin:$PATH" bash -c "cd '$RM/work' && bash '$AUDIT' --remote" 2>/dev/null)"
  assert_contains "remote with a failing gh: UNKNOWN, not NO-MERGED-PR" "$fail_out" "RemoteTier: UNKNOWN"
  assert_not_contains "remote with a failing gh: never claims no merged PR" "$fail_out" "RemoteTier: NO-MERGED-PR"
  noorigin_out="$(PATH="$FL_BIN:$PATH" bash -c "cd '$FL/fresh' && bash '$AUDIT' --remote" 2>/dev/null)"
  assert_contains "remote without an origin: RemoteError" "$noorigin_out" "RemoteError: git ls-remote --heads origin failed"

  # Fleet form: --repos-from and --remote reach every repo; no capture anywhere.
  printf '%s\n%s\n' "$RM/work" "$FL/fresh" >"$RM/repos.txt"
  rfleet="$(PATH="$RM_BIN:$PATH" bash "$AUDIT" --repos-from "$RM/repos.txt" --remote 2>/dev/null)"
  assert_contains "remote fleet: the origin repo is a block with its summary" "$rfleet" "Repo: $RM/work
RemoteBranches: 6"
  assert_contains "remote fleet: a repo without origin reports its error and the fleet goes on" "$rfleet" "RemoteError: git ls-remote --heads origin failed"
  assert_contains "remote fleet: summary" "$rfleet" "FleetSummary: repos=2 audited=2 skipped=0 duplicate=0 blocked=0 failed=0"
  assert_not_contains "remote fleet: no capture" "$rfleet" "TipCapture"

  # Two clones of one origin list the same remote branches: --remote audits the
  # first only. A local audit reads each clone's own branches, so it audits both.
  rdup="$(PATH="$RM_BIN:$PATH" bash "$AUDIT" --repo "$RM/work" "$RM/other" --remote 2>/dev/null)"
  assert_contains "remote fleet: the first clone of an origin is audited" "$rdup" "Repo: $RM/work
RemoteBranches: 6"
  assert_contains "remote fleet: another clone of that origin is a duplicate" "$rdup" "Repo: $RM/other
Outcome: skipped
Reason: skipped duplicate of $RM/work"
  assert_contains "remote fleet: summary counts the clone duplicate" "$rdup" "FleetSummary: repos=2 audited=1 skipped=0 duplicate=1 blocked=0 failed=0"
  rdup_skip="$(PATH="$RM_BIN:$PATH" bash "$AUDIT" --repo "$RM/work" "$RM/other" --remote --skip "$RM/work" 2>/dev/null)"
  assert_contains "remote fleet: skipping one clone leaves the other audited" "$rdup_skip" "Repo: $RM/other
RemoteBranches: 6"
  ldup="$(PATH="$RM_BIN:$PATH" bash "$AUDIT" --repo "$RM/work" "$RM/other" --read-only 2>/dev/null)"
  assert_contains "local fleet: clones of one origin are both audited" "$ldup" "FleetSummary: repos=2 audited=2 skipped=0 duplicate=0 blocked=0 failed=0"
else
  skip_case "--remote tests need jq"
fi

# --remote-families: report-only read of refs/remotes/origin/*. A bare origin and
# a clone whose remote-tracking branches cover every family, each landed case,
# both retention outcomes for an expired branch and the agent-<hex> worktree rule.
if command -v jq >/dev/null 2>&1; then
  RF="$TEST_TMPDIR/rf-repo"
  git init -q --bare "$TEST_TMPDIR/rf-origin.git"
  git init -q -b main "$RF"
  git -C "$RF" config user.email "t@example.com"
  git -C "$RF" config user.name "Test"
  git -C "$RF" remote add origin "$TEST_TMPDIR/rf-origin.git"
  echo a >"$RF/a"
  git -C "$RF" add a
  git -C "$RF" commit -qm init
  git -C "$RF" push -q origin HEAD:main
  git -C "$RF" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  old_date="$(($(date +%s) - 200 * 86400)) +0000"
  # rf_branch <name> [old]: one commit on a new branch, pushed, then the local branch
  # is dropped so only refs/remotes/origin/<name> remains.
  rf_branch() {
    git -C "$RF" checkout -q -b "$1" main
    echo "$1" >"$RF/f"
    git -C "$RF" add f
    if [[ "${2:-}" == old ]]; then
      GIT_AUTHOR_DATE="$old_date" GIT_COMMITTER_DATE="$old_date" git -C "$RF" commit -qm "$1"
    else
      git -C "$RF" commit -qm "$1"
    fi
    git -C "$RF" push -q origin "$1"
    git -C "$RF" checkout -q main
    git -C "$RF" branch -q -D "$1"
  }
  rf_tip() { git -C "$RF" rev-parse "refs/remotes/origin/$1"; }
  for b in agent-abc123 agent-def456 claude/x plan/x stranded/x pre-wipe/x feat/eq; do
    rf_branch "$b"
  done
  rf_branch pre-wipe/old-held old
  rf_branch pre-wipe/old-unique old
  # another ref holds the old-held tip: a branch at the same commit
  git -C "$RF" push -q origin "refs/remotes/origin/pre-wipe/old-held:refs/heads/keep/holder"
  # tip is an ancestor of the merged head; tip is past the merged head
  rf_branch feat/base
  git -C "$RF" checkout -q -b base-head "refs/remotes/origin/feat/base"
  echo more >"$RF/base-more"
  git -C "$RF" add base-more
  git -C "$RF" commit -qm "base head"
  base_head="$(git -C "$RF" rev-parse HEAD)"
  git -C "$RF" checkout -q main
  git -C "$RF" checkout -q -b past-head main
  echo p >"$RF/past-1"
  git -C "$RF" add past-1
  git -C "$RF" commit -qm "past head"
  past_head="$(git -C "$RF" rev-parse HEAD)"
  echo q >"$RF/past-2"
  git -C "$RF" add past-2
  git -C "$RF" commit -qm "past tip"
  git -C "$RF" push -q origin HEAD:refs/heads/feat/past
  git -C "$RF" checkout -q main
  git -C "$RF" fetch -q origin
  # agent-def456 is checked out in a linked worktree under its own name
  git -C "$RF" worktree add -q -b agent-def456 "$TEST_TMPDIR/rf-wt" main
  rf_bin="$TEST_TMPDIR/rf-bin"
  mkdir -p "$rf_bin"
  printf '[{"headRefName":"feat/eq","state":"MERGED","number":11,"headRefOid":"%s"},{"headRefName":"feat/base","state":"MERGED","number":12,"headRefOid":"%s"},{"headRefName":"feat/past","state":"MERGED","number":13,"headRefOid":"%s"},{"headRefName":"agent-abc123","state":"MERGED","number":14,"headRefOid":"%s"},{"headRefName":"feat/eq","state":"OPEN","number":15,"headRefOid":"%s"}]\n' \
    "$(rf_tip feat/eq)" "$base_head" "$past_head" "$(rf_tip agent-abc123)" "$(rf_tip feat/eq)" >"$rf_bin/prs.json"
  printf '#!/usr/bin/env bash\ncase "$*" in *pr\\ list*) cat "%s" ;; *) exit 1 ;; esac\n' "$rf_bin/prs.json" >"$rf_bin/gh"
  chmod +x "$rf_bin/gh"

  refs_before="$(git -C "$RF" for-each-ref --format='%(refname) %(objectname)')"
  rf_rc=0
  rf_out="$(cd "$RF" && PATH="$rf_bin:$PATH" bash "$AUDIT" --remote-families)" || rf_rc=$?
  assert_exit "--remote-families exits 0" 0 "$rf_rc"
  # rf_field <branch> <field>: one line of a RemoteBranch record
  rf_field() { awk -v b="RemoteBranch: $1" -v f="$2: " '$0 == b { p = 1; next } /^RemoteBranch: / { p = 0 } p && index($0, f) == 1 { print substr($0, length(f) + 1); exit }' <<<"$rf_out"; }

  assert_contains "remote mode announces itself as report only" "$rf_out" "Mode: remote-families (report only"
  assert_not_contains "remote mode does not print local branch records" "$(grep -E "^(Branch|Tier): " <<<"$rf_out")" "Branch: "
  assert_not_contains "remote mode lists no default branch" "$rf_out" "RemoteBranch: main"
  for pair in agent-abc123:agent claude/x:claude plan/x:plan stranded/x:stranded pre-wipe/x:pre-wipe feat/eq:none; do
    assert_contains "remote family of ${pair%%:*} is ${pair#*:}" "$(rf_field "${pair%%:*}" Family)" "${pair#*:}"
  done
  assert_contains "merged PR whose head is the tip: landed" "$(rf_field feat/eq Landed)" "PR #11 merged, its head is the tip"
  assert_contains "tip that is an ancestor of the merged head: landed" "$(rf_field feat/base Landed)" "PR #12 merged, the tip is an ancestor of its head"
  assert_contains "tip past the merged head: not landed" "$(rf_field feat/past Landed)" "no"
  assert_contains "a family with no rule has no retention verdict, even with an open PR" "$(rf_field feat/eq Retention)" "n/a"
  assert_contains "fresh claude branch is kept" "$(rf_field claude/x Retention)" "KEEP"
  assert_contains "fresh claude branch reason names the window" "$(rf_field claude/x Reason)" "within the 30d retention for claude"
  assert_contains "fresh plan branch is kept" "$(rf_field plan/x Retention)" "KEEP"
  assert_contains "fresh stranded branch is kept" "$(rf_field stranded/x Retention)" "KEEP"
  assert_contains "fresh pre-wipe branch is kept" "$(rf_field pre-wipe/x Retention)" "KEEP"
  assert_contains "expired pre-wipe with its tip on another ref: candidate" "$(rf_field pre-wipe/old-held Retention) $(rf_field pre-wipe/old-held Reason)" "CANDIDATE tip is 200d old, past the 30d retention for pre-wipe; another ref holds the tip"
  assert_contains "expired pre-wipe with unique commits: kept" "$(rf_field pre-wipe/old-unique Retention) $(rf_field pre-wipe/old-unique Reason)" "KEEP-UNIQUE tip is 200d old, past the 30d retention for pre-wipe; not landed and no other ref holds the tip"
  assert_contains "agent branch with no worktree and a landed PR: candidate" "$(rf_field agent-abc123 Retention) $(rf_field agent-abc123 Landed)" "CANDIDATE PR #14 merged, its head is the tip"
  assert_contains "agent branch checked out in a worktree: kept" "$(rf_field agent-def456 Retention) $(rf_field agent-def456 Reason)" "KEEP checked out in worktree"
  assert_contains "summary counts each family" "$rf_out" "Families: agent=2 claude=1 plan=1 stranded=1 pre-wipe=3 none=4"
  printf '#!/usr/bin/env bash\nexit 1\n' >"$rf_bin/gh"
  rf_nopr_out="$(cd "$RF" && PATH="$rf_bin:$PATH" bash "$AUDIT" --remote-families)"
  assert_contains "failed PR lookup is announced" "$rf_nopr_out" "PRDataUnavailable:"
  assert_contains "expired branch is undetermined when the PR map is missing" "$(awk '$0 == "RemoteBranch: pre-wipe/old-held" { p = 1; next } /^RemoteBranch: / { p = 0 } p && /^Retention: / { print; exit }' <<<"$rf_nopr_out")" "KEEP-UNDETERMINED"
  assert_not_contains "no branch is a candidate without the PR map" "$rf_nopr_out" "Retention: CANDIDATE"
  assert_not_contains "remote mode writes no TipCapture line" "$rf_out" "TipCapture:"
  assert_not_contains "remote mode reports no deletion" "$rf_out" "Deleted:"
  if [[ "$(git -C "$RF" for-each-ref --format='%(refname) %(objectname)')" == "$refs_before" ]]; then
    pass "remote mode deletes and moves no ref"
  else
    fail "remote mode deletes and moves no ref" "no difference" "refs changed"
  fi
  if [[ -z "$(find "$RF/.git" -name '*.tsv*' 2>/dev/null)" ]]; then pass "remote mode writes no capture file"; else fail "remote mode writes no capture file" none present; fi
  rc=0
  (cd "$RF" && PATH="$rf_bin:$PATH" bash "$AUDIT" --remote-families --capture-file "$TEST_TMPDIR/rf.tsv" >/dev/null 2>&1) || rc=$?
  assert_exit "--remote-families with --capture-file exits 2" 2 "$rc"
  assert_file_absent "rejected capture flag writes nothing" "$TEST_TMPDIR/rf.tsv"
else
  skip_case "remote-families cases need jq"
fi

if [[ $FAILED -ne 0 ]]; then
  echo "FAILED: $FAILED test(s)"
  exit 1
fi
echo "OK: git-branch-audit.sh tests passed"
