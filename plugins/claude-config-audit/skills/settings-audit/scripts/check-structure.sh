#!/usr/bin/env bash
# Secret-safe config structure facts for the settings-audit skill.
#
# Output: per-file validity and key counts. Never prints env values.
# Exit: 0 parseable; 1 invalid JSON; 2 jq missing.
#
# Env:
#   SETTINGS_AUDIT_STRUCTURE_FIXTURE_DIR — fixture project root for tests
set -uo pipefail

usage() {
  cat <<'EOF'
check-structure.sh — secret-safe config structure facts for the settings-audit skill.

Never prints env values or secret field contents.

Usage:
  check-structure.sh [--help]

Exit: 0 parseable; 1 invalid JSON found; 2 jq missing.
EOF
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  *) ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq required" >&2
  exit 2
fi

if [[ -n "${SETTINGS_AUDIT_STRUCTURE_FIXTURE_DIR:-}" ]]; then
  PROJECT_ROOT="$SETTINGS_AUDIT_STRUCTURE_FIXTURE_DIR"
else
  # Consumer project root: the cwd's git toplevel, then Claude Code's exported
  # project dir, then cwd. Never the plugin's own install directory.
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
  [[ -n "$PROJECT_ROOT" ]] || PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
fi

SETTINGS="$PROJECT_ROOT/.claude/settings.json"
LOCAL="$PROJECT_ROOT/.claude/settings.local.json"
MCP="$PROJECT_ROOT/.mcp.json"

emit_file_facts() {
  local label="$1" path="$2" kind="$3"
  printf 'File: %s\n' "$label"
  if [[ ! -f "$path" ]]; then
    printf 'Present: no\n'
    printf 'Valid JSON: n/a\n'
    printf 'Top-level keys: n/a\n'
    return 0
  fi
  printf 'Present: yes\n'
  if ! tr -d '\r' <"$path" | jq empty 2>/dev/null; then
    printf 'Valid JSON: no\n'
    return 1
  fi
  printf 'Valid JSON: yes\n'
  local keys
  keys="$(tr -d '\r' <"$path" | jq -r 'keys | length')"
  printf 'Top-level keys: %s\n' "$keys"
  case "$kind" in
    settings)
      tr -d '\r' <"$path" | jq -r '
        "Deny count: \((.permissions.deny // []) | length)",
        "Ask count: \((.permissions.ask // []) | length)",
        "Allow count: \((.permissions.allow // []) | length)",
        "Hooks events: \((.hooks // {} | keys | length))",
        "MCP servers: \((.mcpServers // {} | keys | length))",
        "Plugins enabled: \([.enabledPlugins // {} | to_entries[] | select(.value == true)] | length)"
      '
      ;;
    local)
      tr -d '\r' <"$path" | jq -r '
        "Env keys: \((.env // {} | keys | length))",
        "Deny count: \((.permissions.deny // []) | length)",
        "Ask count: \((.permissions.ask // []) | length)",
        "Allow count: \((.permissions.allow // []) | length)",
        "Plugin keys: \((.enabledPlugins // {} | keys | length))"
      '
      ;;
    mcp)
      tr -d '\r' <"$path" | jq -r '"MCP servers: \((.mcpServers // {} | keys | length))"'
      ;;
    *) ;;
  esac
  return 0
}

invalid=0
emit_file_facts ".claude/settings.json" "$SETTINGS" settings || invalid=1
printf '\n'
emit_file_facts ".claude/settings.local.json" "$LOCAL" local || invalid=1
printf '\n'
emit_file_facts ".mcp.json" "$MCP" mcp || invalid=1

[[ "$invalid" -eq 0 ]]
