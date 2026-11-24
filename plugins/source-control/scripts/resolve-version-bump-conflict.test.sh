#!/usr/bin/env bash
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

r=$(mkfixture 1.3.0 'new desc' '' 1.2.1)
git -C "$r" merge -q main >/dev/null 2>&1
out=$(run "$r")
assert_exit "mixed levels exit 0" 0 "$?"
assert_eq "main's version plus the PR's level" 1.3.0 "$(jq -r .version "$r/$P/.claude-plugin/plugin.json")"
assert_eq "PR's other manifest edit kept" "new desc" "$(jq -r .description "$r/$P/.claude-plugin/plugin.json")"
assert_eq "no unmerged paths left" "" "$(git -C "$r" diff --name-only --diff-filter=U)"

r=$(mkfixture 1.2.1 desc '' 1.2.1)
git -C "$r" rebase -q main >/dev/null 2>&1
out=$(run "$r")
assert_exit "rebase exits 0" 0 "$?"
assert_eq "rebase: PR entry on top at 1.2.2" "$ORDER" "$(headings "$r")"

r=$(mkfixture 1.2.1 desc "$REWRITTEN" 1.2.1)
git -C "$r" merge -q main >/dev/null 2>&1
out=$(run "$r")
assert_exit "PR-only old-entry edit still resolves" 0 "$?"
assert_contains "PR's old-entry rewrite kept" "$(cat "$r/$P/CHANGELOG.md")" "Rewritten."

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

r=$(mkfixture 1.3.0 desc '' 1.2.1)
{ git -C "$r" checkout -q main && git -C "$r" merge -q pr; } >/dev/null 2>&1
out=$(run "$r")
assert_exit "merge onto the default branch: exit 1" 1 "$?"
assert_contains "names the plugin" "$out" "left for manual resolution: $P"
assert_contains "markers untouched" "$(cat "$r/$P/CHANGELOG.md")" "<<<<<<<"

r=$(mkfixture 1.2.1 desc '' 1.2.1)
entry 1.2.2 6 'Later change.'
{
  write_plugin "$r" 1.2.2 desc "$E$(sed '1,4d' "$r/$P/CHANGELOG.md")"
  git -C "$r" commit -qam later
  git -C "$r" revert --no-edit HEAD~1
} >/dev/null 2>&1
if git -C "$r" rev-parse -q --verify REVERT_HEAD >/dev/null; then
  out=$(run "$r")
  assert_exit "conflicted revert: exit 1" 1 "$?"
  assert_contains "names the plugin" "$out" "left for manual resolution: $P"
else
  assert_eq "revert fixture conflicts" conflicted clean
fi

for listed in demo other; do
  r=$(mkfixture 1.2.1 desc '' 1.2.1)
  {
    git -C "$r" checkout -q main
    mkdir -p "$r/scripts"
    printf '# comment\n%s  # inline\n' "$listed" >"$r/scripts/fragment-plugins.txt"
    git -C "$r" add -A && git -C "$r" commit -qm list
    git -C "$r" checkout -q pr
    git -C "$r" merge -q main
  } >/dev/null 2>&1
  out=$(run "$r")
  rc=$?
  if [[ $listed == demo ]]; then
    assert_exit "fragment-mode plugin: exit 1" 1 "$rc"
    assert_contains "names fragment mode" "$out" "$P is in fragment mode"
    assert_contains "markers untouched" "$(cat "$r/$P/CHANGELOG.md")" "<<<<<<<"
  else
    assert_exit "list naming another plugin: exit 0" 0 "$rc"
    assert_eq "list naming another plugin: resolved" "$ORDER" "$(headings "$r")"
  fi
done

for file in CHANGELOG.md .claude-plugin/plugin.json; do
  r=$(mkfixture 1.2.1 desc '' 1.2.1)
  git -C "$r" merge -q main >/dev/null 2>&1
  outside="$(mktemp "$TEST_TMPDIR/outsideXXXXXX")"
  printf 'outside\n' >"$outside"
  rm -f "$r/$P/$file"
  ln -s "$outside" "$r/$P/$file"
  out=$(run "$r")
  assert_exit "symlinked $file: exit 1" 1 "$?"
  assert_contains "symlinked $file: names the plugin" "$out" "left for manual resolution: $P"
  assert_eq "symlinked $file: target untouched" outside "$(cat "$outside")"
  assert_eq "symlinked $file: link kept" "$outside" "$(readlink "$r/$P/$file")"
  for target in "$TEST_TMPDIR/missing" "$TEST_TMPDIR"; do
    rm -f "$r/$P/$file"
    ln -s "$target" "$r/$P/$file"
    out=$(run "$r")
    assert_exit "$file linked to $target: exit 1" 1 "$?"
    assert_contains "$file linked to $target: names the plugin" "$out" "left for manual resolution: $P"
  done
done

[[ $FAILED -eq 0 ]] || exit 1
