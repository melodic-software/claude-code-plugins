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

fixture_tree::build f --sut "$HOOK" --sut check-changelog-fragments.sh --git --plugins --label prepush-budget || exit 1
printf '%s\n' '# fragment mode' >"$f/scripts/fragment-plugins.txt"
for i in $(seq 1 100); do
  mkdir -p "$f/plugins/p$i/.claude-plugin" "$f/plugins/p$i/skills" "$f/.changes/p$i"
  printf '{\n  "name": "p%s",\n  "version": "1.0.0"\n}\n' "$i" >"$f/plugins/p$i/.claude-plugin/plugin.json"
  printf '# Changelog\n\n## [1.0.0] - 2026-10-01\n\n### Added\n\n- First.\n' >"$f/plugins/p$i/CHANGELOG.md"
  printf 'v1\n' >"$f/plugins/p$i/skills/a.md"
  printf 'p%s\n' "$i" >>"$f/scripts/fragment-plugins.txt"
done
commit "$f" base
git_test_config "$f" branch -q -M main
git_test_config "$f" update-ref refs/remotes/origin/main main
git_test_config "$f" checkout -q -b topic
for i in $(seq 1 20); do
  printf 'v2\n' >"$f/plugins/p$i/skills/a.md"
  printf -- '---\nbump: patch\n---\n\n### Fixed\n\n- Topic.\n' >"$f/.changes/p$i/topic-$(printf '%08x' "$i").md"
done
commit "$f" change
h="$(head_of "$f")"
start=$(date +%s%N)
expect "a 100-plugin, 20-fragment push passes" 0 "" "$f" "refs/heads/topic $h refs/heads/topic $ZERO"
ms=$((($(date +%s%N) - start) / 1000000))
if ((ms <= BUDGET_SECONDS * 1000)); then
  ok "the hook ran in ${ms} ms at that scale, within the ${BUDGET_SECONDS} s pre-push budget"
else
  fail "the hook took ${ms} ms at that scale, over the ${BUDGET_SECONDS} s pre-push budget"
fi
rm -rf "$f"

test_harness::report
