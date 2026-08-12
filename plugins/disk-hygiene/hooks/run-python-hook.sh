#!/usr/bin/env bash
# Bash launcher for disk-hygiene Python hooks (#1504, #1505).
#
# Claude Code wires hooks as a literal command string. When that command is
# `python3`, a missing interpreter or a Windows App Execution Alias stub means
# the process never starts — the harness treats that as approval and the Stop
# detector dies the same way. This wrapper resolves a runnable interpreter
# independently and emits HOOK_TELEMETRY_SINK envelopes via hook-utils.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$HOOK_DIR/.." && pwd)"

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"

HOOK_ID="${1:-}"
HOOK_EVENT="${2:-}"
PYTHON_SCRIPT="${3:-}"
if (($# >= 3)); then
  shift 3
else
  set --
fi

start=${EPOCHREALTIME:-}

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  hook::emit_telemetry "$HOOK_ID" "$HOOK_EVENT" "$1" "$start" "$2" "${CLAUDE_PROJECT_DIR:-}"
}

build_data_json() {
  local status="$1"
  local exit_code="$2"
  local interpreter="${3:-}"
  command -v jq >/dev/null 2>&1 || {
    printf '{"status":"%s","exit_code":%s}' "$status" "$exit_code"
    return 0
  }
  jq -n \
    --arg status "$status" \
    --argjson exit_code "$exit_code" \
    --arg interpreter "$interpreter" \
    '{status:$status, exit_code:$exit_code, interpreter:(if $interpreter=="" then null else $interpreter end)}'
}

probe_verdict() {
  local interpreter="$1"
  local probe="$PLUGIN_ROOT/skills/setup/scripts/python3_alias_probe.py"
  [[ -f "$probe" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  local json verdict
  json=$("$interpreter" "$probe" --path "$interpreter" 2>/dev/null) || return 1
  verdict=$(printf '%s' "$json" | jq -r '.verdict // empty' 2>/dev/null)
  case "$verdict" in
  ok | indeterminate) return 0 ;;
  *) return 1 ;;
  esac
}

resolve_python() {
  [[ "${DISK_HYGIENE_FORCE_NO_PYTHON:-}" == 1 ]] && return 1
  local cand name

  if command -v py >/dev/null 2>&1; then
    cand=$(py -3 -c 'import sys; print(sys.executable)' 2>/dev/null) || cand=""
    if [[ -n "$cand" ]] && probe_verdict "$cand"; then
      printf '%s' "$cand"
      return 0
    fi
  fi

  for name in python3 python; do
    command -v "$name" >/dev/null 2>&1 || continue
    cand=$(command -v "$name")
    if probe_verdict "$cand"; then
      printf '%s' "$cand"
      return 0
    fi
  done
  return 1
}

interpreter_unavailable() {
  local reason
  reason="disk-hygiene: no runnable Python interpreter was found for ${HOOK_ID}. The destructive-action guard may not have enforced policy for guarded commands this session."
  case "$HOOK_EVENT" in
  PreToolUse)
    emit_tel "interpreter_unavailable" "$(build_data_json "interpreter_unavailable" 2 "")"
    printf '%s\n' \
      '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"disk-hygiene: Python interpreter unavailable — destructive-action guard could not run (#1504)"}}'
    exit 2
    ;;
  Stop)
    emit_tel "interpreter_unavailable" "$(build_data_json "interpreter_unavailable" 0 "")"
    hook::emit_system_message "$reason"
    exit 0
    ;;
  *)
    emit_tel "interpreter_unavailable" "$(build_data_json "interpreter_unavailable" 1 "")"
    exit 0
    ;;
  esac
}

[[ -n "$HOOK_ID" && -n "$HOOK_EVENT" && -n "$PYTHON_SCRIPT" ]] || exit 0
[[ -f "$PYTHON_SCRIPT" ]] || exit 0

INPUT=$(hook::buffer_stdin) || INPUT=""

PYTHON=$(resolve_python) || interpreter_unavailable

set +e
if [[ -n "$INPUT" ]]; then
  printf '%s' "$INPUT" | "$PYTHON" "$PYTHON_SCRIPT" "$@"
else
  "$PYTHON" "$PYTHON_SCRIPT" "$@"
fi
rc=$?
set -e

case "$rc" in
0) tel_status=ok ;;
2) tel_status=blocked ;;
*) tel_status=error ;;
esac

emit_tel "$tel_status" "$(build_data_json "$tel_status" "$rc" "$PYTHON")"
exit "$rc"
