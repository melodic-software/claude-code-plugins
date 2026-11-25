#!/usr/bin/env bash

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_FLAG_COMMIT_PR_SKILL_BYPASS_ENABLED:-false}" == "true" ]] || exit 0

_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
guard::abort_boundary flag-commit-pr-skill-bypass PreToolUse open 0
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it

start=${EPOCHREALTIME:-}

hook::buffer_stdin_to INPUT || exit 0

hook::require jq "PreToolUse" guardrails "$INPUT"

hook::jq_fields "$INPUT" '.tool_input.command' '.tool_name' || exit 0
COMMAND="${HOOK_JQ_FIELDS[0]}"
[[ -n "$COMMAND" ]] || exit 0
TOOL_NAME="${HOOK_JQ_FIELDS[1]:-Bash}"
if [[ "$TOOL_NAME" == "PowerShell" ]]; then
  PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$_HOOK_SELF/.." && pwd)}"
  # shellcheck source=../lib/powershell/ps-command.sh
  source "$PLUGIN_ROOT/lib/powershell/ps-command.sh"
  ps::blank_herestrings "$COMMAND"
  COMMAND="$PS_BLANKED"
fi

SUBJECT="" # predeclared: the _to helper assigns through a nameref (SC2154)
hook::extract_bash_subject_to SUBJECT "$TOOL_NAME" "$COMMAND"

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local forms_json="[]"
  if ((${#FORMS[@]} > 0)); then
    forms_json=$(printf '%s\n' "${FORMS[@]}" | jq -Rn '[inputs]' 2>/dev/null) || forms_json="[]"
  fi
  local data
  data=$(jq -n --arg tool "$TOOL_NAME" --arg subject "$SUBJECT" --argjson forms "$forms_json" \
    '{tool:$tool,subject:$subject,forms:$forms}' 2>/dev/null) ||
    data='{"tool":"Bash","subject":"","forms":[]}'
  hook::emit_telemetry "flag-commit-pr-skill-bypass" "PreToolUse" "ok" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# shellcheck disable=SC2329  # invoked below via command substitution
sc_keys() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  jq -r '(.enabledPlugins // {}) | keys[] | select(startswith("source-control@"))' "$file" 2>/dev/null
}

# One exact key's value in one settings file: "true"/"false", empty if absent.
# shellcheck disable=SC2329  # invoked below via command substitution
sc_key_value() {
  local file="$1" key="$2"
  [[ -f "$file" ]] || return 0
  jq -r --arg k "$key" '(.enabledPlugins // {}) | if has($k) then (.[$k] | tostring) else empty end' "$file" 2>/dev/null | head -1
}

source_control_enabled() {
  local root="" user_settings settings local_settings keys key uval bval lval effective
  hook::repo_root_to root "${CLAUDE_PROJECT_DIR:-.}" || :
  # Claude Code keeps user settings under CLAUDE_CONFIG_DIR when set, else ~/.claude:
  # https://code.claude.com/docs/en/env-vars
  user_settings="${CLAUDE_CONFIG_DIR:+$CLAUDE_CONFIG_DIR/settings.json}"
  [[ -n "$user_settings" ]] || user_settings="${HOME:+$HOME/.claude/settings.json}"
  settings="$root/.claude/settings.json"
  local_settings="$root/.claude/settings.local.json"

  keys=$(
    {
      [[ -n "$user_settings" ]] && sc_keys "$user_settings"
      sc_keys "$settings"
      sc_keys "$local_settings"
    } | sort -u
  )
  [[ -n "$keys" ]] || return 1

  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    uval=""
    [[ -n "$user_settings" ]] && uval=$(sc_key_value "$user_settings" "$key")
    bval=$(sc_key_value "$settings" "$key")
    lval=$(sc_key_value "$local_settings" "$key")
    effective="$uval"
    [[ -n "$bval" ]] && effective="$bval"
    [[ -n "$lval" ]] && effective="$lval"
    [[ "$effective" == "true" ]] && return 0
  done <<<"$keys"
  return 1
}

source_control_enabled || exit 0

strip_literals() {
  local cmd="$1" line result="" in_heredoc=0 delim="" trimmed
  local heredoc_start_re='(^|[^<])<<-?[[:space:]]*([^[:space:]<>]+)'

  while IFS= read -r line || [[ -n "$line" ]]; do
    if ((in_heredoc)); then
      trimmed="${line#"${line%%[![:space:]]*}"}"
      trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
      [[ "$trimmed" == "$delim" ]] && in_heredoc=0
      continue
    fi
    if [[ "$line" =~ $heredoc_start_re ]]; then
      delim="${BASH_REMATCH[2]}"
      delim="${delim#\\}"
      delim="${delim#\'}"
      delim="${delim%\'}"
      delim="${delim#\"}"
      delim="${delim%\"}"
      line="${line%%<<*}${line#*"${BASH_REMATCH[0]}"}"
      in_heredoc=1
    fi
    result+="${line}"$'\n'
  done < <(printf '%s\n' "$cmd") # not <<<: a >=64KiB here-string deadlocks (see hardcoded-path-patterns.sh)
  printf '%s' "${result%$'\n'}" | sed -E -e "s/'[^']*'//g" -e 's/"([^"\\]|\\.)*"//g'
}

STRIPPED_LC="$(strip_literals "$COMMAND")"
STRIPPED_LC="${STRIPPED_LC,,}"

MESSAGES=()
FORMS=()

if [[ "$STRIPPED_LC" =~ (^|[[:space:];&|()]+)gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$) ]]; then
  MESSAGES+=("Direct \`gh pr create\` skips /source-control:pull-request (rebase onto the default branch, closing-keyword gate, attribution footer).")
  FORMS+=("gh-pr-create-bypass")
fi

if ((${#MESSAGES[@]} == 0)); then
  emit_tel
  exit 0
fi

if hook::notice_once guardrails-gh-pr-create "$INPUT" && [[ "$HOOK_NOTICE_TO_MODEL" == 1 ]]; then
  hook::emit_channels PreToolUse "${MESSAGES[*]}" ""
fi

emit_tel
exit 0
