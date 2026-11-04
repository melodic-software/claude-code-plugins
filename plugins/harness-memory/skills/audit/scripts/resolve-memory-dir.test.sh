#!/usr/bin/env bash
# Regression tests for resolve-memory-dir.sh's pinned project directory name.
# Expected values come from the three rules and the worked example at
# https://code.claude.com/docs/en/sessions#name-the-project-directory-yourself
# (read 2026-11-04): the store is <config dir>/projects/<name>/memory whatever the
# working directory, and an unusable value falls back to the derived name.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/resolve-memory-dir.sh"

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

REPO="$TEST_TMPDIR/repo"
make_repo "$REPO"
NOREPO="$TEST_TMPDIR/plain"
mkdir -p "$NOREPO"
HOME_DIR="$TEST_TMPDIR/home"
CFG="$TEST_TMPDIR/tenant-a"
mkdir -p "$HOME_DIR" "$CFG"

# resolve <cwd> <config dir or empty> <name or empty>
resolve() {
  local args=(-u CLAUDE_CONFIG_DIR -u CLAUDE_CODE_PROJECT_DIR_NAME -u GIT_DIR "HOME=$HOME_DIR")
  [[ -n "$2" ]] && args+=("CLAUDE_CONFIG_DIR=$2")
  [[ -n "$3" ]] && args+=("CLAUDE_CODE_PROJECT_DIR_NAME=$3")
  (cd "$1" && env "${args[@]}" bash "$SCRIPT")
}

DERIVED_CFG="$(resolve "$REPO" "$CFG" "")"
DERIVED_HOME="$(resolve "$REPO" "" "")"
assert_contains "the unpinned store sits under the config dir" "$DERIVED_CFG" "$CFG/projects/"
assert_contains "the unpinned store with no config dir sits under HOME" "$DERIVED_HOME" "$HOME_DIR/.claude/projects/"

# --- The name replaces the derived directory, in a repository and outside one ---
assert_eq "a pinned name in a repository" "$CFG/projects/work/memory" "$(resolve "$REPO" "$CFG" work)"
assert_eq "a pinned name outside a repository" "$CFG/projects/work/memory" "$(resolve "$NOREPO" "$CFG" work)"

# --- The pin wins over a derived directory that already holds a MEMORY.md ---
mkdir -p "$DERIVED_CFG"
printf '# old\n' >"$DERIVED_CFG/MEMORY.md"
assert_eq "the pin beats a derived store with an index" "$CFG/projects/work/memory" "$(resolve "$REPO" "$CFG" work)"
rm -f "$DERIVED_CFG/MEMORY.md"

# --- Length boundary: 1 to 64 characters accepted, 65 ignored ---
NAME64="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
assert_eq "one character is accepted" "$CFG/projects/a/memory" "$(resolve "$REPO" "$CFG" a)"
assert_eq "64 characters are accepted" "$CFG/projects/$NAME64/memory" "$(resolve "$REPO" "$CFG" "$NAME64")"
assert_eq "65 characters are ignored" "$DERIVED_CFG" "$(resolve "$REPO" "$CFG" "${NAME64}a")"

# --- Every other value is ignored, and the derived name is used ---
assert_eq "hyphen and underscore are accepted" "$CFG/projects/a-b_c/memory" "$(resolve "$REPO" "$CFG" a-b_c)"
assert_eq "a space is ignored" "$DERIVED_CFG" "$(resolve "$REPO" "$CFG" "a b")"
assert_eq "a path separator is ignored" "$DERIVED_CFG" "$(resolve "$REPO" "$CFG" "../escape")"
assert_eq "a dot is ignored" "$DERIVED_CFG" "$(resolve "$REPO" "$CFG" "a.b")"
assert_eq "a Windows device name is ignored" "$DERIVED_CFG" "$(resolve "$REPO" "$CFG" con)"
assert_eq "a Windows device name in capitals is ignored" "$DERIVED_CFG" "$(resolve "$REPO" "$CFG" CON)"

# --- With no config dir set the name is ignored ---
assert_eq "a name with no config dir is ignored" "$DERIVED_HOME" "$(resolve "$REPO" "" work)"

report_and_exit
