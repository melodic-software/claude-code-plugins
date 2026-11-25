#!/usr/bin/env bash
# test-scope: .claude/settings.json
set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

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

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}, {"name": "beta"}]}'
write "$case_dir/user_settings.json" '{"enabledPlugins": {"alpha@market1": false}}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir")
missing_install=$(jq -cS '.missing_from_install' <<<"$out" 2>/dev/null)
assert_eq "opt-out before install: excluded from missing_from_install" '["beta@market1"]' "$missing_install"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}, {"name": "beta"}]}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir")
missing=$(jq -cS '.missing_from_install' <<<"$out" 2>/dev/null)
assert_eq "missing-install: both catalog plugins flagged" '["alpha@market1","beta@market1"]' "$missing"

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
# intent (per the plugin manifest reference's defaultEnabled section: the
# marketplace entry's defaultEnabled overrides plugin.json's, so turning the
# plugin on is the user's opt-in, not sync auto-enabling on their behalf)
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

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
ARGS=(--marketplace ghost-market)
out=$(run_state "$case_dir")
rc=$?
assert_exit "absent marketplace: exit 1" 1 "$rc"
error_msg=$(jq -r '.marketplace.error' <<<"$out" 2>/dev/null)
assert_eq "absent marketplace: error field set" "not found in known_marketplaces.json" "$error_msg"

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
# different repos on a case-sensitive filesystem. Same fixture, run twice with
# an EXPLICIT OSTYPE override each time (never "this host's ambient OSTYPE" —
# this suite itself runs on both a case-insensitive dev host and a
# case-sensitive CI runner, so asserting against the ambient value is not
# deterministic across them): forcing linux-gnu must NOT match
# (case-sensitive); forcing msys must still match (case-insensitive — no
# regression to the existing behavior).
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
# is the shadow being honored, not a path-spelling mismatch.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
proj_dir="$case_dir/real-project"
fake_home="$case_dir/elsewhere-home"
mkdir -p "$proj_dir/.claude" "$fake_home"
write "$proj_dir/.claude/settings.json" '{"enabledPlugins":{"alpha@market1": true}}'
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

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/known_marketplaces.json" '{
  "market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"},
  "market2": {"source": {"source": "github", "repo": "example/market2"}, "installLocation": "z2", "lastUpdated": "2026-01-01T00:00:00Z"}
}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}]}'
ARGS=(--all)
out=$(run_state "$case_dir")
rc=$?
assert_exit "--all: exits 0 even with one marketplace unreachable" 0 "$rc"
m1_catalog=$(jq -c '.marketplaces.market1.catalog' <<<"$out" 2>/dev/null)
assert_eq "--all: market1 resolved" '["alpha"]' "$m1_catalog"
m2_error=$(jq -r '.marketplaces.market2.marketplace.error' <<<"$out" 2>/dev/null)
assert_eq "--all: market2 reports its failure inline" "no catalog fixture" "$m2_error"

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
installed_ver_path="$skew_parent/0.18.3"
session_ver_path="$skew_parent/0.19.0"
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

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
dev_checkout="$case_dir/dev-checkout"
dev_root="$dev_checkout/plugins/this-plugin"
mkdir -p "$dev_root" "$dev_checkout/.claude-plugin"
write "$dev_checkout/.claude-plugin/marketplace.json" '{"name": "market1", "plugins": [{"name": "this-plugin", "source": "./plugins/this-plugin"}]}'
write "$case_dir/installed_plugins.json" '{"version": 1, "plugins": {}}'
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "this-plugin"}]}'
ARGS=()
out=$(run_state "$case_dir" CLAUDE_PLUGIN_ROOT="$dev_root")
rc=$?
assert_exit "dev checkout: resolves via marketplace.json walk-up" 0 "$rc"
resolved_name=$(jq -r '.marketplace.name' <<<"$out" 2>/dev/null)
assert_eq "dev checkout: correct marketplace from the manifest" "market1" "$resolved_name"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
deep_checkout="$case_dir/deep-checkout"
deep_root="$deep_checkout/packages/extensions/plugins/x/this-plugin"
mkdir -p "$deep_root" "$deep_checkout/.claude-plugin"
write "$deep_checkout/.claude-plugin/marketplace.json" '{"name": "market1", "plugins": [{"name": "this-plugin", "source": "./packages/extensions/plugins/x/this-plugin"}]}'
write "$case_dir/installed_plugins.json" '{"version": 1, "plugins": {}}'
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "this-plugin"}]}'
ARGS=()
out=$(run_state "$case_dir" CLAUDE_PLUGIN_ROOT="$deep_root")
rc=$?
assert_exit "deep dev checkout: resolves via marketplace.json walk-up" 0 "$rc"
resolved_name=$(jq -r '.marketplace.name' <<<"$out" 2>/dev/null)
assert_eq "deep dev checkout: correct marketplace from the manifest" "market1" "$resolved_name"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
both_checkout="$case_dir/both-checkout"
both_root="$both_checkout/plugins/this-plugin"
mkdir -p "$both_root" "$both_checkout/.claude-plugin"
write "$both_checkout/.claude-plugin/marketplace.json" '{"name": "market2", "plugins": [{"name": "this-plugin", "source": "./plugins/this-plugin"}]}'
native_both="$(cygpath -w "$both_root" 2>/dev/null || echo "$both_root")"
write "$case_dir/installed_plugins.json" "$(
  jq -cn --arg root "$native_both" \
    '{version: 1, plugins: {"this-plugin@market1": [{scope: "user", installPath: $root, version: "0.1.0"}]}}'
)"
write "$case_dir/known_marketplaces.json" '{
  "market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"},
  "market2": {"source": {"source": "github", "repo": "example/market2"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}
}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "this-plugin"}]}'
write "$case_dir/catalog/market2.json" '{"plugins": [{"name": "this-plugin"}]}'
ARGS=()
out=$(run_state "$case_dir" CLAUDE_PLUGIN_ROOT="$both_root")
rc=$?
assert_exit "stage precedence: exit 0" 0 "$rc"
resolved_name=$(jq -r '.marketplace.name' <<<"$out" 2>/dev/null)
assert_eq "stage precedence: installPath match beats the walk-up manifest" "market1" "$resolved_name"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
install_location="$case_dir/market1-clone"
loc_root="$install_location/plugins/this-plugin"
mkdir -p "$loc_root"
native_location="$(cygpath -w "$install_location" 2>/dev/null || echo "$install_location")"
write "$case_dir/installed_plugins.json" '{"version": 1, "plugins": {}}'
write "$case_dir/known_marketplaces.json" "$(
  jq -cn --arg loc "$native_location" \
    '{market1: {source: {source: "github", repo: "example/market1"}, installLocation: $loc, lastUpdated: "2026-01-01T00:00:00Z"}}'
)"
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "this-plugin"}]}'
ARGS=()
out=$(run_state "$case_dir" CLAUDE_PLUGIN_ROOT="$loc_root")
rc=$?
assert_exit "installLocation root: resolves via installLocation prefix" 0 "$rc"
resolved_name=$(jq -r '.marketplace.name' <<<"$out" 2>/dev/null)
assert_eq "installLocation root: correct marketplace from installLocation" "market1" "$resolved_name"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
stranger_checkout="$case_dir/stranger-checkout"
stranger_root="$stranger_checkout/plugins/this-plugin"
mkdir -p "$stranger_root" "$stranger_checkout/.claude-plugin"
write "$stranger_checkout/.claude-plugin/marketplace.json" '{"name": "not-registered", "plugins": [{"name": "this-plugin", "source": "./plugins/this-plugin"}]}'
write "$case_dir/installed_plugins.json" '{"version": 1, "plugins": {}}'
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "this-plugin"}]}'
ARGS=()
out=$(run_state "$case_dir" CLAUDE_PLUGIN_ROOT="$stranger_root")
rc=$?
assert_exit "unregistered manifest name: fails loud, doesn't guess" 1 "$rc"
assert_contains "unregistered manifest name: names the fallback" "$out" "--marketplace"
assert_contains "unregistered manifest name: error names the out-of-cache branch" "$out" "not under the cache"

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

ARGS=(--help)
out=$(run_state "$case_dir" "PATH=$safe_bin_dir")
rc=$?
assert_exit "--help with jq missing: exit 0" 0 "$rc"
assert_contains "--help names the selectors" "$out" "update-candidates-user"
assert_contains "--help lists the exit codes" "$out" "Exit: 0 ran to completion"
ARGS=(--nonsense)
out=$(run_state "$case_dir" "PATH=$safe_bin_dir")
rc=$?
assert_exit "unknown argument: exit 2" 2 "$rc"
assert_contains "unknown argument: names --help" "$out" "(see --help)"

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
# long" (#1336). Guards the argv-length ceiling: catalog/installed/enabled
# JSON payloads must travel via --slurpfile temp files, never as literal
# `jq --argjson` command-line arguments, because a large enough marketplace
# catalog (confirmed against a real 273-plugin catalog) pushes the serialized
# JSON past the platform/shell's argv-length ceiling and jq crashes before
# emitting anything. Uses a synthetic 500-plugin catalog — well past the
# 273-plugin real-world repro — fully installed and enabled, so every array
# in the composed report (catalog, installed, enabled, and all three
# missing_from_* arrays) carries the full payload through the code path the
# guard exists for. Asserts the run completes AND produces the same-shaped,
# semantically-correct output a small catalog would (no silent truncation or
# partial report), not merely that it exits 0.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
big_n=500
write "$case_dir/known_marketplaces.json" '{"bigmarket": {"source": {"source": "github", "repo": "example/bigmarket"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
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
# Case: malformed user_settings.json must fail loud (#1336 fail-loud
# parity). When a prior `jq -c '.enabledPlugins // {}'` read fails on
# malformed source JSON and captures no stdout, --slurpfile would tolerate
# the genuinely EMPTY file as "zero JSON values" (yielding null), turning a
# loud crash into a silent `null`-degraded report. jq_slurp_tmpfile guards
# this by writing a deliberately-invalid token for an empty value, forcing
# jq's own parser to still error at the --slurpfile call site.
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
# Case: static guard: no `--argjson` call site regresses back into
# fleet-state.sh (#1336). The runtime case above proves the CURRENT script
# doesn't crash; this guards against a future edit silently reintroducing
# `--argjson catalog|installed|missing*` (the exact pattern that crashed).
# Every payload now travels as a `--slurpfile` of a validated source file or
# on stdin, and the few fixed-size booleans ride as `--arg` strings, so the
# script body (source lines only, comments excluded) carries no `--argjson`
# at all.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
argjson_code_count=$(grep -v '^[[:space:]]*#' "$SCRIPT" | grep -c -- '--argjson' || true)
assert_eq "static guard: no --argjson call site at all (payloads travel as --slurpfile or stdin)" "0" "$argjson_code_count"

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

stub_probe=$(printf '{"a":"one"}' | PATH="$case_dir/crlf-bin:$PATH" jq -r '.a' | od -An -c | tr -s ' ')
assert_contains "--ids CR regression: stub jq really emits CRLF" "$stub_probe" 'o n e \r \n'

ARGS=(--marketplace market1 --ids installed-user)
out=$(PATH="$case_dir/crlf-bin:$PATH" run_ids "$case_dir")
rc=$?
assert_exit "--ids CR regression: exit 0 under a CRLF-emitting jq" 0 "$rc"
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
pairs=""
while IFS=$'\t' read -r pid pscope; do
  [[ -n "$pid" ]] || continue
  pairs+="${pid}:${pscope} "
done <<<"$out"
assert_eq "--ids current-project: Step 2's IFS=tab read recovers both id/scope pairs" \
  "alpha@market1:project alpha@market1:local " "$pairs"

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
ARGS=(--marketplace market1)
out_report=$(run_ids "$case_dir")
assert_contains "report mode on a broken catalog: error block stays on stdout" \
  "$out_report" '"error"'

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_ids_case "$case_dir"
ARGS=(--marketplace market1 --ids no-such-selector)
out=$(run_state "$case_dir")
rc=$?
assert_exit "--ids unknown selector: exit 2" 2 "$rc"
assert_contains "--ids unknown selector: names the bad selector" "$out" "no-such-selector"

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

seed_catalog_versions_case() {
  local case_dir="$1" pair pname pver entries=""
  shift
  for pair in "$@"; do
    pname="${pair%%=*}"
    pver="${pair#*=}"
    mkdir -p "$case_dir/catalog/market1/$pname/.claude-plugin"
    if [[ -n "$pver" ]]; then
      write "$case_dir/catalog/market1/$pname/.claude-plugin/plugin.json" \
        "$(jq -cn --arg n "$pname" --arg v "$pver" '{name: $n, version: $v}')"
    else
      write "$case_dir/catalog/market1/$pname/.claude-plugin/plugin.json" \
        "$(jq -cn --arg n "$pname" '{name: $n}')"
    fi
    entries+="$pname"$'\n'
  done
  write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
  write "$case_dir/user_settings.json" '{"enabledPlugins":{}}'
}

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_catalog_versions_case "$case_dir" alpha=0.2.0
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha", "source": "./alpha"}]}'
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{"alpha@market1":[{"scope":"user","installPath":"y","version":"0.1.0"}]}}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir")
assert_eq "catalog_versions: reads the version from the plugin's own manifest" \
  "0.2.0" "$(jq -r '.catalog_versions["alpha@market1"]' <<<"$out" 2>/dev/null)"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_catalog_versions_case "$case_dir" alpha=0.2.0
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha", "source": "alpha"}]}'
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{}}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir")
assert_eq "catalog_versions: a source with no ./ prefix resolves identically" \
  "0.2.0" "$(jq -r '.catalog_versions["alpha@market1"]' <<<"$out" 2>/dev/null)"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_catalog_versions_case "$case_dir" alpha=0.2.0
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha", "source": "./alpha"}, {"name": "beta", "source": "./beta"}]}'
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{}}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir")
assert_eq "catalog_versions fail-open: an unmaterialized plugin directory yields null" \
  "null" "$(jq -r '.catalog_versions["beta@market1"]' <<<"$out" 2>/dev/null)"
assert_eq "catalog_versions fail-open: a sibling that DOES resolve is unaffected" \
  "0.2.0" "$(jq -r '.catalog_versions["alpha@market1"]' <<<"$out" 2>/dev/null)"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_catalog_versions_case "$case_dir" alpha=
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha", "source": "./alpha"}]}'
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{}}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir")
assert_eq "catalog_versions fail-open: a manifest with no version key yields null" \
  "null" "$(jq -r '.catalog_versions["alpha@market1"]' <<<"$out" 2>/dev/null)"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_catalog_versions_case "$case_dir" alpha=0.2.0
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha", "source": "./alpha"}, {"name": "remote", "source": {"source": "github", "repo": "example/remote"}}]}'
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{}}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir")
assert_eq "catalog_versions fail-open: an object-valued source yields null, not an error" \
  "null" "$(jq -r '.catalog_versions["remote@market1"]' <<<"$out" 2>/dev/null)"
assert_eq "catalog_versions fail-open: an object-valued source does not abort the block" \
  "0" "$(jq -r 'if .marketplace.error then 1 else 0 end' <<<"$out" 2>/dev/null)"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_catalog_versions_case "$case_dir" alpha=0.2.0
write "$case_dir/catalog/market1/alpha/.claude-plugin/plugin.json" '{not valid json'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha", "source": "./alpha"}]}'
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{"alpha@market1":[{"scope":"user","installPath":"y","version":"0.1.0"}]}}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir")
rc=$?
assert_exit "catalog_versions fail-open: an unparsable manifest still exits 0" 0 "$rc"
assert_eq "catalog_versions fail-open: an unparsable manifest yields null" \
  "null" "$(jq -r '.catalog_versions["alpha@market1"]' <<<"$out" 2>/dev/null)"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_catalog_versions_case "$case_dir" alpha=0.1.0
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha", "source": "./alpha"}]}'
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{"alpha@market1":[{"scope":"user","installPath":"y","version":"0.1.0"}]}}'
ARGS=(--marketplace market1 --ids update-candidates-user)
out=$(run_ids "$case_dir")
rc=$?
assert_exit "update-candidates-user: exit 0" 0 "$rc"
assert_eq "update-candidates-user: withholds an id already at the catalog version" "" "$out"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_catalog_versions_case "$case_dir" alpha=0.2.0
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha", "source": "./alpha"}]}'
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{"alpha@market1":[{"scope":"user","installPath":"y","version":"0.1.0"}]}}'
ARGS=(--marketplace market1 --ids update-candidates-user)
out=$(run_ids "$case_dir")
assert_eq "update-candidates-user: emits an id behind the catalog version" \
  "alpha@market1" "$out"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_catalog_versions_case "$case_dir" alpha=0.2.0
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha", "source": "./alpha"}, {"name": "remote", "source": {"source": "github", "repo": "example/remote"}}]}'
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{"alpha@market1":[{"scope":"user","installPath":"y","version":"0.1.0"}],"provenance@market1":[{"scope":"user","installPath":"p","version":"0.4.0"}],"remote@market1":[{"scope":"user","installPath":"r","version":"1.0.0"}]}}'
write "$case_dir/user_settings.json" '{"enabledPlugins":{"alpha@market1":true,"declined@market1":false,"ghost@market1":true,"provenance@market1":false,"remote@market1":true}}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir")
assert_eq "delisted: only the user-scope install absent from catalog names" \
  '["provenance@market1"]' "$(jq -c '.delisted' <<<"$out" 2>/dev/null)"
assert_eq "delisted: a true key with no install is settings-only" \
  '["ghost@market1"]' "$(jq -c '.delisted_settings_only' <<<"$out" 2>/dev/null)"
assert_eq "delisted: a false key with no install is in neither list" "0" \
  "$(jq -r '[(.delisted + .delisted_settings_only)[]? | select(. == "declined@market1")] | length' <<<"$out" 2>/dev/null)"
assert_eq "delisted: an object-sourced catalog name is not delisted" "0" \
  "$(jq -r '[.delisted[]? | select(. == "remote@market1")] | length' <<<"$out" 2>/dev/null)"
ARGS=(--marketplace market1 --ids update-candidates-user)
out=$(run_ids "$case_dir")
assert_eq "delisted: withheld from update-candidates-user" "0" \
  "$(printf '%s\n' "$out" | grep -c 'provenance@market1' || true)"
assert_contains "delisted: an object-sourced install stays a candidate" "$out" "remote@market1"
assert_contains "delisted: a behind catalog install stays a candidate" "$out" "alpha@market1"
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_catalog_versions_case "$case_dir" alpha=0.1.0
write "$case_dir/catalog/market1.json" '{"plugins":[]}'
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{"alpha@market1":[{"scope":"user","installPath":"y","version":"0.1.0"}]}}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir")
assert_eq "delisted: an empty plugins array yields no delisted set" "[]" \
  "$(jq -c '.delisted' <<<"$out" 2>/dev/null)"
assert_eq "delisted: an empty plugins array yields no settings-only set" "[]" \
  "$(jq -c '.delisted_settings_only' <<<"$out" 2>/dev/null)"
ARGS=(--marketplace market1 --ids update-candidates-user)
out=$(run_ids "$case_dir")
assert_eq "delisted: an empty plugins array does not withhold the install" "alpha@market1" "$out"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_catalog_versions_case "$case_dir" alpha=0.1.0
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha", "source": "./alpha"}]}'
proj_root="$case_dir/proj"
mkdir -p "$proj_root"
native_proj="$(cygpath -w "$proj_root" 2>/dev/null || echo "$proj_root")"
write "$case_dir/installed_plugins.json" "$(
  jq -cn --arg p "$native_proj" '{
    version: 1,
    plugins: {
      "alpha@market1": [{scope: "project", projectPath: $p, installPath: "a", version: "0.1.0"}],
      "provenance@market1": [{scope: "user", installPath: "p", version: "0.4.0"}],
      "stale@market1": [{scope: "project", projectPath: $p, installPath: "s", version: "0.2.0"}]
    }
  }'
)"
ARGS=(--marketplace market1)
out=$(run_state "$case_dir" CLAUDE_PROJECT_DIR="$proj_root")
assert_eq "delisted enable gap: only the cataloged install is missing_from_enabled" \
  '["alpha@market1"]' "$(jq -c '.missing_from_enabled' <<<"$out" 2>/dev/null)"
assert_eq "delisted_project: the in-repo install absent from catalog names, with its scope" \
  '[{"id":"stale@market1","scope":"project"}]' "$(jq -c '.delisted_project' <<<"$out" 2>/dev/null)"
assert_eq "delisted_project: the user-scope delisted install stays in delisted" \
  '["provenance@market1"]' "$(jq -c '.delisted' <<<"$out" 2>/dev/null)"
printf '%s' "$out" >"$case_dir/report.json"
ARGS=(--ids missing-enabled --from "$case_dir/report.json")
assert_eq "delisted enable gap: missing-enabled emits no delisted id" "alpha@market1" "$(run_ids "$case_dir")"
ARGS=(--ids update-candidates-project --from "$case_dir/report.json")
assert_eq "delisted_project: withheld from update-candidates-project" \
  "alpha@market1	project" "$(run_ids "$case_dir")"
jq 'del(.delisted_project)' "$case_dir/report.json" >"$case_dir/report-old.json"
ARGS=(--ids update-candidates-project --from "$case_dir/report-old.json")
assert_eq "delisted_project: a saved report without the field fails open" \
  "alpha@market1	project
stale@market1	project" "$(run_ids "$case_dir")"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_catalog_versions_case "$case_dir" alpha=0.1.0
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha", "source": "./alpha"}]}'
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{"alpha@market1":[{"scope":"user","installPath":"y","version":"9.9.9"}]}}'
ARGS=(--marketplace market1 --ids update-candidates-user)
out=$(run_ids "$case_dir")
assert_eq "downgrade guard: a proven downgrade is withheld from update-candidates-user" \
  "" "$out"
ARGS=(--marketplace market1 --ids downgrade-candidates)
out=$(run_ids "$case_dir")
rc=$?
assert_exit "downgrade guard: downgrade-candidates exit 0" 0 "$rc"
assert_eq "downgrade guard: downgrade-candidates carries id, scope, installed, catalog" \
  "$(printf 'alpha@market1\tuser\t9.9.9\t0.1.0')" "$out"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_catalog_versions_case "$case_dir" alpha=0.2.0
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha", "source": "./alpha"}]}'
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{"alpha@market1":[{"scope":"user","installPath":"y","version":"0.1.0"}]}}'
ARGS=(--marketplace market1 --ids update-candidates-user)
out=$(run_ids "$case_dir")
assert_eq "downgrade guard: a forward move stays a candidate" "alpha@market1" "$out"
ARGS=(--marketplace market1 --ids downgrade-candidates)
out=$(run_ids "$case_dir")
assert_eq "downgrade guard: a forward move is not a downgrade" "" "$out"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_catalog_versions_case "$case_dir" alpha=
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha", "source": "./alpha"}]}'
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{"alpha@market1":[{"scope":"user","installPath":"y","version":"1.2.3"}]}}'
ARGS=(--marketplace market1 --ids update-candidates-user)
out=$(run_ids "$case_dir")
assert_eq "downgrade guard: a null catalog version stays a candidate" "alpha@market1" "$out"
ARGS=(--marketplace market1 --ids downgrade-candidates)
out=$(run_ids "$case_dir")
assert_eq "downgrade guard: a null catalog version is not a proven downgrade" "" "$out"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_catalog_versions_case "$case_dir" alpha=main
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha", "source": "./alpha"}]}'
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{"alpha@market1":[{"scope":"user","installPath":"y","version":"1.2.3"}]}}'
ARGS=(--marketplace market1 --ids update-candidates-user)
out=$(run_ids "$case_dir")
assert_eq "downgrade guard: an unparsable catalog version stays a candidate" \
  "alpha@market1" "$out"
ARGS=(--marketplace market1 --ids downgrade-candidates)
out=$(run_ids "$case_dir")
assert_eq "downgrade guard: an unparsable catalog version is not a proven downgrade" "" "$out"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_catalog_versions_case "$case_dir" alpha=1.2.3
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha", "source": "./alpha"}]}'
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{"alpha@market1":[{"scope":"user","installPath":"y","version":"1.2.3-beta"}]}}'
ARGS=(--marketplace market1 --ids update-candidates-user)
out=$(run_ids "$case_dir")
assert_eq "downgrade guard: a prerelease tie stays a candidate" "alpha@market1" "$out"
ARGS=(--marketplace market1 --ids downgrade-candidates)
out=$(run_ids "$case_dir")
assert_eq "downgrade guard: a prerelease tie is not a proven downgrade" "" "$out"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_catalog_versions_case "$case_dir" alpha=0.1.0
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha", "source": "./alpha"}]}'
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{"alpha@market1":[{"scope":"project","projectPath":"C:\\nope","installPath":"x","version":"0.0.1"},{"scope":"user","installPath":"y","version":"0.1.0"}]}}'
ARGS=(--marketplace market1 --ids update-candidates-user)
out=$(run_ids "$case_dir")
assert_eq "update-candidates-user: a differing project-scope record is not a user-scope candidate" \
  "" "$out"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_catalog_versions_case "$case_dir" alpha=0.1.0
rm -rf "$case_dir/catalog/market1/alpha"
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha", "source": "./alpha"}, {"name": "beta", "source": "./beta"}, {"name": "gamma", "source": {"source": "github", "repo": "e/g"}}, {"name": "delta"}]}'
write "$case_dir/installed_plugins.json" '{
  "version": 1,
  "plugins": {
    "alpha@market1": [{"scope": "user", "installPath": "a", "version": "0.1.0"}],
    "beta@market1":  [{"scope": "user", "installPath": "b", "version": "0.2.0"}],
    "gamma@market1": [{"scope": "user", "installPath": "c", "version": "0.3.0"}],
    "delta@market1": [{"scope": "user", "installPath": "d", "version": "0.4.0"}]
  }
}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir")
assert_eq "fail-open proof: no catalog version resolves for any of the four entries" \
  "0" "$(jq -r '[.catalog_versions | to_entries[] | select(.value != null)] | length' <<<"$out" 2>/dev/null)"
ARGS=(--marketplace market1 --ids installed-user)
out_unfiltered=$(run_ids "$case_dir")
ARGS=(--marketplace market1 --ids update-candidates-user)
out_candidates=$(run_ids "$case_dir")
assert_eq "fail-open proof: with no readable catalog version the sweep is not narrowed at all" \
  "$out_unfiltered" "$out_candidates"
assert_eq "fail-open proof: and that unnarrowed sweep is every user-scope id, not an empty list" \
  "alpha@market1
beta@market1
gamma@market1
delta@market1" "$out_candidates"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_catalog_versions_case "$case_dir" alpha=0.1.0
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha", "source": "./alpha"}, {"name": "beta", "source": "./beta"}]}'
write "$case_dir/installed_plugins.json" '{
  "version": 1,
  "plugins": {
    "alpha@market1": [{"scope": "user", "installPath": "a", "version": "0.1.0"}],
    "beta@market1":  [{"scope": "user", "installPath": "b", "version": "0.2.0"}]
  }
}'
ARGS=(--marketplace market1 --ids update-candidates-user)
out=$(run_ids "$case_dir")
assert_eq "fail-open proof: a partially-readable catalog withholds only the proved id" \
  "beta@market1" "$out"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
live_dir="$case_dir/live-repo"
mkdir -p "$live_dir"
native_live="${live_dir//\//\\}"
write "$case_dir/installed_plugins.json" "$(
  jq -cn --arg p "$native_live" --arg q 'C:\definitely\not\here\at\all' '{
    version: 1,
    plugins: {
      "alpha@market1": [{scope: "project", projectPath: $p, installPath: "x", version: "0.1.0"}],
      "beta@market1":  [{scope: "project", projectPath: $q, installPath: "y", version: "0.1.0"}],
      "gamma@market1": [{scope: "user", installPath: "z", version: "0.1.0"}]
    }
  }'
)"
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}, {"name": "beta"}, {"name": "gamma"}]}'
write "$case_dir/user_settings.json" '{"enabledPlugins":{}}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir")
assert_eq "projectPathPresent: true for a projectPath that exists" \
  "true" "$(jq -r '.installed[] | select(.id == "alpha@market1") | .projectPathPresent' <<<"$out" 2>/dev/null)"
# The load-bearing one: jq's `//` treats FALSE as empty, so a lookup written
# with the alternative operator would silently rewrite this false into null and
# collapse "not present" into "not checked" — the exact distinction the field
# carries.
assert_eq "projectPathPresent: false for an absent projectPath, NOT rewritten to null" \
  "false" "$(jq -r '.installed[] | select(.id == "beta@market1") | .projectPathPresent' <<<"$out" 2>/dev/null)"
assert_eq "projectPathPresent: null for a user-scope record (not applicable)" \
  "null" "$(jq -r '.installed[] | select(.id == "gamma@market1") | .projectPathPresent' <<<"$out" 2>/dev/null)"
assert_eq "projectPathPresent: an absent path never filters the record out of installed[]" \
  "3" "$(jq -r '.installed | length' <<<"$out" 2>/dev/null)"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/installed_plugins.json" "$(
  jq -cn --arg q 'C:\definitely\not\here\at\all' '{
    version: 1,
    plugins: {
      "alpha@market1": [
        {scope: "project", projectPath: $q, installPath: "x", version: "0.1.0"},
        {scope: "user", installPath: "y", version: "0.2.0"}
      ]
    }
  }'
)"
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}]}'
write "$case_dir/user_settings.json" '{"enabledPlugins":{}}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir")
assert_eq "projectPathPresent: carried on divergences[].scopes[] too" \
  "false" "$(jq -r '.divergences[0].scopes[] | select(.scope == "project") | .projectPathPresent' <<<"$out" 2>/dev/null)"
assert_eq "projectPathPresent: an absent path never suppresses the divergence row" \
  "1" "$(jq -r '.divergences | length' <<<"$out" 2>/dev/null)"
assert_eq "projectPathPresent: and the row is still graded on version skew alone" \
  "false" "$(jq -r '.divergences[0].versionsMatch' <<<"$out" 2>/dev/null)"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/installed_plugins.json" '{
  "version": 1,
  "plugins": {
    "wsl@market1":   [{"scope": "project", "projectPath": "/mnt/c/Users/someone", "installPath": "x", "version": "0.1.0"}],
    "wsl-d@market1": [{"scope": "project", "projectPath": "/MNT/D/users/someone/", "installPath": "x", "version": "0.1.0"}],
    "linux@market1": [{"scope": "local", "projectPath": "/home/<user>", "installPath": "x", "version": "0.1.0"}],
    "mac@market1":   [{"scope": "project", "projectPath": "/Users/<user>", "installPath": "x", "version": "0.1.0"}],
    "win@market1":   [{"scope": "project", "projectPath": "C:\\Users\\%USERNAME%", "installPath": "x", "version": "0.1.0"}],
    "envhome@market1": [{"scope": "project", "projectPath": "/srv/odd-home", "installPath": "x", "version": "0.1.0"}],
    "repo@market1":  [{"scope": "project", "projectPath": "/home/<user>/repos/app", "installPath": "x", "version": "0.1.0"}],
    "wslrepo@market1": [{"scope": "project", "projectPath": "/mnt/c/Users/someone/repos/app", "installPath": "x", "version": "0.1.0"}],
    "user@market1":  [{"scope": "user", "installPath": "z", "version": "0.1.0"}]
  }
}'
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "wsl"}, {"name": "wsl-d"}, {"name": "linux"}, {"name": "mac"}, {"name": "win"}, {"name": "envhome"}, {"name": "repo"}, {"name": "wslrepo"}, {"name": "user"}]}'
write "$case_dir/user_settings.json" '{"enabledPlugins":{}}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir" HOME=/srv/odd-home)
home_flag() { jq -r --arg id "$1" '.installed[] | select(.id == $id) | .projectPathIsHome' <<<"$out" 2>/dev/null; }
assert_eq "projectPathIsHome: WSL view of a Windows home (/mnt/c/Users/<name>) is a home" "true" "$(home_flag wsl@market1)"
assert_eq "projectPathIsHome: drive and Users match case-insensitively, trailing slash ignored" "true" "$(home_flag wsl-d@market1)"
assert_eq "projectPathIsHome: /home/<name> is a home (local scope too)" "true" "$(home_flag linux@market1)"
assert_eq "projectPathIsHome: /Users/<name> is a home" "true" "$(home_flag mac@market1)"
# portability-ok: a Windows path in the test title, not a regex
assert_eq "projectPathIsHome: C:\\Users\\<name> is a home" "true" "$(home_flag win@market1)"
assert_eq "projectPathIsHome: the current \$HOME is a home wherever it sits" "true" "$(home_flag envhome@market1)"
assert_eq "projectPathIsHome: a repository under /home/<name>/repos is NOT a home" "false" "$(home_flag repo@market1)"
assert_eq "projectPathIsHome: a repository under /mnt/c/Users/<name>/repos is NOT a home" "false" "$(home_flag wslrepo@market1)"
assert_eq "projectPathIsHome: null for a user-scope record (not applicable)" "null" "$(home_flag user@market1)"
assert_eq "projectPathIsHome: never filters a record out of installed[]" \
  "9" "$(jq -r '.installed | length' <<<"$out" 2>/dev/null)"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/installed_plugins.json" '{
  "version": 1,
  "plugins": {
    "alpha@market1": [
      {"scope": "project", "projectPath": "/mnt/c/Users/someone", "installPath": "x", "version": "0.1.0"},
      {"scope": "user", "installPath": "y", "version": "0.2.0"}
    ]
  }
}'
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}]}'
write "$case_dir/user_settings.json" '{"enabledPlugins":{}}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir")
assert_eq "projectPathIsHome: carried on divergences[].scopes[] too" \
  "true" "$(jq -r '.divergences[0].scopes[] | select(.scope == "project") | .projectPathIsHome' <<<"$out" 2>/dev/null)"
assert_eq "projectPathIsHome: a home path never removes the divergence row" \
  "1" "$(jq -r '.divergences | length' <<<"$out" 2>/dev/null)"

# ============================================================================
# linkedWorktree / label — a lagging record in a linked worktree is labeled,
# stays counted, and a main checkout or a submodule is never mislabeled (#6713).
# ============================================================================

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
main_dir="$case_dir/main-repo"
wt_dir="$case_dir/linked-wt"
sub_dir="$case_dir/submodule"
bare_wt_dir="$case_dir/bare-repo/main"
sep_dir="$case_dir/sep-checkout"
mkdir -p "$main_dir/.git/worktrees/linked-wt" "$wt_dir" "$sub_dir" \
  "$case_dir/bare-repo/.bare/worktrees/main" "$bare_wt_dir" \
  "$case_dir/worktrees/sep.git" "$sep_dir"
printf '../..\n' >"$main_dir/.git/worktrees/linked-wt/commondir"
printf '../..\n' >"$case_dir/bare-repo/.bare/worktrees/main/commondir"
printf 'gitdir: %s/main-repo/.git/worktrees/linked-wt\n' "$case_dir" >"$wt_dir/.git"
printf 'gitdir: ../.git/modules/submodule\n' >"$sub_dir/.git"
printf 'gitdir: %s/bare-repo/.bare/worktrees/main\n' "$case_dir" >"$bare_wt_dir/.git"
printf 'gitdir: %s/worktrees/sep.git\n' "$case_dir" >"$sep_dir/.git"
write "$case_dir/installed_plugins.json" "$(
  jq -cn --arg m "$main_dir" --arg w "$wt_dir" --arg s "$sub_dir" --arg bw "$bare_wt_dir" --arg sd "$sep_dir" '{
    version: 1,
    plugins: {
      "alpha@market1": [
        {scope: "project", projectPath: $w, installPath: "a", version: "0.1.0"},
        {scope: "user", installPath: "u", version: "0.2.0"}
      ],
      "beta@market1": [
        {scope: "project", projectPath: $m, installPath: "b", version: "0.1.0"},
        {scope: "user", installPath: "u2", version: "0.2.0"}
      ],
      "gamma@market1": [
        {scope: "project", projectPath: $s, installPath: "c", version: "0.1.0"},
        {scope: "user", installPath: "u3", version: "0.2.0"}
      ],
      "delta@market1": [
        {scope: "project", projectPath: $w, installPath: "d", version: "0.2.0"},
        {scope: "user", installPath: "u4", version: "0.2.0"}
      ],
      "epsilon@market1": [
        {scope: "project", projectPath: $bw, installPath: "e", version: "0.2.0"},
        {scope: "user", installPath: "u5", version: "0.2.0"}
      ],
      "zeta@market1": [
        {scope: "project", projectPath: $sd, installPath: "f", version: "0.2.0"},
        {scope: "user", installPath: "u6", version: "0.2.0"}
      ]
    }
  }'
)"
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}, {"name": "beta"}, {"name": "gamma"}, {"name": "delta"}, {"name": "epsilon"}, {"name": "zeta"}]}'
write "$case_dir/user_settings.json" '{"enabledPlugins":{}}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir")
assert_eq "linkedWorktree: true for a worktree whose .git file points into worktrees/" \
  "true" "$(jq -r '.installed[] | select(.id == "alpha@market1" and .scope == "project") | .linkedWorktree' <<<"$out" 2>/dev/null)"
assert_eq "linkedWorktree: false for a main checkout (.git is a directory)" \
  "false" "$(jq -r '.installed[] | select(.id == "beta@market1" and .scope == "project") | .linkedWorktree' <<<"$out" 2>/dev/null)"
assert_eq "linkedWorktree: false for a submodule (.git file points into modules/)" \
  "false" "$(jq -r '.installed[] | select(.id == "gamma@market1" and .scope == "project") | .linkedWorktree' <<<"$out" 2>/dev/null)"
assert_eq "linkedWorktree: true for a bare layout (gitdir points into .bare/worktrees/)" \
  "true" "$(jq -r '.installed[] | select(.id == "epsilon@market1" and .scope == "project") | .linkedWorktree' <<<"$out" 2>/dev/null)"
assert_eq "linkedWorktree: false for a separate-git-dir main checkout under a worktrees/ parent" \
  "false" "$(jq -r '.installed[] | select(.id == "zeta@market1" and .scope == "project") | .linkedWorktree' <<<"$out" 2>/dev/null)"
assert_eq "linkedWorktree: null for a user-scope record" \
  "null" "$(jq -r '.installed[] | select(.id == "alpha@market1" and .scope == "user") | .linkedWorktree' <<<"$out" 2>/dev/null)"
assert_eq "label: a lagging linked-worktree record is labeled" \
  "update ineffective, uninstall clears it" \
  "$(jq -r '.installed[] | select(.id == "alpha@market1" and .scope == "project") | .label' <<<"$out" 2>/dev/null)"
assert_eq "label: the same label rides divergences[].scopes[]" \
  "update ineffective, uninstall clears it" \
  "$(jq -r '.divergences[] | select(.id == "alpha@market1") | .scopes[] | select(.scope == "project") | .label' <<<"$out" 2>/dev/null)"
assert_eq "label: a lagging record in a main checkout is not labeled" \
  "null" "$(jq -r '.installed[] | select(.id == "beta@market1" and .scope == "project") | .label' <<<"$out" 2>/dev/null)"
assert_eq "label: a lagging record in a submodule is not labeled" \
  "null" "$(jq -r '.installed[] | select(.id == "gamma@market1" and .scope == "project") | .label' <<<"$out" 2>/dev/null)"
assert_eq "label: a linked-worktree record already at the highest version is not labeled" \
  "null" "$(jq -r '.installed[] | select(.id == "delta@market1" and .scope == "project") | .label' <<<"$out" 2>/dev/null)"
assert_eq "label: the labeled record stays in the actionable divergence count" \
  "alpha@market1 beta@market1 gamma@market1" \
  "$(jq -r '[.divergences[] | select(.versionsMatch == false) | .id] | sort | join(" ")' <<<"$out" 2>/dev/null)"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/installed_plugins.json" '{
  "version": 1,
  "plugins": {
    "orphan@market1": [{"scope": "project", "projectPath": "C:\\repo-one", "installPath": "x", "version": "0.1.0"}],
    "localorphan@market1": [{"scope": "local", "projectPath": "C:\\elsewhere", "installPath": "x", "version": "0.1.0"}],
    "paired@market1": [
      {"scope": "project", "projectPath": "C:\\repo-one", "installPath": "x", "version": "0.1.0"},
      {"scope": "user", "installPath": "y", "version": "0.1.0"}
    ],
    "useronly@market1": [{"scope": "user", "installPath": "y", "version": "0.1.0"}]
  }
}'
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "orphan"}, {"name": "localorphan"}, {"name": "paired"}, {"name": "useronly"}]}'
write "$case_dir/user_settings.json" '{"enabledPlugins":{}}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir")
# `join(",")` rather than `.[]`: the assertion-side `jq` here is the REAL jq,
# not fleet-state.sh's CR-stripping wrapper, and on Windows it terminates every
# line with CRLF. `$(…)` strips only the FINAL terminator as a unit, so a
# multi-line extraction leaves a trailing CR on every line but the last and the
# comparison fails against a byte-identical-looking literal. Collapsing to one
# line keeps the capture in the safe single-line case — the same reason no
# other case in this suite extracts multiple lines through a test-side jq.
assert_eq "user_scope_orphans: names project-only and local-only ids" \
  "localorphan@market1,orphan@market1" "$(jq -r '.user_scope_orphans | join(",")' <<<"$out" 2>/dev/null)"
assert_eq "user_scope_orphans: excludes an id that also holds a user-scope record" \
  "0" "$(jq -r '[.user_scope_orphans[] | select(. == "paired@market1")] | length' <<<"$out" 2>/dev/null)"
assert_eq "user_scope_orphans: excludes a user-only id" \
  "0" "$(jq -r '[.user_scope_orphans[] | select(. == "useronly@market1")] | length' <<<"$out" 2>/dev/null)"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/installed_plugins.json" '{
  "version": 1,
  "plugins": {
    "declined@market1": [{"scope": "project", "projectPath": "C:\\repo-one", "installPath": "x", "version": "0.1.0"}],
    "wanted@market1": [{"scope": "project", "projectPath": "C:\\repo-one", "installPath": "x", "version": "0.1.0"}]
  }
}'
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "declined"}, {"name": "wanted"}]}'
write "$case_dir/user_settings.json" '{"enabledPlugins":{"declined@market1": false}}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir")
assert_eq "user_scope_orphans: an explicitly-disabled project-only id is NOT an orphan" \
  "wanted@market1" "$(jq -r '.user_scope_orphans | join(",")' <<<"$out" 2>/dev/null)"
assert_eq "user_scope_orphans: the sibling id in the same fixture IS still reported" \
  "1" "$(jq -r '.user_scope_orphans | length' <<<"$out" 2>/dev/null)"
assert_eq "user_scope_orphans: the orphans are structurally absent from divergences[]" \
  "0" "$(jq -r '[.divergences[] | select(.id == "orphan@market1" or .id == "localorphan@market1")] | length' <<<"$out" 2>/dev/null)"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/installed_plugins.json" '{
  "version": 1,
  "plugins": {
    "orphan@market1": [{"scope": "project", "projectPath": "C:\\repo-one", "installPath": "x", "version": "0.1.0"}],
    "useronly@market1": [{"scope": "user", "installPath": "y", "version": "0.1.0"}]
  }
}'
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "orphan"}, {"name": "useronly"}]}'
write "$case_dir/user_settings.json" '{"enabledPlugins":{}}'
ARGS=(--marketplace market1 --ids user-scope-orphans)
out=$(run_ids "$case_dir")
rc=$?
assert_exit "--ids user-scope-orphans: exit 0" 0 "$rc"
assert_eq "--ids user-scope-orphans: emits the fully-qualified id, one per line" \
  "orphan@market1" "$out"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
nonrepo_dir="$case_dir/not-a-git-repo"
mkdir -p "$nonrepo_dir"
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{"alpha@market1":[{"scope":"user","installPath":"y","version":"0.1.0"}]}}'
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}]}'
write "$case_dir/user_settings.json" '{"enabledPlugins":{}}'
out=$(cd "$nonrepo_dir" && run_state_no_project_dir "$case_dir")
assert_eq "project_root: null when no project context resolves at all" \
  "null" "$(jq -r '.project_root' <<<"$out" 2>/dev/null)"
assert_eq "project_root: null even though every record's currentProject is also null" \
  "null" "$(jq -r '.installed[0].currentProject' <<<"$out" 2>/dev/null)"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
proj_root="$case_dir/sample-repo"
mkdir -p "$proj_root"
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{"alpha@market1":[{"scope":"user","installPath":"y","version":"0.1.0"}]}}'
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}]}'
write "$case_dir/user_settings.json" '{"enabledPlugins":{}}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir" CLAUDE_PROJECT_DIR="$proj_root")
assert_contains "project_root: names the resolved root when a project context exists" \
  "$(jq -r '.project_root' <<<"$out" 2>/dev/null)" "sample-repo"
assert_eq "project_root: a resolved root with no in-repo installs still has no currentProject:true" \
  "0" "$(jq -r '[.installed[] | select(.currentProject == true)] | length' <<<"$out" 2>/dev/null)"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
mkdir -p "$case_dir/checkout/.claude-plugin"
mkdir -p "$case_dir/checkout/alpha/.claude-plugin"
mkdir -p "$case_dir/outside/.claude-plugin"
write "$case_dir/checkout/.claude-plugin/marketplace.json" '{"plugins": [{"name": "alpha", "source": "./alpha"}, {"name": "escape", "source": "../outside"}]}'
write "$case_dir/checkout/alpha/.claude-plugin/plugin.json" '{"name": "alpha", "version": "1.2.3"}'
write "$case_dir/outside/.claude-plugin/plugin.json" '{"name": "escape", "version": "0.0.1"}'
write "$case_dir/known_marketplaces.json" "$(
  jq -cn --arg loc "$case_dir/checkout" '{market1: {source: {source: "github", repo: "example/market1"}, installLocation: $loc, lastUpdated: "2026-01-01T00:00:00Z"}}'
)"
write "$case_dir/user_settings.json" '{"enabledPlugins":{}}'
write "$case_dir/installed_plugins.json" '{
  "version": 1,
  "plugins": {
    "alpha@market1":  [{"scope": "user", "installPath": "a", "version": "1.2.3"}],
    "escape@market1": [{"scope": "user", "installPath": "b", "version": "0.0.1"}]
  }
}'
out=$(env FLEET_STATE_INSTALLED_JSON="$case_dir/installed_plugins.json" \
  FLEET_STATE_MARKETPLACES_JSON="$case_dir/known_marketplaces.json" \
  FLEET_STATE_USER_SETTINGS="$case_dir/user_settings.json" \
  bash "$SCRIPT" --marketplace market1 2>&1)
assert_eq "production manifest_base: resolves a version from installLocation, no catalog-dir override" \
  "1.2.3" "$(jq -r '.catalog_versions["alpha@market1"]' <<<"$out" 2>/dev/null)"
assert_eq "production manifest_base: a ../-traversing source refuses to resolve (yields null)" \
  "null" "$(jq -r '.catalog_versions["escape@market1"]' <<<"$out" 2>/dev/null)"
out_ids=$(env FLEET_STATE_INSTALLED_JSON="$case_dir/installed_plugins.json" \
  FLEET_STATE_MARKETPLACES_JSON="$case_dir/known_marketplaces.json" \
  FLEET_STATE_USER_SETTINGS="$case_dir/user_settings.json" \
  bash "$SCRIPT" --marketplace market1 --ids update-candidates-user 2>/dev/null)
assert_eq "production manifest_base: the traversing id stays an update candidate, the resolved one is withheld" \
  "escape@market1" "$out_ids"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
mkdir -p "$case_dir/checkout/.claude-plugin"
mkdir -p "$case_dir/outside/.claude-plugin"
write "$case_dir/checkout/.claude-plugin/marketplace.json" '{"plugins": [{"name": "escape", "source": "..\\outside"}]}'
write "$case_dir/outside/.claude-plugin/plugin.json" '{"name": "escape", "version": "0.0.1"}'
write "$case_dir/known_marketplaces.json" "$(
  jq -cn --arg loc "$case_dir/checkout" '{market1: {source: {source: "github", repo: "example/market1"}, installLocation: $loc, lastUpdated: "2026-01-01T00:00:00Z"}}'
)"
write "$case_dir/user_settings.json" '{"enabledPlugins":{}}'
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{"escape@market1":[{"scope":"user","installPath":"b","version":"0.0.1"}]}}'
out=$(env FLEET_STATE_INSTALLED_JSON="$case_dir/installed_plugins.json" \
  FLEET_STATE_MARKETPLACES_JSON="$case_dir/known_marketplaces.json" \
  FLEET_STATE_USER_SETTINGS="$case_dir/user_settings.json" \
  bash "$SCRIPT" --marketplace market1 2>&1)
assert_eq "production manifest_base: a backslash-spelled traversal is refused too" \
  "null" "$(jq -r '.catalog_versions["escape@market1"]' <<<"$out" 2>/dev/null)"

# A SYMLINK inside the checkout pointing outside it reaches a foreign manifest
# through an entirely ordinary `./name` source — no lexical check on the source
# can see it. If that foreign manifest's version were read, it could positively
# but falsely "prove" an installed id current and WITHHOLD its update, which is
# this pre-filter's only unsafe direction. The physical containment check is
# what closes it; this case is the proof.
# Skipped where the platform cannot create a symlink (Windows without developer
# mode / core.symlinks off) — a skip is honest there, since the vector needs a
# real symlink to exist in the first place.
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
mkdir -p "$case_dir/checkout/.claude-plugin"
mkdir -p "$case_dir/outside/.claude-plugin"
write "$case_dir/outside/.claude-plugin/plugin.json" '{"name": "evil", "version": "9.9.9"}'
write "$case_dir/checkout/.claude-plugin/marketplace.json" '{"plugins": [{"name": "evil", "source": "./linkdir"}]}'
write "$case_dir/known_marketplaces.json" "$(
  jq -cn --arg loc "$case_dir/checkout" '{market1: {source: {source: "github", repo: "example/market1"}, installLocation: $loc, lastUpdated: "2026-01-01T00:00:00Z"}}'
)"
write "$case_dir/user_settings.json" '{"enabledPlugins":{}}'
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{"evil@market1":[{"scope":"user","installPath":"a","version":"9.9.9"}]}}'
# `MSYS=winsymlinks:nativestrict` is what makes Git Bash emit a REAL symlink
# instead of silently deep-COPYING the target — the copy would put the manifest
# genuinely inside the checkout and the case would then assert the opposite of
# what it means to. The variable is inert on POSIX, where ln -s already links.
# `[[ -L ]]` is the gate, not `ln`'s exit status: the copying form also succeeds.
MSYS=winsymlinks:nativestrict ln -s "$case_dir/outside" "$case_dir/checkout/linkdir" 2>/dev/null
if [[ -L "$case_dir/checkout/linkdir" ]] &&
  [[ -f "$case_dir/checkout/linkdir/.claude-plugin/plugin.json" ]]; then
  out=$(env FLEET_STATE_INSTALLED_JSON="$case_dir/installed_plugins.json" \
    FLEET_STATE_MARKETPLACES_JSON="$case_dir/known_marketplaces.json" \
    FLEET_STATE_USER_SETTINGS="$case_dir/user_settings.json" \
    bash "$SCRIPT" --marketplace market1 2>&1)
  assert_eq "symlink escape: a manifest reached through a symlink out of the checkout yields null" \
    "null" "$(jq -r '.catalog_versions["evil@market1"]' <<<"$out" 2>/dev/null)"
  out_ids=$(env FLEET_STATE_INSTALLED_JSON="$case_dir/installed_plugins.json" \
    FLEET_STATE_MARKETPLACES_JSON="$case_dir/known_marketplaces.json" \
    FLEET_STATE_USER_SETTINGS="$case_dir/user_settings.json" \
    bash "$SCRIPT" --marketplace market1 --ids update-candidates-user 2>/dev/null)
  assert_eq "symlink escape: the id is NOT withheld — it stays an update candidate" \
    "evil@market1" "$out_ids"
else
  printf 'SKIP: symlink escape (this platform did not produce a real symlink)\n'
fi
rm -rf "$case_dir/checkout/linkdir"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
mkdir -p "$case_dir/checkout/.claude-plugin"
mkdir -p "$case_dir/checkout/realdir/.claude-plugin"
write "$case_dir/checkout/realdir/.claude-plugin/plugin.json" '{"name": "good", "version": "9.9.9"}'
write "$case_dir/checkout/.claude-plugin/marketplace.json" '{"plugins": [{"name": "good", "source": "./realdir"}]}'
write "$case_dir/known_marketplaces.json" "$(
  jq -cn --arg loc "$case_dir/checkout" '{market1: {source: {source: "github", repo: "example/market1"}, installLocation: $loc, lastUpdated: "2026-01-01T00:00:00Z"}}'
)"
write "$case_dir/user_settings.json" '{"enabledPlugins":{}}'
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{"good@market1":[{"scope":"user","installPath":"a","version":"9.9.9"}]}}'
out=$(env FLEET_STATE_INSTALLED_JSON="$case_dir/installed_plugins.json" \
  FLEET_STATE_MARKETPLACES_JSON="$case_dir/known_marketplaces.json" \
  FLEET_STATE_USER_SETTINGS="$case_dir/user_settings.json" \
  bash "$SCRIPT" --marketplace market1 2>&1)
assert_eq "containment control: an in-checkout real directory still resolves its version" \
  "9.9.9" "$(jq -r '.catalog_versions["good@market1"]' <<<"$out" 2>/dev/null)"

# ============================================================================
# --marketplaces — the name enumeration `sync`'s `all` mode loops. Without it
# the only way to get the list is a hand-written `jq -r 'keys[]' | while read`
# over known_marketplaces.json, which carries the identical trailing-CR hazard
# that --ids exists to prevent.
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

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/known_marketplaces.json" '{}'
ARGS=(--marketplaces)
out=$(run_state "$case_dir")
rc=$?
assert_exit "--marketplaces: empty object exits 0" 0 "$rc"
assert_eq "--marketplaces: empty object emits nothing" "" "$out"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_ids_case "$case_dir"
ARGS=(--marketplaces --all)
out=$(run_state "$case_dir")
rc=$?
assert_exit "--marketplaces with --all: exit 2" 2 "$rc"
assert_contains "--marketplaces with --all: refuses the combination" "$out" "cannot be combined"
ARGS=(--all --marketplaces)
out=$(run_state "$case_dir")
rc=$?
assert_exit "--marketplaces after --all: same rejection, order-independent" 2 "$rc"
ARGS=(--marketplaces --ids installed-user)
out=$(run_state "$case_dir")
rc=$?
assert_exit "--marketplaces with --ids: exit 2" 2 "$rc"

# CR regression, same stub mechanism as the --ids case above: the documented
# consumer is a `while read` loop feeding --marketplace, so a surviving CR
# would corrupt every name but the last into an unresolvable marketplace.
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/known_marketplaces.json" '{
  "market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"},
  "market2": {"source": {"source": "github", "repo": "example/market2"}, "installLocation": "z2", "lastUpdated": "2026-01-01T00:00:00Z"}
}'
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
stub_probe=$(printf '{"a":"one"}' | PATH="$case_dir/crlf-bin:$PATH" jq -r '.a' | od -An -c | tr -s ' ')
assert_contains "--marketplaces CR regression: stub jq really emits CRLF" "$stub_probe" 'o n e \r \n'
ARGS=(--marketplaces)
out=$(PATH="$case_dir/crlf-bin:$PATH" run_state "$case_dir")
rc=$?
assert_exit "--marketplaces CR regression: exit 0 under a CRLF-emitting jq" 0 "$rc"
case "$out" in
*$'\r'*) fail "--marketplaces CR regression: no CR survives into the emitted names" \
  "found a CR in: $(printf '%s' "$out" | od -An -c | tr -s ' ')" ;;
*) pass "--marketplaces CR regression: no CR survives into the emitted names" ;;
esac
assert_eq "--marketplaces CR regression: names are byte-exact under a CRLF-emitting jq" \
  "market1
market2" "$out"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
proj_root="$case_dir/sample-repo"
mkdir -p "$proj_root"
write "$case_dir/known_marketplaces.json" '{
  "market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"},
  "market2": {"source": {"source": "github", "repo": "example/market2"}, "installLocation": "z2", "lastUpdated": "2026-01-01T00:00:00Z"}
}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}]}'
write "$case_dir/catalog/market2.json" '{"plugins": [{"name": "beta"}]}'
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{}}'
write "$case_dir/user_settings.json" '{"enabledPlugins":{}}'
ARGS=(--all)
out=$(run_state "$case_dir" CLAUDE_PROJECT_DIR="$proj_root")
assert_eq "--all: every marketplace block carries project_root" \
  "2" "$(jq -r '[.marketplaces[] | select(.project_root != null)] | length' <<<"$out" 2>/dev/null)"
assert_eq "--all: and every block reports the SAME resolved root" \
  "1" "$(jq -r '[.marketplaces[].project_root] | unique | length' <<<"$out" 2>/dev/null)"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_ids_case "$case_dir"
ARGS=(--marketplace market1 --ids no-such-selector)
out=$(run_state "$case_dir")
assert_contains "--ids help text names installed-user" "$out" "installed-user"
assert_contains "--ids help text names update-candidates-user" "$out" "update-candidates-user"
assert_contains "--ids help text names update-candidates-project" "$out" "update-candidates-project"
assert_contains "--ids help text names downgrade-candidates" "$out" "downgrade-candidates"
assert_contains "--ids help text names current-project" "$out" "current-project"
assert_contains "--ids help text names missing-user-install" "$out" "missing-user-install"
assert_contains "--ids help text names missing-enabled" "$out" "missing-enabled"
assert_contains "--ids help text names user-scope-orphans" "$out" "user-scope-orphans"

# ============================================================================
# Process budget: one report costs a FIXED number of process creations, never
# one per catalog entry. Each creation is a fork() emulation plus a
# CreateProcess on Windows Git Bash (roughly 120 ms on a quiet host, seconds
# on a contended one), and the pre-rewrite script paid one jq, one realpath
# and their subshells for every catalog entry: 736 creations and 17 minutes
# for a 74-plugin catalog on the authoring host. Counted the way the baseline
# was: `bash -x` with PS4 carrying $BASHPID, so every subshell shows up as a
# distinct pid, plus every external exec. Two fixtures that differ only in
# catalog size must cost the same, and that cost must sit under the budget.
# The equality half needs a batching `realpath` (hook::_physical_prime); a
# host without one resolves per path and is reported, not failed.
# ============================================================================
count_creations() {
  local trace="$1" forks execs
  forks=$(grep -oE '^\++[0-9]+\+' "$trace" | sort -u | wc -l | tr -d ' ')
  execs=$(grep -cE '^\++[0-9]+\+ (command )?(jq|tr|realpath|readlink|mktemp|git|head|sed|cygpath|rm|cat|grep|awk|sort|uniq|cut|wc|date|dirname|basename|ls|find) ' "$trace" || true)
  echo $((forks - 1 + execs))
}

run_traced() {
  local case_dir="$1" trace="$2"
  mkdir -p "$case_dir/proj"
  # PS4 travels through a BASH_ENV startup file, never the environment: bash
  # 4.4 and later rebind an euid-0 shell's PS4 to '+ ' at startup, before any
  # startup file runs (CVE-2016-7543), so an exported PS4 never reaches a root
  # shell and the probe counts nothing. A BASH_ENV assignment lands after that
  # rebind, and its own unstamped `+ PS4=` trace line matches no pid pattern.
  # shellcheck disable=SC2016  # PS4 must reach bash unexpanded: bash expands it per traced line
  write "$case_dir/ps4.env" 'PS4='\''+${BASHPID}+ '\'''
  env \
    FLEET_STATE_INSTALLED_JSON="$case_dir/installed_plugins.json" \
    FLEET_STATE_MARKETPLACES_JSON="$case_dir/known_marketplaces.json" \
    FLEET_STATE_USER_SETTINGS="$case_dir/user_settings.json" \
    FLEET_STATE_CATALOG_DIR="$case_dir/catalog" \
    CLAUDE_PROJECT_DIR="$case_dir/proj" \
    BASH_ENV="$case_dir/ps4.env" \
    bash -x "$SCRIPT" "${ARGS[@]}" 2>"$trace"
}

seed_budget_case() {
  local case_dir="$1" n="$2" i pairs=() entries=""
  for ((i = 1; i <= n; i++)); do
    pairs+=("plugin$i=0.$i.0")
    entries+="{\"name\": \"plugin$i\", \"source\": \"./plugin$i\"},"
  done
  seed_catalog_versions_case "$case_dir" "${pairs[@]}"
  write "$case_dir/catalog/market1.json" "{\"plugins\": [${entries%,}]}"
  write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{"plugin1@market1":[{"scope":"user","installPath":"y","version":"0.0.1"}]}}'
}

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_budget_case "$case_dir" 2
ARGS=(--marketplace market1)
out=$(run_traced "$case_dir" "$case_dir/trace-small.log")
small=$(count_creations "$case_dir/trace-small.log")
assert_eq "process budget: the small-catalog run still produces the report" \
  "2" "$(jq -r '[.catalog_versions | to_entries[] | select(.value != null)] | length' <<<"$out" 2>/dev/null)"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_budget_case "$case_dir" 12
ARGS=(--marketplace market1)
out=$(run_traced "$case_dir" "$case_dir/trace-large.log")
large=$(count_creations "$case_dir/trace-large.log")
assert_eq "process budget: the large-catalog run resolves every manifest" \
  "12" "$(jq -r '[.catalog_versions | to_entries[] | select(.value != null)] | length' <<<"$out" 2>/dev/null)"
if [[ "$large" -ge 1 ]]; then
  pass "process budget: the trace probe actually counted something (measured $large)"
else
  fail "process budget: the trace probe actually counted something" \
    "measured $large: the pid-stamped PS4 did not reach the traced shell, so the ceilings below are vacuous (trace: $case_dir/trace-large.log)"
fi
if [[ "$large" -ge 1 && "$large" -le 12 ]]; then
  pass "process budget: a --marketplace report costs at most 12 process creations (measured $large)"
else
  fail "process budget: a --marketplace report costs at most 12 process creations" "measured $large (trace: $case_dir/trace-large.log)"
fi
if command -v realpath >/dev/null 2>&1; then
  assert_eq "process budget: the count does not grow with the catalog (2 entries vs 12)" "$small" "$large"
else
  pass "process budget: catalog-size invariance not asserted (no realpath on this host; hook-utils resolves per path)"
fi

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_budget_case "$case_dir" 12
ARGS=(--marketplace market1 --ids update-candidates-user)
out=$(run_traced "$case_dir" "$case_dir/trace-ids.log")
ids_count=$(count_creations "$case_dir/trace-ids.log")
assert_eq "process budget: --ids projects from the same single pass (plugin1 is behind 0.1.0)" \
  "plugin1@market1" "$out"
if [[ "$ids_count" -ge 1 && "$ids_count" -le 12 ]]; then
  pass "process budget: an --ids projection costs at most 12 process creations (measured $ids_count)"
else
  fail "process budget: an --ids projection costs at most 12 process creations" "measured $ids_count"
fi

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/installed_plugins.json" '{
  "version": 1,
  "plugins": {
    "alpha@market1": [
      {"scope": "user", "installPath": "y", "version": "0.1.0"},
      {"scope": "project", "projectPath": "<PROJECT_ROOT>/sample-repo", "installPath": "x", "version": "0.1.0"}
    ],
    "beta@market1": [{"scope": "user", "installPath": "z", "version": "0.2.0"}],
    "delta@market1": [{"scope": "local", "projectPath": "<PROJECT_ROOT>/sample-repo", "installPath": "w", "version": "0.3.0"}]
  }
}'
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha"}, {"name": "beta"}, {"name": "gamma"}, {"name": "delta"}]}'
mkdir -p "$case_dir/sample-repo"
ARGS=(--marketplace market1)
report=$(run_state "$case_dir" "CLAUDE_PROJECT_DIR=$case_dir/sample-repo")
rc=$?
assert_exit "--from: the saved report itself is produced" 0 "$rc"
write "$case_dir/report.json" "$report"

for sel in installed-user update-candidates-user update-candidates-project \
  downgrade-candidates current-project \
  missing-user-install missing-enabled user-scope-orphans; do
  ARGS=(--marketplace market1 --ids "$sel")
  live=$(run_state "$case_dir" "CLAUDE_PROJECT_DIR=$case_dir/sample-repo")
  ARGS=(--ids "$sel" --from "$case_dir/report.json")
  projected=$(run_state "$case_dir" "CLAUDE_PROJECT_DIR=$case_dir/sample-repo")
  assert_eq "--from: '$sel' projection equals the live projection" "$live" "$projected"
done

ARGS=(--ids missing-user-install --from "$case_dir/report.json")
assert_eq "--from: the compared selectors are non-empty (missing-user-install)" \
  "$(printf 'delta@market1\ngamma@market1')" "$(run_state "$case_dir")"

write "$case_dir/current-project-report.json" '{
  "marketplace": {"name": "market1", "autoUpdate": false, "lastUpdated": "2026-01-01T00:00:00Z"},
  "project_root": "/tmp/sample-repo",
  "catalog": ["alpha"],
  "catalog_versions": {"alpha@market1": "0.1.0"},
  "installed": [
    {"id": "alpha@market1", "scope": "project", "version": "0.1.0", "currentProject": true},
    {"id": "alpha@market1", "scope": "local", "version": "0.1.0", "currentProject": true},
    {"id": "beta@market1", "scope": "user", "version": "0.2.0", "currentProject": null}
  ],
  "enabled": {},
  "missing_from_install": [],
  "missing_from_user_install": [],
  "missing_from_enabled": [],
  "user_scope_orphans": [],
  "divergences": []
}'
ARGS=(--ids current-project --from "$case_dir/current-project-report.json")
assert_eq "--from: current-project keeps its second TAB field, one line per scope record" \
  "$(printf 'alpha@market1\tproject\nalpha@market1\tlocal')" "$(run_state "$case_dir")"

ARGS=(--ids update-candidates-project --from "$case_dir/current-project-report.json")
assert_eq "--from: update-candidates-project keeps every in-repo record the catalog does not move backward" \
  "$(printf 'alpha@market1\tproject\nalpha@market1\tlocal')" "$(run_state "$case_dir")"
ARGS=(--ids downgrade-candidates --from "$case_dir/current-project-report.json")
assert_eq "--from: an equal catalog version yields no downgrade candidate" \
  "" "$(run_state "$case_dir")"

write "$case_dir/project-downgrade-report.json" '{
  "marketplace": {"name": "market1", "autoUpdate": false, "lastUpdated": "2026-01-01T00:00:00Z"},
  "project_root": "/p/sample-repo",
  "catalog": ["alpha", "beta"],
  "catalog_versions": {"alpha@market1": "0.0.9", "beta@market1": null},
  "installed": [
    {"id": "alpha@market1", "scope": "project", "version": "0.1.0", "currentProject": true},
    {"id": "beta@market1", "scope": "local", "version": "0.2.0", "currentProject": true}
  ],
  "enabled": {},
  "missing_from_install": [],
  "missing_from_user_install": [],
  "missing_from_enabled": [],
  "user_scope_orphans": [],
  "divergences": []
}'
ARGS=(--ids update-candidates-project --from "$case_dir/project-downgrade-report.json")
assert_eq "--from: update-candidates-project withholds the in-repo record the catalog moves backward" \
  "$(printf 'beta@market1\tlocal')" "$(run_state "$case_dir")"
ARGS=(--ids downgrade-candidates --from "$case_dir/project-downgrade-report.json")
assert_eq "--from: downgrade-candidates names that in-repo record with its scope and both versions" \
  "$(printf 'alpha@market1\tproject\t0.1.0\t0.0.9')" "$(run_state "$case_dir")"
ARGS=(--ids current-project --from "$case_dir/project-downgrade-report.json")
assert_eq "--from: current-project is unguarded and still names the whole set" \
  "$(printf 'alpha@market1\tproject\nbeta@market1\tlocal')" "$(run_state "$case_dir")"

# ============================================================================
# Case: every --from rejection is exit 2 with EMPTY stdout. The documented
# consumer is `while read … done < <(… --ids …)`, which cannot see the exit
# status, so anything left on stdout would be handed to `claude plugin update`
# as an id. Captured WITHOUT 2>&1 for exactly that reason.
# ============================================================================
run_from_stdout_only() {
  local case_dir="$1"
  shift
  env \
    FLEET_STATE_INSTALLED_JSON="$case_dir/installed_plugins.json" \
    FLEET_STATE_MARKETPLACES_JSON="$case_dir/known_marketplaces.json" \
    FLEET_STATE_USER_SETTINGS="$case_dir/user_settings.json" \
    FLEET_STATE_CATALOG_DIR="$case_dir/catalog" \
    bash "$SCRIPT" "$@"
}

CASE_NUM=$((CASE_NUM + 1))
prev_case_dir="$case_dir"
case_dir=$(new_case_dir)
cp "$prev_case_dir/installed_plugins.json" "$prev_case_dir/known_marketplaces.json" \
  "$prev_case_dir/user_settings.json" "$prev_case_dir/report.json" "$case_dir/"
cp "$prev_case_dir/catalog/market1.json" "$case_dir/catalog/"
write "$case_dir/malformed.json" '{"marketplace": {"name": "market1"'
write "$case_dir/envelope.json" '{"marketplaces": {"market1": {"marketplace": {"name": "market1"}, "installed": []}}}'

out=$(run_from_stdout_only "$case_dir" --ids missing-enabled --from "$case_dir/absent.json" 2>/dev/null)
rc=$?
assert_exit "--from: a missing report is exit 2" 2 "$rc"
assert_eq "--from: a missing report leaves stdout empty" "" "$out"
err=$(run_from_stdout_only "$case_dir" --ids missing-enabled --from "$case_dir/absent.json" 2>&1 >/dev/null)
assert_contains "--from: the missing-report error names the file" "$err" "$case_dir/absent.json"

out=$(run_from_stdout_only "$case_dir" --ids missing-enabled --from "$case_dir/malformed.json" 2>/dev/null)
rc=$?
assert_exit "--from: a malformed report is exit 2" 2 "$rc"
assert_eq "--from: a malformed report leaves stdout empty" "" "$out"
err=$(run_from_stdout_only "$case_dir" --ids missing-enabled --from "$case_dir/malformed.json" 2>&1 >/dev/null)
assert_contains "--from: the malformed-report error names the file" "$err" "$case_dir/malformed.json"

out=$(run_from_stdout_only "$case_dir" --ids missing-enabled --from "$case_dir/envelope.json" 2>/dev/null)
rc=$?
assert_exit "--from: an --all envelope is refused, not projected to empty" 2 "$rc"
assert_eq "--from: the refused envelope leaves stdout empty" "" "$out"

out=$(run_from_stdout_only "$case_dir" --all --ids missing-enabled --from "$case_dir/report.json" 2>/dev/null)
rc=$?
assert_exit "--from: combined with --all is exit 2" 2 "$rc"
assert_eq "--from: the --all rejection leaves stdout empty" "" "$out"
err=$(run_from_stdout_only "$case_dir" --all --ids missing-enabled --from "$case_dir/report.json" 2>&1 >/dev/null)
assert_contains "--from: the --all rejection names --all" "$err" "cannot be combined with --all"

out=$(run_from_stdout_only "$case_dir" --all --from "$case_dir/report.json" 2>/dev/null)
rc=$?
assert_exit "--from: --all without --ids is still exit 2" 2 "$rc"
assert_eq "--from: that rejection leaves stdout empty" "" "$out"
err=$(run_from_stdout_only "$case_dir" --all --from "$case_dir/report.json" 2>&1 >/dev/null)
assert_contains "--from: its own --all rejection names --from" "$err" "--from cannot be combined with --all"

out=$(run_from_stdout_only "$case_dir" --from "$case_dir/report.json" 2>/dev/null)
rc=$?
assert_exit "--from: without --ids is exit 2" 2 "$rc"
assert_eq "--from: the no-selector rejection leaves stdout empty" "" "$out"

out=$(run_from_stdout_only "$case_dir" --marketplace other --ids missing-enabled --from "$case_dir/report.json" 2>/dev/null)
rc=$?
assert_exit "--from: a disagreeing --marketplace is exit 2" 2 "$rc"
assert_eq "--from: the disagreement rejection leaves stdout empty" "" "$out"
out=$(run_from_stdout_only "$case_dir" --marketplace market1 --ids missing-user-install --from "$case_dir/report.json" 2>/dev/null)
rc=$?
assert_exit "--from: an agreeing --marketplace passes the consistency check" 0 "$rc"
assert_eq "--from: the agreeing run still projects" "$(printf 'delta@market1\ngamma@market1')" "$out"

out=$(run_from_stdout_only "$case_dir" --marketplaces --ids missing-enabled --from "$case_dir/report.json" 2>/dev/null)
rc=$?
assert_exit "--from: combined with --marketplaces is exit 2" 2 "$rc"

CASE_NUM=$((CASE_NUM + 1))
write "$case_dir/incomplete.json" '{"marketplace":{"name":"m"},"installed":[]}'
out=$(run_from_stdout_only "$case_dir" --ids missing-enabled --from "$case_dir/incomplete.json" 2>/dev/null)
rc=$?
assert_exit "--from: an incomplete report is exit 2, not an empty exit 0" 2 "$rc"
assert_eq "--from: the incomplete report leaves stdout empty" "" "$out"
err=$(run_from_stdout_only "$case_dir" --ids missing-enabled --from "$case_dir/incomplete.json" 2>&1 >/dev/null)
assert_contains "--from: the incomplete-report error names the file" "$err" "$case_dir/incomplete.json"
assert_contains "--from: the incomplete-report error names the missing field" "$err" ".missing_from_enabled"

write "$case_dir/no-installed.json" '{"marketplace":{"name":"m"},"missing_from_enabled":[]}'
out=$(run_from_stdout_only "$case_dir" --ids missing-enabled --from "$case_dir/no-installed.json" 2>/dev/null)
rc=$?
assert_exit "--from: a report with no .installed is exit 2 even for a selector that ignores it" 2 "$rc"
assert_eq "--from: that rejection leaves stdout empty" "" "$out"

write "$case_dir/no-catalog-versions.json" '{"marketplace":{"name":"m"},"installed":[]}'
for sel in update-candidates-user update-candidates-project downgrade-candidates; do
  out=$(run_from_stdout_only "$case_dir" --ids "$sel" --from "$case_dir/no-catalog-versions.json" 2>/dev/null)
  rc=$?
  assert_exit "--from: $sel without .catalog_versions is exit 2" 2 "$rc"
  assert_eq "--from: $sel leaves stdout empty on that rejection" "" "$out"
  err=$(run_from_stdout_only "$case_dir" --ids "$sel" --from "$case_dir/no-catalog-versions.json" 2>&1 >/dev/null)
  assert_contains "--from: the $sel error names .catalog_versions" "$err" ".catalog_versions"
done
out=$(run_from_stdout_only "$case_dir" --ids installed-user --from "$case_dir/no-catalog-versions.json" 2>/dev/null)
rc=$?
assert_exit "--from: installed-user does not require .catalog_versions" 0 "$rc"

write "$case_dir/empty-but-present.json" '{"marketplace":{"name":"m"},"installed":[],"missing_from_enabled":[]}'
out=$(run_from_stdout_only "$case_dir" --ids missing-enabled --from "$case_dir/empty-but-present.json" 2>/dev/null)
rc=$?
assert_exit "--from: the field present but empty is exit 0" 0 "$rc"
assert_eq "--from: the present-but-empty projection emits nothing" "" "$out"

CASE_NUM=$((CASE_NUM + 1))
prev_case_dir="$case_dir"
case_dir=$(new_case_dir)
cp "$prev_case_dir/report.json" "$case_dir/"
out=$(env \
  FLEET_STATE_INSTALLED_JSON="$case_dir/absent-installed.json" \
  FLEET_STATE_MARKETPLACES_JSON="$case_dir/absent-marketplaces.json" \
  FLEET_STATE_USER_SETTINGS="$case_dir/absent-settings.json" \
  FLEET_STATE_CATALOG_DIR="$case_dir/catalog" \
  bash "$SCRIPT" --ids missing-user-install --from "$case_dir/report.json" 2>/dev/null)
rc=$?
assert_exit "--from: projects with every CC state file absent" 0 "$rc"
assert_eq "--from: the state-free projection still emits the ids" \
  "$(printf 'delta@market1\ngamma@market1')" "$out"

CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
mkdir -p "$case_dir/set/.claude" "$case_dir/bad/.claude" "$case_dir/bare"
write "$case_dir/set/.claude/settings.json" '{"enabledPlugins":{"t@market1":true,"f@market1":false,"o@market1":["x"]}}'
write "$case_dir/bad/.claude/settings.json" '{"enabledPlugins":'
mkdir -p "$case_dir/evil/.claude"
printf '{"enabledPlugins":{}}\037%s\036F{"enabledPlugins":{"n@market1":false}}' "$case_dir/gone" \
  >"$case_dir/evil/.claude/settings.json"
write "$case_dir/installed_plugins.json" "{
  \"version\": 1,
  \"plugins\": {
    \"t@market1\": [{\"scope\": \"project\", \"projectPath\": \"$case_dir/set\", \"installPath\": \"x\", \"version\": \"0.1.0\"},
                    {\"scope\": \"user\", \"installPath\": \"x\", \"version\": \"0.2.0\"}],
    \"f@market1\": [{\"scope\": \"project\", \"projectPath\": \"$case_dir/set\", \"installPath\": \"x\", \"version\": \"0.1.0\"}],
    \"o@market1\": [{\"scope\": \"local\", \"projectPath\": \"$case_dir/set\", \"installPath\": \"x\", \"version\": \"0.1.0\"}],
    \"n@market1\": [{\"scope\": \"project\", \"projectPath\": \"$case_dir/set\", \"installPath\": \"x\", \"version\": \"0.1.0\"},
                    {\"scope\": \"project\", \"projectPath\": \"$case_dir/bare\", \"installPath\": \"x\", \"version\": \"0.1.0\"},
                    {\"scope\": \"project\", \"projectPath\": \"$case_dir/bad\", \"installPath\": \"x\", \"version\": \"0.1.0\"},
                    {\"scope\": \"project\", \"projectPath\": \"$case_dir/gone\", \"installPath\": \"x\", \"version\": \"0.1.0\"},
                    {\"scope\": \"project\", \"projectPath\": \"$case_dir/evil\", \"installPath\": \"x\", \"version\": \"0.1.0\"}]
  }
}"
write "$case_dir/known_marketplaces.json" '{"market1": {"source": {"source": "github", "repo": "example/market1"}, "installLocation": "z", "lastUpdated": "2026-01-01T00:00:00Z"}}'
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "t"}, {"name": "f"}, {"name": "o"}, {"name": "n"}]}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir")
entry_of() { jq -r --arg id "$1" --arg p "$case_dir/$2" '.installed[] | select(.id == $id and .projectPath == $p) | .projectEnabledEntry' <<<"$out" 2>/dev/null; }
assert_eq "projectEnabledEntry: an explicit true" "true" "$(entry_of t@market1 set)"
assert_eq "projectEnabledEntry: an explicit false is not read as no entry" "false" "$(entry_of f@market1 set)"
assert_eq "projectEnabledEntry: a value that is not a boolean" "other" "$(entry_of o@market1 set)"
assert_eq "projectEnabledEntry: no key in the map" "absent" "$(entry_of n@market1 set)"
assert_eq "projectEnabledEntry: no settings file" "absent" "$(entry_of n@market1 bare)"
assert_eq "projectEnabledEntry: a file that does not parse" "unreadable" "$(entry_of n@market1 bad)"
assert_eq "projectEnabledEntry: null for a path that is not present" "null" "$(entry_of n@market1 gone)"
assert_eq "projectEnabledEntry: a file holding a separator byte is unreadable" "unreadable" "$(entry_of n@market1 evil)"
assert_eq "projectEnabledEntry: null for a user-scope record" "null" \
  "$(jq -r '.installed[] | select(.scope == "user") | .projectEnabledEntry' <<<"$out" 2>/dev/null)"
assert_eq "projectEnabledEntry: carried on divergences[].scopes[] too" "true" \
  "$(jq -r '.divergences[] | select(.id == "t@market1") | .scopes[] | select(.scope == "project") | .projectEnabledEntry' <<<"$out" 2>/dev/null)"

printf '\n%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]] && exit 0
exit 1
