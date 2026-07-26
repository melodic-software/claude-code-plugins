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
versions_match=$(jq -r '.divergences[0].versionsMatch' <<<"$out" 2>/dev/null)
assert_eq "divergence: differing versions flagged versionsMatch=false" "false" "$versions_match"

# ============================================================================
# Case: same-version multi-scope install is benign — NOT an actionable
# divergence, must not inflate the "N behind" report count
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/installed_plugins.json" '{
  "version": 1,
  "plugins": {
    "alpha@market1": [
      {"scope": "project", "projectPath": "<PROJECT_ROOT>/sample-repo", "installPath": "x", "version": "0.3.0"},
      {"scope": "user", "installPath": "y", "version": "0.3.0"}
    ]
  }
}'
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}]}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir")
same_version_match=$(jq -r '.divergences[0].versionsMatch' <<<"$out" 2>/dev/null)
assert_eq "benign multi-scope: same version flagged versionsMatch=true" "true" "$same_version_match"
actionable_count=$(jq '[.divergences[] | select(.versionsMatch == false)] | length' <<<"$out" 2>/dev/null)
assert_eq "benign multi-scope: zero actionable (version-behind) divergences" "0" "$actionable_count"

# ============================================================================
# Case: explicit enabledPlugins:false opt-out on a NEVER-INSTALLED plugin
# excludes it from missing_from_install too — sync must not offer to install
# something explicitly declined, even pre-install
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}, {"name": "beta"}]}'
write "$case_dir/user_settings.json" '{"enabledPlugins": {"alpha@market1": false}}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir")
missing_install=$(jq -cS '.missing_from_install' <<<"$out" 2>/dev/null)
assert_eq "opt-out before install: excluded from missing_from_install" '["beta@market1"]' "$missing_install"

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
# Case: missing_from_enabled must not false-positive on a DIFFERENT repo's
# project-scope install — fleet-state.sh can only read the current
# PROJECT_ROOT's settings files, so a project/local install belonging to
# another repo can never be verified as known or unknown here. Excluded
# entirely rather than asserted missing (a fixed bug: this used to compare
# every project/local install machine-wide against only the current repo's
# settings, so any other repo's already-enabled install showed up as
# missing_from_enabled and sync could try to `enable -s project` against the
# wrong repo)
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
other_repo_dir="$case_dir/other-repo"
mkdir -p "$other_repo_dir/.claude"
native_other_repo="$(cygpath -w "$other_repo_dir" 2>/dev/null || echo "$other_repo_dir")"
write "$case_dir/installed_plugins.json" "$(
  jq -cn --arg path "$native_other_repo" \
    '{version: 1, plugins: {"alpha@market1": [{scope: "project", projectPath: $path, installPath: "y", version: "0.1.0"}]}}'
)"
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}]}'
write "$other_repo_dir/.claude/settings.json" '{"enabledPlugins": {"alpha@market1": true}}'
ARGS=(--marketplace market1)
current_project_dir="$case_dir/current-repo"
mkdir -p "$current_project_dir"
out=$(run_state "$case_dir" "CLAUDE_PROJECT_DIR=$current_project_dir")
missing_enabled=$(jq -c '.missing_from_enabled' <<<"$out" 2>/dev/null)
assert_eq "missing-enabled: other repo's already-enabled project install excluded, not false-flagged" '[]' "$missing_enabled"

# ============================================================================
# Case: a marketplace-entry defaultEnabled:false install with no explicit
# enabledPlugins entry is a deliberate publisher opt-in-required default, NOT
# missing_from_enabled — auto-enabling it would override the publisher's
# intent (per plugins-reference.md: the marketplace entry's defaultEnabled
# takes precedence over plugin.json's, and "the user turns it on with
# claude plugin enable" is the documented opt-in path, not sync auto-enabling
# on their behalf)
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
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha", "defaultEnabled": false}]}'
write "$case_dir/user_settings.json" '{"enabledPlugins": {}}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir")
missing_enabled=$(jq -c '.missing_from_enabled' <<<"$out" 2>/dev/null)
assert_eq "default-disabled: no explicit entry is the publisher's intended state, not missing_from_enabled" '[]' "$missing_enabled"

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
# Case: case-sensitivity — a case-only path difference must NOT collapse two
# different repos on a case-sensitive filesystem (a fixed bug: the
# currentProject comparison used to case-fold unconditionally, so on a
# case-sensitive POSIX host, e.g. GitHub's ubuntu CI runner, a fixture
# projectPath differing only by case from the real project dir would
# false-positive as the same repo). Same fixture, run twice with an EXPLICIT
# OSTYPE override each time (never "this host's ambient OSTYPE" — this suite
# itself runs on both a case-insensitive dev host and a case-sensitive CI
# runner, so asserting against the ambient value is not deterministic across
# them): forcing linux-gnu must NOT match (case-sensitive); forcing msys must
# still match (case-insensitive — no regression to the existing behavior).
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
project_dir="$case_dir/case-test-root"
mkdir -p "$project_dir/.claude"
differently_cased_path="${project_dir/case-test-root/Case-Test-Root}"
write "$case_dir/installed_plugins.json" "$(
  jq -cn --arg p "$differently_cased_path" \
    '{version: 1, plugins: {"alpha@market1": [{scope: "project", projectPath: $p, installPath: "x", version: "0.1.0"}]}}'
)"
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}]}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir" CLAUDE_PROJECT_DIR="$project_dir" OSTYPE="linux-gnu")
current_flag=$(jq -r '.installed[0].currentProject' <<<"$out" 2>/dev/null)
assert_eq "case-sensitivity: differently-cased sibling does not match on a POSIX (case-sensitive) host" "false" "$current_flag"
out=$(run_state "$case_dir" CLAUDE_PROJECT_DIR="$project_dir" OSTYPE="msys")
current_flag=$(jq -r '.installed[0].currentProject' <<<"$out" 2>/dev/null)
assert_eq "case-sensitivity: still matches under a forced case-insensitive OSTYPE — no regression" "true" "$current_flag"

# ============================================================================
# Case: CLAUDE_PROJECT_DIR unset falls back to the cwd's git toplevel —
# the exact gap a live end-to-end run (a headless `-p` session) exposed:
# CLAUDE_PROJECT_DIR wasn't exported, so currentProject stayed null on every
# install record even while standing inside the actual project.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
project_dir="$case_dir/git-project-root"
mkdir -p "$project_dir/nested/subdir"
(cd "$project_dir" && git init -q && git config user.email t@t.test && git config user.name t && git commit -q --allow-empty -m init)
# Derive the native-Windows form from `git rev-parse --show-toplevel` itself
# (forward-slash-to-backslash only) rather than `cygpath -w`: on this
# machine cygpath silently 8.3-shortens a profile segment (KyleSexton ->
# KYLESE~1), which normalize_path cannot reconcile against the long form
# git and real CC-written projectPath values both use — a test-fixture
# artifact, not a real-world path shape, so the fixture should not
# manufacture it either.
git_toplevel=$(cd "$project_dir" && git rev-parse --show-toplevel)
native_project_path="${git_toplevel//\//\\}"
write "$case_dir/installed_plugins.json" "$(
  jq -cn --arg p "$native_project_path" \
    '{version: 1, plugins: {"alpha@market1": [{scope: "project", projectPath: $p, installPath: "x", version: "0.1.0"}]}}'
)"
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}]}'
[[ -f "$case_dir/user_settings.json" ]] || write "$case_dir/user_settings.json" '{"enabledPlugins":{}}'
out=$(
  cd "$project_dir/nested/subdir" && env -u CLAUDE_PROJECT_DIR \
    FLEET_STATE_INSTALLED_JSON="$case_dir/installed_plugins.json" \
    FLEET_STATE_MARKETPLACES_JSON="$case_dir/known_marketplaces.json" \
    FLEET_STATE_USER_SETTINGS="$case_dir/user_settings.json" \
    FLEET_STATE_CATALOG_DIR="$case_dir/catalog" \
    bash "$SCRIPT" --marketplace market1 2>&1
)
current_flag=$(jq -r '.installed[0].currentProject' <<<"$out" 2>/dev/null)
assert_eq "git-fallback: CLAUDE_PROJECT_DIR unset, cwd inside a subdir, resolves via git toplevel" "true" "$current_flag"

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
# Case: --all sweeps every marketplace; one MALFORMED catalog (not merely
# absent) does not abort the sweep either — this is a distinct code path from
# the absent-fixture case above (a fixed bug: emit_marketplace previously ran
# the catalog JSON through the fatal require_json helper, which exit-2'd the
# whole process before the {marketplaces: ...} report was ever emitted for
# ANY marketplace, not just the malformed one)
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/known_marketplaces.json" '{
  "market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"},
  "market2": {"source": {"source": "github", "repo": "example/market2"}, "installLocation": "z2", "lastUpdated": "2026-01-01T00:00:00Z"}
}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}]}'
write "$case_dir/catalog/market2.json" '{bad'
ARGS=(--all)
out=$(run_state "$case_dir")
rc=$?
assert_exit "--all: exits 0 even with one marketplace's catalog malformed" 0 "$rc"
m1_catalog=$(jq -c '.marketplaces.market1.catalog' <<<"$out" 2>/dev/null)
assert_eq "--all: market1 still resolved despite market2's malformed catalog" '["alpha"]' "$m1_catalog"
m2_error=$(jq -r '.marketplaces.market2.marketplace.error' <<<"$out" 2>/dev/null)
assert_eq "--all: market2's malformed catalog reports its failure inline" "marketplace.json is not valid JSON" "$m2_error"

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
assert_contains "default marketplace: error names the searched root" "$out" "nowhere-installed"

# ============================================================================
# Case: version skew — session's loaded version != installed version.
# installPath is version-pinned; a mid-session autoUpdate (or sync's own Step-3
# self-update) makes the running root's version segment differ, so the exact
# installPath match misses. The version-agnostic parent-prefix fallback must
# still resolve the marketplace so the bare (no --marketplace) default path
# keeps working. Real dirs so realpath resolves both consistently.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
skew_parent="$case_dir/cache/market1/this-plugin"
mkdir -p "$skew_parent/0.18.3" "$skew_parent/0.19.0"
installed_ver_path="$skew_parent/0.18.3" # the version recorded in installed_plugins.json
session_ver_path="$skew_parent/0.19.0"   # the version the session actually loaded
native_installed="$(cygpath -w "$installed_ver_path" 2>/dev/null || echo "$installed_ver_path")"
write "$case_dir/installed_plugins.json" "$(
  jq -cn --arg root "$native_installed" \
    '{version: 1, plugins: {"this-plugin@market1": [{scope: "user", installPath: $root, version: "0.18.3"}]}}'
)"
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "this-plugin"}]}'
ARGS=()
out=$(run_state "$case_dir" CLAUDE_PLUGIN_ROOT="$session_ver_path")
rc=$?
assert_exit "version skew: resolves via version-agnostic parent-prefix fallback" 0 "$rc"
resolved_name=$(jq -r '.marketplace.name' <<<"$out" 2>/dev/null)
assert_eq "version skew: correct marketplace despite version mismatch" "market1" "$resolved_name"

# ============================================================================
# Case: jq missing — clear notice, not a bare command-not-found
# ============================================================================
# A directory-exclusion PATH filter (drop every PATH dir containing a jq
# executable) is NOT safe in general: `command -v jq` only reports the first
# match, and on this dev machine jq lives in its own directory separate from
# bash/coreutils, so excluding it is harmless — but a GitHub Actions
# ubuntu runner colocates jq with bash and coreutils in /usr/bin, so
# excluding jq's directory there also removes bash, and the case fails with
# "env: 'bash': No such file or directory" before it ever reaches the
# script's own jq check. `command -v` also does not skip a shadowed
# non-executable file and fall through to a later PATH entry (verified
# empirically: a chmod-000 decoy at the front of PATH is skipped and the
# real jq further down PATH is still found) — so shadowing can't hide jq
# either.
#
# The only universally safe approach: build an isolated PATH containing
# COPIES (never symlinks — those need elevation on Windows) of just the
# specific tools fleet-state.sh invokes before its jq check (`dirname`) plus
# bash itself to launch the interpreter, with jq deliberately excluded.
# Copying a Linux ELF binary elsewhere is safe (glibc resolves shared libs
# via the system loader, not the binary's own directory) — but bash.exe on
# Windows/MSYS needs a colocated msys-2.0.dll, so any *.dll sitting next to
# the real bash binary is copied alongside it too (a harmless no-op on
# Linux, where no such files exist).
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": []}'
ARGS=(--marketplace market1)
bash_bin=$(command -v bash)
dirname_bin=$(command -v dirname)
bash_dir=$(dirname "$bash_bin")
safe_bin_dir="$case_dir/jq-missing-bin"
mkdir -p "$safe_bin_dir"
cp "$bash_bin" "$safe_bin_dir/"
cp "$dirname_bin" "$safe_bin_dir/"
shopt -s nullglob
for dll in "$bash_dir"/*.dll; do cp "$dll" "$safe_bin_dir/"; done
shopt -u nullglob
out=$(run_state "$case_dir" "PATH=$safe_bin_dir")
rc=$?
assert_exit "jq missing: exit 2" 2 "$rc"
assert_contains "jq missing: actionable notice" "$out" "jq required"

# ============================================================================
# Case: missing_from_user_install is user-scope completeness, distinct from
# all-scope missing_from_install. A plugin installed ONLY at project/local
# scope is present all-scope (absent from missing_from_install) yet absent at
# user scope, so it MUST surface in missing_from_user_install — otherwise sync
# Step 4 never offers to install it at user scope and the "usable from any
# directory" guarantee silently fails for it. A user-scope install is excluded
# from both; an opt-out (false, any scope) is excluded from both.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/installed_plugins.json" '{
  "version": 1,
  "plugins": {
    "alpha@market1": [{"scope": "project", "projectPath": "<PROJECT_ROOT>/sample-repo", "installPath": "x", "version": "0.1.0"}],
    "gamma@market1": [{"scope": "user", "installPath": "y", "version": "0.1.0"}]
  }
}'
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}, {"name": "beta"}, {"name": "gamma"}]}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir")
missing_install=$(jq -cS '.missing_from_install' <<<"$out" 2>/dev/null)
assert_eq "user-scope: project-only install is present all-scope, absent from missing_from_install" '["beta@market1"]' "$missing_install"
missing_user_install=$(jq -cS '.missing_from_user_install' <<<"$out" 2>/dev/null)
assert_eq "user-scope: project-only + never-installed both surface, user-scope install excluded" '["alpha@market1","beta@market1"]' "$missing_user_install"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}, {"name": "beta"}]}'
write "$case_dir/user_settings.json" '{"enabledPlugins": {"alpha@market1": false}}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir")
missing_user_install=$(jq -cS '.missing_from_user_install' <<<"$out" 2>/dev/null)
assert_eq "user-scope: opt-out excluded from missing_from_user_install too" '["beta@market1"]' "$missing_user_install"

# ============================================================================
# Case: a drifted individual plugin entry (non-array value) must fail loud —
# the top-level shape check alone passed it through, and the non-array then
# broke the installed-flatten pipeline inside a command substitution, which
# (no set -e) was swallowed and exited 0 with installed:[] instead of failing
# per the file's stated fail-loud-on-drift design.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/installed_plugins.json" '{"version": 1, "plugins": {"alpha@market1": "not-an-array"}}'
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}]}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir")
rc=$?
assert_exit "non-array plugin entry: exit 2" 2 "$rc"
assert_contains "non-array plugin entry: error names the file" "$out" "installed_plugins.json"

# ============================================================================
# Case: --marketplace with no following name must exit 2 immediately, NOT
# infinite-loop. `shift 2` with one positional param left fails silently (no
# set -e), leaving $1 unchanged so the arg loop re-reads --marketplace forever;
# the in-branch guard exits before shift. timeout catches a regression (a hang
# returns 124, failing the assertion) instead of hanging the whole suite.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{}}'
write "$case_dir/known_marketplaces.json" '{}'
write "$case_dir/user_settings.json" '{"enabledPlugins":{}}'
out=$(timeout 10 env \
  FLEET_STATE_INSTALLED_JSON="$case_dir/installed_plugins.json" \
  FLEET_STATE_MARKETPLACES_JSON="$case_dir/known_marketplaces.json" \
  FLEET_STATE_USER_SETTINGS="$case_dir/user_settings.json" \
  FLEET_STATE_CATALOG_DIR="$case_dir/catalog" \
  bash "$SCRIPT" --marketplace 2>&1)
rc=$?
assert_exit "--marketplace no arg: exit 2, not an infinite loop" 2 "$rc"
assert_contains "--marketplace no arg: actionable error" "$out" "requires a name"

# ============================================================================
# Case: FLEET_STATE_HOOK_UTILS is no longer honored — a caller-supplied path is
# never sourced (security regression guard). hook-utils.sh resolves only from
# the script's own location, so an inherited or hostile environment cannot
# redirect `source` at an arbitrary file. If a future refactor re-introduces an
# env-based override, the decoy below is re-sourced and its marker surfaces in
# the output, failing this case.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": []}'
write "$case_dir/evil-hook-utils.sh" 'echo "PWNED-HOOK-UTILS-SOURCED"'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir" "FLEET_STATE_HOOK_UTILS=$case_dir/evil-hook-utils.sh")
rc=$?
assert_exit "hook-utils override ignored: runs to completion (exit 0)" 0 "$rc"
case "$out" in
*PWNED-HOOK-UTILS-SOURCED*) fail "hook-utils override ignored: caller-supplied path must NOT be sourced" "decoy marker present in output" ;;
*) pass "hook-utils override ignored: caller-supplied path not sourced" ;;
esac

# ============================================================================
# Case: an inherited, exported cd shell function cannot redirect hook-utils
# resolution (security regression guard). Bash imports environment-exported
# functions (BASH_FUNC_cd%%) before the script runs; a plain `cd` in the
# script's root-resolution would then run the attacker's function and make
# PLUGIN_ROOT_DEFAULT point at an attacker tree, sourcing an arbitrary file.
# The script uses `builtin cd`, so the exported function is bypassed. If a
# future refactor drops `builtin`, the hijacked cd redirects resolution to the
# decoy root below and its marker surfaces in the output, failing this case.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": []}'
mkdir -p "$case_dir/evilroot/hooks"
write "$case_dir/evilroot/hooks/hook-utils.sh" 'echo "PWNED-CD-SHADOW-SOURCED"'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir" "BASH_FUNC_cd%%=() { builtin cd \"$case_dir/evilroot\"; }")
rc=$?
assert_exit "exported cd shadow ignored: runs to completion (exit 0)" 0 "$rc"
case "$out" in
*PWNED-CD-SHADOW-SOURCED*) fail "exported cd shadow ignored: hijacked cd must NOT redirect source" "decoy marker present in output" ;;
*) pass "exported cd shadow ignored: hook-utils resolved from real script location" ;;
esac

# ============================================================================
# Case: an attacker-controlled PATH cannot redirect hook-utils resolution
# through the directory resolver (security regression guard). The script
# derives its own directory with parameter expansion, never an external
# `dirname`, so a hostile `dirname` planted at the front of PATH is never
# consulted and hook-utils.sh is still sourced from the real script location.
# If a future refactor reintroduces `dirname` (or any PATH-resolved tool) on
# the resolution path, the decoy below is sourced and its marker surfaces,
# failing this case.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": []}'
decoy_scripts="$case_dir/evilroot/skills/plugins/scripts"
mkdir -p "$decoy_scripts" "$case_dir/evilroot/hooks"
write "$case_dir/evilroot/hooks/hook-utils.sh" 'echo "PWNED-DIRNAME-PATH-SOURCED"'
attack_bash_bin=$(command -v bash)
attack_bash_dir=$(dirname "$attack_bash_bin")
attack_bin_dir="$case_dir/attack-bin"
mkdir -p "$attack_bin_dir"
cp "$attack_bash_bin" "$attack_bin_dir/"
shopt -s nullglob
for dll in "$attack_bash_dir"/*.dll; do cp "$dll" "$attack_bin_dir/"; done
shopt -u nullglob
# A hostile `dirname` that ignores its argument and points the resolver at the
# decoy tree; reachable only if the script resolves its directory via PATH.
printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$decoy_scripts" >"$attack_bin_dir/dirname"
chmod +x "$attack_bin_dir/dirname"
ARGS=(--marketplace market1)
out=$(run_state "$case_dir" "PATH=$attack_bin_dir")
case "$out" in
*PWNED-DIRNAME-PATH-SOURCED*) fail "hostile PATH dirname ignored: PATH-planted dirname must NOT redirect source" "decoy marker present in output" ;;
*) pass "hostile PATH dirname ignored: hook-utils resolved without an external dirname" ;;
esac

# ============================================================================
# Case: an inherited, exported `source` shell function cannot hijack the
# hook-utils source (security regression guard). Bash imports environment-
# exported functions (BASH_FUNC_source%%) before the script runs; a plain
# `source` would then invoke the attacker's function, which receives the
# correctly resolved real path but can ignore it and run arbitrary code —
# making the whole trusted-path resolution moot. The script uses `builtin
# source`, bypassing the exported function. If a future refactor drops
# `builtin`, the decoy function below runs and its marker surfaces, failing
# this case.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": []}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir" 'BASH_FUNC_source%%=() { echo "PWNED-SOURCE-SHADOW"; }')
case "$out" in
*PWNED-SOURCE-SHADOW*) fail "exported source shadow ignored: hijacked source must NOT run" "decoy marker present in output" ;;
*) pass "exported source shadow ignored: real hook-utils sourced via builtin" ;;
esac

# ============================================================================
# Case: large-catalog marketplace does not crash with "Argument list too
# long" (#1336). fleet-state.sh used to embed full catalog/installed/enabled
# JSON blobs as literal `jq --argjson` command-line arguments; once a
# marketplace catalog got large enough (confirmed against a real 273-plugin
# catalog), the serialized JSON exceeded the platform/shell's argv-length
# ceiling and jq crashed before emitting anything. Uses a synthetic 500-plugin
# catalog — well past the 273-plugin real-world repro — fully installed and
# enabled, so every array in the composed report (catalog, installed, enabled,
# and all three missing_from_* arrays) carries the full payload through the
# same code path that used to crash. Asserts the run completes AND produces
# the same-shaped, semantically-correct output a small catalog would (no
# silent truncation or partial report — the acceptance criteria's second
# bullet), not merely that it exits 0.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
big_n=500
write "$case_dir/known_marketplaces.json" '{"bigmarket": {"source": {"source": "github", "repo": "example/bigmarket"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
# Realistic-length ids (not bare "plugin-0") so the serialized payload's
# per-entry size is closer to the real-world repro, not an artificially
# compact worst case.
jq -cn --argjson n "$big_n" \
  '{plugins: [range(0;$n) | {name: ("large-catalog-synthetic-plugin-\(.)"), description: "synthetic fixture entry for issue #1336 large-catalog argv-length regression test"}]}' \
  >"$case_dir/catalog/bigmarket.json"
jq -cn --argjson n "$big_n" \
  '{version: 1, plugins: (reduce range(0;$n) as $i ({};
    . + {("large-catalog-synthetic-plugin-\($i)@bigmarket"): [{scope: "user", installPath: "y", version: "0.1.0"}]}))}' \
  >"$case_dir/installed_plugins.json"
jq -cn --argjson n "$big_n" \
  '{enabledPlugins: (reduce range(0;$n) as $i ({}; . + {("large-catalog-synthetic-plugin-\($i)@bigmarket"): true}))}' \
  >"$case_dir/user_settings.json"
ARGS=(--marketplace bigmarket)
out=$(run_state "$case_dir")
rc=$?
assert_exit "large catalog (500 plugins): exit 0, no argv-length crash" 0 "$rc"
case "$out" in
*"Argument list too long"*) fail "large catalog: no 'Argument list too long'" "found in output: $out" ;;
*) pass "large catalog: no 'Argument list too long'" ;;
esac
catalog_len=$(jq '.catalog | length' <<<"$out" 2>/dev/null)
assert_eq "large catalog: full 500-entry catalog reported, not truncated" "$big_n" "$catalog_len"
installed_len=$(jq '.installed | length' <<<"$out" 2>/dev/null)
assert_eq "large catalog: full 500-entry installed list reported" "$big_n" "$installed_len"
missing_install_len=$(jq '.missing_from_install | length' <<<"$out" 2>/dev/null)
assert_eq "large catalog: every plugin installed, so missing_from_install empty" "0" "$missing_install_len"
missing_user_install_len=$(jq '.missing_from_user_install | length' <<<"$out" 2>/dev/null)
assert_eq "large catalog: every plugin user-installed, so missing_from_user_install empty" "0" "$missing_user_install_len"
missing_enabled_len=$(jq '.missing_from_enabled | length' <<<"$out" 2>/dev/null)
assert_eq "large catalog: every plugin enabled, so missing_from_enabled empty" "0" "$missing_enabled_len"
sample_enabled=$(jq -r '.enabled["large-catalog-synthetic-plugin-499@bigmarket"]' <<<"$out" 2>/dev/null)
assert_eq "large catalog: a spot-checked entry has correct effective-enabled value, not a placeholder" "true" "$sample_enabled"

# ============================================================================
# Case: malformed user_settings.json still fails loud after the --argjson ->
# --slurpfile conversion (#1336 fail-loud parity). --slurpfile tolerates a
# genuinely EMPTY file as "zero JSON values" (yielding null) rather than
# erroring the way `--argjson name ""` used to when a prior `jq -c
# '.enabledPlugins // {}'` read failed on malformed source JSON and captured
# no stdout — so a naive conversion would turn a loud crash into a silent
# `null`-degraded report. jq_slurp_tmpfile guards this by writing a
# deliberately-invalid token for an empty value, forcing jq's own parser to
# still error at the --slurpfile call site. Confirmed against the actual
# pre-fix script (git history) that this exact fixture already failed loud
# (nonzero exit) before this issue's change, so this case is locking in
# existing behavior, not inventing a new contract.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}]}'
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{}}'
write "$case_dir/user_settings.json" '{bad json'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir")
rc=$?
if [[ "$rc" -eq 0 ]]; then
  fail "malformed user_settings.json: fails loud, not silently degraded" "expected nonzero exit, got 0 with output: $out"
else
  pass "malformed user_settings.json: fails loud, not silently degraded"
fi

# ============================================================================
# Case: static guard — no large-payload `--argjson` call site regresses back
# into fleet-state.sh (#1336). The runtime case above proves the CURRENT
# script doesn't crash; this guards against a future edit silently
# reintroducing `--argjson catalog|installed|missing*` (the exact pattern
# that crashed) alongside the harmless small-boolean `--argjson au|ci` uses
# this script legitimately keeps (a fixed literal `true`/`false`, never
# proportional to catalog size). Counts every `--argjson` occurrence in the
# script body (source lines only, comments excluded) and asserts it matches
# the fixed count of boolean-only remaining uses.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
argjson_code_count=$(grep -v '^\s*#' "$SCRIPT" | grep -c -- '--argjson' || true)
assert_eq "static guard: --argjson remains only on fixed-size booleans (au/ci/autoUpdate), not catalog-sized payloads" "7" "$argjson_code_count"

# --- Summary -------------------------------------------------------------
printf '\n%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]] && exit 0
exit 1
