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
Tier: REVIEW"
assert_contains "Tip line for the tracked branch" "$tip_out" "Tip: $tracked_tip"
assert_not_contains "no branch is left without a resolved tip" "$tip_out" "Tip: unresolved"
cap="$(printf '%s\n' "$tip_out" | sed -n 's/^TipCapture: //p')"
assert_file_exists "TipCapture path exists" "$cap"
assert_contains "capture is under <common-dir>/repo-hygiene/branch-tips/" "$cap" "$NU_REPO/.git/repo-hygiene/branch-tips/"
assert_file_absent "no .part left behind" "$cap.part"
cap_body="$(cat "$cap")"
assert_contains "capture header" "$cap_body" "# repo-hygiene branch tip capture v1"
assert_contains "capture names the restore command" "$cap_body" "# restore: git branch <branch> <tip>"
assert_contains "capture row: never-pushed (no upstream, 1 not on default)" "$cap_body" "feat/never-pushed	$never_tip	REVIEW	none	none	-	-	1	"
assert_contains "capture row: tracked (ahead 1, behind 1)" "$cap_body" "feat/tracked	$tracked_tip	REVIEW	none	origin/feat/tracked	1	1	"
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

if [[ $FAILED -ne 0 ]]; then
  echo "FAILED: $FAILED test(s)"
  exit 1
fi
echo "OK: git-branch-audit.sh tests passed"
