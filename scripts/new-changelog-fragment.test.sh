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

test_harness::report
