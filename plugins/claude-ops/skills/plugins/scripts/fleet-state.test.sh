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
# entirely rather than asserted missing.
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
# the absent-fixture case above
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
# Case: FLEET_STATE_HOOK_UTILS must never be honored — a caller-supplied path is
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
# a bare CR check.
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
# catalog_versions — per-plugin versions read from the marketplace checkout,
# and the FAIL-OPEN contract that governs every consumer of them.
# ============================================================================

# Seed a catalog whose entries carry a string `source`, and materialize each
# named plugin's own manifest under the marketplace subdirectory — the fixture
# mirror of production's <installLocation>/<entry.source>/.claude-plugin/.
# Args: case_dir, then `<plugin-name>=<version>` pairs. A pair with an EMPTY
# version writes a manifest with no `version` key; a plugin named in the
# catalog but omitted from the pairs gets no manifest directory at all. Both
# are fail-open inputs, which is why the helper can express them.
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

# A resolvable manifest yields its version; the catalog entry itself carries
# none, which is the whole reason this read exists.
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_catalog_versions_case "$case_dir" alpha=0.2.0
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha", "source": "./alpha"}]}'
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{"alpha@market1":[{"scope":"user","installPath":"y","version":"0.1.0"}]}}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir")
assert_eq "catalog_versions: reads the version from the plugin's own manifest" \
  "0.2.0" "$(jq -r '.catalog_versions["alpha@market1"]' <<<"$out" 2>/dev/null)"

# `./` prefix on the source is stripped; a bare relative source works too.
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_catalog_versions_case "$case_dir" alpha=0.2.0
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha", "source": "alpha"}]}'
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{}}'
ARGS=(--marketplace market1)
out=$(run_state "$case_dir")
assert_eq "catalog_versions: a source with no ./ prefix resolves identically" \
  "0.2.0" "$(jq -r '.catalog_versions["alpha@market1"]' <<<"$out" 2>/dev/null)"

# --- The three fail-open inputs, each asserted to yield null, never a guess.
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_catalog_versions_case "$case_dir" alpha=0.2.0
# `beta` is in the catalog with a valid source but no manifest was materialized.
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

# An object-valued `source` (a remote spec) has no repo-relative path at all.
# It is skipped entirely, so the lookup misses — which must read as null, the
# same fail-open answer, not as an error and not as a version.
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

# A malformed manifest must not take the run down with it.
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

# ============================================================================
# --ids update-candidates-user — a CANDIDATE list. It may withhold an id only
# when it positively proved that id already sits at the catalog version.
# ============================================================================

# Withheld: installed version equals the catalog version.
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

# Emitted: installed version differs from the catalog version.
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_catalog_versions_case "$case_dir" alpha=0.2.0
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha", "source": "./alpha"}]}'
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{"alpha@market1":[{"scope":"user","installPath":"y","version":"0.1.0"}]}}'
ARGS=(--marketplace market1 --ids update-candidates-user)
out=$(run_ids "$case_dir")
assert_eq "update-candidates-user: emits an id behind the catalog version" \
  "alpha@market1" "$out"

# Emitted: installed version is AHEAD of the catalog (a local build). Plain
# inequality, deliberately not an ordering compare — an ahead id stays a
# candidate exactly as it is when no pre-filter runs at all.
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_catalog_versions_case "$case_dir" alpha=0.1.0
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha", "source": "./alpha"}]}'
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{"alpha@market1":[{"scope":"user","installPath":"y","version":"9.9.9"}]}}'
ARGS=(--marketplace market1 --ids update-candidates-user)
out=$(run_ids "$case_dir")
assert_eq "update-candidates-user: an id AHEAD of the catalog stays a candidate" \
  "alpha@market1" "$out"

# Never narrows past user scope: a project-scope record is not this selector's
# business even when its version differs.
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_catalog_versions_case "$case_dir" alpha=0.1.0
write "$case_dir/catalog/market1.json" '{"plugins": [{"name": "alpha", "source": "./alpha"}]}'
write "$case_dir/installed_plugins.json" '{"version":1,"plugins":{"alpha@market1":[{"scope":"project","projectPath":"C:\\nope","installPath":"x","version":"0.0.1"},{"scope":"user","installPath":"y","version":"0.1.0"}]}}'
ARGS=(--marketplace market1 --ids update-candidates-user)
out=$(run_ids "$case_dir")
assert_eq "update-candidates-user: a differing project-scope record is not a user-scope candidate" \
  "" "$out"

# --- THE FAIL-OPEN PROOF ---------------------------------------------------
# The contract that matters is not "one unreadable id is tolerated" — it is
# that when NO catalog version resolves, the pre-filter degrades to exactly the
# unfiltered sweep. Measured on real machines this is the COMMON case, not the
# rare one (a marketplace whose entries carry object sources, or whose checkout
# does not materialize every plugin directory), so it is asserted as an
# equality against installed-user rather than as a spot check.
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_catalog_versions_case "$case_dir" alpha=0.1.0
# Four catalog entries; only `alpha` could ever resolve, and its manifest is
# then removed so that NONE of the four does.
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

# Partial resolution narrows only the ids it proved, and leaves every
# unresolvable sibling in the sweep.
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

# ============================================================================
# projectPathPresent — advisory annotation. Never a filter, never a verdict.
# ============================================================================

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
# Advisory means advisory: an absent path must not remove the record from the
# report. Suppressing on a directory test would hide real drift from anyone
# whose repos sit on an unmounted volume or an offline share.
assert_eq "projectPathPresent: an absent path never filters the record out of installed[]" \
  "3" "$(jq -r '.installed | length' <<<"$out" 2>/dev/null)"

# The same annotation rides each divergences[].scopes[] entry, and an absent
# path never removes the divergence row either.
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

# ============================================================================
# user_scope_orphans — the class every other field is structurally blind to.
# ============================================================================

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
# The two exclusions that make the field mean something.
assert_eq "user_scope_orphans: excludes an id that also holds a user-scope record" \
  "0" "$(jq -r '[.user_scope_orphans[] | select(. == "paired@market1")] | length' <<<"$out" 2>/dev/null)"
assert_eq "user_scope_orphans: excludes a user-only id" \
  "0" "$(jq -r '[.user_scope_orphans[] | select(. == "useronly@market1")] | length' <<<"$out" 2>/dev/null)"

# An id installed ONLY at project/local scope and explicitly disabled somewhere
# is a decision already made, not a gap. SKILL.md's Report puts this array under
# "Action needed", so leaving an opt-out in it resurfaces the user's own decline
# as drift to act on — the same reason missing_from_install and
# missing_from_user_install both subtract the explicit-false set.
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
# Guard the guard: the opt-out must be excluded because it is opted out, not
# because the fixture failed to produce an orphan population at all.
assert_eq "user_scope_orphans: the sibling id in the same fixture IS still reported" \
  "1" "$(jq -r '.user_scope_orphans | length' <<<"$out" 2>/dev/null)"
# Why the field is needed at all: a single-scope orphan is absent from
# divergences[] BY CONSTRUCTION (that array discards any id with fewer than two
# records), so nothing else in the output could carry it.
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

# ============================================================================
# project_root — the top-level field that makes Step 2's skip reportable.
# Without it, "no project context resolved" and "a project with nothing
# installed in it" are one indistinguishable signal downstream.
# ============================================================================

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
# The distinction is only useful if it survives alongside a currentProject that
# is ALSO null — which is precisely the collapse project_root exists to break.
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
# A project DID resolve and it simply has no project/local installs — the
# honest zero, reportable only because project_root is non-null here while every
# currentProject is still null.
assert_contains "project_root: names the resolved root when a project context exists" \
  "$(jq -r '.project_root' <<<"$out" 2>/dev/null)" "sample-repo"
assert_eq "project_root: a resolved root with no in-repo installs still has no currentProject:true" \
  "0" "$(jq -r '[.installed[] | select(.currentProject == true)] | length' <<<"$out" 2>/dev/null)"

# ============================================================================
# catalog_versions in PRODUCTION mode — manifest_base derived from the
# marketplace's own installLocation rather than from FLEET_STATE_CATALOG_DIR.
# Every other case above sets the catalog-dir override, so without this one the
# branch that actually runs on a real machine is never exercised.
# ============================================================================
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
mkdir -p "$case_dir/checkout/.claude-plugin"
mkdir -p "$case_dir/checkout/alpha/.claude-plugin"
mkdir -p "$case_dir/outside/.claude-plugin"
write "$case_dir/checkout/.claude-plugin/marketplace.json" '{"plugins": [{"name": "alpha", "source": "./alpha"}, {"name": "escape", "source": "../outside"}]}'
write "$case_dir/checkout/alpha/.claude-plugin/plugin.json" '{"name": "alpha", "version": "1.2.3"}'
# A manifest that DOES exist outside the checkout, reachable only by traversal.
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
# Deliberately NOT via run_state: that helper always sets
# FLEET_STATE_CATALOG_DIR, which is the branch this case exists to bypass.
out=$(env FLEET_STATE_INSTALLED_JSON="$case_dir/installed_plugins.json" \
  FLEET_STATE_MARKETPLACES_JSON="$case_dir/known_marketplaces.json" \
  FLEET_STATE_USER_SETTINGS="$case_dir/user_settings.json" \
  bash "$SCRIPT" --marketplace market1 2>&1)
assert_eq "production manifest_base: resolves a version from installLocation, no catalog-dir override" \
  "1.2.3" "$(jq -r '.catalog_versions["alpha@market1"]' <<<"$out" 2>/dev/null)"
# `source` is third-party content. A traversing source must NOT resolve — it
# would read a manifest outside the checkout and could positively but falsely
# "prove" an id is current, which is the ONLY way this pre-filter could wrongly
# WITHHOLD an update.
assert_eq "production manifest_base: a ../-traversing source refuses to resolve (yields null)" \
  "null" "$(jq -r '.catalog_versions["escape@market1"]' <<<"$out" 2>/dev/null)"
out_ids=$(env FLEET_STATE_INSTALLED_JSON="$case_dir/installed_plugins.json" \
  FLEET_STATE_MARKETPLACES_JSON="$case_dir/known_marketplaces.json" \
  FLEET_STATE_USER_SETTINGS="$case_dir/user_settings.json" \
  bash "$SCRIPT" --marketplace market1 --ids update-candidates-user 2>/dev/null)
assert_eq "production manifest_base: the traversing id stays an update candidate, the resolved one is withheld" \
  "escape@market1" "$out_ids"

# Windows spelling of the same traversal must be refused identically.
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
# The outside manifest deliberately carries the SAME version as the installed
# record, so reading it would withhold the id. Anything else would pass this
# test for the wrong reason.
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

# Control for the case above: the identical shape with a REAL directory instead
# of a symlink still resolves, so the guard is containment and not a blanket
# refusal of everything that case constructs.
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

# Nothing to enumerate is an answer, not an error.
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
write "$case_dir/known_marketplaces.json" '{}'
ARGS=(--marketplaces)
out=$(run_state "$case_dir")
rc=$?
assert_exit "--marketplaces: empty object exits 0" 0 "$rc"
assert_eq "--marketplaces: empty object emits nothing" "" "$out"

# Standalone mode: every shaping flag is refused, and the refusal is
# order-independent so `--marketplaces --all` and `--all --marketplaces` agree.
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
# Guard the guard: a stub that silently stopped CRLF-terminating would make
# this case pass while testing nothing.
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

# project_root is marketplace-invariant but must ride EVERY block: an --all
# consumer reads blocks independently, so the field that explains each block's
# currentProject flags has to travel with it.
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

# The unknown-selector help text must name every selector the case arms accept,
# or the two lists drift apart silently.
CASE_NUM=$((CASE_NUM + 1))
case_dir=$(new_case_dir)
seed_ids_case "$case_dir"
ARGS=(--marketplace market1 --ids no-such-selector)
out=$(run_state "$case_dir")
assert_contains "--ids help text names installed-user" "$out" "installed-user"
assert_contains "--ids help text names update-candidates-user" "$out" "update-candidates-user"
assert_contains "--ids help text names current-project" "$out" "current-project"
assert_contains "--ids help text names missing-user-install" "$out" "missing-user-install"
assert_contains "--ids help text names missing-enabled" "$out" "missing-enabled"
assert_contains "--ids help text names user-scope-orphans" "$out" "user-scope-orphans"

# --- Summary -------------------------------------------------------------
printf '\n%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]] && exit 0
exit 1
