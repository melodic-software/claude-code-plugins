#!/usr/bin/env bash
# Secret-safe config structure facts for the audit skill.
#
# Output: per-file validity and key counts, plus the model and effort values
# audit category H needs from settings.local.json. Never prints env values.
# Exit: 0 parseable; 1 invalid JSON; 2 jq missing.
#
# Env:
#   SETTINGS_AUDIT_STRUCTURE_FIXTURE_DIR — fixture project root for tests
set -uo pipefail

usage() {
  cat <<'EOF'
check-structure.sh — secret-safe config structure facts for the audit skill.

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

# A pre-v2.1.211 Claude Code wrote settings.local.json into the directory the
# session started in, and the current one "still reads a .claude/settings.local
# .json that an earlier version left there… permission rules from both files stay
# in effect". So a leftover copy is live configuration that a repository-root-only
# scan cannot see. Default the start directory to the project root (and to the
# fixture root under test) so the row appears only where the two genuinely differ.
if [[ -n "${SETTINGS_AUDIT_STARTDIR_FIXTURE_DIR:-}" ]]; then
  START_DIR="$SETTINGS_AUDIT_STARTDIR_FIXTURE_DIR"
elif [[ -n "${SETTINGS_AUDIT_STRUCTURE_FIXTURE_DIR:-}" ]]; then
  START_DIR="$PROJECT_ROOT"
else
  START_DIR="$PWD"
fi
STARTDIR_LOCAL="$START_DIR/.claude/settings.local.json"

# Managed (machine-scope) policy settings — highest-precedence layer. The per-OS
# locations are shared vocabulary (lib/managed-scope.sh), not this script's to
# restate. Claude Code sets CLAUDE_PLUGIN_ROOT in plugin form; the BASH_SOURCE
# fallback keeps a direct invocation working. SETTINGS_AUDIT_MANAGED_PATH stays
# this script's own test seam — the real locations are absolute system paths a
# fixture dir cannot reach.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "${BASH_SOURCE[0]%/*}/../../.." && pwd)}"
MANAGED_SCOPE_LIB="$PLUGIN_ROOT/lib/managed-scope.sh"
# Fail loudly rather than fall through: an unsourced library leaves the managed
# path empty and every managed row would read `Present: no`, reporting an
# administrator's policy as absent because this script could not find its own
# location list.
if [[ ! -r "$MANAGED_SCOPE_LIB" ]]; then
  echo "ERROR: cannot read $MANAGED_SCOPE_LIB — the plugin's shared managed-scope library is missing" >&2
  exit 2
fi
# shellcheck source=../../../lib/managed-scope.sh
source "$MANAGED_SCOPE_LIB"
MANAGED="$(mscope::base_file "${SETTINGS_AUDIT_MANAGED_PATH:-}")"
MANAGED_DROPIN="$(mscope::dropin_dir "${SETTINGS_AUDIT_MANAGED_PATH:-}")"

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
  # A read that fails is NOT invalid JSON. A Read deny rule, a sandbox denyRead
  # path, or plain filesystem permissions all make open() fail here, and
  # reporting that as malformed config would be a false finding. Distinguish it
  # and report the file as not inspectable instead.
  #
  # `: <"$path"` opens the file and discards it — an open() probe that never
  # reads a byte. Deliberately not `content=$(…)`: holding the file in a shell
  # variable would put every credential in it into `set -x` trace output. File
  # contents stay inside pipelines, where tracing prints the command only.
  if ! : <"$path" 2>/dev/null; then
    printf 'Readable: no\n'
    printf 'Valid JSON: n/a\n'
    printf 'Top-level keys: n/a\n'
    printf 'Note: present but unreadable — not inspectable (deny rule, sandbox denyRead, or filesystem permissions). Not a malformed-config finding.\n'
    return 0
  fi
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
    # Model and effort values are emitted in full, unlike env and permission
    # entries which stay counts. They are configuration identifiers — level
    # names, model names, a boolean — not credentials, and the audit's category
    # H cannot decide its findings from counts: the allowlist wildcard rule
    # turns on which family each entry names, and the fallback cap turns on
    # entry order. Counting them here would leave a local-only misconfiguration
    # invisible. The env-value and secret-field guard above is unchanged.
    tr -d '\r' <"$path" | jq -r '
        "Env keys: \((.env // {} | keys | length))",
        "Deny count: \((.permissions.deny // []) | length)",
        "Ask count: \((.permissions.ask // []) | length)",
        "Allow count: \((.permissions.allow // []) | length)",
        "Plugin keys: \((.enabledPlugins // {} | keys | length))",
        "Effort level: \(if has("effortLevel") then (.effortLevel | tostring) else "unset" end)",
        "Fallback chain: \(if has("fallbackModel") then "\(.fallbackModel | length) raw, \(.fallbackModel | reduce .[] as $m ([]; if index($m) then . else . + [$m] end) | length) after dedup" else "unset" end)",
        "Fallback entries: \(if has("fallbackModel") then (if (.fallbackModel | length) == 0 then "(empty list)" else (.fallbackModel | join(", ")) end) else "unset" end)",
        "Available models: \(if has("availableModels") then (if (.availableModels | length) == 0 then "(empty list)" else (.availableModels | join(", ")) end) else "unset" end)",
        "Enforce available models: \(if has("enforceAvailableModels") then (.enforceAvailableModels | tostring) else "unset" end)"
      '
    ;;
  mcp)
    tr -d '\r' <"$path" | jq -r '"MCP servers: \((.mcpServers // {} | keys | length))"'
    ;;
  managed)
    # Structure only, same posture as `local`: managed policy can carry org
    # values an operator would not expect echoed into a report.
    tr -d '\r' <"$path" | jq -r '
        "Deny count: \((.permissions.deny // []) | length)",
        "Ask count: \((.permissions.ask // []) | length)",
        "Allow count: \((.permissions.allow // []) | length)",
        "Hooks events: \((.hooks // {} | keys | length))",
        "Env keys: \((.env // {} | keys | length))"
      '
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
# Only when the start directory is genuinely a different directory AND holds a
# leftover copy: reporting an absent row for every session started at the repo
# root would be noise, and reporting the same file twice would be a lie about
# how many permission-rule sources are live.
if [[ "$STARTDIR_LOCAL" != "$LOCAL" && -f "$STARTDIR_LOCAL" ]]; then
  emit_file_facts "$STARTDIR_LOCAL (start-directory copy, pre-v2.1.211)" "$STARTDIR_LOCAL" local || invalid=1
  printf 'Note: a start-directory settings.local.json left by a pre-v2.1.211 Claude Code. The repository-root copy wins on a shared key, but permission rules from BOTH files stay in effect.\n'
  printf '\n'
fi
emit_file_facts ".mcp.json" "$MCP" mcp || invalid=1
printf '\n'
emit_file_facts "managed-settings.json (machine scope)" "$MANAGED" managed || invalid=1
if [[ -d "$MANAGED_DROPIN" ]]; then
  dropin_count=0
  for f in "$MANAGED_DROPIN"/*.json; do
    [[ -f "$f" ]] && dropin_count=$((dropin_count + 1))
  done
  printf 'Managed drop-in dir: present (%s *.json file(s), merged alphabetically on top of the base)\n' "$dropin_count"
else
  printf 'Managed drop-in dir: absent\n'
fi
# Managed policy also lives outside the filesystem on some platforms. This check
# reads files only, so it names what it did not read rather than letting an
# absent JSON file read as "no managed policy deployed".
while IFS= read -r key; do
  [[ -n "$key" ]] && printf 'Managed registry key (not read by this check): %s\n' "$key"
done < <(mscope::registry_keys)
plist_domain="$(mscope::plist_domain)"
[[ -n "$plist_domain" ]] && printf 'Managed preferences domain (not read by this check): %s\n' "$plist_domain"

[[ "$invalid" -eq 0 ]]
