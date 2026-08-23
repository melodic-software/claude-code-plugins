#!/usr/bin/env bash
# Black-box contract tests for fleet-state.sh (self-contained — ships with the plugin).
# Fixtures are built per-case into a temp dir via FLEET_STATE_* env overrides,
# mirroring the claude-config audit skill's SETTINGS_AUDIT_FIXTURE_DIR pattern.
set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

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

# Like run_state but with CLAUDE_PROJECT_DIR explicitly UNSET, for the cases that
# exercise cwd-based project resolution. The caller must `cd` into the directory
# under test itself — which directory that is IS the thing each such case
# exercises — so this only carries the fixture env: extra `NAME=value` pairs (and
# exported-function decoys) are passed through ahead of the FLEET_STATE_* vars.
# Args: case_dir [env pair …]
run_state_no_project_dir() {
  local case_dir="$1"
  shift
  env -u CLAUDE_PROJECT_DIR "$@" \
    FLEET_STATE_INSTALLED_JSON="$case_dir/installed_plugins.json" \
    FLEET_STATE_MARKETPLACES_JSON="$case_dir/known_marketplaces.json" \
    FLEET_STATE_USER_SETTINGS="$case_dir/user_settings.json" \
    FLEET_STATE_CATALOG_DIR="$case_dir/catalog" \
    bash "$SCRIPT" --marketplace market1 2>&1
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
(cd "$project_dir" && git init -q && git -c user.email=t@t.test -c user.name=t -c commit.gpgsign=false commit -q --allow-empty -m init)
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
out=$(cd "$project_dir/nested/subdir" && run_state_no_project_dir "$case_dir")
current_flag=$(jq -r '.installed[0].currentProject' <<<"$out" 2>/dev/null)
assert_eq "git-fallback: CLAUDE_PROJECT_DIR unset, cwd inside a subdir, resolves via git toplevel" "true" "$current_flag"

# ============================================================================
# Case: a non-git cwd with CLAUDE_PROJECT_DIR unset and NO .claude directory
# has no project context. Without the corroborating `.claude` marker, falling
# back to bare $PWD manufactures project context for any non-repo directory,
# so an install record whose projectPath happens to equal the cwd must not be
# promoted to currentProject.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
nonrepo_dir="$case_dir/not-a-git-repo"
mkdir -p "$nonrepo_dir"
native_nonrepo_path="${nonrepo_dir//\//\\}"
write "$case_dir/installed_plugins.json" "$(
  jq -cn --arg p "$native_nonrepo_path" \
    '{version: 1, plugins: {"alpha@market1": [{scope: "project", projectPath: $p, installPath: "x", version: "0.1.0"}]}}'
)"
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}]}'
write "$case_dir/user_settings.json" '{"enabledPlugins":{}}'
out=$(cd "$nonrepo_dir" && run_state_no_project_dir "$case_dir")
current_flag=$(jq -r '.installed[0].currentProject' <<<"$out" 2>/dev/null)
assert_eq "no-project-context: non-git cwd with CLAUDE_PROJECT_DIR unset manufactures no currentProject" "null" "$current_flag"

# ============================================================================
# Case: a non-git cwd WITH a .claude directory is project context. Claude Code
# does not require a repo: a headless session anchored in a plain directory
# has neither CLAUDE_PROJECT_DIR nor a git toplevel, but its .claude marker
# corroborates the anchor, so its install records keep currentProject and its
# .claude/settings*.json stays visible.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
nongit_proj="$case_dir/plain-project"
mkdir -p "$nongit_proj/.claude"
write "$nongit_proj/.claude/settings.json" '{"enabledPlugins":{"alpha@market1": true}}'
# The native form a real CC-written projectPath carries: on Git Bash `pwd -W`
# yields the long drive-letter form (no git toplevel exists here to derive it
# from, and cygpath 8.3-shortens — see the git-fallback case's note); on POSIX
# hosts plain pwd is already the native form.
nongit_native=$(cd "$nongit_proj" && (pwd -W 2>/dev/null || pwd))
native_nongit_path="${nongit_native//\//\\}"
write "$case_dir/installed_plugins.json" "$(
  jq -cn --arg p "$native_nongit_path" \
    '{version: 1, plugins: {"alpha@market1": [{scope: "project", projectPath: $p, installPath: "x", version: "0.1.0"}]}}'
)"
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}]}'
write "$case_dir/user_settings.json" '{"enabledPlugins":{}}'
out=$(cd "$nongit_proj" && run_state_no_project_dir "$case_dir")
current_flag=$(jq -r '.installed[0].currentProject' <<<"$out" 2>/dev/null)
assert_eq "non-git project: .claude marker preserves currentProject without CLAUDE_PROJECT_DIR or git" "true" "$current_flag"
effective_val=$(jq -r '.enabled."alpha@market1"' <<<"$out" 2>/dev/null)
assert_eq "non-git project: .claude/settings.json read as the project scope" "true" "$effective_val"

# ============================================================================
# Case: $HOME is never project context, even though it carries .claude. That
# directory is USER scope; reading $HOME/.claude/settings.json as the project
# map would duplicate the user map.
#
# Load-bearing only where `mktemp -d` yields a path the shell and the OS spell
# differently — Git Bash, whose `/tmp/…` mount alias has no drive letter for the
# normalizer to reconcile against `pwd -W`'s `C:/…`. On a POSIX host both sides
# already agree, so this case passes there whether or not the exclusion works: a
# green run off Windows is not evidence about it.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
fake_home="$case_dir/fake-home"
mkdir -p "$fake_home/.claude"
write "$fake_home/.claude/settings.json" '{"enabledPlugins":{"alpha@market1": true}}'
native_home_path="${fake_home//\//\\}"
write "$case_dir/installed_plugins.json" "$(
  jq -cn --arg p "$native_home_path" \
    '{version: 1, plugins: {"alpha@market1": [{scope: "project", projectPath: $p, installPath: "x", version: "0.1.0"}]}}'
)"
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}]}'
write "$case_dir/user_settings.json" '{"enabledPlugins":{}}'
out=$(cd "$fake_home" && run_state_no_project_dir "$case_dir" HOME="$fake_home")
current_flag=$(jq -r '.installed[0].currentProject' <<<"$out" 2>/dev/null)
assert_eq "home exclusion: \$HOME with .claude is user scope, not project context" "null" "$current_flag"

# ============================================================================
# Case: an exported `cd` function cannot collapse a real project onto $HOME.
# The exclusion spells $HOME by changing into it, so a hijacked `cd` that
# returns success WITHOUT moving would make $HOME resolve to the cwd — and
# every corroborated non-git project would then compare equal to $HOME and
# lose both its project settings and its currentProject marker. The resolution
# uses `builtin cd`/`builtin pwd`, so the shadow is never consulted. Unlike the
# exclusion case above, this one is load-bearing on every platform: the failure
# is the shadow being honoured, not a path-spelling mismatch.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
proj_dir="$case_dir/real-project"
fake_home="$case_dir/elsewhere-home"
mkdir -p "$proj_dir/.claude" "$fake_home"
write "$proj_dir/.claude/settings.json" '{"enabledPlugins":{"alpha@market1": true}}'
# Native spelling, as the non-git-project case above derives it: a record built
# from the MSYS path could never match what the script resolves, which would
# make this case report `false` whether or not the shadow was honoured.
proj_native=$(cd "$proj_dir" && (pwd -W 2>/dev/null || pwd))
native_proj_path="${proj_native//\//\\}"
write "$case_dir/installed_plugins.json" "$(
  jq -cn --arg p "$native_proj_path" \
    '{version: 1, plugins: {"alpha@market1": [{scope: "project", projectPath: $p, installPath: "x", version: "0.1.0"}]}}'
)"
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}]}'
write "$case_dir/user_settings.json" '{"enabledPlugins":{}}'
out=$(cd "$proj_dir" && run_state_no_project_dir "$case_dir" \
  HOME="$fake_home" "BASH_FUNC_cd%%=() { return 0; }")
current_flag=$(jq -r '.installed[0].currentProject' <<<"$out" 2>/dev/null)
assert_eq "cd shadow cannot collapse a real project onto \$HOME" "true" "$current_flag"

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
argjson_code_count=$(grep -v '^[[:space:]]*#' "$SCRIPT" | grep -c -- '--argjson' || true)
assert_eq "static guard: --argjson remains only on fixed-size booleans (au/ci/autoUpdate), not catalog-sized payloads" "7" "$argjson_code_count"

# ============================================================================
# --ids: the id-projection mode `sync` Steps 2-5 loop, so no caller hand-writes
# `jq -r ... | while read` (#2578).
#
# Fixture shared by the cases below: two plugins installed at user scope plus a
# third catalog entry installed nowhere, so installed-user yields TWO ids (the
# minimum that can exhibit the all-but-last CR signature) and
# missing-user-install yields one.
# ============================================================================
seed_ids_case() {
  local case_dir="$1"
  write "$case_dir/installed_plugins.json" '{
    "version": 1,
    "plugins": {
      "alpha@market1": [{"scope": "user", "installPath": "x", "version": "0.1.0"}],
      "beta@market1": [{"scope": "user", "installPath": "y", "version": "0.2.0"}]
    }
  }'
  write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
  write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}, {"name": "beta"}, {"name": "gamma"}]}'
  write "$case_dir/user_settings.json" '{"enabledPlugins": {"alpha@market1": true, "beta@market1": true}}'
}

# Like run_state but keeps stderr OFF stdout: these cases assert on exact bytes.
run_ids() {
  local case_dir="$1"
  shift
  env \
    FLEET_STATE_INSTALLED_JSON="$case_dir/installed_plugins.json" \
    FLEET_STATE_MARKETPLACES_JSON="$case_dir/known_marketplaces.json" \
    FLEET_STATE_USER_SETTINGS="$case_dir/user_settings.json" \
    FLEET_STATE_CATALOG_DIR="$case_dir/catalog" \
    "$@" \
    bash "$SCRIPT" "${ARGS[@]}" 2>/dev/null
}

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_ids_case "$case_dir"
ARGS=(--marketplace market1 --ids installed-user)
out=$(run_ids "$case_dir")
rc=$?
assert_exit "--ids installed-user: exit 0" 0 "$rc"
assert_eq "--ids installed-user: one fully-qualified id per line" \
  "alpha@market1
beta@market1" "$out"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_ids_case "$case_dir"
ARGS=(--marketplace market1 --ids missing-user-install)
out=$(run_ids "$case_dir")
assert_eq "--ids missing-user-install: catalog entry installed nowhere" "gamma@market1" "$out"

# ============================================================================
# REGRESSION (#2578): --ids output must carry no CR even when jq writes stdout
# in Windows text mode.
#
# Host-independent by construction: a PATH stub named `jq` normalizes every
# emitted line to exactly ONE trailing CR, so the case exercises the same bytes
# on a Linux runner (where real jq emits bare LF and the stub ADDS the CR) as on
# Windows (where the native binary already emits CRLF and the stub is a no-op).
# Without that normalization the case would be vacuous on Linux — green for the
# wrong reason, which is the failure mode #2571 was landed to stop repeating.
#
# `command jq` resolves through PATH, so fleet-state.sh's own
# `jq() { command jq "$@" | tr -d '\r'; }` wrapper calls the stub exactly as it
# would call a native Windows jq. This case therefore goes red BOTH if --ids is
# removed and if that wrapper is ever deleted.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_ids_case "$case_dir"
mkdir -p "$case_dir/crlf-bin"
REAL_JQ="$(command -v jq)"
{
  printf '#!/usr/bin/env bash\n'
  # pipefail so the stub reports JQ's status, not sed's. Without it every
  # invocation exits 0 and a future failure-path case added under this stub
  # would pass vacuously.
  printf 'set -o pipefail\n'
  # s/\r*$/\r/ collapses "already CRLF" and "bare LF" to the same one-CR form.
  printf '"%s" "$@" | sed '"'"'s/\\r*$/\\r/'"'"'\n' "$REAL_JQ"
} >"$case_dir/crlf-bin/jq"
chmod +x "$case_dir/crlf-bin/jq"

# Guard the guard: prove the stub actually CRLF-terminates, so a stub that
# silently stopped working cannot make the assertion below vacuously pass.
stub_probe=$(printf '{"a":"one"}' | PATH="$case_dir/crlf-bin:$PATH" jq -r '.a' | od -An -c | tr -s ' ')
assert_contains "--ids CR regression: stub jq really emits CRLF" "$stub_probe" 'o n e \r \n'

ARGS=(--marketplace market1 --ids installed-user)
out=$(PATH="$case_dir/crlf-bin:$PATH" run_ids "$case_dir")
rc=$?
assert_exit "--ids CR regression: exit 0 under a CRLF-emitting jq" 0 "$rc"
# The empty branch is not redundant: with no output at all "contains no CR" is
# vacuously true, so a regression that stopped emitting ids entirely would pass
# a bare CR check. Verified against the pre-fix script — it emitted nothing and
# the CR assertion passed for the wrong reason until this branch was added.
case "$out" in
"") fail "--ids CR regression: no CR survives into the emitted ids" \
  "output was EMPTY — a CR assertion over no output proves nothing" ;;
*$'\r'*) fail "--ids CR regression: no CR survives into the emitted ids" \
  "output carried a CR: $(printf '%s' "$out" | od -An -c | tr -s ' ')" ;;
*) pass "--ids CR regression: no CR survives into the emitted ids" ;;
esac
assert_eq "--ids CR regression: ids are byte-exact under a CRLF-emitting jq" \
  "alpha@market1
beta@market1" "$out"

# current-project carries the scope as a second tab-separated field. The fixture
# is the case that makes it necessary: ONE plugin holding both a project- and a
# local-scope record for the current repo, both currentProject:true. An id-only
# projection emits that id twice with nothing to tell the lines apart, and Step
# 2 picks the wrong `-s` flag (or drops an update to `sort -u`).
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
proj_root="$case_dir/sample-repo"
mkdir -p "$proj_root"
native_proj="$(cygpath -w "$proj_root" 2>/dev/null || echo "$proj_root")"
write "$case_dir/installed_plugins.json" "$(
  jq -cn --arg p "$native_proj" '{
    version: 1,
    plugins: {
      "alpha@market1": [
        {scope: "project", projectPath: $p, installPath: "x", version: "0.1.0"},
        {scope: "local", projectPath: $p, installPath: "y", version: "0.1.0"}
      ]
    }
  }'
)"
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}]}'
ARGS=(--marketplace market1 --ids current-project)
out=$(run_ids "$case_dir" CLAUDE_PROJECT_DIR="$proj_root")
rc=$?
assert_exit "--ids current-project: exit 0" 0 "$rc"
assert_eq "--ids current-project: dual-scope install keeps each scope on its own record" \
  "alpha@market1	project
alpha@market1	local" "$out"
# Consume it exactly as sync.md Step 2 documents, and prove the pairing survives.
pairs=""
while IFS=$'\t' read -r pid pscope; do
  [[ -n "$pid" ]] || continue
  pairs+="${pid}:${pscope} "
done <<<"$out"
assert_eq "--ids current-project: Step 2's IFS=tab read recovers both id/scope pairs" \
  "alpha@market1:project alpha@market1:local " "$pairs"

# --ids also works on the zero-arg default path, not just with --marketplace:
# both route through emit_one, and this pins that they stay wired together.
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
write "$case_dir/user_settings.json" '{"enabledPlugins": {"this-plugin@market1": true}}'
ARGS=(--ids installed-user)
out=$(run_ids "$case_dir" CLAUDE_PLUGIN_ROOT="$fake_plugin_root")
rc=$?
assert_exit "--ids on the default (zero-arg) path: exit 0" 0 "$rc"
assert_eq "--ids on the default (zero-arg) path: emits the resolved marketplace's ids" \
  "this-plugin@market1" "$out"

# A per-marketplace failure must NOT put its JSON error block on the --ids
# stdout stream. `done < <(… --ids …)` cannot see the process's exit status, so
# an error object left on stdout is read as an id and passed straight to
# `claude plugin update`. Report mode still gets the block on stdout.
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{not valid json'
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{}}'
write "$case_dir/user_settings.json" '{"enabledPlugins":{}}'
ARGS=(--marketplace market1 --ids installed-user)
out=$(run_ids "$case_dir")
rc=$?
assert_exit "--ids on a broken catalog: nonzero exit" 1 "$rc"
assert_eq "--ids on a broken catalog: stdout carries no error JSON, only records" "" "$out"
# Same fixture in report mode still writes the error block to stdout.
ARGS=(--marketplace market1)
out_report=$(run_ids "$case_dir")
assert_contains "report mode on a broken catalog: error block stays on stdout" \
  "$out_report" '"error"'

# ============================================================================
# --ids rejections: refused loudly, never a silently-empty list.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_ids_case "$case_dir"
ARGS=(--marketplace market1 --ids no-such-selector)
out=$(run_state "$case_dir")
rc=$?
assert_exit "--ids unknown selector: exit 2" 2 "$rc"
assert_contains "--ids unknown selector: names the bad selector" "$out" "no-such-selector"

# A bad selector is a USAGE error, so it must report as exit 2 even when the
# marketplace would itself fail to resolve (exit 1). Guards the ordering: with
# the selector checked lazily inside emit_ids, resolution runs first and its
# exit 1 masks the real cause.
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_ids_case "$case_dir"
ARGS=(--marketplace no-such-marketplace --ids no-such-selector)
out=$(run_state "$case_dir")
rc=$?
assert_exit "--ids bad selector outranks an unresolvable marketplace: exit 2" 2 "$rc"
assert_contains "--ids bad selector outranks an unresolvable marketplace: reports the selector" \
  "$out" "no-such-selector"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_ids_case "$case_dir"
ARGS=(--marketplace market1 --ids)
out=$(run_state "$case_dir")
rc=$?
assert_exit "--ids with no selector: exit 2, does not spin" 2 "$rc"
assert_contains "--ids with no selector: says a selector is required" "$out" "requires a selector"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_ids_case "$case_dir"
ARGS=(--all --ids installed-user)
out=$(run_state "$case_dir")
rc=$?
assert_exit "--ids with --all: exit 2" 2 "$rc"
assert_contains "--ids with --all: refuses rather than inventing a shape" "$out" "cannot be combined"

# ============================================================================
# Case: project_root disambiguates the current-project tri-state. `--ids
# current-project` matches currentProject == true, so "no project context at
# all" (flags null) and "project context with zero in-repo installs" (flags
# false) both project to zero ids; project_root is the field a consumer reads
# to tell those apart. String when context resolved, null when none — never "".
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
project_dir="$case_dir/pr-project"
mkdir -p "$project_dir"
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}]}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir" CLAUDE_PROJECT_DIR="$project_dir")
project_root=$(jq -r '.project_root' <<<"$out" 2>/dev/null)
assert_eq "project_root: resolved context surfaces as the PROJECT_ROOT string" "$project_dir" "$project_root"

# No context: non-git cwd, no .claude marker, CLAUDE_PROJECT_DIR unset — the
# same anchor-less setup the currentProject null case exercises.
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
nonrepo_dir="$case_dir/not-a-git-repo"
mkdir -p "$nonrepo_dir"
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{}}'
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}]}'
write "$case_dir/user_settings.json" '{"enabledPlugins":{}}'
out=$(cd "$nonrepo_dir" && run_state_no_project_dir "$case_dir")
project_root=$(jq -r '.project_root' <<<"$out" 2>/dev/null)
assert_eq "project_root: no project context is null, not empty string" "null" "$project_root"

# Every per-marketplace block under --all carries it too: --all consumers read
# blocks independently, so the tri-state must travel with each one.
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
project_dir="$case_dir/all-project"
mkdir -p "$project_dir"
write "$case_dir/known_marketplaces.json" '{
  "market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"},
  "market2": {"source": {"source": "github", "repo": "example/market2"}, "installLocation": "z2", "lastUpdated": "2026-01-01T00:00:00Z"}
}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}]}'
write "$case_dir/catalog/market2.json" '{"plugins": [{"name": "beta"}]}'
ARGS=(--all)
out=$(run_state "$case_dir" CLAUDE_PROJECT_DIR="$project_dir")
roots=$(jq -r '[.marketplaces.market1.project_root, .marketplaces.market2.project_root] | unique | .[]' <<<"$out" 2>/dev/null)
assert_eq "project_root: every --all block carries the same resolved root" "$project_dir" "$roots"

# ============================================================================
# Case: projectPathExists tri-state. converge/sync must not emit
# `(cd "<projectPath>" && claude plugin …)` against a directory that no longer
# exists — no CLI verb reaps such records (observed on the audited CC 2.1.240
# run), so they are report-only, and this field is how a consumer knows.
# true: projectPath recorded and the directory exists. false: recorded but
# gone. null: user-scope record, no projectPath at all. The dead-path plugin
# is dual-scope so divergences[].scopes[] is pinned to carry the field too.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
live_dir="$case_dir/live-repo"
mkdir -p "$live_dir"
write "$case_dir/installed_plugins.json" "$(
  jq -cn --arg live "$live_dir" --arg dead "$case_dir/deleted-repo" '{
    version: 1,
    plugins: {
      "alpha@market1": [{scope: "project", projectPath: $live, installPath: "x", version: "0.1.0"}],
      "beta@market1": [
        {scope: "project", projectPath: $dead, installPath: "y", version: "0.1.0"},
        {scope: "user", installPath: "z", version: "0.2.0"}
      ]
    }
  }'
)"
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}, {"name": "beta"}]}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir")
tri=$(jq -c '[.installed[] | {id, scope, projectPathExists}]' <<<"$out" 2>/dev/null)
assert_eq "projectPathExists: live dir true, deleted dir false, user-scope null" \
  '[{"id":"alpha@market1","scope":"project","projectPathExists":true},{"id":"beta@market1","scope":"project","projectPathExists":false},{"id":"beta@market1","scope":"user","projectPathExists":null}]' \
  "$tri"
div_tri=$(jq -c '[.divergences[0].scopes[] | .projectPathExists]' <<<"$out" 2>/dev/null)
assert_eq "projectPathExists: divergences[].scopes[] carries it per scope entry" "[false,null]" "$div_tri"

# ============================================================================
# Case: --marketplaces enumerates known_marketplaces.json names one per line,
# stdout-only, so sync's all-marketplace mode iterates `--marketplace <name>
# --ids <selector>` per name without hand-writing `jq -r 'keys[]' | while
# read` (the Windows-CRLF corruption --ids itself exists to prevent).
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/known_marketplaces.json" '{
  "market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"},
  "market2": {"source": {"source": "github", "repo": "example/market2"}, "installLocation": "z2", "lastUpdated": "2026-01-01T00:00:00Z"}
}'
ARGS=(--marketplaces)
out=$(run_state "$case_dir")
rc=$?
assert_exit "--marketplaces: exit 0" 0 "$rc"
assert_eq "--marketplaces: every marketplace name, one per line" \
  "market1
market2" "$out"

# Empty object: nothing to enumerate is an answer, not an error.
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/known_marketplaces.json" '{}'
ARGS=(--marketplaces)
out=$(run_state "$case_dir")
rc=$?
assert_exit "--marketplaces: empty object exits 0" 0 "$rc"
assert_eq "--marketplaces: empty object emits nothing" "" "$out"

# CR regression, same stub mechanism as the --ids case above: the emitted
# names must be CR-free even under a CRLF-emitting native-Windows jq, because
# the documented consumer is a `while read` loop feeding --marketplace.
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/known_marketplaces.json" '{
  "market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"},
  "market2": {"source": {"source": "github", "repo": "example/market2"}, "installLocation": "z2", "lastUpdated": "2026-01-01T00:00:00Z"}
}'
# run_ids does not seed the prerequisite state files the way run_state does.
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{}}'
write "$case_dir/user_settings.json" '{"enabledPlugins":{}}'
mkdir -p "$case_dir/crlf-bin"
REAL_JQ="$(command -v jq)"
{
  printf '#!/usr/bin/env bash\n'
  printf 'set -o pipefail\n'
  printf '"%s" "$@" | sed '"'"'s/\\r*$/\\r/'"'"'\n' "$REAL_JQ"
} >"$case_dir/crlf-bin/jq"
chmod +x "$case_dir/crlf-bin/jq"
ARGS=(--marketplaces)
out=$(PATH="$case_dir/crlf-bin:$PATH" run_ids "$case_dir")
rc=$?
assert_exit "--marketplaces CR regression: exit 0 under a CRLF-emitting jq" 0 "$rc"
case "$out" in
"") fail "--marketplaces CR regression: no CR survives into the names" \
  "output was EMPTY — a CR assertion over no output proves nothing" ;;
*$'\r'*) fail "--marketplaces CR regression: no CR survives into the names" \
  "output carried a CR: $(printf '%s' "$out" | od -An -c | tr -s ' ')" ;;
*) pass "--marketplaces CR regression: no CR survives into the names" ;;
esac

# Standalone mode: refused loudly with every report-shaping flag, in either
# argument order — never silently ignored.
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": []}'
for combo in "--marketplaces --all" "--all --marketplaces" "--marketplaces --marketplace market1" "--marketplaces --ids installed-user"; do
  # combo is a fixed space-separated flag list; word splitting is the point.
  # shellcheck disable=SC2206
  ARGS=($combo)
  out=$(run_state "$case_dir")
  rc=$?
  assert_exit "--marketplaces combination '$combo': exit 2" 2 "$rc"
  assert_contains "--marketplaces combination '$combo': refused loudly" "$out" "cannot be combined"
done

# ============================================================================
# --ids stale-user: the subset of user-scope installed ids NOT confirmed
# current with the local marketplace checkout's catalog version — sync Step 3
# skips `claude plugin update` for the confirmed-current rest. FAIL OPEN: any
# id whose catalog version cannot be resolved is emitted (a wrong emission
# costs one no-op CLI call; a wrong omission skips a real update). Fixture
# note: FLEET_STATE_CATALOG_DIR replaces the CATALOG file only — the
# per-plugin manifests resolve under the real installLocation, so this case
# builds a real clone directory with pinned plugin.json versions.
#
# One fixture, every resolution edge:
#   alpha    string source "./plugins/alpha", manifest current   → omitted
#   beta     no source, default plugins/beta, manifest ahead     → emitted
#   curr     no source, default plugins/curr, manifest current   → omitted
#   custom   string source "./nested/custom", manifest current   → omitted
#            (proves the source path is honored: the plugins/custom default
#            carries no manifest, so ignoring source would fail it open)
#   ghost    manifest missing                                    → emitted
#   broken   manifest invalid JSON                               → emitted
#   notstr   manifest .version is a number                       → emitted
#   objsrc   object source, no local manifest anywhere           → emitted
#   projonly project-scope only — outside the user-scope population, never
#            emitted no matter how stale
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
clone="$case_dir/mp-clone"
mkdir -p "$clone/plugins/alpha/.claude-plugin" "$clone/plugins/beta/.claude-plugin" \
  "$clone/plugins/curr/.claude-plugin" "$clone/nested/custom/.claude-plugin" \
  "$clone/plugins/broken/.claude-plugin" "$clone/plugins/notstr/.claude-plugin"
write "$clone/plugins/alpha/.claude-plugin/plugin.json" '{"name": "alpha", "version": "1.0.0"}'
write "$clone/plugins/beta/.claude-plugin/plugin.json" '{"name": "beta", "version": "2.1.0"}'
write "$clone/plugins/curr/.claude-plugin/plugin.json" '{"name": "curr", "version": "3.3.3"}'
write "$clone/nested/custom/.claude-plugin/plugin.json" '{"name": "custom", "version": "4.0.0"}'
write "$clone/plugins/broken/.claude-plugin/plugin.json" '{not valid json'
write "$clone/plugins/notstr/.claude-plugin/plugin.json" '{"name": "notstr", "version": 7}'
write "$case_dir/installed_plugins.json" '{
  "version": 1,
  "plugins": {
    "alpha@market1": [{"scope": "user", "installPath": "a", "version": "1.0.0"}],
    "beta@market1": [{"scope": "user", "installPath": "b", "version": "2.0.0"}],
    "curr@market1": [{"scope": "user", "installPath": "c", "version": "3.3.3"}],
    "custom@market1": [{"scope": "user", "installPath": "d", "version": "4.0.0"}],
    "ghost@market1": [{"scope": "user", "installPath": "e", "version": "0.1.0"}],
    "broken@market1": [{"scope": "user", "installPath": "f", "version": "0.1.0"}],
    "notstr@market1": [{"scope": "user", "installPath": "g", "version": "7"}],
    "objsrc@market1": [{"scope": "user", "installPath": "h", "version": "0.1.0"}],
    "projonly@market1": [{"scope": "project", "projectPath": "<PROJECT_ROOT>/x", "installPath": "i", "version": "0.0.1"}]
  }
}'
write "$case_dir/known_marketplaces.json" "$(
  jq -cn --arg loc "$clone" \
    '{market1: {source: {source: "github", repo: "example/market1"}, installLocation: $loc, lastUpdated: "2026-01-01T00:00:00Z"}}'
)"
write "$case_dir/catalog/market1.json" '{"plugins": [
  {"name": "alpha", "source": "./plugins/alpha"},
  {"name": "beta"},
  {"name": "curr"},
  {"name": "custom", "source": "./nested/custom"},
  {"name": "ghost"},
  {"name": "broken"},
  {"name": "notstr"},
  {"name": "objsrc", "source": {"source": "github", "repo": "example/objsrc"}},
  {"name": "projonly"}
]}'
ARGS=(--marketplace market1 --ids stale-user)
out=$(run_ids "$case_dir")
rc=$?
assert_exit "--ids stale-user: exit 0" 0 "$rc"
assert_eq "--ids stale-user: stale + every unresolvable edge emitted, confirmed-current omitted, project-scope out of population" \
  "beta@market1
ghost@market1
broken@market1
notstr@market1
objsrc@market1" "$out"

# Missing installLocation: no clone to read a catalog version from, so every
# user-scope id fails open into the emitted set.
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/installed_plugins.json" '{
  "version": 1,
  "plugins": {"alpha@market1": [{"scope": "user", "installPath": "a", "version": "1.0.0"}]}
}'
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha", "source": "./plugins/alpha"}]}'
ARGS=(--marketplace market1 --ids stale-user)
out=$(run_ids "$case_dir")
rc=$?
assert_exit "--ids stale-user: missing installLocation exits 0" 0 "$rc"
assert_eq "--ids stale-user: missing installLocation fails open, id emitted" "alpha@market1" "$out"

# Zero user-scope installs: empty output is success, matching every other
# selector's zero-match contract.
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}]}'
# run_ids does not seed the prerequisite state files the way run_state does.
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{}}'
write "$case_dir/user_settings.json" '{"enabledPlugins":{}}'
ARGS=(--marketplace market1 --ids stale-user)
out=$(run_ids "$case_dir")
rc=$?
assert_exit "--ids stale-user: zero user-scope installs is success" 0 "$rc"
assert_eq "--ids stale-user: zero user-scope installs emits nothing" "" "$out"

# --- Summary -------------------------------------------------------------
printf '\n%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]] && exit 0
exit 1
