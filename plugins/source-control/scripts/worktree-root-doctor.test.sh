#!/usr/bin/env bash
# Regression tests for worktree-root-doctor.sh (#2612). Black-box: build
# throwaway git fixtures with an ISOLATED global config (GIT_CONFIG_GLOBAL +
# GIT_CONFIG_NOSYSTEM, HOME pinned inside the sandbox) and assert on the
# doctor's findings lines and exit codes. Every fixture reproduces one of the
# silent-failure classes the doctor exists to make loud. No network.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCTOR="$SCRIPT_DIR/worktree-root-doctor.sh"

FAILED=0
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

command -v git >/dev/null 2>&1 || skip_suite "git not available"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

HOME_DIR="$TEST_TMPDIR/home"
mkdir -p "$HOME_DIR"

# run <global-config-file> <repo-dir-or-empty> [extra doctor args...]
# One doctor invocation against a pinned global config; sets RC and OUT.
# XDG_CONFIG_HOME is cleared so ~/.config/git/config on the host machine can
# never leak a real includeIf into a fixture's report.
RC=0
OUT=""
run() {
  local gcfg="$1" repo="$2"
  shift 2
  local -a args=()
  [[ -n "$repo" ]] && args=(--repo-dir "$repo")
  OUT=$(GIT_CONFIG_GLOBAL="$gcfg" GIT_CONFIG_NOSYSTEM=1 HOME="$HOME_DIR" \
    XDG_CONFIG_HOME="$TEST_TMPDIR/xdg-empty" \
    bash "$DOCTOR" "${args[@]}" "$@" 2>&1)
  RC=$?
}

mkrepo() {
  local repo
  repo="$(mktemp -d "$TEST_TMPDIR/${1:-repo}XXXXXX")"
  GIT_CONFIG_GLOBAL="$TEST_TMPDIR/empty-gitconfig" GIT_CONFIG_NOSYSTEM=1 \
    git -C "$repo" init -q -b main >/dev/null 2>&1
  printf '%s' "$repo"
}
: >"$TEST_TMPDIR/empty-gitconfig"

EMPTY_GCFG="$TEST_TMPDIR/empty-gitconfig"

# --- CLI contract ---------------------------------------------------------------

help_out=$(bash "$DOCTOR" --help 2>&1)
assert_exit "--help exits 0" 0 "$?"
assert_contains "--help documents the exit taxonomy" "$help_out" "at least one warn/error"

bash "$DOCTOR" --frobnicate >/dev/null 2>&1
assert_exit "an unknown argument is a usage error (exit 2)" 2 "$?"

bash "$DOCTOR" --repo-dir >/dev/null 2>&1
assert_exit "--repo-dir without a value is a usage error (exit 2)" 2 "$?"

# --- The gate: an unreadable repository is the whole report ----------------------

NOTREPO="$(mktemp -d "$TEST_TMPDIR/notrepoXXXXXX")"
run "$EMPTY_GCFG" "$NOTREPO"
assert_exit "a non-repository exits 1" 1 "$RC"
assert_contains "the gate finding names the silent global-fallback hazard" "$OUT" \
  "silently returns the GLOBAL value"
assert_contains "the gate finding names safe.directory as a cause" "$OUT" "safe.directory"

# --- Unset key: informational, exit 0 --------------------------------------------

REPO="$(mkrepo plain)"
run "$EMPTY_GCFG" "$REPO"
assert_exit "a clean repo with no key exits 0" 0 "$RC"
assert_contains "an unset key is reported as info, with the set command" "$OUT" \
  "melodic.worktreeroot is unset"
assert_contains "the unset finding names the fallthrough rungs" "$OUT" "worktree_root plugin option"

# --- A set key: named with its origin, exit 0 ------------------------------------

KEYED="$(mkrepo keyed)"
GIT_CONFIG_GLOBAL="$EMPTY_GCFG" GIT_CONFIG_NOSYSTEM=1 \
  git -C "$KEYED" config melodic.worktreeroot "$TEST_TMPDIR/wt-root"
run "$EMPTY_GCFG" "$KEYED"
assert_exit "a conforming keyed repo exits 0" 0 "$RC"
assert_contains "the winning value is reported ok with its value" "$OUT" \
  "melodic.worktreeroot = $TEST_TMPDIR/wt-root"
assert_contains "the winner names the file that supplied it" "$OUT" "supplied by"

# --- includeIf attribution: the winner names WHICH condition fired ---------------
# The include is anchored by repository NAME (**/<name>/.git) so the pattern is
# canonicalization-proof across platforms; /i keeps it firing on Windows.

INCREPO_PARENT="$(mktemp -d "$TEST_TMPDIR/incparentXXXXXX")"
INCREPO="$INCREPO_PARENT/increpo-fixture"
mkdir -p "$INCREPO"
GIT_CONFIG_GLOBAL="$EMPTY_GCFG" GIT_CONFIG_NOSYSTEM=1 \
  git -C "$INCREPO" init -q -b main >/dev/null 2>&1
INC_FILE="$TEST_TMPDIR/identity-work.inc"
printf '[melodic]\n\tworktreeroot = %s\n' "$TEST_TMPDIR/work-root" >"$INC_FILE"
INC_GCFG="$TEST_TMPDIR/gitconfig-include"
printf '[includeIf "gitdir/i:**/increpo-fixture/.git"]\n\tpath = %s\n' "$INC_FILE" >"$INC_GCFG"
run "$INC_GCFG" "$INCREPO"
assert_exit "an include-supplied root is a clean report (exit 0)" 0 "$RC"
assert_contains "the winner is attributed to its includeIf condition" "$OUT" \
  'supplied by includeIf "gitdir/i:**/increpo-fixture/.git"'
assert_contains "the fired include is reported as contributing" "$OUT" \
  "target file contributed values here"
assert_contains "the scoped-read divergence is surfaced" "$OUT" \
  "never pass a scope flag without --includes"

# In an UNRELATED repo the same condition is declared but never fires — the
# doctor must say so rather than leaving declared and fired indistinguishable.
run "$INC_GCFG" "$REPO"
assert_contains "an unfired condition is reported as not contributing" "$OUT" \
  "did not contribute values here"

# --- A declared include pointing at a nonexistent file (rc=0 upstream, silent) ---

GHOST_GCFG="$TEST_TMPDIR/gitconfig-ghost"
printf '[includeIf "gitdir/i:**/increpo-fixture/.git"]\n\tpath = %s\n' \
  "$TEST_TMPDIR/no-such-file.inc" >"$GHOST_GCFG"
run "$GHOST_GCFG" "$INCREPO"
assert_exit "a missing include file is a finding (exit 1)" 1 "$RC"
assert_contains "the missing file is named, with the silent-skip diagnosis" "$OUT" \
  "points at a nonexistent file"

# --- An unrecognized condition keyword (typo class, silent upstream) --------------

TYPO_GCFG="$TEST_TMPDIR/gitconfig-typo"
printf '[includeIf "gitdirs:/x/"]\n\tpath = %s\n' "$INC_FILE" >"$TYPO_GCFG"
run "$TYPO_GCFG" "$REPO"
assert_exit "an unknown condition keyword is a finding (exit 1)" 1 "$RC"
assert_contains "the unknown keyword is called out as silently skipped" "$OUT" \
  "not a keyword this git recognizes"

# --- A worktree:/worktree-i: condition on a pre-2.56 git --------------------------

WT_GCFG="$TEST_TMPDIR/gitconfig-worktreecond"
printf '[includeIf "worktree:/x/"]\n\tpath = %s\n' "$INC_FILE" >"$WT_GCFG"
run "$WT_GCFG" "$REPO"
if [[ "$(git --version)" =~ ([0-9]+)\.([0-9]+) ]] &&
  ((BASH_REMATCH[1] * 100 + BASH_REMATCH[2] < 256)); then
  assert_exit "a worktree: condition on an older git is a finding (exit 1)" 1 "$RC"
  assert_contains "the version floor is named" "$OUT" "needs git >= 2.56"
else
  skip_case "worktree: version-floor warning needs a pre-2.56 git"
fi

# --- Parse order IS precedence: a plain value after an include-supplied one ------

SHADOW_GCFG="$TEST_TMPDIR/gitconfig-shadow"
{
  printf '[includeIf "gitdir/i:**/increpo-fixture/.git"]\n\tpath = %s\n' "$INC_FILE"
  printf '[melodic]\n\tworktreeroot = %s\n' "$TEST_TMPDIR/machine-default"
} >"$SHADOW_GCFG"
run "$SHADOW_GCFG" "$INCREPO"
assert_exit "a plain value shadowing an include is a finding (exit 1)" 1 "$RC"
assert_contains "the shadow warning names parse order as the precedence rule" "$OUT" \
  "precedence is parse order, not specificity"
assert_contains "the shadow warning names the remedy (move the default up)" "$OUT" \
  "ABOVE the includeIf block"

# The correct layering — plain default FIRST, include after — is a clean report.
LAYERED_GCFG="$TEST_TMPDIR/gitconfig-layered"
{
  printf '[melodic]\n\tworktreeroot = %s\n' "$TEST_TMPDIR/machine-default"
  printf '[includeIf "gitdir/i:**/increpo-fixture/.git"]\n\tpath = %s\n' "$INC_FILE"
} >"$LAYERED_GCFG"
run "$LAYERED_GCFG" "$INCREPO"
assert_exit "the correct layering is a clean report (exit 0)" 0 "$RC"
assert_contains "the include-supplied winner is reported as working layering" "$OUT" \
  "the layering is working"
assert_contains "the layered winner is the include's value" "$OUT" \
  "melodic.worktreeroot = $TEST_TMPDIR/work-root"

# --- The root itself must not sit inside a working tree --------------------------

NESTED_ROOT_REPO="$(mkrepo nestroot)"
GIT_CONFIG_GLOBAL="$EMPTY_GCFG" GIT_CONFIG_NOSYSTEM=1 \
  git -C "$NESTED_ROOT_REPO" config melodic.worktreeroot "$NESTED_ROOT_REPO/worktrees"
mkdir -p "$NESTED_ROOT_REPO/worktrees"
run "$EMPTY_GCFG" "$NESTED_ROOT_REPO"
assert_exit "a root inside a working tree is a finding (exit 1)" 1 "$RC"
assert_contains "the nested root names the invariant it violates" "$OUT" \
  "INSIDE a git working tree"

# --- Identity partials: user.email in an include without user.signingkey ---------

IDREPO_PARENT="$(mktemp -d "$TEST_TMPDIR/idparentXXXXXX")"
IDREPO="$IDREPO_PARENT/identity-fixture"
mkdir -p "$IDREPO"
GIT_CONFIG_GLOBAL="$EMPTY_GCFG" GIT_CONFIG_NOSYSTEM=1 \
  git -C "$IDREPO" init -q -b main >/dev/null 2>&1
PARTIAL_INC="$TEST_TMPDIR/identity-partial.inc"
printf '[user]\n\temail = work@example.com\n' >"$PARTIAL_INC"
PARTIAL_GCFG="$TEST_TMPDIR/gitconfig-partial"
{
  printf '[user]\n\tsigningkey = ~/.ssh/personal.pub\n'
  printf '[includeIf "gitdir/i:**/identity-fixture/.git"]\n\tpath = %s\n' "$PARTIAL_INC"
} >"$PARTIAL_GCFG"
run "$PARTIAL_GCFG" "$IDREPO"
assert_exit "an identity partial is a finding (exit 1)" 1 "$RC"
assert_contains "the partial names the leaking key and the verifies-Good trap" "$OUT" \
  "sets user.email but not user.signingkey"

# A COMPLETE identity include raises no partial warning.
FULL_INC="$TEST_TMPDIR/identity-full.inc"
printf '[user]\n\temail = work@example.com\n\tsigningkey = ~/.ssh/work.pub\n' >"$FULL_INC"
FULL_GCFG="$TEST_TMPDIR/gitconfig-full"
{
  printf '[user]\n\tsigningkey = ~/.ssh/personal.pub\n'
  printf '[includeIf "gitdir/i:**/identity-fixture/.git"]\n\tpath = %s\n' "$FULL_INC"
} >"$FULL_GCFG"
run "$FULL_GCFG" "$IDREPO"
assert_not_contains "a complete identity include is not flagged as partial" "$OUT" \
  "sets user.email but not user.signingkey"

# --- A linked worktree classifies with its repository -----------------------------

WTREPO="$(mkrepo wthost)"
GIT_CONFIG_GLOBAL="$EMPTY_GCFG" GIT_CONFIG_NOSYSTEM=1 git -C "$WTREPO" config user.email t@t.t
GIT_CONFIG_GLOBAL="$EMPTY_GCFG" GIT_CONFIG_NOSYSTEM=1 git -C "$WTREPO" config user.name t
GIT_CONFIG_GLOBAL="$EMPTY_GCFG" GIT_CONFIG_NOSYSTEM=1 git -C "$WTREPO" config commit.gpgsign false
printf 'seed\n' >"$WTREPO/README.md"
GIT_CONFIG_GLOBAL="$EMPTY_GCFG" GIT_CONFIG_NOSYSTEM=1 git -C "$WTREPO" add README.md >/dev/null 2>&1
GIT_CONFIG_GLOBAL="$EMPTY_GCFG" GIT_CONFIG_NOSYSTEM=1 git -C "$WTREPO" commit -qm init >/dev/null 2>&1
LINKED="$TEST_TMPDIR/linked-wt"
if GIT_CONFIG_GLOBAL="$EMPTY_GCFG" GIT_CONFIG_NOSYSTEM=1 \
  git -C "$WTREPO" worktree add -q "$LINKED" -b feat/doctor >/dev/null 2>&1; then
  run "$EMPTY_GCFG" "$LINKED"
  assert_contains "a linked worktree's classification rule is surfaced" "$OUT" \
    "classify this worktree WITH its repository"
else
  skip_case "worktree add unavailable for the linked-worktree note fixture"
fi

# --- Standing notes are always present ---------------------------------------------

run "$EMPTY_GCFG" "$REPO"
assert_contains "the un-probe-able classes are reported as standing notes" "$OUT" \
  "not machine-checked here"

[[ $FAILED -eq 0 ]] || exit 1
