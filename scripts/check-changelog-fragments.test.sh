#!/usr/bin/env bash
# Unit tests for check-changelog-fragments.sh. Each case builds a throwaway git
# repo holding the gate, scripts/lib/ and a scripts/fragment-plugins.txt, and
# runs the gate against it.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-changelog-fragments.sh"
. "$SELF_DIR/test-git-helpers.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh"

f=""

# base_fixture <out-var> [listed...] — plugins alpha and beta at 1.0.0, the
# named ones in fragment mode, committed on main.
base_fixture() {
  local dir name
  fixture_tree::build "$1" --sut "$SCRIPT" --git --plugins --label fragments || return 1
  dir="${!1}"
  shift
  for name in alpha beta; do
    mkdir -p "$dir/plugins/$name/.claude-plugin" "$dir/plugins/$name/skills"
    printf '{\n  "name": "%s",\n  "version": "1.0.0"\n}\n' "$name" >"$dir/plugins/$name/.claude-plugin/plugin.json"
    printf '# Changelog\n\n## [1.0.0] - 2026-10-01\n\n### Added\n\n- First.\n' >"$dir/plugins/$name/CHANGELOG.md"
    printf 'v1\n' >"$dir/plugins/$name/skills/a.md"
  done
  printf '%s\n' '# fragment mode' "$@" >"$dir/scripts/fragment-plugins.txt"
  git_test_config "$dir" add -A
  git_test_config "$dir" commit -qm base
  git_test_config "$dir" branch -q -M main
}

# fragment <fixture> <plugin> <name> <bump> [body]
fragment() {
  local dir="$1" plugin="$2" name="$3" bump="$4" body="${5-### Fixed

- A fix.}"
  mkdir -p "$dir/.changes/$plugin"
  printf -- '---\nbump: %s\n---\n\n%s\n' "$bump" "$body" >"$dir/.changes/$plugin/$name.md"
}

commit() { git_test_config "$1" add -A && git_test_config "$1" commit -qm "$2"; }

# HEAD_REF, when set, is the CHANGELOG_HEAD_REF the gate sees, as CI passes it.
HEAD_REF=""
run_gate() (
  cd "$1" && shift && CHANGELOG_HEAD_REF="$HEAD_REF" bash scripts/check-changelog-fragments.sh "$@"
)

# expect <label> <rc> <needle> <fixture> <args...>
expect() {
  local label="$1" want="$2" needle="$3" fixture="$4" out rc
  shift 4
  out="$(run_gate "$fixture" "$@" 2>&1)"
  rc=$?
  if ((rc == want)) && [[ "$out" == *"$needle"* ]]; then
    ok "$label"
  else
    fail "$label: want rc=$want and '$needle', got rc=$rc: $out"
  fi
}

# --- --check ------------------------------------------------------------------
base_fixture f alpha
expect "--check passes with no .changes/ directory" 0 "All 0 changelog fragment(s)" "$f" --check
fragment "$f" alpha feat-x-0123abcd minor
fragment "$f" alpha fix-y-89abcdef none "Test-only change; nothing ships."
expect "--check passes valid minor and none fragments" 0 "All 2 changelog fragment(s)" "$f" --check
rm -rf "$f"

base_fixture f alpha
fragment "$f" beta feat-x-0123abcd minor
expect "--check rejects a fragment for a plugin not in fragment mode" 1 "NOT IN FRAGMENT MODE: .changes/beta/" "$f" --check
rm -rf "$f"

base_fixture f alpha
fragment "$f" gamma feat-x-0123abcd minor
expect "--check rejects a fragment for an unknown plugin" 1 "UNKNOWN PLUGIN" "$f" --check
rm -rf "$f"

base_fixture f alpha
fragment "$f" alpha feat-x minor
expect "--check rejects a name without the 8-hex suffix" 1 "FRAGMENT NAME" "$f" --check
rm -rf "$f"

base_fixture f alpha
mkdir -p "$f/.changes"
printf 'x\n' >"$f/.changes/stray.md"
expect "--check rejects a file directly under .changes/" 1 "MISPLACED FRAGMENT" "$f" --check
rm -rf "$f"

base_fixture f alpha
fragment "$f" alpha feat-x-0123abcd huge
expect "--check rejects an unknown bump level" 1 "bump must be major, minor, patch or none" "$f" --check
rm -rf "$f"

base_fixture f alpha
mkdir -p "$f/.changes/alpha"
printf -- '---\nbump: patch\nscope: x\n---\n\n### Fixed\n\n- x\n' >"$f/.changes/alpha/feat-x-0123abcd.md"
expect "--check rejects a front matter key other than bump" 1 "a key other than bump" "$f" --check
rm -rf "$f"

base_fixture f alpha
mkdir -p "$f/.changes/alpha"
printf '### Fixed\n\n- x\n' >"$f/.changes/alpha/feat-x-0123abcd.md"
expect "--check rejects a fragment without front matter" 1 "must open with ---" "$f" --check
rm -rf "$f"

base_fixture f alpha
fragment "$f" alpha feat-x-0123abcd patch "### Tweaked

- x"
expect "--check rejects an unknown section" 1 'unknown section "### Tweaked"' "$f" --check
rm -rf "$f"

base_fixture f alpha
fragment "$f" alpha feat-x-0123abcd patch "Just prose."
expect "--check rejects a release fragment with no ### section" 1 "no ### section" "$f" --check
rm -rf "$f"

base_fixture f alpha
fragment "$f" alpha feat-x-0123abcd patch "### Fixed

### Added

- x"
expect "--check rejects an empty section" 1 'section "### Fixed" is empty' "$f" --check
rm -rf "$f"

base_fixture f alpha
fragment "$f" alpha feat-x-0123abcd patch "## [9.9.9]

### Fixed

- x"
expect "--check rejects a ## heading in the body" 1 "would break the CHANGELOG structure" "$f" --check
rm -rf "$f"

base_fixture f alpha
fragment "$f" alpha feat-x-0123abcd none ""
expect "--check rejects a none fragment without a reason" 1 "no line saying why" "$f" --check
rm -rf "$f"

# --- --check-required -----------------------------------------------------------
base_fixture f alpha
git_test_config "$f" checkout -qb feat/x
printf 'v2\n' >"$f/plugins/alpha/skills/a.md"
commit "$f" change
expect "--check-required fails a fragment-mode change with no fragment" 1 "MISSING FRAGMENT: this change set changes files under plugins/alpha/" "$f" --check-required main
fragment "$f" alpha feat-x-0123abcd patch
commit "$f" fragment
expect "--check-required passes once a fragment is added" 0 "has a fragment" "$f" --check-required main
rm -rf "$f"

base_fixture f alpha
git_test_config "$f" checkout -qb feat/x
printf 'v2\n' >"$f/plugins/beta/skills/a.md"
commit "$f" change
expect "--check-required leaves a plugin not in fragment mode alone" 0 "has a fragment" "$f" --check-required main
rm -rf "$f"

base_fixture f alpha
fragment "$f" alpha feat-x-0123abcd patch
commit "$f" pending
git_test_config "$f" checkout -qb feat/y
printf 'v2\n' >"$f/plugins/alpha/skills/a.md"
fragment "$f" alpha feat-x-0123abcd none "Edited reason."
commit "$f" edit
expect "--check-required counts an edited fragment as covering the change" 0 "has a fragment" "$f" --check-required main
rm -rf "$f"

base_fixture f alpha
git_test_config "$f" checkout -qb feat/x
printf '{\n  "name": "alpha",\n  "version": "1.0.1"\n}\n' >"$f/plugins/alpha/.claude-plugin/plugin.json"
printf '# Changelog\n\n## [1.0.1] - 2026-10-02\n\n### Fixed\n\n- x\n\n## [1.0.0] - 2026-10-01\n\n### Added\n\n- First.\n' >"$f/plugins/alpha/CHANGELOG.md"
commit "$f" release
expect "--check-required asks a non-release change set that bumps by hand for a fragment" 1 "MISSING FRAGMENT: this change set changes files under plugins/alpha/" "$f" --check-required main
HEAD_REF=release/plugins
expect "--check-required exempts the release pull request's version-only manifest edit and CHANGELOG.md" 0 "has a fragment" "$f" --check-required main
HEAD_REF=release/plugins-fork
expect "--check-required grants the exemption to the exact release branch only" 1 "MISSING FRAGMENT" "$f" --check-required main
HEAD_REF=""
rm -rf "$f"

base_fixture f alpha
git_test_config "$f" checkout -qb feat/x
printf '# Changelog\n\n## [1.0.0] - 2026-10-01\n\n### Added\n\n- First, reworded.\n' >"$f/plugins/alpha/CHANGELOG.md"
commit "$f" reword
expect "--check-required asks for a fragment when a non-release change set edits CHANGELOG.md" 1 "MISSING FRAGMENT" "$f" --check-required main
fragment "$f" alpha feat-x-0123abcd none "Changelog wording only."
commit "$f" fragment
expect "--check-required accepts a bump: none fragment for a CHANGELOG.md edit" 0 "has a fragment" "$f" --check-required main
rm -rf "$f"

base_fixture f alpha
git_test_config "$f" checkout -qb release/plugins
printf 'v2\n' >"$f/plugins/alpha/skills/a.md"
commit "$f" smuggled
HEAD_REF=release/plugins
expect "--check-required still asks the release pull request for a fragment for a shipped file" 1 "MISSING FRAGMENT" "$f" --check-required main
HEAD_REF=""
rm -rf "$f"

base_fixture f alpha
git_test_config "$f" checkout -qb feat/x
printf '{\n  "name": "alpha",\n  "version": "1.0.0",\n  "description": "new"\n}\n' >"$f/plugins/alpha/.claude-plugin/plugin.json"
commit "$f" describe
expect "--check-required treats a manifest edit beyond version as shipped" 1 "MISSING FRAGMENT" "$f" --check-required main
rm -rf "$f"

base_fixture f alpha
git_test_config "$f" checkout -qb feat/x
fragment "$f" alpha feat-x-0123abcd patch
commit "$f" mine
git_test_config "$f" checkout -q main
fragment "$f" alpha feat-x-0123abcd minor
commit "$f" theirs
git_test_config "$f" checkout -q feat/x
expect "--check-required rejects an added fragment whose path exists on the base" 1 "FRAGMENT PATH TAKEN: .changes/alpha/feat-x-0123abcd.md" "$f" --check-required main
rm -rf "$f"

# --- --check-release ------------------------------------------------------------
# release_branch <fixture>: main holds alpha's fragment; release/plugins consumes
# it and bumps alpha.
release_branch() {
  fragment "$1" alpha feat-x-0123abcd minor
  commit "$1" pending
  git_test_config "$1" checkout -qb release/plugins
  git_test_config "$1" rm -q .changes/alpha/feat-x-0123abcd.md
  printf '{\n  "name": "alpha",\n  "version": "1.1.0"\n}\n' >"$1/plugins/alpha/.claude-plugin/plugin.json"
  commit "$1" release
}

base_fixture f alpha beta
release_branch "$f"
expect "--check-release passes when every fragment for a bumped plugin is consumed" 0 "for the 1 plugin(s) it bumps" "$f" --check-release main
git_test_config "$f" checkout -q main
fragment "$f" alpha late-z-fedcba98 patch
fragment "$f" beta late-z-fedcba98 patch
commit "$f" late
git_test_config "$f" checkout -q release/plugins
expect "--check-release fails on a fragment that landed on the base after the release was cut" 1 "UNCONSUMED FRAGMENT: .changes/alpha/late-z-fedcba98.md" "$f" --check-release main
out="$(run_gate "$f" --check-release main 2>&1)"
if [[ "$out" != *".changes/beta/"* ]]; then
  ok "--check-release ignores a pending fragment for a plugin the release does not bump"
else
  fail "--check-release should not name beta: $out"
fi
rm -rf "$f"

base_fixture f alpha
release_branch "$f"
git_test_config "$f" checkout -q main
fragment "$f" alpha feat-x-0123abcd minor "### Added

- Reworded after the release was cut."
commit "$f" edit-consumed
git_test_config "$f" checkout -q release/plugins
expect "--check-release fails when a consumed fragment was edited on the base after the cut" 1 "EDITED FRAGMENT: .changes/alpha/feat-x-0123abcd.md" "$f" --check-release main
rm -rf "$f"

# The merge queue: each queued pull request is one squash commit on top of main
# and the entries ahead of it, and the gate reads HEAD^1 as the landing base.
base_fixture f alpha
release_branch "$f"
release_commit="$(git -C "$f" rev-parse HEAD)"
git_test_config "$f" checkout -qb queue-alone main
git_test_config "$f" cherry-pick "$release_commit" >/dev/null
expect "--check-release HEAD^1 passes a queued release that lands on the base it was cut from" 0 "for the 1 plugin(s) it bumps" "$f" --check-release 'HEAD^1'
git_test_config "$f" checkout -qb queue-behind main
fragment "$f" alpha queued-a-0badc0de patch
commit "$f" "fragment pull request ahead in the queue"
git_test_config "$f" cherry-pick "$release_commit" >/dev/null
expect "--check-release HEAD^1 ejects a queued release behind a fragment for a plugin it bumps" 1 "UNCONSUMED FRAGMENT: .changes/alpha/queued-a-0badc0de.md" "$f" --check-release 'HEAD^1'
git_test_config "$f" checkout -qb queue-other main
printf 'v2\n' >"$f/plugins/beta/skills/a.md"
printf '{\n  "name": "beta",\n  "version": "1.0.1"\n}\n' >"$f/plugins/beta/.claude-plugin/plugin.json"
commit "$f" "legacy pull request"
expect "--check-release HEAD^1 passes a queued pull request that bumps a plugin with no fragments" 0 "for the 1 plugin(s) it bumps" "$f" --check-release 'HEAD^1'
rm -rf "$f"

# --- usage ------------------------------------------------------------------------
base_fixture f alpha
expect "no arguments exits 2" 2 "usage" "$f"
expect "--check-required without a ref exits 2" 2 "usage" "$f" --check-required
expect "an unresolvable base ref exits 2" 2 "not a resolvable commit" "$f" --check-release no-such-ref
rm -rf "$f"

test_harness::report
