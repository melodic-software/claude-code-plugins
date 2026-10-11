#!/usr/bin/env bash
# test-scope: scripts/lib/*
# Regression tests for convert-bump-to-fragment.sh against throwaway git
# fixtures: a plugin at 1.2.0 listed in scripts/fragment-plugins.txt, a `pr`
# branch that bumps it by hand, and a stub scripts/new-changelog-fragment.sh
# with the real one's contract (print the path of a new fragment holding only
# the front matter). Every fixture carries the repository's real
# scripts/lib, and one case swaps in its real fragment and parity scripts.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONVERT="$SCRIPT_DIR/convert-bump-to-fragment.sh"

FAILED=0
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

command -v git >/dev/null 2>&1 || skip_suite "git not available"
command -v jq >/dev/null 2>&1 || skip_suite "jq not available"
REPO_SCRIPTS="$SCRIPT_DIR/../../../scripts"
[[ -f $REPO_SCRIPTS/lib/changelog-fragments.sh ]] || skip_suite "no scripts/lib/changelog-fragments.sh at $REPO_SCRIPTS"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

P=plugins/demo
# shellcheck disable=SC2016  # the stub's own expansions run when it does
STUB='#!/usr/bin/env bash
cd "$(dirname "$0")/.." || exit 2
grep -qx "$1" scripts/fragment-plugins.txt || exit 2
branch=$(git symbolic-ref --quiet --short HEAD) || exit 2
path=".changes/$1/${branch//\//-}-$(printf %08x $((RANDOM * 32768 + RANDOM))).md"
mkdir -p ".changes/$1" && printf -- "---\nbump: %s\n---\n\n" "$2" >"$path" && echo "$path"
'

# write_plugin <repo> <name> <version> <description> <changelog-body>
write_plugin() {
  mkdir -p "$1/plugins/$2/.claude-plugin"
  printf '{\n  "name": "%s",\n  "version": "%s",\n  "description": "%s"\n}\n' "$2" "$3" "$4" >"$1/plugins/$2/.claude-plugin/plugin.json"
  printf '# Changelog\n\nIntro.\n\n%s' "$5" >"$1/plugins/$2/CHANGELOG.md"
}

# entry <version> <day> <body> -- one changelog section into $E.
entry() { printf -v E '## [%s] - 2026-09-2%s\n\n%s\n\n' "$1" "$2" "$3"; }
entry 1.2.0 1 '### Added

- Base release.' && BASE=$E

# mkfixture [list] -- a repo on branch `pr` forked from `main`, both plugins at
# 1.2.0; [list] (default demo) is written to scripts/fragment-plugins.txt, and
# "none" writes no list. Echoes the repo path.
mkfixture() {
  local r list=${1:-demo}
  r="$(mktemp -d "$TEST_TMPDIR/repoXXXXXX")"
  {
    git init -q -b main "$r"
    git -C "$r" config user.email t@t.t
    git -C "$r" config user.name t
    git -C "$r" config commit.gpgsign false
    git -C "$r" config core.autocrlf false
    mkdir -p "$r/scripts"
    cp -R "$REPO_SCRIPTS/lib" "$r/scripts/"
    printf '%s' "$STUB" >"$r/scripts/new-changelog-fragment.sh"
    chmod +x "$r/scripts/new-changelog-fragment.sh"
    [[ $list == none ]] || printf '# fragment mode\n%s\n' "$list" >"$r/scripts/fragment-plugins.txt"
    write_plugin "$r" demo 1.2.0 desc "$BASE"
    write_plugin "$r" other 1.2.0 desc "$BASE"
    git -C "$r" add -A && git -C "$r" commit -qm base
    git -C "$r" checkout -qb pr
  } >/dev/null 2>&1
  printf '%s' "$r"
}

# bump <repo> <plugin> <version> <description> <entry-body> -- commit on the branch.
bump() {
  entry "$3" 5 "$5"
  write_plugin "$1" "$2" "$3" "$4" "$E$BASE"
  git -C "$1" commit -qam "bump $2" >/dev/null 2>&1
}

run() { (cd "$1" && "$2" "${@:3}") 2>&1; }
fragment() { git -C "$1" diff --cached --name-only -- ".changes/$2/"; }

# 1. A minor bump with an Added entry and an unrelated description edit: the
#    version and CHANGELOG return to the base, the description edit stays, and
#    a staged minor fragment carries the entry body.
r=$(mkfixture)
bump "$r" demo 1.3.0 'new desc' '### Added

- **New thing.** Detail.'
out=$(run "$r" "$CONVERT" main)
assert_exit "minor bump converts" 0 "$?"
assert_eq "version restored" 1.2.0 "$(jq -r .version "$r/$P/.claude-plugin/plugin.json")"
assert_eq "other manifest edit kept" "new desc" "$(jq -r .description "$r/$P/.claude-plugin/plugin.json")"
assert_eq "CHANGELOG back to base" "$(git -C "$r" show "main:$P/CHANGELOG.md")" "$(cat "$r/$P/CHANGELOG.md")"
f=$(fragment "$r" demo)
assert_contains "fragment staged under .changes/demo" "$f" ".changes/demo/pr-"
assert_contains "bump from the version delta" "$(cat "$r/$f")" "bump: minor"
assert_contains "entry body moved" "$(cat "$r/$f")" "### Added

- **New thing.** Detail."
assert_not_contains "no version heading in the fragment" "$(cat "$r/$f")" "## ["
assert_eq "manifest staged" 1.2.0 "$(git -C "$r" show ":$P/.claude-plugin/plugin.json" | jq -r .version)"

# 2. Running again finds nothing to convert.
out=$(run "$r" "$CONVERT" main)
assert_exit "second run exits 0" 0 "$?"
assert_eq "no second fragment" 1 "$(git -C "$r" diff --cached --name-only -- .changes/demo/ | wc -l | tr -d ' ')"

# 3. A patch bump whose entry has no ### section goes under Changed.
r=$(mkfixture)
bump "$r" demo 1.2.1 desc '- Plain bullet.'
out=$(run "$r" "$CONVERT" main)
assert_exit "plain entry converts" 0 "$?"
f=$(fragment "$r" demo)
assert_contains "patch level" "$(cat "$r/$f")" "bump: patch"
assert_contains "wrapped under Changed" "$(cat "$r/$f")" "### Changed

- Plain bullet."

# 4. A plugin the list does not name keeps its bump.
r=$(mkfixture)
bump "$r" other 1.3.0 desc '- Other change.'
out=$(run "$r" "$CONVERT" main)
assert_exit "unlisted plugin: exit 0" 0 "$?"
assert_eq "unlisted plugin keeps its bump" 1.3.0 "$(jq -r .version "$r/plugins/other/.claude-plugin/plugin.json")"
assert_eq "no fragment for it" "" "$(fragment "$r" other)"

# 5. A repository with no fragment list: nothing to do.
r=$(mkfixture none)
bump "$r" demo 1.3.0 desc '- Change.'
out=$(run "$r" "$CONVERT" main)
assert_exit "no list: exit 0" 0 "$?"
assert_eq "no list: bump kept" 1.3.0 "$(jq -r .version "$r/$P/.claude-plugin/plugin.json")"

# 6. A version moved with no new CHANGELOG heading is left for manual work.
r=$(mkfixture)
write_plugin "$r" demo 1.2.1 desc "$BASE"
git -C "$r" commit -qam 'bump only' >/dev/null 2>&1
out=$(run "$r" "$CONVERT" main)
assert_exit "no heading: exit 1" 1 "$?"
assert_contains "names the plugin" "$out" "left for manual conversion: plugins/demo"
assert_eq "left untouched" 1.2.1 "$(jq -r .version "$r/$P/.claude-plugin/plugin.json")"

# 7. A major bump whose entry has two ### sections keeps both.
r=$(mkfixture)
bump "$r" demo 2.0.0 desc '### Removed

- Old flag.

### Fixed

- A crash.'
out=$(run "$r" "$CONVERT" main)
assert_exit "major bump converts" 0 "$?"
f=$(fragment "$r" demo)
assert_contains "major level" "$(cat "$r/$f")" "bump: major"
assert_contains "both sections kept" "$(cat "$r/$f")" "### Removed

- Old flag.

### Fixed

- A crash."

# 8. A branch that bumped twice: both new entries go into one fragment at the
#    level of the whole delta, and a plain-bullet second entry gets its own
#    Changed section instead of joining the first entry's last one.
r=$(mkfixture)
entry 1.3.0 6 '- Second change.' && E2=$E
entry 1.2.1 5 '### Fixed

- First fix.'
write_plugin "$r" demo 1.3.0 desc "$E2$E$BASE"
git -C "$r" commit -qam 'bump twice' >/dev/null 2>&1
out=$(run "$r" "$CONVERT" main)
assert_exit "double bump converts" 0 "$?"
f=$(fragment "$r" demo)
assert_eq "one fragment" 1 "$(printf '%s\n' "$f" | grep -c .)"
assert_contains "level of the whole delta" "$(cat "$r/$f")" "bump: minor"
assert_contains "both entries, each sectioned" "$(cat "$r/$f")" "### Changed

- Second change.

### Fixed

- First fix."
assert_eq "CHANGELOG back to base" "$(git -C "$r" show "main:$P/CHANGELOG.md")" "$(cat "$r/$P/CHANGELOG.md")"

# 9. A version that went down is left for manual work.
r=$(mkfixture)
bump "$r" demo 1.1.9 desc '- Odd.'
out=$(run "$r" "$CONVERT" main)
assert_exit "downgrade: exit 1" 1 "$?"
assert_contains "names the downgrade" "$out" "version went from 1.2.0 to 1.1.9"

# 10. A section name the fragment format does not know converts, and is named.
r=$(mkfixture)
bump "$r" demo 1.2.1 desc '### Notes

- Something.'
out=$(run "$r" "$CONVERT" main)
assert_exit "unknown section: exit 1" 1 "$?"
assert_contains "names the section" "$out" 'unknown section "### Notes"'
assert_contains "still converted" "$(cat "$r/$(fragment "$r" demo)")" "### Notes"

# 11. Mid-merge of main with no conflict: the merge tip is the base, and the
#     merge concludes after the conversion.
r=$(mkfixture)
bump "$r" demo 1.3.0 desc '### Added

- PR thing.'
{
  git -C "$r" checkout -q main
  write_plugin "$r" other 1.2.1 desc "$BASE"
  git -C "$r" commit -qam main
  git -C "$r" checkout -q pr
  git -C "$r" merge -q --no-commit --no-ff main
} >/dev/null 2>&1
out=$(run "$r" "$CONVERT")
assert_exit "mid-merge converts" 0 "$?"
assert_contains "mid-merge fragment" "$(cat "$r/$(fragment "$r" demo)")" "- PR thing."
assert_eq "main's change to other kept" 1.2.1 "$(jq -r .version "$r/plugins/other/.claude-plugin/plugin.json")"
GIT_EDITOR=true git -C "$r" merge --continue >/dev/null 2>&1
assert_exit "merge concludes" 0 "$?"

# 12. Mid-merge with the version files still conflicted: left for manual work.
r=$(mkfixture)
bump "$r" demo 1.3.0 a '- PR change.'
{
  git -C "$r" checkout -q main
  entry 1.2.1 4 '- Main change.'
  write_plugin "$r" demo 1.2.1 b "$E$BASE"
  git -C "$r" commit -qam main
  git -C "$r" checkout -q pr
  git -C "$r" merge -q main
} >/dev/null 2>&1
out=$(run "$r" "$CONVERT")
assert_exit "conflicted: exit 1" 1 "$?"
assert_contains "names the conflict" "$out" "still conflicted"

# 13. A rebase stopped on a conflict is refused.
{
  git -C "$r" merge --abort
  git -C "$r" rebase -q main
} >/dev/null 2>&1
out=$(run "$r" "$CONVERT" main)
assert_exit "rebase in progress: exit 2" 2 "$?"

# 14. Against the repository's real fragment scripts: the fragment passes
#     check-changelog-fragments.sh --check and --check-required, and
#     check-changelog-parity.sh --check-bump passes for the plugin.
if [[ -f $REPO_SCRIPTS/check-changelog-fragments.sh && -f $REPO_SCRIPTS/check-changelog-parity.sh ]]; then
  r=$(mkfixture)
  {
    cp "$REPO_SCRIPTS/new-changelog-fragment.sh" "$REPO_SCRIPTS/check-changelog-fragments.sh" \
      "$REPO_SCRIPTS/check-changelog-parity.sh" "$r/scripts/"
    git -C "$r" add -A && git -C "$r" commit -qm 'real scripts'
  } >/dev/null 2>&1
  bump "$r" demo 1.3.0 'new desc' '### Added

- **New thing.** Detail.

### Fixed

- A bug.'
  out=$(run "$r" "$CONVERT" main)
  assert_exit "real scripts: converts" 0 "$?"
  git -C "$r" commit -qm convert >/dev/null 2>&1
  out=$(run "$r" scripts/check-changelog-fragments.sh --check)
  assert_exit "fragment is valid ($out)" 0 "$?"
  out=$(run "$r" scripts/check-changelog-fragments.sh --check-required main)
  assert_exit "fragment satisfies --check-required ($out)" 0 "$?"
  out=$(run "$r" scripts/check-changelog-parity.sh --check-bump main)
  assert_exit "parity --check-bump passes ($out)" 0 "$?"
else
  skip_case "real fragment scripts not found at $REPO_SCRIPTS"
fi

# 15. Mid-merge after both sides bumped: main's 1.2.1 is the base, so the
#     version lands on it, main's entry stays, and only the PR's entry moves.
r=$(mkfixture)
bump "$r" demo 1.3.0 desc '### Added

- PR feature.'
{
  git -C "$r" checkout -q main
  entry 1.2.1 4 '### Fixed

- Main fix.'
  MAIN_ENTRY=$E
  write_plugin "$r" demo 1.2.1 desc "$E$BASE"
  git -C "$r" commit -qam main
  git -C "$r" checkout -q pr
  git -C "$r" merge -q main
  entry 1.3.0 5 '### Added

- PR feature.'
  write_plugin "$r" demo 1.3.0 desc "$E$MAIN_ENTRY$BASE"
  git -C "$r" add -A
} >/dev/null 2>&1
out=$(run "$r" "$CONVERT")
assert_exit "both bumped: converts" 0 "$?"
assert_eq "version lands on main's" 1.2.1 "$(jq -r .version "$r/$P/.claude-plugin/plugin.json")"
assert_eq "main's entry stays" "$(git -C "$r" show "main:$P/CHANGELOG.md")" "$(cat "$r/$P/CHANGELOG.md")"
f=$(fragment "$r" demo)
assert_contains "PR text in the fragment" "$(cat "$r/$f")" "- PR feature."
assert_not_contains "main's text not in the fragment" "$(cat "$r/$f")" "Main fix."
assert_contains "level against main's version" "$(cat "$r/$f")" "bump: minor"

# 16. A CHANGELOG heading added with no version change fails the parity gate,
#     so it is named, not passed.
r=$(mkfixture)
entry 1.2.1 5 '- Heading only.'
write_plugin "$r" demo 1.2.0 desc "$E$BASE"
git -C "$r" commit -qam 'heading only' >/dev/null 2>&1
out=$(run "$r" "$CONVERT" main)
assert_exit "heading without bump: exit 1" 1 "$?"
assert_contains "names it" "$out" "CHANGELOG.md gained a version heading but plugin.json stayed at 1.2.0"

# 17. A code fence holding # and ## lines: the ## line does not cut the entry
#     short, and the fragment the validator rejects is named.
r=$(mkfixture)
bump "$r" demo 1.2.1 desc '### Changed

- Example:

  ```bash
# comment
## not a heading
  ```

- After the fence.'
out=$(run "$r" "$CONVERT" main)
assert_exit "fenced headings: exit 1" 1 "$?"
assert_contains "names the fragment" "$out" "until scripts/check-changelog-fragments.sh --check passes"
f=$(fragment "$r" demo)
assert_contains "entry not cut at the fence" "$(cat "$r/$f")" "- After the fence."
assert_eq "CHANGELOG back to base" "$(git -C "$r" show "main:$P/CHANGELOG.md")" "$(cat "$r/$P/CHANGELOG.md")"

# 18. Staging fails (the index is locked): the bump and its entry are put back
#     and no fragment is left, so a re-run converts it.
r=$(mkfixture)
bump "$r" demo 1.3.0 desc '- Locked change.'
: >"$(git -C "$r" rev-parse --absolute-git-dir)/index.lock"
out=$(run "$r" "$CONVERT" main)
assert_exit "staging failure: exit 2" 2 "$?"
assert_eq "bump restored" 1.3.0 "$(jq -r .version "$r/$P/.claude-plugin/plugin.json")"
assert_contains "entry restored" "$(cat "$r/$P/CHANGELOG.md")" "- Locked change."
assert_eq "no fragment left" "" "$(find "$r/.changes" -type f -name '*.md' 2>/dev/null)"
rm -f "$(git -C "$r" rev-parse --absolute-git-dir)/index.lock"
out=$(run "$r" "$CONVERT" main)
assert_exit "re-run converts" 0 "$?"
assert_eq "re-run restores the version" 1.2.0 "$(jq -r .version "$r/$P/.claude-plugin/plugin.json")"

[[ $FAILED -eq 0 ]] || exit 1
