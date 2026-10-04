#!/usr/bin/env bash
# Unit tests for release-plugins.sh. Each case builds a throwaway git repo with
# plugins in fragment mode, commits fragments in a known order, runs the release
# and compares the written CHANGELOG and manifest against literal expectations.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/release-plugins.sh"
. "$SELF_DIR/test-git-helpers.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh"

f=""

# base_fixture <out-var> — alpha 1.2.3 and beta 0.4.0, both in fragment mode.
base_fixture() {
  local dir name
  fixture_tree::build "$1" --sut "$SCRIPT" --git --plugins --label release || return 1
  dir="${!1}"
  for name in alpha beta; do
    mkdir -p "$dir/plugins/$name/.claude-plugin"
    printf '# Changelog\n\nIntro.\n\n## [0.0.1] - 2026-01-01\n\n### Added\n\n- First.\n' >"$dir/plugins/$name/CHANGELOG.md"
  done
  printf '{\n  "name": "alpha",\n  "version": "1.2.3",\n  "options": ["a", "b"]\n}\n' >"$dir/plugins/alpha/.claude-plugin/plugin.json"
  printf '{\n  "name": "beta",\n  "version": "0.4.0"\n}\n' >"$dir/plugins/beta/.claude-plugin/plugin.json"
  printf 'alpha\nbeta\n' >"$dir/scripts/fragment-plugins.txt"
  git_test_config "$dir" add -A
  git_test_config "$dir" commit -qm base
}

# add_fragment <fixture> <plugin> <name> <bump> <body> — written and committed.
add_fragment() {
  mkdir -p "$1/.changes/$2"
  printf -- '---\nbump: %s\n---\n\n%s\n' "$4" "$5" >"$1/.changes/$2/$3.md"
  git_test_config "$1" add -A
  git_test_config "$1" commit -qm "fragment $3"
}

run_release() (
  cd "$1" && bash scripts/release-plugins.sh --date 2026-10-04
)

# expect_file <label> <path> <expected content>
expect_file() {
  local got
  got="$(cat "$2")"
  if [[ "$got" == "$3" ]]; then
    ok "$1"
  else
    fail "$1: got
$got
--- want
$3"
  fi
}

# --- several fragments: one version at the highest bump, sections merged -------
base_fixture f
# Committed z-first so commit order differs from file-name order.
add_fragment "$f" alpha zeta-11111111 patch "### Fixed

- Zeta fix."
add_fragment "$f" alpha alpha-22222222 minor "### Added

- Alpha feature.

### Fixed

- Alpha fix."
add_fragment "$f" alpha mid-33333333 none "Docs only."
out="$(run_release "$f" 2>&1)"
rc=$?
if ((rc == 0)) && [[ "$out" == *"alpha: 1.2.3 -> 1.3.0 (minor) from 3 fragment(s)"* ]]; then
  ok "raises the version once, at the highest bump among the fragments"
else
  fail "expected alpha 1.2.3 -> 1.3.0, got rc=$rc: $out"
fi
expect_file "writes one entry, Keep a Changelog section order, fragments in commit order" \
  "$f/plugins/alpha/CHANGELOG.md" '# Changelog

Intro.

## [1.3.0] - 2026-10-04

### Added

- Alpha feature.

### Fixed

- Zeta fix.

- Alpha fix.

## [0.0.1] - 2026-01-01

### Added

- First.'
expect_file "changes only the version line of plugin.json" \
  "$f/plugins/alpha/.claude-plugin/plugin.json" '{
  "name": "alpha",
  "version": "1.3.0",
  "options": ["a", "b"]
}'
if [[ ! -e "$f/.changes/alpha" ]]; then
  ok "deletes every consumed fragment, none included"
else
  fail "fragments left behind: $(ls "$f/.changes/alpha")"
fi
expect_file "leaves a plugin with no fragments alone" "$f/plugins/beta/.claude-plugin/plugin.json" '{
  "name": "beta",
  "version": "0.4.0"
}'
rm -rf "$f"

# --- major and patch arithmetic -------------------------------------------------
base_fixture f
add_fragment "$f" alpha a-11111111 major "### Removed

- Old thing."
add_fragment "$f" beta b-22222222 patch "### Fixed

- Beta fix."
out="$(run_release "$f" 2>&1)"
if [[ "$out" == *"alpha: 1.2.3 -> 2.0.0"* && "$out" == *"beta: 0.4.0 -> 0.4.1"* ]]; then
  ok "major resets minor and patch; patch raises patch"
else
  fail "expected alpha 2.0.0 and beta 0.4.1, got: $out"
fi
rm -rf "$f"

# --- all-none plugin: fragments deleted, no bump, no entry ---------------------
base_fixture f
add_fragment "$f" beta b-22222222 none "Test fixture refresh only."
before="$(cat "$f/plugins/beta/CHANGELOG.md")"
out="$(run_release "$f" 2>&1)"
if [[ "$out" == *"beta: no release"* && ! -e "$f/.changes/beta/b-22222222.md" ]]; then
  ok "deletes a bump: none fragment without releasing"
else
  fail "expected the none fragment deleted with no release, got: $out"
fi
expect_file "an all-none plugin keeps its version" "$f/plugins/beta/.claude-plugin/plugin.json" '{
  "name": "beta",
  "version": "0.4.0"
}'
expect_file "an all-none plugin gets no CHANGELOG entry" "$f/plugins/beta/CHANGELOG.md" "$before"
rm -rf "$f"

# --- a release note keeps its backslashes ---------------------------------------
base_fixture f
# shellcheck disable=SC2016  # the backticks are markdown, not command substitution
add_fragment "$f" beta b-22222222 patch '### Fixed

- Match `a\nb` and `C:\temp` literally.'
run_release "$f" >/dev/null 2>&1
# shellcheck disable=SC2016  # see above
if grep -qF -- '- Match `a\nb` and `C:\temp` literally.' "$f/plugins/beta/CHANGELOG.md"; then
  ok "copies a fragment body byte for byte, backslashes included"
else
  fail "backslashes were rewritten: $(cat "$f/plugins/beta/CHANGELOG.md")"
fi
rm -rf "$f"

# --- nothing pending ---------------------------------------------------------------
base_fixture f
out="$(run_release "$f" 2>&1)"
if [[ $? -eq 0 && "$out" == "No pending changelog fragments." ]]; then
  ok "exits 0 with nothing pending"
else
  fail "expected the nothing-pending message, got: $out"
fi
rm -rf "$f"

# --- an invalid fragment stops the release before anything is written -----------
base_fixture f
add_fragment "$f" alpha a-11111111 minor "### Added

- Fine."
add_fragment "$f" beta b-22222222 patch "No sections."
out="$(run_release "$f" 2>&1)"
rc=$?
if ((rc == 2)) && grep -q '"version": "1.2.3"' "$f/plugins/alpha/.claude-plugin/plugin.json" && [[ -f "$f/.changes/alpha/a-11111111.md" ]]; then
  ok "an invalid fragment exits 2 and writes nothing"
else
  fail "expected exit 2 and an untouched tree, got rc=$rc: $out"
fi
rm -rf "$f"

# --- a plugin not in fragment mode is refused ------------------------------------
base_fixture f
printf 'alpha\n' >"$f/scripts/fragment-plugins.txt"
add_fragment "$f" beta b-22222222 patch "### Fixed

- x"
out="$(run_release "$f" 2>&1)"
if [[ $? -eq 2 && "$out" == *"NOT IN FRAGMENT MODE"* ]]; then
  ok "refuses a fragment for a plugin not in fragment mode"
else
  fail "expected exit 2 naming the mode, got: $out"
fi
rm -rf "$f"

# --- a failure producing a later plugin's files leaves the whole tree unchanged ---
# beta's manifest has one line that starts with "version", but the first match on
# it is the nested key, so the rewrite misses the top-level version. alpha sorts
# first and has already been produced when beta fails.
base_fixture f
printf '{"name": "beta", "meta": {\n  "version": "0.4.0" }, "version": "0.4.0"}\n' >"$f/plugins/beta/.claude-plugin/plugin.json"
add_fragment "$f" alpha a-11111111 minor "### Added

- x"
add_fragment "$f" beta b-22222222 patch "### Fixed

- y"
out="$(run_release "$f" 2>&1)"
rc=$?
if ((rc == 2)) && [[ -z "$(git -C "$f" status --porcelain)" ]]; then
  ok "a failure producing a later plugin's files exits 2 and leaves the tree unchanged"
else
  fail "expected exit 2 and a clean tree, got rc=$rc: $out; status: $(git -C "$f" status --porcelain)"
fi
rm -rf "$f"

# --- a rerun after a run cut short does not write a second entry ------------------
base_fixture f
add_fragment "$f" alpha a-11111111 minor "### Added

- x"
printf '\n## [1.3.0] - 2026-10-04\n' >>"$f/plugins/alpha/CHANGELOG.md"
out="$(run_release "$f" 2>&1)"
if [[ $? -eq 2 && "$out" == *"already has a '## [1.3.0]' entry"* ]]; then
  ok "refuses to write a version the changelog already carries"
else
  fail "expected exit 2 naming the existing entry, got: $out"
fi
rm -rf "$f"

# --- a shallow clone is refused, since commit order is unknown -------------------
base_fixture f
add_fragment "$f" alpha a-11111111 minor "### Added

- x"
add_fragment "$f" alpha b-22222222 patch "### Fixed

- y"
g=""
fixture_tree::build g --label release-shallow || exit 2
git clone -q --depth 1 "file://$f" "$g/repo" 2>/dev/null
out="$(cd "$g/repo" && bash scripts/release-plugins.sh --date 2026-10-04 2>&1)"
rc=$?
if ((rc == 2)) && [[ "$out" == *"shallow"* ]] && grep -q '"version": "1.2.3"' "$g/repo/plugins/alpha/.claude-plugin/plugin.json"; then
  ok "refuses a shallow clone with exit 2 and writes nothing"
else
  fail "expected exit 2 naming the shallow clone, got rc=$rc: $out"
fi
rm -rf "$f" "$g"

# --- usage ------------------------------------------------------------------------
base_fixture f
out="$(cd "$f" && bash scripts/release-plugins.sh --date tomorrow 2>&1)"
if [[ $? -eq 2 && "$out" == *usage* ]]; then
  ok "a malformed --date exits 2"
else
  fail "expected usage exit 2, got: $out"
fi
rm -rf "$f"

test_harness::report
