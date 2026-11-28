#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCTOR="$SCRIPT_DIR/worktree-root-doctor.sh"

FAILED=0
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

command -v git >/dev/null 2>&1 || skip_suite "git not available"

TEST_TMPDIR="$(native_mktemp_dir)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

HOME_DIR="$TEST_TMPDIR/home"
mkdir -p "$HOME_DIR"

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
  fgit -C "$repo" init -q -b main >/dev/null 2>&1
  printf '%s' "$repo"
}
EMPTY_GCFG="$TEST_TMPDIR/empty-gitconfig"
: >"$EMPTY_GCFG"

fgit() { GIT_CONFIG_GLOBAL="$EMPTY_GCFG" GIT_CONFIG_NOSYSTEM=1 git "$@"; }

help_out=$(bash "$DOCTOR" --help 2>&1)
assert_exit "--help exits 0" 0 "$?"
assert_contains "--help documents the exit taxonomy" "$help_out" "at least one warn/error"
assert_contains "--help includes the usage-error exit code" \
  "$help_out" "2  usage error"

bash "$DOCTOR" --frobnicate >/dev/null 2>&1
assert_exit "an unknown argument is a usage error (exit 2)" 2 "$?"

bash "$DOCTOR" --repo-dir >/dev/null 2>&1
assert_exit "--repo-dir without a value is a usage error (exit 2)" 2 "$?"

NOTREPO="$(mktemp -d "$TEST_TMPDIR/notrepoXXXXXX")"
run "$EMPTY_GCFG" "$NOTREPO"
assert_exit "a non-repository exits 1" 1 "$RC"
assert_contains "the gate finding names the silent global-fallback hazard" "$OUT" \
  "silently returns the GLOBAL value"
assert_contains "the gate finding names safe.directory as a cause" "$OUT" "safe.directory"

REPO="$(mkrepo plain)"
run "$EMPTY_GCFG" "$REPO"
assert_exit "a clean repo with no key exits 0" 0 "$RC"
assert_contains "an unset key is reported as info, with the set command" "$OUT" \
  "worktreeroot.path is unset"
assert_contains "the unset finding names the fallthrough rungs" "$OUT" "worktree_root plugin option"

KEYED="$(mkrepo keyed)"
fgit -C "$KEYED" config worktreeroot.path "$TEST_TMPDIR/wt-root"
run "$EMPTY_GCFG" "$KEYED"
assert_exit "a conforming keyed repo exits 0" 0 "$RC"
assert_contains "the winning value is reported ok with its value" "$OUT" \
  "worktreeroot.path = $TEST_TMPDIR/wt-root"
assert_contains "the winner names the file that supplied it" "$OUT" "supplied by"

LEGACY_KEYED="$(mkrepo legacykeyed)"
fgit -C "$LEGACY_KEYED" config melodic.worktreeroot "$TEST_TMPDIR/wt-root-legacy"
run "$EMPTY_GCFG" "$LEGACY_KEYED"
assert_exit "a retired-alias repo exits 0" 0 "$RC"
assert_contains "the rewritten current key is reported ok" "$OUT" \
  "worktreeroot.path = $TEST_TMPDIR/wt-root-legacy"
assert_not_contains "the retired alias is not named in the report" "$OUT" \
  "melodic.worktreeroot ="
legacy_now=$(fgit -C "$LEGACY_KEYED" config --get --type=path worktreeroot.path)
legacy_old_rc=0
fgit -C "$LEGACY_KEYED" config --get melodic.worktreeroot >/dev/null 2>&1 || legacy_old_rc=$?
assert_eq "the doctor rewrote worktreeroot.path at the origin" \
  "$TEST_TMPDIR/wt-root-legacy" "$legacy_now"
assert_exit "the retired alias is unset after the doctor run" 1 "$legacy_old_rc"

SPACE_ROOT="$TEST_TMPDIR/wt root space"
mkdir -p "$SPACE_ROOT"
SPACE_KEYED="$(mkrepo spacekeyed)"
fgit -C "$SPACE_KEYED" config melodic.worktreeroot "$SPACE_ROOT"
run "$EMPTY_GCFG" "$SPACE_KEYED"
assert_exit "a space-bearing retired alias exits 0" 0 "$RC"
space_now=$(fgit -C "$SPACE_KEYED" config --get --type=path worktreeroot.path)
assert_eq "a space-bearing rewrite keeps the whole path" "$SPACE_ROOT" "$space_now"

BOTH_KEYED="$(mkrepo bothkeyed)"
fgit -C "$BOTH_KEYED" config worktreeroot.path "$TEST_TMPDIR/wt-root-new"
fgit -C "$BOTH_KEYED" config melodic.worktreeroot "$TEST_TMPDIR/wt-root-old"
run "$EMPTY_GCFG" "$BOTH_KEYED"
assert_exit "both keys set exits 0" 0 "$RC"
assert_contains "the current key wins when both are set" "$OUT" \
  "worktreeroot.path = $TEST_TMPDIR/wt-root-new"
assert_not_contains "the outranked retired value is not the ok line" "$OUT" \
  "melodic.worktreeroot = $TEST_TMPDIR/wt-root-old"
both_old_rc=0
fgit -C "$BOTH_KEYED" config --get melodic.worktreeroot >/dev/null 2>&1 || both_old_rc=$?
assert_exit "a leftover retired alias is unset when the current key already answers" 1 "$both_old_rc"

INCREPO_PARENT="$(mktemp -d "$TEST_TMPDIR/incparentXXXXXX")"
INCREPO="$INCREPO_PARENT/increpo-fixture"
mkdir -p "$INCREPO"
fgit -C "$INCREPO" init -q -b main >/dev/null 2>&1
INC_FILE="$TEST_TMPDIR/identity-work.inc"
printf '[worktreeroot]\n\tpath = %s\n' "$TEST_TMPDIR/work-root" >"$INC_FILE"
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

run "$INC_GCFG" "$REPO"
assert_contains "an unfired condition is reported as not contributing" "$OUT" \
  "did not contribute values here"

GHOST_GCFG="$TEST_TMPDIR/gitconfig-ghost"
printf '[includeIf "gitdir/i:**/increpo-fixture/.git"]\n\tpath = %s\n' \
  "$TEST_TMPDIR/no-such-file.inc" >"$GHOST_GCFG"
run "$GHOST_GCFG" "$INCREPO"
assert_exit "a missing include file is a finding (exit 1)" 1 "$RC"
assert_contains "the missing file is named, with the silent-skip diagnosis" "$OUT" \
  "points at a nonexistent file"

TYPO_GCFG="$TEST_TMPDIR/gitconfig-typo"
printf '[includeIf "gitdirs:/x/"]\n\tpath = %s\n' "$INC_FILE" >"$TYPO_GCFG"
run "$TYPO_GCFG" "$REPO"
assert_exit "an unknown condition keyword is a finding (exit 1)" 1 "$RC"
assert_contains "the unknown keyword is called out as silently skipped" "$OUT" \
  "not a keyword this git recognizes"

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

SHADOW_GCFG="$TEST_TMPDIR/gitconfig-shadow"
{
  printf '[includeIf "gitdir/i:**/increpo-fixture/.git"]\n\tpath = %s\n' "$INC_FILE"
  printf '[worktreeroot]\n\tpath = %s\n' "$TEST_TMPDIR/machine-default"
} >"$SHADOW_GCFG"
run "$SHADOW_GCFG" "$INCREPO"
assert_exit "a plain value shadowing an include is a finding (exit 1)" 1 "$RC"
assert_contains "the shadow warning names parse order as the precedence rule" "$OUT" \
  "precedence is parse order, not specificity"
assert_contains "the shadow warning names the remedy (move the default up)" "$OUT" \
  "ABOVE the includeIf block"

LAYERED_GCFG="$TEST_TMPDIR/gitconfig-layered"
{
  printf '[worktreeroot]\n\tpath = %s\n' "$TEST_TMPDIR/machine-default"
  printf '[includeIf "gitdir/i:**/increpo-fixture/.git"]\n\tpath = %s\n' "$INC_FILE"
} >"$LAYERED_GCFG"
run "$LAYERED_GCFG" "$INCREPO"
assert_exit "the correct layering is a clean report (exit 0)" 0 "$RC"
assert_contains "the include-supplied winner is reported as working layering" "$OUT" \
  "the layering is working"
assert_contains "the layered winner is the include's value" "$OUT" \
  "worktreeroot.path = $TEST_TMPDIR/work-root"

NESTED_ROOT_REPO="$(mkrepo nestroot)"
fgit -C "$NESTED_ROOT_REPO" config worktreeroot.path "$NESTED_ROOT_REPO/worktrees"
mkdir -p "$NESTED_ROOT_REPO/worktrees"
run "$EMPTY_GCFG" "$NESTED_ROOT_REPO"
assert_exit "a root inside a working tree is a finding (exit 1)" 1 "$RC"
assert_contains "the nested root names the invariant it violates" "$OUT" \
  "INSIDE a git working tree"

IDREPO_PARENT="$(mktemp -d "$TEST_TMPDIR/idparentXXXXXX")"
IDREPO="$IDREPO_PARENT/identity-fixture"
mkdir -p "$IDREPO"
fgit -C "$IDREPO" init -q -b main >/dev/null 2>&1
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

WTREPO="$(mkrepo wthost)"
fgit -C "$WTREPO" config user.email t@t.t
fgit -C "$WTREPO" config user.name t
fgit -C "$WTREPO" config commit.gpgsign false
printf 'seed\n' >"$WTREPO/README.md"
fgit -C "$WTREPO" add README.md >/dev/null 2>&1
fgit -C "$WTREPO" commit -qm init >/dev/null 2>&1
LINKED="$TEST_TMPDIR/linked-wt"
if fgit -C "$WTREPO" worktree add -q "$LINKED" -b feat/doctor >/dev/null 2>&1; then
  run "$EMPTY_GCFG" "$LINKED"
  assert_contains "a linked worktree's classification rule is surfaced" "$OUT" \
    "classify this worktree WITH its repository"
else
  skip_case "worktree add unavailable for the linked-worktree note fixture"
fi

NEST_A="$(mkrepo nesta)"
NEST_B="$(mkrepo nestb)"
for r in "$NEST_A" "$NEST_B"; do
  fgit -C "$r" config user.email t@t.t
  fgit -C "$r" config user.name t
  fgit -C "$r" config commit.gpgsign false
  printf 'seed\n' >"$r/README.md"
  fgit -C "$r" add README.md >/dev/null 2>&1
  fgit -C "$r" commit -qm init >/dev/null 2>&1
done
mkdir -p "$NEST_A/.work"
NESTED_WT="$NEST_A/.work/b-wt"
if fgit -C "$NEST_B" worktree add -q "$NESTED_WT" -b feat/nested >/dev/null 2>&1; then
  run "$EMPTY_GCFG" "$NEST_B"
  assert_exit "a worktree inside another repository is a finding (exit 1)" 1 "$RC"
  assert_contains "the finding is error-level" "$OUT" "error: worktree "
  NEST_A_P="$(physical_dir "$NEST_A")"
  NEST_B_P="$(physical_dir "$NEST_B")"
  assert_contains "the finding names the nested worktree" "$OUT" "b-wt"
  assert_contains "the finding names the containing repository" "$OUT" "different repository ($NEST_A_P)"
  assert_contains "the finding names the owning repository" "$OUT" "of repository $NEST_B_P"
  assert_contains "the finding carries the remove command" "$OUT" "git -C $NEST_B_P worktree remove "
else
  skip_case "worktree add unavailable for the nested-worktree fixture"
fi

IN_ROOT="$TEST_TMPDIR/ok-root"
mkdir -p "$IN_ROOT"
fgit -C "$WTREPO" config worktreeroot.path "$IN_ROOT"
OWN_WT="$WTREPO/.work/own"
mkdir -p "$WTREPO/.work"
if fgit -C "$WTREPO" worktree add -q "$IN_ROOT/in-root-wt" -b feat/in-root >/dev/null 2>&1 &&
  fgit -C "$WTREPO" worktree add -q "$OWN_WT" -b feat/own >/dev/null 2>&1; then
  run "$EMPTY_GCFG" "$WTREPO"
  assert_not_contains "in-root and own-repository worktrees raise no nesting error" "$OUT" \
    "sits inside the work tree of a different repository"
else
  skip_case "worktree add unavailable for the in-root fixture"
fi

mkdir -p "$NEST_A/clone"
fgit -C "$NEST_A/clone" init -q -b main >/dev/null 2>&1
run "$EMPTY_GCFG" "$NEST_A/clone"
assert_not_contains "a clone under another repository is not flagged" "$OUT" \
  "sits inside the work tree of a different repository"

fgit -C "$NEST_A/clone" config user.email t@t.t
fgit -C "$NEST_A/clone" config user.name t
fgit -C "$NEST_A/clone" config commit.gpgsign false
printf 'seed\n' >"$NEST_A/clone/README.md"
fgit -C "$NEST_A/clone" add README.md >/dev/null 2>&1
fgit -C "$NEST_A/clone" commit -qm init >/dev/null 2>&1
mkdir -p "$NEST_A/clone/.work"
if fgit -C "$NEST_A/clone" worktree add -q "$NEST_A/clone/.work/x" -b feat/clone-own >/dev/null 2>&1; then
  run "$EMPTY_GCFG" "$NEST_A/clone"
  assert_not_contains "an own-tree worktree of a nested clone is not flagged" "$OUT" \
    "sits inside the work tree of a different repository"
else
  skip_case "worktree add unavailable for the nested-clone fixture"
fi

run "$EMPTY_GCFG" "$REPO"
assert_contains "the un-probe-able classes are reported as standing notes" "$OUT" \
  "not machine-checked here"

[[ $FAILED -eq 0 ]] || exit 1
