#!/usr/bin/env bash
# Regression tests for landed-work.sh.
# Black-box against throwaway git fixtures under a mktemp dir: a bare origin plus
# a working clone, so `HEAD --not --remotes` has real remote refs to subtract.
# No network.
#
# The four discriminating cases are the multi-commit squash, the same squash
# after the base advances, the genuinely-unmerged negative control, and the
# not-a-worktree-root probe. The rest guard the degradation paths.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$SCRIPT_DIR/landed-work.sh"

FAILED=0
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

command -v git >/dev/null 2>&1 || skip_suite "git not available"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# mkfixture — bare origin + working clone with one pushed commit on main and a
# local origin/HEAD, which is what the engine's default base resolution reads.
# Echoes the working repository path as the sole stdout line.
mkfixture() {
  local origin work
  origin="$(mktemp -d "$TEST_TMPDIR/originXXXXXX")"
  work="$(mktemp -d "$TEST_TMPDIR/workXXXXXX")"
  {
    git init -q --bare -b main "$origin"
    git init -q -b main "$work"
    git -C "$work" config user.email t@t.t
    git -C "$work" config user.name t
    git -C "$work" config commit.gpgsign false
    # Line endings are pinned so the EOL case tests what it says. With the
    # Windows default (core.autocrlf=true) git normalizes CRLF to LF on the way
    # into the object store, so a fixture "with CRLF endings" would commit the
    # same blob as its LF twin and the case would pass for a reason that has
    # nothing to do with the classifier.
    git -C "$work" config core.autocrlf false
    printf 'seed\n' >"$work/README.md"
    git -C "$work" add README.md
    git -C "$work" commit -qm init
    git -C "$work" remote add origin "$origin"
    git -C "$work" push -q -u origin main
    git -C "$work" remote set-head origin main
  } >/dev/null 2>&1
  printf '%s' "$work"
}

# commit_in <dir> <file> <content> <subject> — content is newline-terminated so a
# fixture never differs from its base only by "\ No newline at end of file",
# which git reports as a real added line and would make a behind-only branch
# look like it adds content.
commit_in() {
  printf '%s\n' "$3" >"$1/$2"
  git -C "$1" add "$2" >/dev/null 2>&1
  git -C "$1" commit -qm "$4" >/dev/null 2>&1
}

# row <output> <path-substring> — the TSV row whose path contains the substring.
row() {
  awk -F'\t' -v pat="$2" 'index($1, pat) { print; exit }' <<<"$1"
}

# col <row> <n>
col() {
  awk -F'\t' -v c="$2" '{ print $c; exit }' <<<"$1"
}

C_BRANCH=2
C_UNPUSHED=4
C_LANDED=5
C_METHOD=6
C_INPROGRESS=8
C_CONFLICTED=11
C_PEERS=13
C_RISK=14
C_REASON=15

# --------------------------------------------------------------------------
# Path key normalization
# --------------------------------------------------------------------------

assert_eq "path-key strips a trailing slash" "$(bash "$ENGINE" --path-key "/a/b/")" "$(bash "$ENGINE" --path-key "/a/b")"
# The separator is assembled rather than written literally: the two characters
# `\` + `b` are a GNU-only regex escape the shell-portability gate scans for, and
# the gate reads source lines, not their meaning.
BACKSLASH="$(printf '\134')"
assert_eq "path-key folds backslashes to slashes" \
  "$(bash "$ENGINE" --path-key "/a/b")" "$(bash "$ENGINE" --path-key "${BACKSLASH}a${BACKSLASH}b")"

case "$(uname -s 2>/dev/null || true)" in
MINGW* | MSYS* | CYGWIN*)
  # The trap this exists for: git emits D:/repos/x while the shell holds
  # /d/repos/x, and a comparison that treats them as different paths reports
  # every real worktree as not-a-worktree.
  assert_eq "path-key reconciles the MSYS and Windows drive forms" \
    "$(bash "$ENGINE" --path-key "D:/repos/x")" "$(bash "$ENGINE" --path-key "/d/repos/x")"
  ;;
*)
  # Off Windows /d/repos/x is a legitimate POSIX path and must NOT be folded.
  assert_eq "path-key leaves a POSIX /d/ path alone off Windows" \
    "/d/repos/x" "$(bash "$ENGINE" --path-key "/d/repos/x")"
  ;;
esac

# --------------------------------------------------------------------------
# Multi-commit squash-merge, and the same after the base advances
# --------------------------------------------------------------------------

W="$(mkfixture)"
WT_SQUASH="$TEST_TMPDIR/wt-squash"
git -C "$W" worktree add -q -b feat-squash "$WT_SQUASH" main >/dev/null 2>&1
commit_in "$WT_SQUASH" a.txt "alpha" "add a"
commit_in "$WT_SQUASH" b.txt "beta" "add b"
git -C "$W" merge --squash feat-squash >/dev/null 2>&1
git -C "$W" commit -qm "squash feat-squash" >/dev/null 2>&1
git -C "$W" push -q origin main >/dev/null 2>&1

OUT="$(bash "$ENGINE" --repo-dir "$W" --no-peers)"
R="$(row "$OUT" "wt-squash")"
assert_eq "squash: two commits are unpushed" "2" "$(col "$R" $C_UNPUSHED)"
assert_eq "squash: classified landed" "yes" "$(col "$R" $C_LANDED)"
assert_eq "squash: seen by the range patch-id, which per-commit cannot see" \
  "range-patchid" "$(col "$R" $C_METHOD)"
assert_eq "squash: risk is landed, not stranded" "landed" "$(col "$R" $C_RISK)"

# The base advances over a path the branch touched — the exact condition that
# decays a path-scoped two-dot verdict to a false `no`.
commit_in "$W" a.txt "alpha
gamma" "base advances over a.txt"
git -C "$W" push -q origin main >/dev/null 2>&1

OUT="$(bash "$ENGINE" --repo-dir "$W" --no-peers)"
R="$(row "$OUT" "wt-squash")"
assert_eq "squash: still landed after the base advances" "yes" "$(col "$R" $C_LANDED)"
assert_eq "squash: still by range patch-id after the base advances" \
  "range-patchid" "$(col "$R" $C_METHOD)"

# --------------------------------------------------------------------------
# Negative control — a genuinely unmerged branch is NOT landed
# --------------------------------------------------------------------------

W="$(mkfixture)"
WT_STRANDED="$TEST_TMPDIR/wt-stranded"
git -C "$W" worktree add -q -b feat-stranded "$WT_STRANDED" main >/dev/null 2>&1
commit_in "$WT_STRANDED" only-here.txt "unique work" "add unique work"

OUT="$(bash "$ENGINE" --repo-dir "$W" --no-peers)"
R="$(row "$OUT" "wt-stranded")"
assert_eq "negative control: not landed" "no" "$(col "$R" $C_LANDED)"
assert_eq "negative control: risk is STRANDED" "STRANDED" "$(col "$R" $C_RISK)"

# Same fixture, with the branch named as a merged PR head ref: landed=no plus a
# merged PR is a superseded draft, a different disposition from stranded.
MERGED_REFS="$TEST_TMPDIR/merged-refs.txt"
printf 'feat-stranded\n' >"$MERGED_REFS"
OUT="$(bash "$ENGINE" --repo-dir "$W" --no-peers --merged-refs-file "$MERGED_REFS")"
R="$(row "$OUT" "wt-stranded")"
assert_eq "merged head ref reclassifies landed=no as superseded" \
  "superseded" "$(col "$R" $C_RISK)"

# The main checkout itself has nothing unpushed and must not be classified.
R="$(row "$OUT" "$(basename "$W")")"
assert_eq "nothing unpushed skips the landed computation" "n/a" "$(col "$R" $C_LANDED)"
assert_eq "nothing unpushed is ok" "ok" "$(col "$R" $C_RISK)"

# --------------------------------------------------------------------------
# A branch whose only unique work is a DELETION is not landed
# --------------------------------------------------------------------------

# The case that retired the direction test. `git diff base..HEAD` reports
# deletions both for a branch that is merely BEHIND the base and for a branch
# whose own unique work IS a deletion — the numstat rows are identical. So
# "additions are zero" proved nothing, and this fixture is what it classified as
# landed while the deletion commit existed nowhere else.
W="$(mkfixture)"
WT_DEL="$TEST_TMPDIR/wt-delete-only"
commit_in "$W" doomed.txt "keep
remove" "base adds doomed.txt"
git -C "$W" push -q origin main >/dev/null 2>&1
git -C "$W" worktree add -q -b feat-delete-only "$WT_DEL" main >/dev/null 2>&1
commit_in "$WT_DEL" doomed.txt "keep" "branch deletes a line the base still has"

OUT="$(bash "$ENGINE" --repo-dir "$W" --no-peers)"
R="$(row "$OUT" "wt-delete-only")"
assert_eq "a delete-only branch is NOT landed" "no" "$(col "$R" $C_LANDED)"
assert_eq "a delete-only branch is STRANDED" "STRANDED" "$(col "$R" $C_RISK)"

# --------------------------------------------------------------------------
# Behind the base is no longer proven landed by content alone
# --------------------------------------------------------------------------

# The base takes the branch's content AND more of the same file, so its commit is
# a different patch — no patch-id matches, and the two-dot is non-empty. With the
# direction test retired this reports `no`: over-cautious by exactly one
# confirmation prompt, and indistinguishable-from-data-loss if it said otherwise.
# The genuinely landed shapes are caught by the range patch-id above instead.
W="$(mkfixture)"
WT_BEHIND="$TEST_TMPDIR/wt-behind"
git -C "$W" worktree add -q -b feat-behind "$WT_BEHIND" main >/dev/null 2>&1
commit_in "$WT_BEHIND" shared.txt "line1
line2" "branch adds shared.txt"
commit_in "$W" shared.txt "line1
line2
line3
line4" "base takes it and adds more"
git -C "$W" push -q origin main >/dev/null 2>&1

OUT="$(bash "$ENGINE" --repo-dir "$W" --no-peers)"
R="$(row "$OUT" "wt-behind")"
assert_eq "merely-behind is not claimed landed without proof" "no" "$(col "$R" $C_LANDED)"
assert_eq "and the method names the test that produced it" "two-dot" "$(col "$R" $C_METHOD)"

# --------------------------------------------------------------------------
# Whitespace-only difference is not sameness
# --------------------------------------------------------------------------

# `git patch-id` strips whitespace before hashing, so `a b` and `ab` hash
# identically under the default and `--stable` — measured on git 2.54, both
# `7ad14294…`. A branch whose unique change differs from the base's only in
# whitespace would classify as landed. `--verbatim` is what separates them.
W="$(mkfixture)"
WT_WS="$TEST_TMPDIR/wt-whitespace"
commit_in "$W" ws.txt "x" "base seeds ws.txt"
git -C "$W" push -q origin main >/dev/null 2>&1
git -C "$W" worktree add -q -b feat-whitespace "$WT_WS" main >/dev/null 2>&1
commit_in "$WT_WS" ws.txt "a b" "branch writes spaced content"
commit_in "$W" ws.txt "ab" "base writes unspaced content"
git -C "$W" push -q origin main >/dev/null 2>&1

OUT="$(bash "$ENGINE" --repo-dir "$W" --no-peers)"
R="$(row "$OUT" "wt-whitespace")"
assert_eq "a whitespace-only difference is not landed" "no" "$(col "$R" $C_LANDED)"

# --------------------------------------------------------------------------
# Path spellings the two-dot fallback must not be defeated by
# --------------------------------------------------------------------------

# The fallback used to compare two diff invocations' TEXT output, and the two did
# not agree on how a path is spelled. `--name-only` octal-escapes a non-ASCII byte
# under git's default `core.quotePath=true`; the numstat side was pinned to false.
# The join then matched nothing, and matching nothing is the same shape as
# "identical to the base" — an unproven `landed=yes` on a commit that exists
# nowhere else. Pinning quotepath on both sides closed that byte class and left
# another, since git escapes `"`, `\` and control characters regardless of the
# setting. Handing the paths back to git as literal pathspecs closes the class.
#
# Three spellings, all of which must classify as STRANDED: a non-ASCII name, a
# name containing a glob metacharacter (which must be matched literally, not as a
# pattern), and a name beginning with `:` (which must not be read as pathspec
# magic).
W="$(mkfixture)"
WT_PATHS="$TEST_TMPDIR/wt-odd-paths"
git -C "$W" worktree add -q -b feat-odd-paths "$WT_PATHS" main >/dev/null 2>&1
printf 'unique content\n' >"$WT_PATHS/café.txt"
printf 'unique content\n' >"$WT_PATHS/star[1].txt"
git -C "$WT_PATHS" add -A >/dev/null 2>&1
git -C "$WT_PATHS" commit -qm "branch adds oddly-named files" >/dev/null 2>&1

OUT="$(bash "$ENGINE" --repo-dir "$W" --no-peers)"
R="$(row "$OUT" "wt-odd-paths")"
assert_eq "a non-ASCII path does not defeat the fallback" "no" "$(col "$R" $C_LANDED)"
assert_eq "and the row is STRANDED, not landed" "STRANDED" "$(col "$R" $C_RISK)"
assert_not_contains "the verdict is not the vacuous empty-match one" \
  "$(col "$R" $C_METHOD)" "two-dot-empty"

# --------------------------------------------------------------------------
# An incomplete patch-id set yields no verdict
# --------------------------------------------------------------------------

# An empty commit produces no patch, so it is invisible to patch-id and the id
# set silently under-represents the branch. Any affirmative verdict over that set
# would be a statement about the commits that happened to hash, not about the
# branch.
W="$(mkfixture)"
WT_EMPTY="$TEST_TMPDIR/wt-empty-commit"
git -C "$W" worktree add -q -b feat-empty "$WT_EMPTY" main >/dev/null 2>&1
commit_in "$WT_EMPTY" e.txt "content" "branch adds content"
git -C "$WT_EMPTY" commit -q --allow-empty -m "marker" >/dev/null 2>&1
git -C "$W" merge --squash feat-empty >/dev/null 2>&1
git -C "$W" commit -qm "squash feat-empty" >/dev/null 2>&1
git -C "$W" push -q origin main >/dev/null 2>&1

OUT="$(bash "$ENGINE" --repo-dir "$W" --no-peers)"
R="$(row "$OUT" "wt-empty-commit")"
assert_eq "an empty commit makes the id set incomplete, so no verdict" "?" "$(col "$R" $C_LANDED)"
assert_contains "and the reason names the incompleteness" \
  "$(col "$R" $C_REASON)" "patchid-set-incomplete"

# --------------------------------------------------------------------------
# An ambiguous merge base yields no verdict
# --------------------------------------------------------------------------

# A criss-cross history has more than one merge base. Picking one silently means
# testing against a base the work did not diverge at, which can produce a
# favourable verdict for content that is not there.
W="$(mkfixture)"
git -C "$W" checkout -q -b sideA main >/dev/null 2>&1
commit_in "$W" a.txt "a" "A"
git -C "$W" checkout -q -b sideB main >/dev/null 2>&1
commit_in "$W" b.txt "b" "B"
git -C "$W" checkout -q -b crossA sideA >/dev/null 2>&1
git -C "$W" merge -q --no-edit sideB >/dev/null 2>&1
git -C "$W" checkout -q -b crossB sideB >/dev/null 2>&1
git -C "$W" merge -q --no-edit sideA >/dev/null 2>&1
git -C "$W" checkout -q main >/dev/null 2>&1
git -C "$W" branch -f main crossA >/dev/null 2>&1
git -C "$W" push -q -f origin main >/dev/null 2>&1
WT_CROSS="$TEST_TMPDIR/wt-crisscross"
git -C "$W" worktree add -q "$WT_CROSS" crossB >/dev/null 2>&1
commit_in "$WT_CROSS" unique.txt "only here" "branch-only work"

OUT="$(bash "$ENGINE" --repo-dir "$W" --no-peers)"
R="$(row "$OUT" "wt-crisscross")"
if [[ "$(col "$R" $C_LANDED)" == "yes" ]]; then
  fail "a criss-cross history never yields an affirmative verdict" "no or ?" "yes"
else
  pass "a criss-cross history never yields an affirmative verdict"
fi

# --------------------------------------------------------------------------
# EOL renormalization
# --------------------------------------------------------------------------

# The base carries the same content with CRLF endings; the branch has LF.
#
# This is the documented COST of `--verbatim`, asserted rather than left to be
# discovered. The whitespace-insensitive default would call these identical — and
# would equally call `a b` and `ab` identical, which is a false `yes` in the
# direction that destroys work. Trading the EOL tolerance for that separation is
# the deliberate choice: this branch reports `no`, the operator gets one
# confirmation prompt, and nothing is lost. Reverse the trade and the prompt is
# replaced by a silent deletion.
W="$(mkfixture)"
WT_EOL="$TEST_TMPDIR/wt-eol"
git -C "$W" worktree add -q -b feat-eol "$WT_EOL" main >/dev/null 2>&1
printf 'alpha\nbeta\n' >"$WT_EOL/eol.txt"
git -C "$WT_EOL" add eol.txt >/dev/null 2>&1
git -C "$WT_EOL" commit -qm "branch adds eol.txt with LF" >/dev/null 2>&1
printf 'alpha\r\nbeta\r\n' >"$W/eol.txt"
git -C "$W" add eol.txt >/dev/null 2>&1
git -C "$W" commit -qm "base adds eol.txt with CRLF" >/dev/null 2>&1
git -C "$W" push -q origin main >/dev/null 2>&1

OUT="$(bash "$ENGINE" --repo-dir "$W" --no-peers)"
R="$(row "$OUT" "wt-eol")"
assert_eq "an EOL-only difference is reported unproven, not landed" "no" "$(col "$R" $C_LANDED)"

# --------------------------------------------------------------------------
# Detached HEAD, and peers
# --------------------------------------------------------------------------

W="$(mkfixture)"
WT_DETACHED="$TEST_TMPDIR/wt-detached"
git -C "$W" worktree add -q --detach "$WT_DETACHED" main >/dev/null 2>&1
commit_in "$WT_DETACHED" detached-work.txt "no branch holds this" "detached commit"

OUT="$(bash "$ENGINE" --repo-dir "$W" --no-peers)"
R="$(row "$OUT" "wt-detached")"
assert_eq "detached HEAD is reported as such" "(detached)" "$(col "$R" $C_BRANCH)"
assert_eq "detached HEAD reports THIS worktree's own commit" "1" "$(col "$R" $C_UNPUSHED)"
assert_eq "detached HEAD with unlanded work is STRANDED" "STRANDED" "$(col "$R" $C_RISK)"

# A second detached worktree at the same commit: the commits are held elsewhere.
WT_PEER="$TEST_TMPDIR/wt-peer"
DETACHED_OID="$(git -C "$WT_DETACHED" rev-parse HEAD)"
git -C "$W" worktree add -q --detach "$WT_PEER" "$DETACHED_OID" >/dev/null 2>&1
OUT="$(bash "$ENGINE" --repo-dir "$W")"
R="$(row "$OUT" "wt-detached")"
assert_contains "peer worktree holding the same commits is named" \
  "$(col "$R" $C_PEERS)" "wt-peer"

# --------------------------------------------------------------------------
# Not a worktree root
# --------------------------------------------------------------------------

# An empty leftover directory inside a repository. Probed with `git -C` it
# reports the CONTAINING repository's clean state with a zero exit, which reads
# as a healthy worktree that is safe to remove.
HUSK="$W/husk-dir"
mkdir -p "$HUSK"
OUT="$(bash "$ENGINE" --worktree "$HUSK" --no-peers)"
R="$(row "$OUT" "husk-dir")"
assert_eq "a directory inside a repo is not a worktree root" "notgit" "$(col "$R" $C_RISK)"
assert_contains "notgit says why the naive probe is wrong" \
  "$(col "$R" $C_REASON)" "not-a-worktree-root"

case "$(uname -s 2>/dev/null || true)" in
MINGW* | MSYS* | CYGWIN*)
  HUSK_WIN="$(bash "$ENGINE" --path-key "$HUSK")"
  OUT="$(bash "$ENGINE" --worktree "$HUSK_WIN" --no-peers)"
  R="$(row "$OUT" "husk-dir")"
  assert_eq "notgit holds in the Windows drive-form spelling too" \
    "notgit" "$(col "$R" $C_RISK)"
  ;;
*)
  skip_case "Windows-form path pair — single path spelling on this platform"
  ;;
esac

# A bare-clone hub's own entry is the first row `git worktree list` emits and it
# carries no HEAD. It passes the work-tree-root probe, so without its own branch
# it would reach the landed computation and report a healthy hub as UNKNOWN.
BARE_HUB="$(mktemp -d "$TEST_TMPDIR/hubXXXXXX")/hub.bare"
git init -q --bare -b main "$BARE_HUB" >/dev/null 2>&1
OUT="$(bash "$ENGINE" --repo-dir "$BARE_HUB" --no-peers)"
R="$(row "$OUT" "hub.bare")"
assert_eq "a bare hub is reported as bare, not UNKNOWN" "bare" "$(col "$R" $C_RISK)"
assert_eq "a bare hub has no landed verdict to give" "n/a" "$(col "$R" $C_LANDED)"

OUT="$(bash "$ENGINE" --worktree "$TEST_TMPDIR/does-not-exist" --no-peers)"
R="$(row "$OUT" "does-not-exist")"
assert_eq "an absent path is notgit, never silently omitted" "notgit" "$(col "$R" $C_RISK)"

# --------------------------------------------------------------------------
# Degradation paths each carry a reason
# --------------------------------------------------------------------------

# No remote at all: no base resolves. The fail-closed rule makes this `?`, never
# `no` — and a guard must treat `?` exactly as it treats `no`.
NOREMOTE="$(mktemp -d "$TEST_TMPDIR/noremoteXXXXXX")"
git -C "$NOREMOTE" init -q -b main >/dev/null 2>&1
git -C "$NOREMOTE" config user.email t@t.t
git -C "$NOREMOTE" config user.name t
commit_in "$NOREMOTE" seed.txt "seed" "init"
OUT="$(bash "$ENGINE" --repo-dir "$NOREMOTE" --no-peers)"
R="$(row "$OUT" "$(basename "$NOREMOTE")")"
assert_eq "no resolvable base yields ? and never no" "?" "$(col "$R" $C_LANDED)"
assert_eq "no resolvable base is UNKNOWN, which a guard treats as stranded" \
  "UNKNOWN" "$(col "$R" $C_RISK)"
assert_contains "the degradation carries a reason" "$(col "$R" $C_REASON)" "no-base-ref"

# --------------------------------------------------------------------------
# A paused merge inflates the staged tree with the merge's own result
# --------------------------------------------------------------------------

W="$(mkfixture)"
WT_MERGE="$TEST_TMPDIR/wt-merge"
git -C "$W" worktree add -q -b feat-merge "$WT_MERGE" main >/dev/null 2>&1
commit_in "$WT_MERGE" conflict.txt "branch side" "branch edits conflict.txt"
commit_in "$W" conflict.txt "base side" "base edits conflict.txt"
git -C "$W" push -q origin main >/dev/null 2>&1
git -C "$WT_MERGE" merge origin/main >/dev/null 2>&1 || true

OUT="$(bash "$ENGINE" --repo-dir "$W" --no-peers)"
R="$(row "$OUT" "wt-merge")"
assert_eq "a paused merge is reported as in progress" "merge" "$(col "$R" $C_INPROGRESS)"
assert_eq "the conflicted files are counted apart from the staged tree" \
  "1" "$(col "$R" $C_CONFLICTED)"
assert_contains "the reason says the staged tree is recomputable" \
  "$(col "$R" $C_REASON)" "recomputable"

# --------------------------------------------------------------------------
# A truncated pass fails loudly
# --------------------------------------------------------------------------

# `source=/dev/null` scopes the analysis rather than silencing a finding: under
# LANDED_WORK_LIB the engine returns at its library seam, but shellcheck follows
# the file to its terminal `exit 0` and therefore reads everything after the
# source as unreachable. It cannot model a conditional early return in a sourced
# file, so the resolution is turned off for these two blocks only.
(
  LANDED_WORK_LIB=1
  export LANDED_WORK_LIB
  # shellcheck source=/dev/null
  . "$ENGINE"
  assert_row_count 3 3 || exit 1
  assert_row_count 3 2
  rc=$?
  [[ "$rc" -eq 5 ]]
) >/dev/null 2>&1
assert_exit "the row-count assertion fails with exit 5 on a short list" 0 "$?"

TRUNC_ERR="$(
  (
    LANDED_WORK_LIB=1
    export LANDED_WORK_LIB
    # shellcheck source=/dev/null
    . "$ENGINE"
    assert_row_count 3 2
  ) 2>&1 >/dev/null
)"
assert_contains "the short list says how short it was" "$TRUNC_ERR" "enumerated 3"

# --------------------------------------------------------------------------
# Contract surface
# --------------------------------------------------------------------------

bash "$ENGINE" --repo-dir "$TEST_TMPDIR" --no-peers >/dev/null 2>&1
assert_exit "a non-repository scope is an environment error" 4 "$?"

bash "$ENGINE" --nonsense >/dev/null 2>&1
assert_exit "an unknown flag is a usage error" 2 "$?"

bash "$ENGINE" --help >/dev/null 2>&1
assert_exit "--help exits 0" 0 "$?"

OUT="$(bash "$ENGINE" --repo-dir "$W" --no-peers)"
assert_eq "the header names every column" \
  "path	branch	head	unpushed	landed	method	base	inprogress	staged	unstaged	conflicted	untracked	peers	risk	reason" \
  "$(printf '%s' "$OUT" | head -n 1)"

# Every field is non-empty, so a `while IFS=$'\t' read` consumer — the shape the
# skill's own prose tells callers to use — sees the columns it names. Tab is IFS
# whitespace, so bash collapses a run of them and an empty field would shift every
# later column left. Asserted by reading a row the natural way and checking that
# the LAST column is the one it should be.
R="$(row "$OUT" "$(basename "$W")")"
unset _p _b _h _u _l _m _base _ip _st _un _cf _ut _pe _risk _reason
IFS=$'\t' read -r _p _b _h _u _l _m _base _ip _st _un _cf _ut _pe _risk _reason <<<"$R"
assert_eq "a tab-splitting consumer lands on the risk column" "ok" "$_risk"
assert_contains "and on the reason column" "$_reason" "nothing-unpushed"
assert_not_contains "no field is empty" "	$R	" "		"

EXPECTED_ROWS="$(git -C "$W" worktree list --porcelain | grep -c '^worktree ')"
ACTUAL_ROWS="$(printf '%s\n' "$OUT" | tail -n +2 | grep -c .)"
assert_eq "one row per registered worktree" "$EXPECTED_ROWS" "$ACTUAL_ROWS"

[[ $FAILED -eq 0 ]] || exit 1
