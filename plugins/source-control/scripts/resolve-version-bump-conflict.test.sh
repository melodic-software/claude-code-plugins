#!/usr/bin/env bash
# Regression tests for resolve-version-bump-conflict.sh against throwaway git
# fixtures: one plugin at 1.2.0, a `pr` branch and `main` that each bump it and
# add a changelog entry, then a merge (or rebase) that stops on the conflict.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SCRIPT_DIR/resolve-version-bump-conflict.sh"

FAILED=0
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

command -v git >/dev/null 2>&1 || skip_suite "git not available"
command -v jq >/dev/null 2>&1 || skip_suite "jq not available"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

P=plugins/demo

# write_plugin <repo> <version> <description> <changelog-body>
write_plugin() {
  mkdir -p "$1/$P/.claude-plugin"
  printf '{\n  "name": "demo",\n  "version": "%s",\n  "description": "%s"\n}\n' "$2" "$3" >"$1/$P/.claude-plugin/plugin.json"
  printf '# Changelog\n\nIntro.\n\n%s' "$4" >"$1/$P/CHANGELOG.md"
}

# entry <version> <day> <text> — one changelog section into $E. printf -v,
# because a command substitution would strip its trailing blank line.
entry() { printf -v E '## [%s] - 2026-09-2%s\n\n- %s\n\n' "$1" "$2" "$3"; }
entry 1.2.0 1 'Base release.' && BASE=$E
entry 1.1.0 0 'Older release.' && BASE+=$E && OLDER=$E
entry 1.2.0 1 'Rewritten.' && REWRITTEN=$E$OLDER

# mkfixture <pr-version> <pr-description> <pr-old-entries> <main-version>
# Echoes the repo path. <pr-old-entries> replaces the base entries on the PR
# side (empty keeps them).
mkfixture() {
  local r
  r="$(mktemp -d "$TEST_TMPDIR/repoXXXXXX")"
  {
    git init -q -b main "$r"
    git -C "$r" config user.email t@t.t
    git -C "$r" config user.name t
    git -C "$r" config commit.gpgsign false
    git -C "$r" config core.autocrlf false
    write_plugin "$r" 1.2.0 desc "$BASE"
    git -C "$r" add -A && git -C "$r" commit -qm base
    git -C "$r" checkout -qb pr
    entry "$1" 5 'PR change.'
    write_plugin "$r" "$1" "$2" "$E${3:-$BASE}"
    git -C "$r" commit -qam pr
    git -C "$r" checkout -q main
    entry "$4" 4 'Main change.'
    write_plugin "$r" "$4" desc "$E$BASE"
    git -C "$r" commit -qam main
    git -C "$r" checkout -q pr
  } >/dev/null 2>&1
  printf '%s' "$r"
}

run() { (cd "$1" && "$RESOLVER") 2>&1; }
headings() { grep '^## ' "$1/$P/CHANGELOG.md" | tr '\n' '|'; }
ORDER='## [1.2.2] - 2026-09-25|## [1.2.1] - 2026-09-24|## [1.2.0] - 2026-09-21|## [1.1.0] - 2026-09-20|'

# 1. Same-number collision: both sides patch-bump to 1.2.1. plugin.json merges
#    cleanly, only CHANGELOG conflicts; the manifest must still move to 1.2.2
#    and be staged.
r=$(mkfixture 1.2.1 desc '' 1.2.1)
git -C "$r" merge -q main >/dev/null 2>&1
out=$(run "$r")
assert_exit "same-number collision exits 0" 0 "$?"
assert_eq "manifest bumped past both" 1.2.2 "$(jq -r .version "$r/$P/.claude-plugin/plugin.json")"
assert_eq "manifest staged" 1.2.2 "$(git -C "$r" show ":$P/.claude-plugin/plugin.json" | jq -r .version)"
assert_eq "PR entry re-headed above main's" "$ORDER" "$(headings "$r")"
assert_contains "PR text kept" "$(cat "$r/$P/CHANGELOG.md")" "PR change."
assert_contains "main text kept" "$(cat "$r/$P/CHANGELOG.md")" "Main change."
assert_not_contains "no markers" "$(cat "$r/$P/CHANGELOG.md")" "<<<<<<<"
GIT_EDITOR=true git -C "$r" merge --continue >/dev/null 2>&1
assert_exit "merge concludes" 0 "$?"

# 2. PR minor-bumps (1.3.0), main patch-bumps (1.2.1): the higher (1.3.0) plus
#    one minor. The PR's unrelated description edit survives the merge.
r=$(mkfixture 1.3.0 'new desc' '' 1.2.1)
git -C "$r" merge -q main >/dev/null 2>&1
out=$(run "$r")
assert_exit "mixed levels exit 0" 0 "$?"
assert_eq "higher version plus the PR's level" 1.4.0 "$(jq -r .version "$r/$P/.claude-plugin/plugin.json")"
assert_eq "PR's other manifest edit kept" "new desc" "$(jq -r .description "$r/$P/.claude-plugin/plugin.json")"
assert_eq "no unmerged paths left" "" "$(git -C "$r" diff --name-only --diff-filter=U)"

# 3. Rebase orientation: the PR commit replayed onto main (sides inverted).
r=$(mkfixture 1.2.1 desc '' 1.2.1)
git -C "$r" rebase -q main >/dev/null 2>&1
out=$(run "$r")
assert_exit "rebase exits 0" 0 "$?"
assert_eq "rebase: PR entry on top at 1.2.2" "$ORDER" "$(headings "$r")"

# 4. The PR also rewrote an old entry main left alone: merged in.
r=$(mkfixture 1.2.1 desc "$REWRITTEN" 1.2.1)
git -C "$r" merge -q main >/dev/null 2>&1
out=$(run "$r")
assert_exit "PR-only old-entry edit still resolves" 0 "$?"
assert_contains "PR's old-entry rewrite kept" "$(cat "$r/$P/CHANGELOG.md")" "Rewritten."

# 5. Main rewrote that same entry differently: left for manual resolution.
r=$(mkfixture 1.2.1 desc "$REWRITTEN" 1.2.1)
entry 1.2.1 4 'Main change.' && m=$E
entry 1.2.0 1 'Main rewrote this.' && m+=$E$OLDER
{
  git -C "$r" checkout -q main
  write_plugin "$r" 1.2.1 desc "$m"
  git -C "$r" commit -qam main2
  git -C "$r" checkout -q pr
  git -C "$r" merge -q main
} >/dev/null 2>&1
out=$(run "$r")
assert_exit "both sides rewrote an old entry: exit 1" 1 "$?"
assert_contains "names the plugin" "$out" "left for manual resolution: $P"
assert_contains "markers untouched" "$(cat "$r/$P/CHANGELOG.md")" "<<<<<<<"

[[ $FAILED -eq 0 ]] || exit 1
