#!/usr/bin/env bash
# Black-box contract tests for fleet-state.sh (self-contained — ships with the plugin).
# Fixtures are built per-case into a temp dir via FLEET_STATE_* env overrides,
# mirroring the claude-config audit skill's SETTINGS_AUDIT_FIXTURE_DIR pattern.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/fleet-state.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0

pass() {
  printf 'PASS: %s\n' "$1"
}
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: $2, actual: $3"; fi
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3 — got: $2" ;;
  esac
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed" >&2
  exit 0
fi

# --- Fixture builders --------------------------------------------------------

# CASE_NUM must be incremented in the CALLER's shell before calling this,
# never inside it: `case_dir=$(new_case_dir)` runs in a subshell, so a
# `CASE_NUM=...` assignment made in here is discarded when the subshell
# exits, silently leaving every case reuse case-1's directory.
new_case_dir() {
  local case_dir="$TEST_TMPDIR/case-$CASE_NUM"
  mkdir -p "$case_dir/catalog"
  echo "$case_dir"
}

write() {
  local path="$1" json="$2"
  printf '%s' "$json" >"$path"
}

# Args: case_dir, marketplace name, run extra env (e.g. "CLAUDE_PROJECT_DIR=/x").
# Always seeds a minimal installed_plugins.json / known_marketplaces.json /
# user settings.json unless the case already wrote its own.
run_state() {
  local case_dir="$1"
  shift
  [[ -f "$case_dir/installed_plugins.json" ]] || write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{}}'
  [[ -f "$case_dir/known_marketplaces.json" ]] || write "$case_dir/known_marketplaces.json" '{}'
  [[ -f "$case_dir/user_settings.json" ]] || write "$case_dir/user_settings.json" '{"enabledPlugins":{}}'
  env \
    FLEET_STATE_INSTALLED_JSON="$case_dir/installed_plugins.json" \
    FLEET_STATE_MARKETPLACES_JSON="$case_dir/known_marketplaces.json" \
    FLEET_STATE_USER_SETTINGS="$case_dir/user_settings.json" \
    FLEET_STATE_CATALOG_DIR="$case_dir/catalog" \
    FLEET_STATE_HOOK_UTILS="$SCRIPT_DIR/../../../hooks/hook-utils.sh" \
    "$@" \
    bash "$SCRIPT" "${ARGS[@]}" 2>&1
}

# ============================================================================
# Case: dual-scope divergence
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/installed_plugins.json" '{
  "version": 1,
  "plugins": {
    "alpha@market1": [
      {"scope": "project", "projectPath": "<PROJECT_ROOT>/sample-repo", "installPath": "x", "version": "0.1.0"},
      {"scope": "user", "installPath": "y", "version": "0.2.0"}
    ]
  }
}'
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}]}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir")
rc=$?
assert_exit "divergence: exit 0" 0 "$rc"
divergence_count=$(jq '.divergences | length' <<<"$out" 2>/dev/null)
assert_eq "divergence: one divergence entry" "1" "$divergence_count"
divergence_id=$(jq -r '.divergences[0].id' <<<"$out" 2>/dev/null)
assert_eq "divergence: correct id" "alpha@market1" "$divergence_id"
scope_count=$(jq '.divergences[0].scopes | length' <<<"$out" 2>/dev/null)
assert_eq "divergence: two scopes listed" "2" "$scope_count"

# ============================================================================
# Case: plugin missing from installs
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}, {"name": "beta"}]}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir")
missing=$(jq -cS '.missing_from_install' <<<"$out" 2>/dev/null)
assert_eq "missing-install: both catalog plugins flagged" '["alpha@market1","beta@market1"]' "$missing"

# ============================================================================
# Case: plugin missing from enabledPlugins (never mentioned anywhere)
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/installed_plugins.json" '{
  "version": 1,
  "plugins": {
    "alpha@market1": [{"scope": "user", "installPath": "y", "version": "0.1.0"}]
  }
}'
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}]}'
write "$case_dir/user_settings.json" '{"enabledPlugins": {}}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir")
missing_enabled=$(jq -c '.missing_from_enabled' <<<"$out" 2>/dev/null)
assert_eq "missing-enabled: installed-but-never-mentioned flagged" '["alpha@market1"]' "$missing_enabled"

# ============================================================================
# Case: explicit enabledPlugins:false is an opt-out, NOT missing_from_enabled
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/installed_plugins.json" '{
  "version": 1,
  "plugins": {
    "alpha@market1": [{"scope": "user", "installPath": "y", "version": "0.1.0"}]
  }
}'
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}]}'
write "$case_dir/user_settings.json" '{"enabledPlugins": {"alpha@market1": false}}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir")
missing_enabled=$(jq -c '.missing_from_enabled' <<<"$out" 2>/dev/null)
assert_eq "opt-out: explicit false is not missing_from_enabled" '[]' "$missing_enabled"
enabled_value=$(jq -r '.enabled["alpha@market1"]' <<<"$out" 2>/dev/null)
assert_eq "opt-out: effective value reported as false, never flipped" "false" "$enabled_value"

# ============================================================================
# Case: marketplace absent from known_marketplaces.json
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
ARGS=(--marketplace ghost-market)
out=$(run_state "$case_dir")
rc=$?
assert_exit "absent marketplace: exit 1" 1 "$rc"
error_msg=$(jq -r '.marketplace.error' <<<"$out" 2>/dev/null)
assert_eq "absent marketplace: error field set" "not found in known_marketplaces.json" "$error_msg"

# ============================================================================
# Case: malformed/drifted installed_plugins.json shape — must fail loud
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/installed_plugins.json" '{"unexpectedShape": true}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir")
rc=$?
assert_exit "malformed installed_plugins.json: exit 2" 2 "$rc"
assert_contains "malformed installed_plugins.json: error names the file" "$out" "installed_plugins.json"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/known_marketplaces.json" '["not", "an", "object"]'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir")
rc=$?
assert_exit "malformed known_marketplaces.json: exit 2" 2 "$rc"
assert_contains "malformed known_marketplaces.json: error names the file" "$out" "known_marketplaces.json"

# ============================================================================
# Case: native-Windows projectPath vs Git Bash cwd — CRITICAL normalization
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
project_dir="$case_dir/project-root"
mkdir -p "$project_dir/.claude"
native_project_path="$(cygpath -w "$project_dir" 2>/dev/null || echo "$project_dir")"
write "$case_dir/installed_plugins.json" "$(
  jq -cn --arg p "$native_project_path" \
    '{version: 1, plugins: {"alpha@market1": [{scope: "project", projectPath: $p, installPath: "x", version: "0.1.0"}]}}'
)"
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}]}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir" CLAUDE_PROJECT_DIR="$project_dir")
current_flag=$(jq -r '.installed[0].currentProject' <<<"$out" 2>/dev/null)
assert_eq "windows-path: native backslash projectPath matches Git Bash cwd" "true" "$current_flag"

# ============================================================================
# Case: --all sweeps every marketplace; one absent-catalog failure does not
# abort the sweep
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/known_marketplaces.json" '{
  "market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"},
  "market2": {"source": {"source": "github", "repo": "example/market2"}, "installLocation": "z2", "lastUpdated": "2026-01-01T00:00:00Z"}
}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}]}'
# market2 deliberately has no catalog fixture — simulates an unreachable marketplace.
ARGS=(--all)
out=$(run_state "$case_dir")
rc=$?
assert_exit "--all: exits 0 even with one marketplace unreachable" 0 "$rc"
m1_catalog=$(jq -c '.marketplaces.market1.catalog' <<<"$out" 2>/dev/null)
assert_eq "--all: market1 resolved" '["alpha"]' "$m1_catalog"
m2_error=$(jq -r '.marketplaces.market2.marketplace.error' <<<"$out" 2>/dev/null)
assert_eq "--all: market2 reports its failure inline" "no catalog fixture" "$m2_error"

# ============================================================================
# Case: default marketplace resolved dynamically from CLAUDE_PLUGIN_ROOT
# (never hardcoded) — zero-arg invocation
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
fake_plugin_root="$case_dir/fake-plugin-root"
mkdir -p "$fake_plugin_root"
native_root="$(cygpath -w "$fake_plugin_root" 2>/dev/null || echo "$fake_plugin_root")"
write "$case_dir/installed_plugins.json" "$(
  jq -cn --arg root "$native_root" \
    '{version: 1, plugins: {"this-plugin@market1": [{scope: "user", installPath: $root, version: "0.1.0"}]}}'
)"
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "this-plugin"}]}'
ARGS=()
out=$(run_state "$case_dir" CLAUDE_PLUGIN_ROOT="$fake_plugin_root")
rc=$?
assert_exit "default marketplace: resolves via CLAUDE_PLUGIN_ROOT join" 0 "$rc"
resolved_name=$(jq -r '.marketplace.name' <<<"$out" 2>/dev/null)
assert_eq "default marketplace: correct name" "market1" "$resolved_name"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
ARGS=()
out=$(run_state "$case_dir" CLAUDE_PLUGIN_ROOT="$case_dir/nowhere-installed")
rc=$?
assert_exit "default marketplace: unresolvable root fails loud, doesn't guess" 1 "$rc"
assert_contains "default marketplace: names the fallback" "$out" "--marketplace"

# ============================================================================
# Case: jq missing — clear notice, not a bare command-not-found
# ============================================================================
# Strip only jq's own directory out of PATH (rather than rebuilding PATH from
# scratch via symlinks) so bash, dirname, and every other tool the script
# needs stay resolvable — symlinking coreutils individually is unreliable on
# Windows without elevated rights.
real_jq=$(command -v jq)
jq_dir=$(dirname "$real_jq")
filtered_path=$(printf '%s' "$PATH" | tr ':' '\n' | grep -vF "$jq_dir" | tr '\n' ':')
out=$(PATH="$filtered_path" bash "$SCRIPT" --marketplace market1 2>&1)
rc=$?
assert_exit "jq missing: exit 2" 2 "$rc"
assert_contains "jq missing: actionable notice" "$out" "jq required"

# --- Summary -------------------------------------------------------------
printf '\n%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]] && exit 0
exit 1
