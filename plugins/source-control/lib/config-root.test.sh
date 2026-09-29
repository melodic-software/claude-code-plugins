#!/usr/bin/env bash
# Tests for config-root.sh: root classification (repo | non-repo | home), the
# physical path-equality helper, and the CLI entry. Every path lives under a
# fixture tree this suite creates; the real home directory is never read.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/config-root.sh"
TEST_TMPDIR="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../scripts/test-helpers.sh
source "$SCRIPT_DIR/../scripts/test-helpers.sh"
# shellcheck source=config-root.sh
source "$LIB"

# A fixture directory under a TMPDIR that is itself inside a work tree must not
# classify as a repository.
export GIT_CEILING_DIRECTORIES="$TEST_TMPDIR"
unset CLAUDE_PROJECT_DIR

# Fixture tree:
#   users/alice        fixture HOME, holds .claude/source-control.md and proj/ (a repo)
#   users              an ancestor of HOME
#   users/ali          a string prefix of HOME that is not an ancestor
#   dotfiles-home      a fixture HOME that is itself a repository
#   work/repo          a repository, work/repo/sub/dir nested in it
#   work/plain         a directory outside any repository
#   team-repo          a repository whose .claude is a symlink to HOME's .claude
#   own-repo           a repository with its own .claude/source-control.md
HOME_DIR="$TEST_TMPDIR/users/alice"
ANCESTOR="$TEST_TMPDIR/users"
REPO="$TEST_TMPDIR/work/repo"
PLAIN="$TEST_TMPDIR/work/plain"
mkdir -p "$HOME_DIR/.claude" "$TEST_TMPDIR/users/ali" "$REPO/sub/dir" "$PLAIN" \
  "$TEST_TMPDIR/dotfiles-home" "$TEST_TMPDIR/team-repo" "$TEST_TMPDIR/own-repo/.claude"
printf '# Source control\n' >"$HOME_DIR/.claude/source-control.md"
printf '# Source control\n' >"$TEST_TMPDIR/own-repo/.claude/source-control.md"
for d in "$REPO" "$HOME_DIR/proj" "$TEST_TMPDIR/dotfiles-home" "$TEST_TMPDIR/team-repo" "$TEST_TMPDIR/own-repo"; do
  mkdir -p "$d"
  git init -q "$d"
done

# mklink <target> <link>: succeeds only when a real symlink came out. Git Bash
# without native symlink support copies instead, which would prove nothing.
mklink() {
  MSYS=winsymlinks:nativestrict ln -s "$1" "$2" 2>/dev/null && [[ -L "$2" ]]
}

# classify_as <home> <root>: classification with HOME pointed at a fixture.
classify_as() { (HOME="$1" config_root_classify "$2"); }
same() { config_root_paths_same "$2" "$3"; assert_exit "$1" 0 "$?"; }
differ() { config_root_paths_same "$2" "$3"; assert_exit "$1" 1 "$?"; }

# --- classification ----------------------------------------------------------
assert_eq "repo root is a repo" repo "$(classify_as "$HOME_DIR" "$REPO")"
assert_eq "a nested directory of a repo is a repo" repo "$(classify_as "$HOME_DIR" "$REPO/sub/dir")"
assert_eq "a repo under HOME is a repo, not home" repo "$(classify_as "$HOME_DIR" "$HOME_DIR/proj")"
assert_eq "a directory outside any repo is non-repo" non-repo "$(classify_as "$HOME_DIR" "$PLAIN")"
assert_eq "a missing directory is non-repo" non-repo "$(classify_as "$HOME_DIR" "$TEST_TMPDIR/missing")"
assert_eq "HOME itself is home" home "$(classify_as "$HOME_DIR" "$HOME_DIR")"
assert_eq "HOME with a trailing slash is home" home "$(classify_as "$HOME_DIR" "$HOME_DIR/")"
assert_eq "HOME that is a repository is still home" home \
  "$(classify_as "$TEST_TMPDIR/dotfiles-home" "$TEST_TMPDIR/dotfiles-home")"
assert_eq "an ancestor of HOME is home" home "$(classify_as "$HOME_DIR" "$ANCESTOR")"
assert_eq "a string prefix of HOME that is not an ancestor is not home" non-repo \
  "$(classify_as "$HOME_DIR" "$TEST_TMPDIR/users/ali")"
assert_eq "an empty HOME makes nothing home" repo "$(classify_as "" "$REPO")"

# --- root resolution ---------------------------------------------------------
resolved="$(cd "$REPO/sub/dir" && unset CLAUDE_PROJECT_DIR && config_root_resolve)"
same "with CLAUDE_PROJECT_DIR unset the root is the git toplevel of a nested cwd" "$resolved" "$REPO"
assert_eq "a nested cwd resolves to a repo root" repo \
  "$(cd "$REPO/sub/dir" && unset CLAUDE_PROJECT_DIR && HOME="$HOME_DIR" config_root_classify)"
resolved="$(cd "$PLAIN" && CLAUDE_PROJECT_DIR="$REPO" config_root_resolve)"
assert_eq "CLAUDE_PROJECT_DIR wins over the cwd's own repository" "$REPO" "$resolved"
resolved="$(cd "$PLAIN" && unset CLAUDE_PROJECT_DIR && config_root_resolve)"
assert_eq "no CLAUDE_PROJECT_DIR and no repository resolves to nothing" "" "$resolved"
assert_eq "no root at all is non-repo" non-repo \
  "$(cd "$PLAIN" && unset CLAUDE_PROJECT_DIR && HOME="$HOME_DIR" config_root_classify)"
assert_eq "CLAUDE_PROJECT_DIR at HOME classifies as home" home \
  "$(cd "$REPO" && CLAUDE_PROJECT_DIR="$HOME_DIR" HOME="$HOME_DIR" config_root_classify)"

# --- physical path equality --------------------------------------------------
same "a directory equals itself with a trailing slash" "$REPO" "$REPO/"
differ "two different directories differ" "$REPO" "$PLAIN"
differ "empty equals nothing" "" ""
differ "an empty side equals nothing" "$REPO" ""
differ "same leaf name in different directories differ" \
  "$HOME_DIR/.claude/source-control.md" "$TEST_TMPDIR/own-repo/.claude/source-control.md"
differ "a file never equals its directory" "$HOME_DIR/.claude/source-control.md" "$HOME_DIR/.claude"
err="$(config_root_paths_same "$HOME_DIR/.claude/source-control.md" "$HOME_DIR/.claude" 2>&1)"
assert_silent "comparing a file with a directory prints nothing on stderr" "$err"
same "missing paths compare after slash, case, and trailing-slash folding" "D:\\Repos\\Alice\\" "d:/repos/alice"

if mklink "$HOME_DIR" "$TEST_TMPDIR/alias-home"; then
  same "a symlink alias of a directory equals the directory" "$TEST_TMPDIR/alias-home" "$HOME_DIR"
  assert_eq "a symlink alias of HOME is home" home "$(classify_as "$HOME_DIR" "$TEST_TMPDIR/alias-home")"
  assert_eq "HOME spelled as a symlink alias still matches the real HOME" home \
    "$(classify_as "$TEST_TMPDIR/alias-home" "$HOME_DIR")"
else
  skip_case "symlink alias cases need a host that can create symlinks (uname: $(uname -s))"
fi

if mklink "$HOME_DIR/.claude" "$TEST_TMPDIR/team-repo/.claude"; then
  same "a team path reached through a symlinked .claude equals the user-global file" \
    "$TEST_TMPDIR/team-repo/.claude/source-control.md" "$HOME_DIR/.claude/source-control.md"
  assert_eq "that repo is still a repo, so only path equality can drop its team layer" repo \
    "$(classify_as "$HOME_DIR" "$TEST_TMPDIR/team-repo")"
else
  skip_case "team-equals-user-global symlink case needs a host that can create symlinks (uname: $(uname -s))"
fi
differ "a repo's own team file differs from the user-global file" \
  "$TEST_TMPDIR/own-repo/.claude/source-control.md" "$HOME_DIR/.claude/source-control.md"

# --- Windows native vs MSYS spelling (real only under MINGW/MSYS) ------------
case "$(uname -s)" in
  MINGW* | MSYS*) windows_shell=1 ;;
  *) windows_shell=0 ;;
esac
if [[ "$windows_shell" -eq 1 ]] && command -v cygpath >/dev/null 2>&1; then
  native="$(cygpath -m "$HOME_DIR")"
  msys="$(cygpath -u "$HOME_DIR")"
  same "a native and an MSYS spelling of one home are the same directory" "$native" "$msys"
  assert_eq "native root against an MSYS HOME is home" home "$(classify_as "$msys" "$native")"
  assert_eq "MSYS root against a native HOME is home" home "$(classify_as "$native" "$msys")"
  assert_eq "a native spelling of an ancestor of an MSYS HOME is home" home \
    "$(classify_as "$msys" "$(cygpath -m "$ANCESTOR")")"
else
  skip_case "Windows native vs MSYS spelling needs MINGW/MSYS with cygpath (uname: $(uname -s))"
fi

# --- CLI entry ---------------------------------------------------------------
cli() { (HOME="$HOME_DIR" bash "$LIB" "$@" 2>&1); }
assert_eq "CLI classify ROOT: repo" repo "$(cli classify "$REPO")"
assert_eq "CLI classify ROOT: non-repo" non-repo "$(cli classify "$PLAIN")"
assert_eq "CLI classify ROOT: home" home "$(cli classify "$HOME_DIR")"
assert_eq "CLI classify with CLAUDE_PROJECT_DIR at HOME: home" home \
  "$(CLAUDE_PROJECT_DIR="$HOME_DIR" cli classify)"
assert_eq "CLI classify with CLAUDE_PROJECT_DIR at a repo: repo" repo \
  "$(CLAUDE_PROJECT_DIR="$REPO" cli classify)"
assert_eq "CLI resolve prints CLAUDE_PROJECT_DIR" "$REPO" "$(CLAUDE_PROJECT_DIR="$REPO" cli resolve)"
cli same "$REPO" "$REPO/" >/dev/null
assert_exit "CLI same: equal paths exit 0" 0 "$?"
bash "$LIB" same "$REPO" "$PLAIN"
assert_exit "CLI same: different paths exit 1" 1 "$?"
out="$(bash "$LIB" bogus 2>&1)"
assert_exit "CLI: an unknown subcommand exits 2" 2 "$?"
assert_contains "CLI: an unknown subcommand prints usage" "$out" "usage: bash config-root.sh"
assert_silent "sourcing the library prints nothing and runs no subcommand" \
  "$(bash -c 'source "$1"' _ "$LIB" 2>&1)"

printf '\nResults: %d passed, %d failed, %d skipped\n' "$((CASE_NUM - FAILED))" "$FAILED" "$SKIP_CASES"
[[ $FAILED -eq 0 ]] || exit 1
exit 0
