#!/usr/bin/env bash
# The nine claude-ops audit hooks put the payload's session_id into their
# envelope `data` (additive, docs/conventions/hook-telemetry rule 1) so the
# reference sink can route the line into the per-session log. One suite for
# all of them: each hook is driven black-box with a minimal payload that
# carries a session_id, and once without one, and the captured envelope is
# read back. Covers: api-error-audit.sh config-change-audit.sh
# instructions-loaded-audit.sh permission-denied-audit.sh pre-compact-audit.sh
# skill-usage-audit.sh skill-usage-expansion-audit.sh tool-failure-audit.sh
# hook-failure-audit.sh
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=claude-ops-test-helpers.sh
source "$HOOK_DIR/claude-ops-test-helpers.sh"

PROJ="$TEST_TMPDIR/proj"
mkdir -p "$PROJ/.claude/rules"
: >"$PROJ/.claude/rules/x.md"
DATA_DIR="$TEST_TMPDIR/data"
mkdir -p "$DATA_DIR"

# A transcript for hook-failure-audit carrying one unsurfaced failure.
TRANSCRIPT="$TEST_TMPDIR/transcript.jsonl"
printf '{"attachment":{"type":"hook_non_blocking_error","hookName":"PreToolUse:demo","toolUseID":"toolu_x","hookEvent":"PreToolUse","stderr":"boom","stdout":"","exitCode":1,"command":"bash demo.sh","durationMs":2},"type":"attachment","uuid":"u","session_id":"s"}\n' >"$TRANSCRIPT"

# hook <name> -> the payload members (without session_id) that make it emit
members() {
  case "$1" in
  api-error-audit) printf '"error":"rate_limit"' ;;
  config-change-audit) printf '"source":"project_settings"' ;;
  instructions-loaded-audit) printf '"file_path":"%s/.claude/rules/x.md","load_reason":"path_glob_match"' "$PROJ" ;;
  permission-denied-audit) printf '"tool_name":"Bash","tool_input":{"command":"git push"}' ;;
  pre-compact-audit) printf '"trigger":"auto"' ;;
  skill-usage-audit) printf '"tool_name":"Skill","tool_input":{"skill":"/research"}' ;;
  skill-usage-expansion-audit) printf '"command_name":"/research","expansion_type":"slash_command"' ;;
  tool-failure-audit) printf '"tool_name":"Bash","tool_input":{"command":"dotnet build"}' ;;
  hook-failure-audit) printf '"transcript_path":"%s","hook_event_name":"Stop"' "$TRANSCRIPT" ;;
  *) printf '' ;;
  esac
}

# drive <hook> <payload> <capture-file>
drive() {
  local sink
  : >"$3"
  sink="$(make_sink "$3")"
  env HOOK_TELEMETRY_SINK="$sink" CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_PLUGIN_DATA="$DATA_DIR" \
    CLAUDE_PLUGIN_OPTION_SKILL_USAGE_SCOPE=data-dir \
    bash "$HOOK_DIR/$1.sh" <<<"$2" >/dev/null 2>&1
}

for hook in api-error-audit config-change-audit instructions-loaded-audit permission-denied-audit \
  pre-compact-audit skill-usage-audit skill-usage-expansion-audit tool-failure-audit hook-failure-audit; do
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
