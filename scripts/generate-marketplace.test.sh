#!/usr/bin/env bash
# Unit tests for generate-marketplace.mjs. Each scenario builds a throwaway
# fixture tree (marketplace + plugin manifests) and drives the generator through
# CHECK_DATA_ROOT: the green generate/--check path, that only category and tags
# are taken from plugin.json while order and the entry's own fields stay, drift
# detection, and each failure mode (missing metadata.category, missing keywords,
# a plugin.json name that disagrees with its entry).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERATOR="$SELF_DIR/generate-marketplace.mjs"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh"

tree=""

# write_manifest <dir> <plugin> <json>
write_manifest() {
  mkdir -p "$1/plugins/$2/.claude-plugin"
  printf '%s\n' "$3" >"$1/plugins/$2/.claude-plugin/plugin.json"
}

# mk_tree: two plugins listed beta-first, beta with a hand-owned
# defaultEnabled, and stale category/tags in both entries.
mk_tree() { # <out-var>
  local dir
  fixture_tree::build "$1" || return 1
  dir="${!1}"
  mkdir -p "$dir/.claude-plugin"
  cat >"$dir/.claude-plugin/marketplace.json" <<'EOF'
{
  "name": "fixture",
  "plugins": [
    { "name": "beta", "source": "./plugins/beta", "category": "old", "tags": ["stale"], "defaultEnabled": false },
    { "name": "alpha", "source": "./plugins/alpha", "category": "old", "tags": ["stale"] }
  ]
}
EOF
  write_manifest "$dir" alpha '{ "name": "alpha", "keywords": ["a1", "a2"], "metadata": { "category": "testing" } }'
  write_manifest "$dir" beta '{ "name": "beta", "keywords": ["b1"], "metadata": { "category": "quality" } }'
}

run_gen() { # run_gen <tree> [extra args...]: stdout+stderr to $OUT, exit code in $CODE
  local dir="$1"
  shift
  OUT="$(CHECK_DATA_ROOT="$dir" node "$GENERATOR" "$@" 2>&1)"
  CODE=$?
}

# assert_fails <label> <tree> <expected substring>
assert_fails() {
  local label="$1" dir="$2" expected="$3"
  run_gen "$dir"
  if [[ "$CODE" -ne 0 && "$OUT" == *"$expected"* ]]; then
    ok "$label"
  else
    fail "$label (exit=$CODE, output: $OUT)"
  fi
  rm -rf "$dir"
}

# --- stale entries: --check fails before any generate --------------------------
mk_tree tree
run_gen "$tree" --check
if [[ "$CODE" -ne 0 && "$OUT" == *"Marketplace drift"* && "$OUT" == *"First difference at generated line "* ]]; then
  ok "--check fails on stale entries and names the first differing line"
else
  fail "stale entries not detected (exit=$CODE: $OUT)"
fi

# --- green path: generate, idempotent --check, entry content -------------------
run_gen "$tree"
if [[ "$CODE" -eq 0 ]]; then ok "generate exits 0"; else fail "generate (exit=$CODE: $OUT)"; fi
run_gen "$tree" --check
if [[ "$CODE" -eq 0 ]]; then ok "--check exits 0 after generate"; else fail "--check after generate (exit=$CODE: $OUT)"; fi
expected='[{"name":"beta","source":"./plugins/beta","category":"quality","tags":["b1"],"defaultEnabled":false},{"name":"alpha","source":"./plugins/alpha","category":"testing","tags":["a1","a2"]}]'
actual="$(node -e 'console.log(JSON.stringify(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).plugins))' "$tree/.claude-plugin/marketplace.json")"
if [[ "$actual" == "$expected" ]]; then
  ok "category and tags come from plugin.json; order and entry-owned fields stay"
else
  fail "entries: expected $expected, got $actual"
fi

# --- drift: a keyword edit in plugin.json makes --check fail -------------------
write_manifest "$tree" alpha '{ "name": "alpha", "keywords": ["a1", "a3"], "metadata": { "category": "testing" } }'
run_gen "$tree" --check
if [[ "$CODE" -ne 0 && "$OUT" == *"generate-marketplace.mjs"* ]]; then
  ok "--check fails when plugin.json keywords change"
else
  fail "keyword drift not detected (exit=$CODE: $OUT)"
fi
rm -rf "$tree"

# --- failure modes ----------------------------------------------------------------
mk_tree tree
write_manifest "$tree" alpha '{ "name": "alpha", "keywords": ["a1"] }'
assert_fails "missing metadata.category names the plugin" "$tree" "alpha: plugin.json has no metadata.category"

mk_tree tree
write_manifest "$tree" alpha '{ "name": "alpha", "metadata": { "category": "testing" } }'
assert_fails "missing keywords names the plugin" "$tree" "alpha: plugin.json has no keywords"

mk_tree tree
write_manifest "$tree" alpha '{ "name": "gamma", "keywords": ["a1"], "metadata": { "category": "testing" } }'
assert_fails "plugin.json name must match the entry" "$tree" 'alpha: plugin.json at ./plugins/alpha names "gamma"'

test_harness::report
