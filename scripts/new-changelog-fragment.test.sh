#!/usr/bin/env bash
# Unit tests for new-changelog-fragment.sh: the name it gives a fragment, the
# front matter it writes, and the cases it refuses. The fragment it writes is
# filled in the way a contributor would and run through the shared validator.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/new-changelog-fragment.sh"
. "$SELF_DIR/test-git-helpers.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh"

f=""

base_fixture() {
  local dir
  fixture_tree::build "$1" --sut "$SCRIPT" --git --plugins --label new-fragment || return 1
  dir="${!1}"
  mkdir -p "$dir/plugins/alpha/.claude-plugin" "$dir/plugins/beta/.claude-plugin"
  printf '{"name":"alpha","version":"1.0.0"}\n' >"$dir/plugins/alpha/.claude-plugin/plugin.json"
  printf '{"name":"beta","version":"1.0.0"}\n' >"$dir/plugins/beta/.claude-plugin/plugin.json"
  printf 'alpha # pilot\n' >"$dir/scripts/fragment-plugins.txt"
  git_test_config "$dir" add -A
  git_test_config "$dir" commit -qm base
  git_test_config "$dir" checkout -qb Feat/Some_Thing
}

run_new() (
  cd "$1" && shift && bash scripts/new-changelog-fragment.sh "$@"
)

base_fixture f
first="$(run_new "$f" alpha minor)"
rc=$?
second="$(run_new "$f" alpha minor)"
if ((rc == 0)) && [[ "$first" =~ ^\.changes/alpha/feat-some_thing-[0-9a-f]{8}\.md$ ]]; then
  ok "names the fragment after the branch slug plus 8 hex characters"
else
  fail "unexpected path (rc=$rc): $first"
fi
if [[ "$first" != "$second" && -f "$f/$first" && -f "$f/$second" ]]; then
  ok "two fragments from one branch get different names"
else
  fail "expected two distinct files, got '$first' and '$second'"
fi
if [[ "$(cat "$f/$first")" == $'---\nbump: minor\n---' ]]; then
  ok "writes the front matter with the requested bump"
else
  fail "unexpected content: $(cat "$f/$first")"
fi
printf '### Added\n\n- New thing.\n' >>"$f/$first"
# shellcheck source=lib/changelog-fragments.sh
if (cd "$f" && . scripts/lib/changelog-fragments.sh && changelog_fragments::validate "$first"); then
  ok "a created fragment, once filled in, passes validation"
else
  fail "the filled-in fragment failed validation"
fi
rm -rf "$f"

base_fixture f
out="$(run_new "$f" beta patch 2>&1)"
if [[ $? -eq 2 && "$out" == *"not in fragment mode"* && ! -e "$f/.changes" ]]; then
  ok "refuses a plugin that is not in fragment mode"
else
  fail "expected exit 2 for beta, got: $out"
fi
out="$(run_new "$f" gamma patch 2>&1)"
if [[ $? -eq 2 && "$out" == *"no plugin named 'gamma'"* ]]; then
  ok "refuses an unknown plugin"
else
  fail "expected exit 2 for gamma, got: $out"
fi
out="$(run_new "$f" alpha huge 2>&1)"
if [[ $? -eq 2 && "$out" == *usage* ]]; then
  ok "refuses an unknown bump level"
else
  fail "expected usage exit 2, got: $out"
fi
git_test_config "$f" checkout -qb _lead
lead="$(run_new "$f" alpha patch)"
[[ -f "$f/$lead" ]] && printf '### Fixed\n\n- x\n' >>"$f/$lead"
# shellcheck source=lib/changelog-fragments.sh
if [[ "$lead" =~ ^\.changes/alpha/lead-[0-9a-f]{8}\.md$ ]] && (cd "$f" && . scripts/lib/changelog-fragments.sh && changelog_fragments::validate "$lead"); then
  ok "strips a leading non-alphanumeric so the slug passes validation"
else
  fail "expected .changes/alpha/lead-<hex>.md that validates, got: $lead"
fi
git_test_config "$f" checkout -qb __
out="$(run_new "$f" alpha patch 2>&1)"
if [[ $? -eq 2 && "$out" == *"no letter or digit"* ]]; then
  ok "refuses a branch with no letter or digit"
else
  fail "expected exit 2 for branch __, got: $out"
fi
git_test_config "$f" checkout -q --detach
out="$(run_new "$f" alpha patch 2>&1)"
if [[ $? -eq 2 && "$out" == *"not on a branch"* ]]; then
  ok "refuses a detached HEAD"
else
  fail "expected exit 2 on a detached HEAD, got: $out"
fi
rm -rf "$f"

# --- several plugins, --carriers-of, and a body from stdin -------------------
# alpha and gamma are in fragment mode, beta is not; lib/esc.mjs is carried by
# alpha (twice), beta and gamma, lib/other.sh by gamma only.
multi_fixture() {
  local dir
  fixture_tree::build "$1" --sut "$SCRIPT" --sut sync-shared-copies.sh --git --plugins --label new-fragment || return 1
  dir="${!1}"
  for name in alpha beta gamma; do
    mkdir -p "$dir/plugins/$name/.claude-plugin"
    printf '{"name":"%s","version":"1.0.0"}\n' "$name" >"$dir/plugins/$name/.claude-plugin/plugin.json"
  done
  mkdir -p "$dir/lib"
  printf 'export const esc = (s) => s;\n' >"$dir/lib/esc.mjs"
  printf 'echo other\n' >"$dir/lib/other.sh"
  printf '%s\n' "lib/esc.mjs plugins/alpha/lib/esc.mjs" "lib/esc.mjs plugins/alpha/scripts/esc.mjs" \
    "lib/esc.mjs plugins/beta/lib/esc.mjs" "lib/esc.mjs plugins/gamma/lib/esc.mjs" \
    "lib/other.sh plugins/gamma/scripts/other.sh" >"$dir/scripts/shared-copies.txt"
  printf 'alpha\ngamma\n' >"$dir/scripts/fragment-plugins.txt"
  git_test_config "$dir" add -A
  git_test_config "$dir" commit -qm base
  git_test_config "$dir" checkout -qb sync/esc
}
declare -A want=()
body=$'### Changed\n\n- Shared `esc.mjs` synced.'

# The reference: one run per plugin, each body appended by hand.
multi_fixture f
for name in alpha gamma; do
  p="$(run_new "$f" "$name" patch)" && printf '%s\n' "$body" >>"$f/$p"
  want[$name]="$(cat "$f/$p")"
done
rm -rf "$f"

multi_fixture f
out="$(run_new "$f" --stdin --carriers-of lib/esc.mjs patch <<<"$body" 2>"$f/.git/err")"
rc=$?
err="$(cat "$f/.git/err")"
mapfile -t paths <<<"$out"
if ((rc == 0 && ${#paths[@]} == 2)) && [[ "${paths[0]}" == .changes/alpha/sync-esc-* && "${paths[1]}" == .changes/gamma/sync-esc-* ]]; then
  ok "--carriers-of writes one fragment per fragment-mode carrier, a carrier with two copies once"
else
  fail "expected one alpha and one gamma fragment (rc=$rc): $out"
fi
same=1
for p in "${paths[@]}"; do
  name="${p#.changes/}"
  [[ "$(cat "$f/$p" 2>/dev/null)" == "${want[${name%%/*}]}" ]] || same=0
done
if ((same)); then
  ok "--carriers-of with --stdin writes what a per-plugin loop plus a hand-appended body writes"
else
  fail "fragment content differs from the per-plugin loop"
fi
if [[ "$err" == *"skipped 'beta': not in fragment mode"* && ! -e "$f/.changes/beta" ]]; then
  ok "--carriers-of skips a legacy carrier with a note"
else
  fail "expected a skip note for beta and no beta fragment: $err"
fi
out="$(run_new "$f" --carriers-of lib/esc.mjs --carriers-of lib/other.sh gamma alpha minor 2>/dev/null)"
if [[ "$(grep -c '^\.changes/gamma/' <<<"$out")" == 1 && "$(grep -c '^\.changes/alpha/' <<<"$out")" == 1 ]]; then
  ok "a plugin reached through several canonicals and by name gets one fragment"
else
  fail "expected one gamma and one alpha fragment: $out"
fi
out="$(run_new "$f" --carriers-of lib/missing.mjs patch 2>&1)"
if [[ $? -eq 2 && "$out" == *"not a canonical in scripts/shared-copies.txt"* ]]; then
  ok "refuses a path that is not a registered canonical"
else
  fail "expected exit 2 for an unregistered canonical, got: $out"
fi
rm -rf "$f"

multi_fixture f
out="$(run_new "$f" --stdin alpha gamma patch 2>&1 <<<$'### Added\n\nText with no list item is fine, but\n## a level-2 heading is not')"
if [[ $? -eq 2 && "$out" == *"wrote nothing"* && -z "$(find "$f/.changes" -type f 2>/dev/null)" ]]; then
  ok "an invalid --stdin body keeps no fragment for any plugin"
else
  fail "expected exit 2 and no fragments, got: $out"
fi
out="$(run_new "$f" --stdin alpha patch 2>&1 </dev/null)"
if [[ $? -eq 2 && "$out" == *"empty body"* ]]; then
  ok "refuses an empty --stdin body"
else
  fail "expected exit 2 for an empty body, got: $out"
fi
out="$(run_new "$f" beta patch 2>&1)"
if [[ $? -eq 2 && "$out" == *"no named plugin is in fragment mode"* && -z "$(find "$f/.changes" -type f 2>/dev/null)" ]]; then
  ok "writes nothing and exits 2 when no named plugin is in fragment mode"
else
  fail "expected exit 2 with only legacy plugins, got: $out"
fi
out="$(run_new "$f" alpha nosuch patch 2>&1)"
if [[ $? -eq 2 && "$out" == *"no plugin named 'nosuch'"* && -z "$(find "$f/.changes" -type f 2>/dev/null)" ]]; then
  ok "an unknown plugin among several stops before anything is written"
else
  fail "expected exit 2 and no fragments for an unknown plugin, got: $out"
fi
rm -rf "$f"

# --- a copy of scripts/ kept outside the checkout -----------------------------
# The issue lane runs a read-only base copy of only scripts/ through a wrapper
# whose working directory is the checkout (pr-run-activity.md, "Skill
# activities"), so the fragment must land in the checkout and no checkout code
# may run.
tools="" elsewhere=""
multi_fixture f
fixture_tree::build tools --label new-fragment-tools || exit 2
cp -R "$f/scripts/." "$tools/scripts/"
chmod -R a-w "$tools"
tools_before="$(find "$tools" | sort)"
printf 'touch "%s/ran-checkout-code"\n' "$f" >"$f/scripts/sync-shared-copies.sh"
ext() { (cd "$1" && shift && bash "$tools/scripts/new-changelog-fragment.sh" "$@"); }
out="$(ext "$f" alpha patch)"
if [[ $? -eq 0 && "$out" =~ ^\.changes/alpha/sync-esc-[0-9a-f]{8}\.md$ && -f "$f/$out" ]]; then
  ok "an outside copy writes the fragment into the checkout it runs in"
else
  fail "expected .changes/alpha/sync-esc-<hex>.md in the checkout, got: $out"
fi
# Whether the copy's own sync-shared-copies.sh can read the checkout's registry
# is that script's concern; this asserts only that the checkout's never runs.
ext "$f" --carriers-of lib/esc.mjs patch >/dev/null 2>&1
if [[ ! -e "$f/ran-checkout-code" ]]; then
  ok "an outside copy runs its own sync-shared-copies.sh for --carriers-of, never the checkout's"
else
  fail "--carriers-of ran the checkout's scripts/sync-shared-copies.sh"
fi
if [[ "$(find "$tools" | sort)" == "$tools_before" ]]; then
  ok "an outside copy writes nothing beside itself"
else
  fail "the outside copy's directory changed"
fi
fixture_tree::build elsewhere --label new-fragment-elsewhere || exit 2
out="$(ext "$elsewhere" alpha patch 2>&1)"
if [[ $? -eq 2 && "$out" == *"work tree"* && -z "$(find "$elsewhere" "$tools" -name '*.md')" ]]; then
  ok "outside any work tree it writes nothing and exits 2"
else
  fail "expected exit 2 and no fragment outside a work tree, got: $out"
fi
chmod -R u+w "$tools"
rm -rf "$f" "$tools" "$elsewhere"

# --- every fragment stays under .changes/<plugin>/ -----------------------------
# The lane passes the model's arguments, and the checkout's fragment-plugins.txt
# and plugin.json files are the model's to edit.
base_fixture f
mkdir -p "$f/escape/.claude-plugin"
printf '{"name":"escape","version":"1.0.0"}\n' >"$f/escape/.claude-plugin/plugin.json"
printf 'alpha\n../escape\n' >"$f/scripts/fragment-plugins.txt"
out="$(run_new "$f" ../escape patch 2>&1)"
if [[ $? -eq 2 && "$out" == *"not a plugin name"* && -z "$(find "$f" -path "$f/.git" -prune -o -name '*.md' -print)" ]]; then
  ok "refuses a plugin name with a path in it and writes nothing"
else
  fail "expected exit 2 for ../escape and no fragment, got: $out"
fi
rm -rf "$f"
for link in .changes .changes/alpha; do
  base_fixture f
  fixture_tree::build elsewhere --label new-fragment-elsewhere || exit 2
  mkdir -p "$f/$(dirname "$link")"
  ln -s "$elsewhere" "$f/$link"
  out="$(run_new "$f" alpha patch 2>&1)"
  if [[ $? -eq 2 && "$out" == *"symbolic link"* && -z "$(find "$elsewhere" -name '*.md')" ]]; then
    ok "refuses $link as a symbolic link and writes nothing through it"
  else
    fail "expected exit 2 for a $link link and nothing outside, got: $out"
  fi
  rm -rf "$f" "$elsewhere"
done

test_harness::report
