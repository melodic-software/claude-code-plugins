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

run_hook() {
  local input="$1" project="$2"
  shift 2
  env CLAUDE_PROJECT_DIR="$project" "$@" bash "$HOOK" <<<"$input" 2>&1
}

# --- source-control enabled: bypass shapes fire ------------------------------
out=$(run_hook "$(command_json 'git commit -m "quick fix"')" "$ENABLED_PROJECT")
assert_contains "git commit -m fires" "$out" "git commit"
assert_contains "names the /commit skill" "$out" "/commit"

out=$(run_hook "$(command_json 'gh pr create --title x --body y')" "$ENABLED_PROJECT")
assert_contains "gh pr create fires" "$out" "gh pr create"
assert_contains "names the /pull-request skill" "$out" "/pull-request create"

# --- source-control enabled: canonical shape stays silent --------------------
out=$(run_hook "$(command_json 'git commit -F - --cleanup=verbatim --trailer "Co-Authored-By: Claude <noreply@anthropic.com>"')" "$ENABLED_PROJECT")
assert_silent "canonical -F - + --trailer stays silent" "$out"

out=$(run_hook "$(command_json 'git commit --file - --trailer "Co-Authored-By: Claude"')" "$ENABLED_PROJECT")
assert_silent "canonical --file - + --trailer stays silent" "$out"

# --- non-bypass commands stay silent -----------------------------------------
out=$(run_hook "$(command_json 'git status')" "$ENABLED_PROJECT")
assert_silent "unrelated git command stays silent" "$out"

out=$(run_hook "$(command_json "echo 'reminder: use git commit -m for quick fixes'")" "$ENABLED_PROJECT")
assert_silent "prose mentioning git commit -m stays silent" "$out"

# --- source-control NOT available: stays silent regardless of shape ----------
out=$(run_hook "$(command_json 'git commit -m "quick fix"')" "$DISABLED_PROJECT")
assert_silent "source-control explicitly disabled stays silent" "$out"

out=$(run_hook "$(command_json 'git commit -m "quick fix"')" "$NO_KEY_PROJECT")
assert_silent "source-control key absent stays silent" "$out"

NO_SETTINGS_PROJECT="$(mktemp -d -p "$TEST_TMPDIR")"
out=$(run_hook "$(command_json 'git commit -m "quick fix"')" "$NO_SETTINGS_PROJECT")
assert_silent "no .claude/settings.json at all stays silent" "$out"

# --- settings.local.json override --------------------------------------------
OVERRIDE_OFF="$(make_project true false)"
out=$(run_hook "$(command_json 'git commit -m "quick fix"')" "$OVERRIDE_OFF")
assert_silent "settings.local.json false overrides settings.json true" "$out"

OVERRIDE_ON="$(make_project false true)"
out=$(run_hook "$(command_json 'git commit -m "quick fix"')" "$OVERRIDE_ON")
assert_contains "settings.local.json true overrides settings.json false" "$out" "git commit"

# --- kill switch — disabled path is a clean no-op even on a bypass shape -----
out=$(run_hook "$(command_json 'git commit -m "quick fix"')" "$ENABLED_PROJECT" \
  HOOK_FLAG_COMMIT_PR_SKILL_BYPASS_ENABLED=false)
assert_silent "kill switch off → no-op despite bypass shape" "$out"

# --- empty stdin → silent (graceful no-op) -----------------------------------
out=$(env CLAUDE_PROJECT_DIR="$ENABLED_PROJECT" bash "$HOOK" <<<"" 2>&1)
assert_silent "empty stdin is a no-op" "$out"

# --- telemetry: fired case emits an `ok` envelope with a category label ------
TEL="$(mktemp -p "$TEST_TMPDIR")"
SINK="$(make_sink "cat >>\"$TEL\"")"
env HOOK_TELEMETRY_SINK="$SINK" CLAUDE_PROJECT_DIR="$ENABLED_PROJECT" \
  bash "$HOOK" <<<"$(command_json 'git commit -m "quick fix"')" >/dev/null 2>&1 || true
if wait_for_sink "$TEL"; then
  assert_contains "telemetry: hook id" "$(jq -r '.hook' "$TEL")" "flag-commit-pr-skill-bypass"
  assert_contains "telemetry: status ok (advisory never blocks)" "$(jq -r '.status' "$TEL")" "ok"
  assert_contains "telemetry: subject Bash:git" "$(jq -r '.data.subject' "$TEL")" "Bash:git"
  assert_contains "telemetry: form git-commit-bypass" "$(jq -r '.data.forms[0]' "$TEL")" "git-commit-bypass"
else
  bad "telemetry: no envelope written on advisory fire"
fi

report
