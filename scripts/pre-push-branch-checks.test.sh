#!/usr/bin/env bash
# test-scope: scripts/check-changelog-fragments.sh scripts/check-changelog-parity.sh scripts/sync-plugin-options-docs.py
# test-scope: scripts/validate-plugin-contracts.mjs scripts/generate-marketplace.mjs scripts/generate-catalog.mjs
# test-scope: scripts/generate-cheatsheet.mjs scripts/cheatsheet-config.mjs scripts/fragment-plugins.txt scripts/lib/*
# test-scope: .claude-plugin/marketplace.json plugins/*/.claude-plugin/plugin.json docs/catalog.md docs/skill-cheat-sheet.md .changes/*
set -uo pipefail

unset GITHUB_EVENT_NAME MERGE_GROUP_BASE_SHA CHANGELOG_PR_HEAD CHANGELOG_HEAD_REF \
  CHANGELOG_PR_AUTHOR GITHUB_REPOSITORY VALIDATE_CONTRACTS_BASE_REF CHECK_DATA_ROOT CHANGELOG_PARITY_ROOT

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/.." && pwd)"
HOOK="$SELF_DIR/pre-push-branch-checks.sh"
. "$SELF_DIR/test-git-helpers.sh"
# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh"

ZERO=0000000000000000000000000000000000000000
REAL_HEAD="$(git -C "$REPO_ROOT" rev-parse HEAD)" || exit 2
OBJECTS="$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-common-dir)/objects" || exit 2
f=""
PATH_OVERRIDE=""

commit() { git_test_config "$1" add -A && git_test_config "$1" commit -qm "$2"; }

snapshot() {
  local dir
  fixture_tree::build "$1" --git --label "$2" || return 1
  dir="${!1}"
  printf '%s\n' "$OBJECTS" >"$dir/.git/objects/info/alternates"
  git_test_config "$dir" update-ref refs/heads/main "$REAL_HEAD" &&
    git_test_config "$dir" symbolic-ref HEAD refs/heads/main &&
    git_test_config "$dir" read-tree -u --reset HEAD || return 1
  cp "$HOOK" "$dir/scripts/pre-push-branch-checks.sh"
  git_test_config "$dir" add -A && git_test_config "$dir" commit -q --allow-empty -m hook &&
    git_test_config "$dir" update-ref refs/remotes/origin/main HEAD
}

topic() { git_test_config "$f" checkout -q -f -B topic main && git_test_config "$f" clean -qfdx; }

fragment() {
  mkdir -p "$f/.changes/$1"
  printf -- '---\nbump: patch\n---\n\n%s\n' "${3:-### Fixed

- Topic.}" >"$f/.changes/$1/topic-$2.md"
}

fragment_mode() { grep -qx "$1" "$f/scripts/fragment-plugins.txt"; }

first_plugin() {
  local path p
  while IFS= read -r path; do
    p="${path#plugins/}"
    p="${p%%/*}"
    fragment_mode "$p" && {
      printf '%s\n' "$path"
      cat >/dev/null
      return 0
    }
  done
  return 1
}

run_hook() {
  local input
  input="refs/heads/topic $(git -C "$f" rev-parse HEAD) refs/heads/topic $ZERO"
  out="$(cd "$f" && printf '%s\n' "${1:-$input}" | PATH="${PATH_OVERRIDE:-$PATH}" bash scripts/pre-push-branch-checks.sh origin 2>&1)"
  rc=$?
}

expect() {
  local label="$1" want="$2" needle
  shift 2
  for needle in "$@"; do
    if [[ "$out" != *"$needle"* ]]; then
      fail "$label: want rc=$want and '$needle', got rc=$rc: $out"
      return
    fi
  done
  if ((rc == want)); then ok "$label"; else fail "$label: want rc=$want, got rc=$rc: $out"; fi
}

snapshot f prepush || {
  fail "the snapshot fixture of HEAD could not be built"
  test_harness::report
}

README="$(cd "$f" && git ls-files 'plugins/*/README.md' | first_plugin)"
PLAIN="${README#plugins/}"
PLAIN="${PLAIN%%/*}"
OPTIONS_README="$(cd "$f" && git grep -l -F '<!-- END GENERATED: plugin options -->' -- 'plugins/*/README.md' | first_plugin)"
OPTIONS_PLUGIN="${OPTIONS_README#plugins/}"
OPTIONS_PLUGIN="${OPTIONS_PLUGIN%%/*}"
HINT_SKILL="$(cd "$f" && git grep -l -E '^\*\*Arguments\.\*\*' -- 'plugins/*/SKILL.md' | xargs grep -l -E '^argument-hint: *"?[a-z<[]' | first_plugin)"
HINT_PLUGIN="${HINT_SKILL#plugins/}"
HINT_PLUGIN="${HINT_PLUGIN%%/*}"
PARITY_LOG="$(cd "$f" && for c in plugins/*/CHANGELOG.md; do (($(grep -c '^## \[' "$c") >= 2)) && echo "$c"; done | first_plugin)"
PARITY_PLUGIN="${PARITY_LOG#plugins/}"
PARITY_PLUGIN="${PARITY_PLUGIN%%/*}"
for v in PLAIN OPTIONS_PLUGIN HINT_PLUGIN PARITY_PLUGIN; do
  [[ -n "${!v}" ]] || fail "no fragment-mode plugin in HEAD has the shape $v needs"
done

h="$(git -C "$f" rev-parse HEAD)"
run_hook "(delete) $ZERO refs/heads/topic $h"
expect "a deleted ref is not checked" 0
run_hook "refs/heads/topic $h refs/heads/main $h"
expect "a push to the default branch is not checked" 0
run_hook "refs/tags/v1 $h refs/tags/v1 $ZERO"
expect "a tag is not checked" 0
run_hook "refs/heads/other 1111111111111111111111111111111111111111 refs/heads/other $ZERO"
expect "a ref that is not HEAD is left to CI" 0 "is not HEAD"
run_hook " "
expect "blank stdin checks nothing" 0

topic
printf '\nTopic.\n' >>"$f/$README"
fragment "$PLAIN" 0000000a
commit "$f" clean
run_hook
expect "a clean branch with its fragment passes all seven checks" 0
if [[ "$out" != *"left to CI"* && "$out" != *failed* ]]; then
  ok "the clean branch ran every check and none failed"
else
  fail "the clean branch skipped or failed a check: $out"
fi

topic
printf '\nTopic.\n' >>"$f/$README"
commit "$f" no-fragment
run_hook
expect "a shipped change with no fragment stops the push" 1 "fix the fragment finding"

fragment "$PLAIN" 0123abcd "Missing section heading."
commit "$f" bad-fragment
run_hook
expect "a malformed fragment stops the push" 1 "fix the fragment finding"
fragment "$PLAIN" 0123abcd
run_hook
expect "an uncommitted repair leaves the committed fragment's format and the whole-branch checks to CI" 0 \
  "the pushed fragments' format is left to CI" "the working tree has uncommitted changes, so the whole-branch checks are left to CI"
commit "$f" good-fragment

topic
fragment "$PARITY_PLUGIN" 0000000b
awk '/^## \[/ { n++; if (n == 2) next } { print }' "$f/$PARITY_LOG" >"$f/.git/parity.tmp" && mv "$f/.git/parity.tmp" "$f/$PARITY_LOG"
commit "$f" parity
run_hook
expect "a dropped released CHANGELOG heading stops the push" 1 "lost release section heading" \
  "changelog-parity failed; fix: fix the CHANGELOG or version finding"

topic
fragment "$OPTIONS_PLUGIN" 0000000c
awk '/<!-- END GENERATED: plugin options -->/ { print "stale row" } { print }' "$f/$OPTIONS_README" >"$f/.git/readme.tmp" && mv "$f/.git/readme.tmp" "$f/$OPTIONS_README"
commit "$f" options
run_hook
expect "a stale plugin options block stops the push" 1 "STALE options docs" \
  "plugin-options-docs failed; fix: python3 scripts/sync-plugin-options-docs.py"

topic
fragment "$PLAIN" 0000000d
jq '. + {defaultEnabled: true}' "$f/plugins/$PLAIN/.claude-plugin/plugin.json" >"$f/.git/m.tmp" && mv "$f/.git/m.tmp" "$f/plugins/$PLAIN/.claude-plugin/plugin.json"
commit "$f" contract-error
run_hook
expect "a plugin contract error stops the push" 1 "must not set defaultEnabled" \
  "plugin-contracts failed; fix: fix the manifest or skill finding, then re-run node scripts/validate-plugin-contracts.mjs"
if [[ "$out" != *"VALIDATE_CONTRACTS_BASE_REF unset"* ]]; then
  ok "the contract check runs with the push's base, so the retirements append-only check is not skipped"
else
  fail "the contract check ran without VALIDATE_CONTRACTS_BASE_REF: $out"
fi

topic
fragment "$HINT_PLUGIN" 0000000e
sed 's/^\*\*Arguments\.\*\*.*/**Arguments.** not-the-hint/' "$f/$HINT_SKILL" >"$f/.git/skill.tmp" && mv "$f/.git/skill.tmp" "$f/$HINT_SKILL"
commit "$f" contract-warning
run_hook
expect "a plugin contract warning stops the push like an error" 1 "warning: " "a contract warning fails like an error" \
  "plugin-contracts failed"

topic
jq '.plugins[0].tags = ["drift"]' "$f/.claude-plugin/marketplace.json" >"$f/.git/mp.tmp" && mv "$f/.git/mp.tmp" "$f/.claude-plugin/marketplace.json"
commit "$f" marketplace
run_hook
expect "a marketplace entry out of step with its manifest stops the push" 1 "Marketplace drift" \
  "marketplace failed; fix: node scripts/generate-marketplace.mjs"

topic
awk '/<!-- END GENERATED: catalog -->/ { print "- stale row" } { print }' "$f/docs/catalog.md" >"$f/.git/cat.tmp" && mv "$f/.git/cat.tmp" "$f/docs/catalog.md"
commit "$f" catalog
run_hook
expect "a stale catalog stops the push" 1 "Catalog drift" "catalog failed; fix: node scripts/generate-catalog.mjs"
CATALOG_HEAD="$(git -C "$f" rev-parse HEAD)"

printf 'scratch\n' >"$f/scratch.txt"
run_hook
expect "an uncommitted file leaves the whole-branch checks to CI" 0 \
  "the working tree has uncommitted changes, so the whole-branch checks are left to CI"
rm -f "$f/scratch.txt"

stub="$f/.git/stub"
mkdir -p "$stub"
printf '#!/bin/sh\necho MINGW64_NT-10.0-26100\n' >"$stub/uname"
chmod +x "$stub/uname"
PATH_OVERRIDE="$stub:$PATH"
run_hook
expect "on Windows the whole-branch checks are left to CI" 0 "on Windows only the fragment checks run"
git_test_config "$f" checkout -q -f -B topic main
printf '\nTopic.\n' >>"$f/$README"
commit "$f" windows-no-fragment
run_hook
expect "on Windows a missing fragment still stops the push" 1 "fix the fragment finding" "on Windows only the fragment checks run"
PATH_OVERRIDE=""

git_test_config "$f" checkout -q -f -B topic "$CATALOG_HEAD"
farm="$f/.git/farm"
mkdir -p "$farm"
IFS=: read -r -a path_dirs <<<"$PATH"
for d in "${path_dirs[@]}"; do
  [[ -d "$d" ]] || continue
  find "$d" -maxdepth 1 \( -type f -o -type l \) ! -name node ! -name python3 -exec ln -s -t "$farm" {} + 2>/dev/null
done
PATH_OVERRIDE="$farm"
run_hook
expect "with no node or python3 their checks are left to CI" 0 \
  "node is not on PATH, so catalog is left to CI" "python3 is not on PATH, so plugin-options-docs is left to CI"
PATH_OVERRIDE=""

topic
awk '/<!-- END GENERATED: cheatsheet -->/ { print "stale row" } { print }' "$f/docs/skill-cheat-sheet.md" >"$f/.git/cs.tmp" && mv "$f/.git/cs.tmp" "$f/docs/skill-cheat-sheet.md"
commit "$f" cheatsheet
run_hook
expect "a stale cheat sheet stops the push" 1 "Cheat sheet drift" "cheatsheet failed; fix: node scripts/generate-cheatsheet.mjs --root ."

git_test_config "$f" update-ref -d refs/remotes/origin/main
run_hook
expect "an unfetched base is left to CI" 0 "is not fetched"

test_harness::report
