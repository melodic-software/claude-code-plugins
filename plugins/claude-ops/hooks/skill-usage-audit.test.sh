#!/usr/bin/env bash
# Contract test for skill-usage-audit.sh (claude-ops plugin). Black-box.
# Covers both outputs: the unconditional skill-usage.jsonl second store (with
# its project-relative destination + skill_usage_dir override) and the telemetry
# envelope emitted only when a sink is wired.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/skill-usage-audit.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=claude-ops-test-helpers.sh
source "$HOOK_DIR/claude-ops-test-helpers.sh"

INPUT='{"tool_name":"Skill","tool_input":{"skill":"/research"}}'

# --- Second store: written unconditionally, default .claude/observability ---
PROJ="$TEST_TMPDIR/proj"
mkdir -p "$PROJ"
env -u HOOK_TELEMETRY_SINK CLAUDE_PROJECT_DIR="$PROJ" \
  bash "$HOOK" <<<"$INPUT" >/dev/null 2>&1
STORE="$PROJ/.claude/observability/skill-usage.jsonl"
if [[ -s "$STORE" ]]; then
  assert_eq "second store event" "SkillUse" "$(jq -r '.event' "$STORE")"
  assert_eq "second store skill (slash stripped)" "research" "$(jq -r '.skill' "$STORE")"
  assert_eq "second store hook" "skill-usage-audit" "$(jq -r '.hook' "$STORE")"
  assert_eq "second store source" "tool" "$(jq -r '.source' "$STORE")"
else
  bad "second store not written (unconditional)"
fi

# --- skill_usage_dir userConfig override -----------------------------------
PROJ2="$TEST_TMPDIR/proj2"
mkdir -p "$PROJ2"
env -u HOOK_TELEMETRY_SINK CLAUDE_PROJECT_DIR="$PROJ2" \
  CLAUDE_PLUGIN_OPTION_SKILL_USAGE_DIR="telemetry/skills" \
  bash "$HOOK" <<<"$INPUT" >/dev/null 2>&1
assert_eq "override dir used" "research" \
  "$(jq -r '.skill' "$PROJ2/telemetry/skills/skill-usage.jsonl" 2>/dev/null)"

# --- Invalid override is visible and cannot escape the project -------------
# CLAUDE_PLUGIN_DATA isolated to a fresh dir: the config-invalid branch now
# goes through hook::notice_once (once-per-session gate), which persists a
# marker file under CLAUDE_PLUGIN_DATA — an unisolated real machine path would
# make this assertion pass only on the first-ever run.
PROJB="$TEST_TMPDIR/projb"
mkdir -p "$PROJB"
OUTSIDE="$TEST_TMPDIR/outside"
BADCFG_DATA="$TEST_TMPDIR/badcfg-data"
mkdir -p "$BADCFG_DATA"
INVALID_OUTPUT=$(env -u HOOK_TELEMETRY_SINK CLAUDE_PROJECT_DIR="$PROJB" \
  CLAUDE_PLUGIN_OPTION_SKILL_USAGE_DIR="../outside" \
  CLAUDE_PLUGIN_DATA="$BADCFG_DATA" \
  bash "$HOOK" <<<"$INPUT" 2>/dev/null)
assert_file_absent "traversal override cannot write outside project" "$OUTSIDE/skill-usage.jsonl"
assert_contains "invalid override emits visible advisory" "$INVALID_OUTPUT" \
  "claude-ops skipped skill-usage logging"
assert_eq "invalid override advisory uses hook protocol" "PostToolUse" \
  "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$INVALID_OUTPUT" 2>/dev/null)"
assert_contains "invalid override advisory is user-visible (systemMessage)" \
  "$(jq -r '.systemMessage // empty' <<<"$INVALID_OUTPUT" 2>/dev/null)" \
  "claude-ops skipped skill-usage logging"

# --- Envelope emitted when a sink is wired ---------------------------------
PROJ3="$TEST_TMPDIR/proj3"
mkdir -p "$PROJ3"
TEL="$TEST_TMPDIR/tel.json"
SINK="$(make_sink "$TEL")"
env HOOK_TELEMETRY_SINK="$SINK" CLAUDE_PROJECT_DIR="$PROJ3" \
  bash "$HOOK" <<<"$INPUT" >/dev/null 2>&1
if wait_for_sink "$TEL"; then
  assert_eq "hook id" "skill-usage-audit" "$(jq -r '.hook' "$TEL")"
  assert_eq "hook_event" "PostToolUse" "$(jq -r '.hook_event' "$TEL")"
  assert_eq "status" "ok" "$(jq -r '.status' "$TEL")"
  assert_eq "data.subject" "Skill:research" "$(jq -r '.data.subject' "$TEL")"
  assert_eq "data.skill" "research" "$(jq -r '.data.skill' "$TEL")"
  assert_eq "data.source" "tool" "$(jq -r '.data.source' "$TEL")"
else
  bad "no envelope written when sink wired"
fi

# --- Non-Skill tool is skipped (no store, no envelope) ---------------------
PROJ4="$TEST_TMPDIR/proj4"
mkdir -p "$PROJ4"
TELN="$TEST_TMPDIR/teln.json"
SINKN="$(make_sink "$TELN")"
env HOOK_TELEMETRY_SINK="$SINKN" CLAUDE_PROJECT_DIR="$PROJ4" \
  bash "$HOOK" <<<'{"tool_name":"Bash","tool_input":{"command":"ls"}}' >/dev/null 2>&1
assert_file_absent "non-Skill → no second store" "$PROJ4/.claude/observability/skill-usage.jsonl"
assert_file_absent "non-Skill → no envelope" "$TELN"

# --- Repo scope in a git work tree: machine-local exclude hygiene ----------
PROJG="$TEST_TMPDIR/projg"
mkdir -p "$PROJG"
if git -C "$PROJG" init -q 2>/dev/null; then
  env -u HOOK_TELEMETRY_SINK CLAUDE_PROJECT_DIR="$PROJG" \
    bash "$HOOK" <<<"$INPUT" >/dev/null 2>&1
  assert_eq "repo-scope store written in git repo" "research" \
    "$(jq -r '.skill' "$PROJG/.claude/observability/skill-usage.jsonl" 2>/dev/null)"
  assert_eq "row carries project field" "projg" \
    "$(jq -r '.project' "$PROJG/.claude/observability/skill-usage.jsonl" 2>/dev/null)"
  if grep -qxF -- '/.claude/observability/' "$PROJG/.git/info/exclude" 2>/dev/null; then
    ok "exclude entry keeps git status clean"
  else
    bad "exclude entry keeps git status clean"
  fi
  if [[ -z "$(git -C "$PROJG" status --porcelain 2>/dev/null)" ]]; then
    ok "git status clean after hook write"
  else
    bad "git status clean after hook write"
  fi
fi

# --- user scope writes under HOME ------------------------------------------
PROJU="$TEST_TMPDIR/proju"
mkdir -p "$PROJU"
HOMEU="$TEST_TMPDIR/homeu"
mkdir -p "$HOMEU"
env -u HOOK_TELEMETRY_SINK CLAUDE_PROJECT_DIR="$PROJU" HOME="$HOMEU" \
  CLAUDE_PLUGIN_OPTION_SKILL_USAGE_SCOPE="user" \
  bash "$HOOK" <<<"$INPUT" >/dev/null 2>&1
assert_eq "user scope writes under HOME" "research" \
  "$(jq -r '.skill' "$HOMEU/.claude/observability/skill-usage.jsonl" 2>/dev/null)"
assert_file_absent "user scope leaves the project tree untouched" \
  "$PROJU/.claude/observability/skill-usage.jsonl"

# --- data-dir scope writes under CLAUDE_PLUGIN_DATA, keyed by repo slug -----
PROJD="$TEST_TMPDIR/projd"
mkdir -p "$PROJD"
DATAD="$TEST_TMPDIR/datad"
mkdir -p "$DATAD"
env -u HOOK_TELEMETRY_SINK CLAUDE_PROJECT_DIR="$PROJD" \
  CLAUDE_PLUGIN_DATA="$DATAD" \
  CLAUDE_PLUGIN_OPTION_SKILL_USAGE_SCOPE="data-dir" \
  bash "$HOOK" <<<"$INPUT" >/dev/null 2>&1
DATAD_STORE=$(find "$DATAD/skill-usage" -name skill-usage.jsonl 2>/dev/null | head -n1)
if [[ -n "$DATAD_STORE" ]]; then
  assert_eq "data-dir scope writes keyed store" "research" "$(jq -r '.skill' "$DATAD_STORE")"
else
  bad "data-dir scope writes keyed store"
fi
assert_file_absent "data-dir scope leaves the project tree untouched" \
  "$PROJD/.claude/observability/skill-usage.jsonl"

# --- Unknown scope: visible advisory, falls back to repo --------------------
PROJS="$TEST_TMPDIR/projs"
mkdir -p "$PROJS"
BADSCOPE_DATA="$TEST_TMPDIR/badscope-data"
mkdir -p "$BADSCOPE_DATA"
BADSCOPE_OUTPUT=$(env -u HOOK_TELEMETRY_SINK CLAUDE_PROJECT_DIR="$PROJS" \
  CLAUDE_PLUGIN_DATA="$BADSCOPE_DATA" \
  CLAUDE_PLUGIN_OPTION_SKILL_USAGE_SCOPE="machine" \
  bash "$HOOK" <<<"$INPUT" 2>/dev/null)
assert_contains "unknown scope emits visible advisory" "$BADSCOPE_OUTPUT" \
  "unknown skill_usage_scope"
assert_eq "unknown scope falls back to repo store" "research" \
  "$(jq -r '.skill' "$PROJS/.claude/observability/skill-usage.jsonl" 2>/dev/null)"

# --- Kill switch suppresses both outputs -----------------------------------
PROJ5="$TEST_TMPDIR/proj5"
mkdir -p "$PROJ5"
TELK="$TEST_TMPDIR/telk.json"
SINKK="$(make_sink "$TELK")"
env HOOK_TELEMETRY_SINK="$SINKK" CLAUDE_PROJECT_DIR="$PROJ5" \
  CLAUDE_PLUGIN_OPTION_SKILL_USAGE_AUDIT_ENABLED=false \
  bash "$HOOK" <<<"$INPUT" >/dev/null 2>&1
assert_file_absent "kill switch → no second store" "$PROJ5/.claude/observability/skill-usage.jsonl"
assert_file_absent "kill switch → no envelope" "$TELK"

report
