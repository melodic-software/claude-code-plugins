#!/usr/bin/env bash
# test-scope: plugins/session-telemetry/hooks/*-audit.sh
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=session-telemetry-test-helpers.sh
source "$HOOK_DIR/session-telemetry-test-helpers.sh"

PROJ="$TEST_TMPDIR/proj"
mkdir -p "$PROJ/.claude/rules"
: >"$PROJ/.claude/rules/x.md"
DATA_DIR="$TEST_TMPDIR/data"
mkdir -p "$DATA_DIR"

members() {
  case "$1" in
  api-error-audit) printf '"hook_event_name":"StopFailure","error":"rate_limit"' ;;
  config-change-audit) printf '"hook_event_name":"ConfigChange","source":"project_settings"' ;;
  instructions-loaded-audit) printf '"hook_event_name":"InstructionsLoaded","file_path":"%s/.claude/rules/x.md","load_reason":"path_glob_match"' "$PROJ" ;;
  permission-denied-audit) printf '"hook_event_name":"PermissionDenied","tool_name":"Bash","tool_input":{"command":"git push"}' ;;
  pre-compact-audit) printf '"hook_event_name":"PreCompact","trigger":"auto"' ;;
  skill-usage-audit) printf '"hook_event_name":"PostToolUse","tool_name":"Skill","tool_input":{"skill":"/research"}' ;;
  skill-usage-expansion-audit) printf '"hook_event_name":"UserPromptExpansion","command_name":"/research","expansion_type":"slash_command"' ;;
  tool-failure-audit) printf '"hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"dotnet build"}' ;;
  *) printf '' ;;
  esac
}

script_for() {
  case "$1" in
  skill-usage-audit) printf '%s.sh' "$1" ;;
  *) printf 'audit-event-emitter.sh' ;;
  esac
}

drive() {
  local sink
  : >"$3"
  sink="$(make_sink "$3")"
  env HOOK_TELEMETRY_SINK="$sink" CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_PLUGIN_DATA="$DATA_DIR" \
    CLAUDE_PLUGIN_OPTION_SKILL_USAGE_SCOPE=data-dir \
    bash "$HOOK_DIR/$(script_for "$1")" <<<"$2" >/dev/null 2>&1
}

for hook in api-error-audit config-change-audit instructions-loaded-audit permission-denied-audit \
  pre-compact-audit skill-usage-audit skill-usage-expansion-audit tool-failure-audit; do
  TEL="$TEST_TMPDIR/$hook.with.json"
  drive "$hook" "{\"session_id\":\"sess-$hook\",$(members "$hook")}" "$TEL"
  if wait_for_sink "$TEL"; then
    assert_eq "$hook: data.session_id carried" "sess-$hook" "$(jq -r '.data.session_id' "$TEL")"
  else
    bad "$hook: no envelope captured with a session_id in the payload"
  fi

  TEL2="$TEST_TMPDIR/$hook.without.json"
  drive "$hook" "{$(members "$hook")}" "$TEL2"
  if wait_for_sink "$TEL2"; then
    assert_eq "$hook: no session_id → key absent from data" "false" "$(jq '.data | has("session_id")' "$TEL2")"
  else
    bad "$hook: no envelope captured without a session_id"
  fi

  TEL3="$TEST_TMPDIR/$hook.hostile.json"
  drive "$hook" "{\"session_id\":\"../x\",$(members "$hook")}" "$TEL3"
  if wait_for_sink "$TEL3"; then
    assert_eq "$hook: a non-id session_id is not carried" "false" "$(jq '.data | has("session_id")' "$TEL3")"
  else
    bad "$hook: no envelope captured with a hostile session_id"
  fi
done

report
