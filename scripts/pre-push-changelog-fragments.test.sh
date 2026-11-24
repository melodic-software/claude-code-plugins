#!/usr/bin/env bash
set -uo pipefail

unset GITHUB_EVENT_NAME MERGE_GROUP_BASE_SHA CHANGELOG_PR_HEAD CHANGELOG_HEAD_REF \
  CHANGELOG_PR_AUTHOR GITHUB_REPOSITORY

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SELF_DIR/pre-push-changelog-fragments.sh"
. "$SELF_DIR/test-git-helpers.sh"
# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh"
# shellcheck source=lib/changed-files.sh
. "$SELF_DIR/lib/changed-files.sh"

ZERO=0000000000000000000000000000000000000000
BUDGET_SECONDS=3
f=""

fixture() {
  local dir
  fixture_tree::build "$1" --sut "$HOOK" --sut check-changelog-fragments.sh --git --plugins --label prepush || return 1
  dir="${!1}"
  mkdir -p "$dir/plugins/alpha/.claude-plugin" "$dir/plugins/alpha/skills"
  printf '{\n  "name": "alpha",\n  "version": "1.0.0"\n}\n' >"$dir/plugins/alpha/.claude-plugin/plugin.json"
  printf '# Changelog\n\n## [1.0.0] - 2026-10-01\n\n### Added\n\n- First.\n' >"$dir/plugins/alpha/CHANGELOG.md"
  printf 'v1\n' >"$dir/plugins/alpha/skills/a.md"
  printf '%s\n' '# fragment mode' alpha >"$dir/scripts/fragment-plugins.txt"
  commit "$dir" base
  git_test_config "$dir" branch -q -M main
  git_test_config "$dir" update-ref refs/remotes/origin/main main
  git_test_config "$dir" checkout -q -b topic
  printf 'v2\n' >"$dir/plugins/alpha/skills/a.md"
  commit "$dir" change
}

commit() { git_test_config "$1" add -A && git_test_config "$1" commit -qm "$2"; }

fragment() {
  mkdir -p "$1/.changes/alpha"
  printf -- '---\nbump: patch\n---\n\n%s\n' "$3" >"$1/.changes/alpha/$2.md"
}

head_of() { git -C "$1" rev-parse HEAD; }

expect() {
  local label="$1" want="$2" needle="$3" fixture="$4" input="$5" out rc
  out="$(cd "$fixture" && printf '%s\n' "$input" | bash scripts/pre-push-changelog-fragments.sh origin 2>&1)"
  rc=$?
  if ((rc == want)) && [[ "$out" == *"$needle"* ]]; then
    ok "$label"
  else
    fail "$label: want rc=$want and '$needle', got rc=$rc: $out"
  fi
}

fixture f
h="$(head_of "$f")"
expect "a shipped change with no fragment stops the push" 1 "fix the fragment finding" "$f" "refs/heads/topic $h refs/heads/topic $ZERO"
expect "a deleted ref is not checked" 0 "" "$f" "(delete) $ZERO refs/heads/topic $h"
expect "a push to the default branch is not checked" 0 "" "$f" "refs/heads/topic $h refs/heads/main $h"
expect "a tag is not checked" 0 "" "$f" "refs/tags/v1 $h refs/tags/v1 $ZERO"
expect "a ref that is not HEAD is left to CI" 0 "is not HEAD" "$f" "refs/heads/other 1111111111111111111111111111111111111111 refs/heads/other $ZERO"
expect "empty stdin checks nothing" 0 "" "$f" ""

fragment "$f" topic-0123abcd "Missing section heading."
commit "$f" bad-fragment
h="$(head_of "$f")"
expect "a malformed fragment stops the push" 1 "fix the fragment finding" "$f" "refs/heads/topic $h refs/heads/topic $ZERO"

fragment "$f" topic-0123abcd "### Fixed

- A fix."
expect "an uncommitted repair leaves the committed fragment's format to CI" 0 "left to CI" "$f" "refs/heads/topic $h refs/heads/topic $ZERO"
commit "$f" good-fragment
h="$(head_of "$f")"
fragment "$f" topic-89abcdef "Unfinished."
expect "an untracked unfinished fragment does not block a valid push" 0 "left to CI" "$f" "refs/heads/topic $h refs/heads/topic $ZERO"
rm -f "$f/.changes/alpha/topic-89abcdef.md"
h="$(head_of "$f")"
expect "a valid fragment lets the push through" 0 "" "$f" "refs/heads/topic $h refs/heads/topic $ZERO"

git_test_config "$f" update-ref -d refs/remotes/origin/main
expect "an unfetched base is left to CI" 0 "is not fetched" "$f" "refs/heads/topic $h refs/heads/topic $ZERO"
rm -rf "$f"

repo="$(cd "$SELF_DIR/.." && pwd)"
if (cd "$repo" && changed_files::verify_base origin/main); then
  h="$(head_of "$repo")"
  start=$(date +%s%N)
  (cd "$repo" && printf 'refs/heads/t %s refs/heads/t %s\n' "$h" "$ZERO" | bash scripts/pre-push-changelog-fragments.sh origin >/dev/null 2>&1)
  ms=$((($(date +%s%N) - start) / 1000000))
  if ((ms <= BUDGET_SECONDS * 1000)); then
    ok "the hook runs in ${ms} ms on this repository, within ${BUDGET_SECONDS} s"
  else
    fail "the hook took ${ms} ms on this repository, over the ${BUDGET_SECONDS} s pre-push budget"
  fi
else
  ok "budget case skipped: origin/main is not fetched in this checkout"
fi

test_harness::report
