#!/usr/bin/env bash
# Unit tests for dependabot-fragments.sh, driven through its CLI against a
# throwaway repository whose history holds Dependabot squash merges.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/dependabot-fragments.sh"
. "$SELF_DIR/test-git-helpers.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh"

f=""
fixture() {
  local dir name
  fixture_tree::build "$1" --sut "$SCRIPT" --git --plugins --label dependabot-fragments || return 1
  dir="${!1}"
  for name in alpha beta; do
    mkdir -p "$dir/plugins/$name/.claude-plugin" "$dir/plugins/$name/server"
    printf '{"name":"%s","version":"1.0.0"}\n' "$name" >"$dir/plugins/$name/.claude-plugin/plugin.json"
    printf '{}\n' >"$dir/plugins/$name/server/package-lock.json"
  done
  printf 'alpha\n' >"$dir/scripts/fragment-plugins.txt"
  git_test_config "$dir" add -A
  git_test_config "$dir" commit -qm base
}
commit() { git_test_config "$1" add -A && git_test_config "$1" commit -qm "$2"; }
# dependabot_merge <dir> <message>: a squash merge as Dependabot authors it.
dependabot_merge() (
  export GIT_AUTHOR_NAME='dependabot[bot]' GIT_AUTHOR_EMAIL='49699333+dependabot[bot]@users.noreply.github.com'
  commit "$1" "$2"
)
run() (cd "$1" && bash scripts/dependabot-fragments.sh "${@:2}")

fixture f
printf 'x\n' >>"$f/plugins/alpha/server/package-lock.json"
printf 'y\n' >>"$f/plugins/beta/server/package-lock.json"
dependabot_merge "$f" $'build(deps): Bump the npm-minor-patch group (#7)\n\nUpdates `zod` from 1.0.0 to 1.0.1\nUpdates `ajv` from 8.1.0 to 8.2.0'
sha="$(git -C "$f" rev-parse HEAD)"
printf 'z\n' >>"$f/plugins/alpha/server/package-lock.json"
commit "$f" "fix(alpha): a person's change (#8)"
out="$(run "$f")"
rc=$?
want_path=".changes/alpha/dependabot-7-${sha:0:8}.md"
# shellcheck disable=SC2016  # the backticks are Markdown in the expected fragment
want='---
bump: patch
---

### Changed

- **Bump the npm-minor-patch group** (#7).
  - `ajv` 8.1.0→8.2.0
  - `zod` 1.0.0→1.0.1'
if ((rc == 0)) && [[ "$out" == "$want_path" && "$(cat "$f/$want_path" 2>/dev/null)" == "$want" ]]; then
  ok "writes one patch fragment per merged Dependabot update of a fragment-mode plugin, with its dependency lines"
else
  fail "rc=$rc out='$out' content='$(cat "$f/$want_path" 2>/dev/null)'"
fi
if [[ ! -e "$f/.changes/beta" ]]; then
  ok "writes nothing for a legacy plugin, which the pull request bumped itself"
else
  fail "wrote a fragment for legacy beta"
fi
if [[ -z "$(run "$f")" ]]; then
  ok "a second run writes nothing while the fragment is in the working tree"
else
  fail "a second run wrote again"
fi
commit "$f" "chore(release): changelog fragments for merged Dependabot updates (#9)"
git_test_config "$f" rm -q "$want_path"
git_test_config "$f" commit -qm "chore(release): release 1 plugins (#10)"
if [[ -z "$(run "$f")" && ! -e "$f/$want_path" ]]; then
  ok "a fragment a release already consumed is not written again"
else
  fail "rewrote a consumed fragment"
fi
rm -rf "$f"

# A merge from before the plugin's flip bumped the plugin itself; one that added
# its own fragment needs no second one.
fixture f
printf 'x\n' >>"$f/plugins/beta/server/package-lock.json"
dependabot_merge "$f" "build(deps): Bump zod in /plugins/beta/server (#11)"
printf 'beta\n' >>"$f/scripts/fragment-plugins.txt"
commit "$f" "feat(release): put beta in fragment mode (#12)"
printf 'x\n' >>"$f/plugins/alpha/server/package-lock.json"
mkdir -p "$f/.changes/alpha"
printf -- '---\nbump: patch\n---\n\n### Changed\n\n- Old-style fragment.\n' >"$f/.changes/alpha/dependabot-npm-0123abcd.md"
dependabot_merge "$f" "build(deps): Bump zod in /plugins/alpha/server (#13)"
printf 'y\n' >>"$f/plugins/beta/server/package-lock.json"
dependabot_merge "$f" "build(deps): Bump ajv in /plugins/beta/server (#15)"
out="$(run "$f")"
if [[ $? -eq 0 && "$out" =~ ^\.changes/beta/dependabot-15-[0-9a-f]{8}\.md$ ]]; then
  ok "skips a merge from before the plugin's flip and one that carried its own fragment, not one after the flip"
else
  fail "expected only the #15 fragment, got: $out"
fi
rm -rf "$f"

# A plugin whose CHANGELOG.md takes no em dash gets a hyphen in its place.
fixture f
printf 'plugins/alpha/CHANGELOG.md\n' >"$f/scripts/em-dash-purged-paths.txt"
commit "$f" "purge"
printf 'x\n' >>"$f/plugins/alpha/server/package-lock.json"
dependabot_merge "$f" $'build(deps): Bump zod \xe2\x80\x94 security (#14)'
out="$(run "$f")"
if [[ $? -eq 0 && -n "$out" ]] && grep -qF -- '- **Bump zod - security** (#14).' "$f/$out"; then
  ok "replaces an em dash so the fragment fits a purged CHANGELOG.md"
else
  fail "em dash: out='$out' content='$(cat "$f/$out" 2>/dev/null)'"
fi
rm -rf "$f"

test_harness::report
