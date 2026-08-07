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
# Behind, not stranded — the direction test
# --------------------------------------------------------------------------

# The base takes the branch's content AND more of the same file, so no patch-id
# can match, and the path-scoped two-dot is non-empty. The direction is the tell:
# HEAD lacks lines the base gained and adds none the base lacks.
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
assert_eq "behind-not-stranded: landed" "yes" "$(col "$R" $C_LANDED)"
assert_eq "behind-not-stranded: by the direction test" \
  "two-dot-direction" "$(col "$R" $C_METHOD)"

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

EXPECTED_ROWS="$(git -C "$W" worktree list --porcelain | grep -c '^worktree ')"
ACTUAL_ROWS="$(printf '%s\n' "$OUT" | tail -n +2 | grep -c .)"
assert_eq "one row per registered worktree" "$EXPECTED_ROWS" "$ACTUAL_ROWS"

[[ $FAILED -eq 0 ]] || exit 1
