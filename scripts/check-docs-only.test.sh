#!/usr/bin/env bash
# Unit tests for check-docs-only.sh. Each scenario builds a throwaway git repo
# with the REAL shipped allowlist (scripts/docs-only-paths.txt), commits a base
# tree, commits a change, and asserts the emitted docs_only flag. Using the real
# allowlist makes these tests the honesty proof the #532 liveness convention
# wants: the README / protocol / taxonomy cases below fail the moment someone
# widens the allowlist to cover a doc a code lane actually reads.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-docs-only.sh"
ALLOWLIST="$SELF_DIR/docs-only-paths.txt"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

mk_repo() {
  local dir
  dir="$(mktemp -d)"
  git -C "$dir" init -q
  git -C "$dir" config user.email t@t.test
  git -C "$dir" config user.name test
  git -C "$dir" config commit.gpgsign false
  git -C "$dir" config core.autocrlf false
  mkdir -p "$dir/scripts"
  cp "$SCRIPT" "$dir/scripts/check-docs-only.sh"
  cp "$ALLOWLIST" "$dir/scripts/docs-only-paths.txt"
  # A committed base tree spanning every path class the assertions touch.
  mkdir -p "$dir/docs/topics/example" "$dir/docs" "$dir/plugins/p1/skills/alpha" \
    "$dir/plugins/miro" "$dir/.github/workflows"
  printf 'seed\n' >"$dir/docs/topics/example/PLAN.md"
  printf 'seed\n' >"$dir/README.md"
  printf 'seed\n' >"$dir/docs/PLUGIN-ARTIFACT-PROTOCOL.md"
  printf 'seed\n' >"$dir/docs/CATALOG-TAXONOMY.md"
  printf 'seed\n' >"$dir/docs/MIGRATION-PLAYBOOK.md"
  printf 'seed\n' >"$dir/plugins/p1/skills/alpha/SKILL.md"
  printf 'seed\n' >"$dir/plugins/miro/index.ts"
  printf 'seed\n' >"$dir/.github/workflows/ci.yml"
  printf 'seed\n' >"$dir/package-lock.json"
  git -C "$dir" add -A >/dev/null
  git -C "$dir" commit -qm base
  printf '%s' "$dir"
}

# assert_flag <label> <expected true|false> <repo-relpath-to-touch...>
# Commits an edit to each given path, runs the detector against the base sha,
# and asserts the emitted docs_only value.
assert_flag() {
  local label="$1" expected="$2"
  shift 2
  local repo base p out
  repo="$(mk_repo)"
  base="$(git -C "$repo" rev-parse HEAD)"
  for p in "$@"; do
    mkdir -p "$repo/$(dirname "$p")"
    printf 'changed %s\n' "$RANDOM" >"$repo/$p"
  done
  git -C "$repo" add -A >/dev/null
  git -C "$repo" commit -qm change >/dev/null
  out="$(cd "$repo" && bash scripts/check-docs-only.sh "$base" 2>/dev/null)"
  if [[ "$out" == "docs_only=$expected" ]]; then
    ok "$label -> $expected"
  else
    fail "$label: expected docs_only=$expected, got '$out'"
  fi
  rm -rf "$repo"
}

# --- the honest win: a diff confined to docs/topics/ ------------------------
assert_flag "docs/topics-only" true "docs/topics/example/PLAN.md"
assert_flag "docs/topics new nested file" true "docs/topics/new-precedent/NOTES.md"

# --- the grep payoff: docs a code lane actually consumes are NOT docs-only --
assert_flag "README.md (not on the allowlist; runs full)" false "README.md"
assert_flag "docs/PLUGIN-ARTIFACT-PROTOCOL.md (validator reads it)" false "docs/PLUGIN-ARTIFACT-PROTOCOL.md"
assert_flag "docs/CATALOG-TAXONOMY.md (catalog reads it)" false "docs/CATALOG-TAXONOMY.md"
assert_flag "docs/SKILL-CHEAT-SHEET.md (cheat-sheet --check reads it)" false "docs/SKILL-CHEAT-SHEET.md"
assert_flag "docs/CATALOG.md (catalog --check reads it)" false "docs/CATALOG.md"

# --- conservative: any non-topics doc, and every code class, run full ------
assert_flag "non-topics docs/ file" false "docs/MIGRATION-PLAYBOOK.md"
assert_flag "plugin SKILL.md is code" false "plugins/p1/skills/alpha/SKILL.md"
assert_flag "plugin source" false "plugins/miro/index.ts"
assert_flag "scripts/ change" false "scripts/run-plugin-tests.sh"
assert_flag ".github/ workflow change" false ".github/workflows/ci.yml"
assert_flag "toolchain lockfile" false "package-lock.json"
assert_flag "sibling of an allowed prefix (docs/topics-archive/)" false "docs/topics-archive/old.md"
assert_flag "mixed docs+code" false "docs/topics/example/PLAN.md" "plugins/p1/skills/alpha/SKILL.md"

# --- hygiene job's docs-irrelevant step set: their inputs are NOT docs-only --
# ShellCheck (scripts/, plugins/**), actionlint + workflow-schema (.github/
# workflows/) are already pinned false above; these pin the remaining check-
# jsonschema inputs so a widened allowlist that let one through fails the suite.
assert_flag "marketplace manifest (marketplace-schema reads it)" false ".claude-plugin/marketplace.json"
assert_flag "plugin manifest (plugin-schema reads it)" false "plugins/p1/.claude-plugin/plugin.json"
assert_flag "dependabot.yml (dependabot-schema reads it)" false ".github/dependabot.yml"

# --- fail-closed paths: emit false, exit 0 (run full, never block) ---------
repo="$(mk_repo)"
out="$(cd "$repo" && bash scripts/check-docs-only.sh "does-not-exist" 2>/dev/null)"
rc=$?
if [[ "$out" == "docs_only=false" && $rc -eq 0 ]]; then
  ok "unresolvable base ref -> false, exit 0"
else
  fail "bad base ref: expected docs_only=false exit 0, got '$out' rc=$rc"
fi
rm -rf "$repo"

repo="$(mk_repo)"
base="$(git -C "$repo" rev-parse HEAD)"
: >"$repo/empty-allowlist.txt"
printf 'changed\n' >"$repo/docs/topics/example/PLAN.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm change >/dev/null
out="$(cd "$repo" && DOCS_ONLY_ALLOWLIST=empty-allowlist.txt bash scripts/check-docs-only.sh "$base" 2>/dev/null)"
if [[ "$out" == "docs_only=false" ]]; then
  ok "empty allowlist -> false (fail-closed)"
else
  fail "empty allowlist: expected docs_only=false, got '$out'"
fi
rm -rf "$repo"

# --- GITHUB_OUTPUT is written for the step to consume ----------------------
repo="$(mk_repo)"
base="$(git -C "$repo" rev-parse HEAD)"
printf 'changed\n' >"$repo/docs/topics/example/PLAN.md"
git -C "$repo" add -A >/dev/null && git -C "$repo" commit -qm change >/dev/null
gho="$(mktemp)"
(cd "$repo" && GITHUB_OUTPUT="$gho" bash scripts/check-docs-only.sh "$base" >/dev/null 2>&1)
if grep -qx 'docs_only=true' "$gho"; then
  ok "writes docs_only to GITHUB_OUTPUT"
else
  fail "GITHUB_OUTPUT missing docs_only=true, got: $(cat "$gho")"
fi
rm -rf "$repo" "$gho"

printf '\nPASS=%d FAIL=%d\n' "$PASS" "$FAIL"
((FAIL == 0))
