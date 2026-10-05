#!/usr/bin/env bash
# Unit tests for scripts/lib/changelog-fragments.sh: the opt-in list reader and
# the shared bump predicate. Fragment validation is exercised through
# scripts/check-changelog-fragments.test.sh.
#
# The predicate's contract with its callers (check-vendor-version-bump.sh,
# sync-shared-copies.sh, check-standards-contract-bump.sh) is that a plugin not
# in fragment mode answers exactly as "did the manifest version move", so a
# fragment can never stand in for a legacy plugin's bump.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SELF_DIR/changelog-fragments.sh"
. "$SELF_DIR/../test-git-helpers.sh"

# shellcheck source=test-harness.sh
. "$SELF_DIR/test-harness.sh"
# shellcheck source=fixture-tree.sh
. "$SELF_DIR/fixture-tree.sh"

f=""

use_lib() {
  # shellcheck source=changelog-fragments.sh
  . "$LIB"
}

# base_fixture <out-var> <list content>: plugins alpha and beta, committed.
base_fixture() {
  local dir name
  fixture_tree::build "$1" --git --plugins --label fragments-lib || return 1
  dir="${!1}"
  for name in alpha beta; do
    mkdir -p "$dir/plugins/$name/.claude-plugin"
    printf '{"name":"%s","version":"1.0.0"}\n' "$name" >"$dir/plugins/$name/.claude-plugin/plugin.json"
  done
  if [[ -n "$2" ]]; then
    printf '%s\n' "$2" >"$dir/scripts/fragment-plugins.txt"
  fi
  git_test_config "$dir" add -A
  git_test_config "$dir" commit -qm base
}

fragment() { # <fixture> <plugin> <bump>
  mkdir -p "$1/.changes/$2"
  printf -- '---\nbump: %s\n---\n\n### Fixed\n\n- x\n' "$3" >"$1/.changes/$2/feat-x-0123abcd.md"
  git_test_config "$1" add -A
}

# delivered <fixture> <plugin> <base-version> <head-version> → the predicate's rc
delivered() {
  (cd "$1" && use_lib && changelog_fragments::bump_delivered HEAD "$2" "$3" "$4")
}

expect_rc() { # <label> <want> <got>
  if (($2 == $3)); then ok "$1"; else fail "$1: want rc $2, got $3"; fi
}

# --- in_mode ------------------------------------------------------------------------
base_fixture f $'# comment\nalpha  # pilot'
(cd "$f" && use_lib && changelog_fragments::in_mode alpha)
expect_rc "a listed plugin is in fragment mode, inline comment stripped" 0 $?
(cd "$f" && use_lib && changelog_fragments::in_mode beta)
expect_rc "an unlisted plugin is not" 1 $?
rm -rf "$f"

base_fixture f ""
(cd "$f" && use_lib && changelog_fragments::in_mode alpha)
expect_rc "a missing list puts no plugin in fragment mode" 1 $?
rm -rf "$f"

# --- is_release_pr ----------------------------------------------------------------
(use_lib && CHANGELOG_HEAD_REF=release/plugins changelog_fragments::is_release_pr)
expect_rc "the release branch is the release pull request" 0 $?
(use_lib && CHANGELOG_HEAD_REF=feat/release/plugins changelog_fragments::is_release_pr)
expect_rc "a branch that only contains the release branch name is not" 1 $?
(use_lib && unset CHANGELOG_HEAD_REF && changelog_fragments::is_release_pr)
expect_rc "no head ref (a push, a fork, a local run) is not" 1 $?

# --- bump_delivered ---------------------------------------------------------------
base_fixture f alpha
delivered "$f" beta 1.0.0 1.0.1
expect_rc "a moved version is a bump for a legacy plugin" 0 $?
delivered "$f" alpha 1.0.0 1.0.1
expect_rc "a moved version is a bump for a fragment-mode plugin" 0 $?
delivered "$f" alpha 1.0.0 1.0.0
expect_rc "an unmoved version with no fragment is no bump" 1 $?
fragment "$f" alpha minor
delivered "$f" alpha 1.0.0 1.0.0
expect_rc "an added minor fragment is a bump for a fragment-mode plugin" 0 $?
fragment "$f" beta minor
delivered "$f" beta 1.0.0 1.0.0
expect_rc "an added fragment is no bump for a plugin not in fragment mode" 1 $?
rm -rf "$f"

base_fixture f alpha
fragment "$f" alpha none
delivered "$f" alpha 1.0.0 1.0.0
expect_rc "an added bump: none fragment is no bump" 1 $?
rm -rf "$f"

base_fixture f alpha
fragment "$f" alpha patch
git_test_config "$f" commit -qm pending
delivered "$f" alpha 1.0.0 1.0.0
expect_rc "a fragment already on the base is not this change set's bump" 1 $?
(cd "$f" && use_lib && changelog_fragments::bump_delivered no-such-ref alpha 1.0.0 1.0.0 2>/dev/null)
expect_rc "a git failure is rc 2, never a pass or a plain stale" 2 $?
rm -rf "$f"

test_harness::report
