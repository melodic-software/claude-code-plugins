#!/usr/bin/env bash
# Contract test for flag-commit-pr-skill-bypass.sh (guardrails plugin).
#
# Black-box: pipes PreToolUse Bash JSON on stdin against a fixture consuming
# project (a temp dir with its own .claude/settings.json), asserts on the
# emitted additionalContext. The hook is advisory (always exit 0) — these
# cases verify WHEN it speaks (source-control enabled + bypass shape) and WHEN
# it stays silent (source-control absent/disabled, canonical shape already
# used, kill switch, no jq). Self-contained — no host-repo assertion library.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/flag-commit-pr-skill-bypass.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

# make_project <enabledPlugins-json-or-empty> [settings.local.json-value] -> project dir
# Writes a fixture consuming project with .claude/settings.json (and an
# optional settings.local.json override) so the hook resolves source-control
# enablement from files, never this repo's own settings.
make_project() {
  local dir enabled="${1:-}" local_val="${2:-}"
  dir="$(mktemp -d -p "$TEST_TMPDIR")"
  mkdir -p "$dir/.claude"
  if [[ -n "$enabled" ]]; then
    jq -n --argjson v "$enabled" '{enabledPlugins:{"source-control@melodic-software":$v}}' \
      >"$dir/.claude/settings.json"
  else
    printf '{}' >"$dir/.claude/settings.json"
  fi
  if [[ -n "$local_val" ]]; then
    jq -n --argjson v "$local_val" '{enabledPlugins:{"source-control@melodic-software":$v}}' \
      >"$dir/.claude/settings.local.json"
  fi
  printf '%s' "$dir"
}

ENABLED_PROJECT="$(make_project true)"
DISABLED_PROJECT="$(make_project false)"
NO_KEY_PROJECT="$(make_project)"

# make_home <enabledPlugins-value> -> a HOME dir carrying ~/.claude/settings.json
# so a user-global enablement can be exercised hermetically.
make_home() {
  local dir enabled="$1"
  dir="$(mktemp -d -p "$TEST_TMPDIR")"
  mkdir -p "$dir/.claude"
  jq -n --argjson v "$enabled" '{enabledPlugins:{"source-control@melodic-software":$v}}' \
    >"$dir/.claude/settings.json"
  printf '%s' "$dir"
}

# A clean HOME with no ~/.claude, so a case that does not set its own HOME never
# reads the CI runner's real user-global settings. Cases exercising user-global
# scope pass HOME=<make_home ...> through run_hook's trailing env args.
HERMETIC_HOME="$(mktemp -d -p "$TEST_TMPDIR")"

# settings.json directly in the dir (the CLAUDE_CONFIG_DIR layout, no `.claude/`).
make_config_dir() {
  local dir enabled="$1"
  dir="$(mktemp -d -p "$TEST_TMPDIR")"
  jq -n --argjson v "$enabled" '{enabledPlugins:{"source-control@melodic-software":$v}}' \
    >"$dir/settings.json"
  printf '%s' "$dir"
}

run_hook() {
  local input="$1" project="$2"
  shift 2
  # -u CLAUDE_CONFIG_DIR so a leaked value never overrides the HOME fixture; a
  # case exercising it passes CLAUDE_CONFIG_DIR=... in the trailing args (which
  # come after the -u and win).
  env -u CLAUDE_CONFIG_DIR CLAUDE_PROJECT_DIR="$project" HOME="$HERMETIC_HOME" "$@" bash "$HOOK" <<<"$input" 2>&1
}

# --- source-control enabled: bypass shapes fire ------------------------------
out=$(run_hook "$(command_json 'gh pr create --title x --body y')" "$ENABLED_PROJECT")
assert_contains "gh pr create fires" "$out" "gh pr create"
assert_contains "names the /pull-request skill" "$out" "/pull-request create"

# --- git commit is no longer this hook's concern -----------------------------
# It moved to block-noncanonical-commit.sh, which BLOCKS on the stdin-form
# mechanic. A duplicate advisory here would double-fire on one command.
out=$(run_hook "$(command_json 'git commit -m "quick fix"')" "$ENABLED_PROJECT")
assert_silent "git commit -m is not flagged here (owned by block-noncanonical-commit)" "$out"

out=$(run_hook "$(command_json 'git commit -F - --cleanup=verbatim')" "$ENABLED_PROJECT")
assert_silent "canonical -F - without --trailer stays silent (trailer_policy none)" "$out"

# --- non-bypass commands stay silent -----------------------------------------
out=$(run_hook "$(command_json 'git status')" "$ENABLED_PROJECT")
assert_silent "unrelated git command stays silent" "$out"

out=$(run_hook "$(command_json "echo 'reminder: use git commit -m for quick fixes'")" "$ENABLED_PROJECT")
assert_silent "prose mentioning git commit -m stays silent" "$out"

# --- source-control NOT available: stays silent regardless of shape ----------
out=$(run_hook "$(command_json 'gh pr create --title x --body y')" "$DISABLED_PROJECT")
assert_silent "source-control explicitly disabled stays silent" "$out"

out=$(run_hook "$(command_json 'gh pr create --title x --body y')" "$NO_KEY_PROJECT")
assert_silent "source-control key absent stays silent" "$out"

NO_SETTINGS_PROJECT="$(mktemp -d -p "$TEST_TMPDIR")"
out=$(run_hook "$(command_json 'gh pr create --title x --body y')" "$NO_SETTINGS_PROJECT")
assert_silent "no .claude/settings.json at all stays silent" "$out"

# --- settings.local.json override --------------------------------------------
OVERRIDE_OFF="$(make_project true false)"
out=$(run_hook "$(command_json 'gh pr create --title x --body y')" "$OVERRIDE_OFF")
assert_silent "settings.local.json false overrides settings.json true" "$out"

OVERRIDE_ON="$(make_project false true)"
out=$(run_hook "$(command_json 'gh pr create --title x --body y')" "$OVERRIDE_ON")
assert_contains "settings.local.json true overrides settings.json false" "$out" "gh pr create"

# --- user-global scope: enablement resolves across ~/.claude too -------------
HOME_ENABLED="$(make_home true)"
HOME_DISABLED="$(make_home false)"

# The exact false-negative this fixes: enabled ONLY at user-global, project has
# no settings file at all — the advisory MUST fire.
out=$(run_hook "$(command_json 'gh pr create --title x --body y')" "$NO_SETTINGS_PROJECT" HOME="$HOME_ENABLED")
assert_contains "user-global enable fires with no project settings" "$out" "gh pr create"

# user-global enabled, project settings present but key absent — fires.
out=$(run_hook "$(command_json 'gh pr create --title x --body y')" "$NO_KEY_PROJECT" HOME="$HOME_ENABLED")
assert_contains "user-global enable fires when project key absent" "$out" "gh pr create"

# project explicitly disables what user-global enabled — silent (project wins).
out=$(run_hook "$(command_json 'gh pr create --title x --body y')" "$DISABLED_PROJECT" HOME="$HOME_ENABLED")
assert_silent "project false overrides user-global true" "$out"

# user-global disabled, project enables — fires (project wins over base).
out=$(run_hook "$(command_json 'gh pr create --title x --body y')" "$ENABLED_PROJECT" HOME="$HOME_DISABLED")
assert_contains "project true overrides user-global false" "$out" "gh pr create"

# Local scope stands alone (settings precedence Local > Project > User;
# `claude plugin install --scope local` writes enabledPlugins to
# settings.local.json as a first-class state) — a local value participates in
# per-key resolution whether or not the project settings.json declares the key.
LOCAL_ONLY_OFF="$(make_project '' false)" # project {} (no key), local=false
out=$(run_hook "$(command_json 'gh pr create --title x --body y')" "$LOCAL_ONLY_OFF" HOME="$HOME_ENABLED")
assert_silent "local-only false overrides user-global true (no project key)" "$out"

LOCAL_ONLY_ON="$(make_project '' true)" # project {} (no key), local=true
out=$(run_hook "$(command_json 'gh pr create --title x --body y')" "$LOCAL_ONLY_ON" HOME="$HOME_DISABLED")
assert_contains "local-only true overrides user-global false (no project key)" "$out" "gh pr create"

out=$(run_hook "$(command_json 'gh pr create --title x --body y')" "$LOCAL_ONLY_ON")
assert_contains "local-only enablement fires with no other scope set" "$out" "gh pr create"

# user-global via a relocated CLAUDE_CONFIG_DIR (not ~/.claude) is honored.
CFG_ENABLED="$(make_config_dir true)"
out=$(run_hook "$(command_json 'gh pr create --title x --body y')" "$NO_SETTINGS_PROJECT" CLAUDE_CONFIG_DIR="$CFG_ENABLED")
assert_contains "user-global via CLAUDE_CONFIG_DIR fires" "$out" "gh pr create"

# Multiple source-control@ keys (marketplace migration): ANY enabled key means
# the skill is available, resolved per exact key — not collapsed to one value.
MK_HOME="$(mktemp -d -p "$TEST_TMPDIR")"
mkdir -p "$MK_HOME/.claude"
jq -n '{enabledPlugins:{"source-control@old":true}}' >"$MK_HOME/.claude/settings.json"
MK_PROJ="$(mktemp -d -p "$TEST_TMPDIR")"
mkdir -p "$MK_PROJ/.claude"
jq -n '{enabledPlugins:{"source-control@new":false}}' >"$MK_PROJ/.claude/settings.json"
out=$(run_hook "$(command_json 'gh pr create --title x --body y')" "$MK_PROJ" HOME="$MK_HOME")
assert_contains "an enabled source-control@old fires despite a disabled @new" "$out" "gh pr create"

# --- kill switch — disabled path is a clean no-op even on a bypass shape -----
out=$(run_hook "$(command_json 'gh pr create --title x --body y')" "$ENABLED_PROJECT" \
  CLAUDE_PLUGIN_OPTION_FLAG_COMMIT_PR_SKILL_BYPASS_ENABLED=false)
assert_silent "kill switch off → no-op despite bypass shape" "$out"

# --- empty stdin → silent (graceful no-op) -----------------------------------
out=$(env CLAUDE_PROJECT_DIR="$ENABLED_PROJECT" bash "$HOOK" <<<"" 2>&1)
assert_silent "empty stdin is a no-op" "$out"

# --- telemetry: fired case emits an `ok` envelope with a category label ------
TEL="$(mktemp -p "$TEST_TMPDIR")"
SINK="$(make_sink "cat >>\"$TEL\"")"
env HOOK_TELEMETRY_SINK="$SINK" CLAUDE_PROJECT_DIR="$ENABLED_PROJECT" \
  bash "$HOOK" <<<"$(command_json 'gh pr create --title x --body y')" >/dev/null 2>&1 || true
if wait_for_sink "$TEL"; then
  assert_contains "telemetry: hook id" "$(jq -r '.hook' "$TEL")" "flag-commit-pr-skill-bypass"
  assert_contains "telemetry: status ok (advisory never blocks)" "$(jq -r '.status' "$TEL")" "ok"
  assert_contains "telemetry: subject Bash:gh" "$(jq -r '.data.subject' "$TEL")" "Bash:gh"
  assert_contains "telemetry: form gh-pr-create-bypass" "$(jq -r '.data.forms[0]' "$TEL")" "gh-pr-create-bypass"
else
  bad "telemetry: no envelope written on advisory fire"
fi

# --- PowerShell tool coverage ------------------------------------------------
# The advisory is matched on Bash|PowerShell. A direct `gh pr create` on the
# PowerShell tool still fires; the same text quarantined inside a here-string
# body is neutralized (blanked) and stays silent.
out=$(run_hook "$(pwsh_command_json 'gh pr create --title x --body y')" "$ENABLED_PROJECT")
assert_contains "PS: gh pr create fires" "$out" "gh pr create"

out=$(run_hook "$(pwsh_command_json "$(printf '%s\n%s\n%s' "@'" "gh pr create in a message body" "'@ | git commit -F -")")" "$ENABLED_PROJECT")
assert_silent "PS: gh pr create inside a here-string body stays silent" "$out"

report
