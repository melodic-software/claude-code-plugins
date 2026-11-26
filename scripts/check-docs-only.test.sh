#!/usr/bin/env bash
set -uo pipefail

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-docs-only.sh"

ALLOWLIST="$SELF_DIR/docs-only-paths.txt"
# shellcheck source=test-git-helpers.sh
. "$SELF_DIR/test-git-helpers.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh"

repo=""

mk_repo() {
  local dir
  fixture_tree::build "$1" --sut "$SCRIPT" --git || return 1
  dir="${!1}"
  cp "$ALLOWLIST" "$dir/scripts/docs-only-paths.txt"
  printf 'docs/inert/\n' >>"$dir/scripts/docs-only-paths.txt"
  mkdir -p "$dir/docs/inert/example" "$dir/docs" "$dir/plugins/p1/skills/alpha" \
    "$dir/plugins/miro" "$dir/.github/workflows"
  printf 'seed\n' >"$dir/docs/inert/example/PLAN.md"
  printf 'seed\n' >"$dir/README.md"
  printf 'seed\n' >"$dir/docs/plugin-artifact-protocol.md"
  printf 'seed\n' >"$dir/docs/catalog-taxonomy.md"
  printf 'seed\n' >"$dir/docs/migration-playbook.md"
  printf 'seed\n' >"$dir/plugins/p1/skills/alpha/SKILL.md"
  printf 'seed\n' >"$dir/plugins/miro/index.ts"
  printf 'seed\n' >"$dir/.github/workflows/pr-require-checks.yml"
  printf 'seed\n' >"$dir/package-lock.json"
  git_test_config "$dir" add -A >/dev/null
  git_test_config "$dir" commit -qm base
}

assert_flag() {
  local label="$1" expected="$2"
  shift 2
  local repo base p out
  mk_repo repo
  base="$(git -C "$repo" rev-parse HEAD)"
  for p in "$@"; do
    mkdir -p "$repo/$(dirname "$p")"
    printf 'changed %s\n' "$RANDOM" >"$repo/$p"
  done
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm change >/dev/null
  out="$(cd "$repo" && bash scripts/check-docs-only.sh "$base" 2>/dev/null)"
  if [[ "$out" == "docs_only=$expected" ]]; then
    ok "$label -> $expected"
  else
    fail "$label: expected docs_only=$expected, got '$out'"
  fi
  rm -rf "$repo"
}

assert_flag "allowlisted-prefix-only" true "docs/inert/example/PLAN.md"
assert_flag "allowlisted prefix, new nested file" true "docs/inert/new-precedent/NOTES.md"

assert_flag "README.md (not on the allowlist; runs full)" false "README.md"
assert_flag "docs/plugin-artifact-protocol.md (validator reads it)" false "docs/plugin-artifact-protocol.md"
assert_flag "docs/catalog-taxonomy.md (catalog reads it)" false "docs/catalog-taxonomy.md"
assert_flag "docs/skill-cheat-sheet.md (cheat-sheet --check reads it)" false "docs/skill-cheat-sheet.md"
assert_flag "docs/catalog.md (catalog --check reads it)" false "docs/catalog.md"

assert_flag "non-allowlisted docs/ file" false "docs/migration-playbook.md"
assert_flag "plugin SKILL.md is code" false "plugins/p1/skills/alpha/SKILL.md"
assert_flag "plugin source" false "plugins/miro/index.ts"
assert_flag "scripts/ change" false "scripts/run-plugin-tests.sh"
assert_flag ".github/ workflow change" false ".github/workflows/pr-require-checks.yml"
assert_flag "toolchain lockfile" false "package-lock.json"
assert_flag "sibling of an allowed prefix (docs/inert-archive/)" false "docs/inert-archive/old.md"
assert_flag "mixed docs+code" false "docs/inert/example/PLAN.md" "plugins/p1/skills/alpha/SKILL.md"

assert_flag "marketplace manifest (marketplace-schema reads it)" false ".claude-plugin/marketplace.json"
assert_flag "plugin manifest (plugin-schema reads it)" false "plugins/p1/.claude-plugin/plugin.json"
assert_flag "dependabot.yml (dependabot-schema reads it)" false ".github/dependabot.yml"

mk_repo repo
out="$(cd "$repo" && bash scripts/check-docs-only.sh "does-not-exist" 2>/dev/null)"
rc=$?
if [[ "$out" == "docs_only=false" && $rc -eq 0 ]]; then
  ok "unresolvable base ref -> false, exit 0"
else
  fail "bad base ref: expected docs_only=false exit 0, got '$out' rc=$rc"
fi
rm -rf "$repo"

mk_repo repo
base="$(git -C "$repo" rev-parse HEAD)"
: >"$repo/empty-allowlist.txt"
printf 'changed\n' >"$repo/docs/inert/example/PLAN.md"
git_test_config "$repo" add -A >/dev/null && git_test_config "$repo" commit -qm change >/dev/null
out="$(cd "$repo" && DOCS_ONLY_ALLOWLIST=empty-allowlist.txt bash scripts/check-docs-only.sh "$base" 2>/dev/null)"
if [[ "$out" == "docs_only=false" ]]; then
  ok "empty allowlist -> false (fail-closed)"
else
  fail "empty allowlist: expected docs_only=false, got '$out'"
fi
rm -rf "$repo"

mk_repo repo
base="$(git -C "$repo" rev-parse HEAD)"
printf 'changed\n' >"$repo/docs/inert/example/PLAN.md"
git_test_config "$repo" add -A >/dev/null && git_test_config "$repo" commit -qm change >/dev/null
gho="$(mktemp "$TMP_ROOT/f.XXXXXX")"
(cd "$repo" && GITHUB_OUTPUT="$gho" bash scripts/check-docs-only.sh "$base" >/dev/null 2>&1)
if grep -qx 'docs_only=true' "$gho"; then
  ok "writes docs_only to GITHUB_OUTPUT"
else
  fail "GITHUB_OUTPUT missing docs_only=true, got: $(cat "$gho")"
fi
rm -rf "$repo" "$gho"

test_harness::report
