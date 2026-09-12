#!/usr/bin/env bash
# One emitter for the audit telemetry rows that differ only in an event, a kill
# switch and a payload projection. Registered in hooks.json on each of those
# events and dispatching on the payload's `hook_event_name`, the same shape
# session-event-log.sh uses to serve ~30 events from one script.
#
# Sharing a script shares no identity and no switch. Each row emits its own
# telemetry `hook` id, `hook_event`, `status` and `data` fields, and reads its
# own `<name>_enabled` userConfig boolean from
# CLAUDE_PLUGIN_OPTION_<NAME>_ENABLED, so a downstream reader sees independent
# producers and an operator turns one off without touching the rest.
#
#   event                | hook id                   | switch
#   StopFailure          | api-error-audit           | API_ERROR_AUDIT
#   ConfigChange         | config-change-audit       | CONFIG_CHANGE_AUDIT
#   PreCompact           | pre-compact-audit         | PRE_COMPACT_AUDIT
#   PostToolUseFailure   | tool-failure-audit        | TOOL_FAILURE_AUDIT
#   PermissionDenied     | permission-denied-audit   | PERMISSION_DENIED_AUDIT
#   InstructionsLoaded   | instructions-loaded-audit | INSTRUCTIONS_LOADED_AUDIT
#   UserPromptExpansion  | skill-usage-audit         | SKILL_USAGE_AUDIT
#
# The seven events are distinct, so the event alone selects the row and no
# matcher field is read to disambiguate.
#
# NON-BLOCKING on every row: exit 0 always, never a decision or a retry.
# Privacy is per row, and no row captures a command body, an error message, an
# absolute path, or an argument body.
# Pure telemetry emitter on six rows: no sink wired (HOOK_TELEMETRY_SINK unset)
# → no-op. The UserPromptExpansion row also writes the skill-usage.jsonl second
# store, which is unconditional and needs no sink.

set -uo pipefail

# All seven rows off means nothing below can run, so leave before parsing the
# library. One disabled row still reaches the library and buffers the payload:
# the row is only known once the event is read, and the payload is the only
# place the event arrives.
_any_on=0
for _opt in API_ERROR_AUDIT CONFIG_CHANGE_AUDIT INSTRUCTIONS_LOADED_AUDIT \
  PERMISSION_DENIED_AUDIT PRE_COMPACT_AUDIT SKILL_USAGE_AUDIT TOOL_FAILURE_AUDIT; do
  _var="CLAUDE_PLUGIN_OPTION_${_opt}_ENABLED"
  if [[ "${!_var:-true}" == "true" ]]; then
    _any_on=1
    break
  fi
done
((_any_on)) || exit 0

# Hook directory by parameter expansion, never `dirname`. GNU Bash forks a
# subshell for every command substitution even when the body is a builtin
# (Command Substitution, Bash Reference Manual). On Windows Git Bash that
# fork is a process. `${BASH_SOURCE[0]%/*}` equals dirname for every shape
# BASH_SOURCE takes; the fallback covers a bare filename, where the strip is a
# no-op and dirname answers `.`.
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"

START=${EPOCHREALTIME:-}

hook::buffer_stdin_to INPUT || exit 0

# The row selector. A bash match over the buffered payload, no extra process.
# `hook_event_name` is a common field on every hook payload; a payload without
# one names no row and is a silent skip.
EVENT=""
[[ "$INPUT" =~ \"hook_event_name\"[[:space:]]*:[[:space:]]*\"([A-Za-z]+)\" ]] && EVENT="${BASH_REMATCH[1]}"

# data.session_id (additive, hook-telemetry rule 1): the sink routes an
# envelope carrying one into the per-session log beside session-event-log.sh.
# The library also puts it on the envelope spine; both are sent, because a sink
# on contract 1.0 reads only data. Extracted once here for every row.
# Empty when the payload carries none, and the key is then left out of data.
SESSION_ID=""
[[ "$INPUT" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([A-Za-z0-9._-]+)\" ]] && SESSION_ID="${BASH_REMATCH[1]}"

# emit::subject_row <jq-filter> <hook-id> <event> <status>
# The rows whose whole projection is one payload field as the subject. An
# absent or empty field is a silent skip.
emit::subject_row() {
  local subject data
  subject=$(hook::jq_field "$INPUT" "$1") || return 0
  data=$(jq -nc --arg session_id "$SESSION_ID" --arg subject "$subject" \
    '{subject: $subject} + (if $session_id == "" then {} else {session_id: $session_id} end)')
  hook::emit_telemetry "$2" "$3" "$4" "$START" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# emit::tool_row <hook-id> <event> <status>
# The rows keyed on a tool call. Privacy-safe subject convention:
#   Bash       → "Bash:<first-token>" (e.g. "Bash:git", "Bash:dotnet")
#   Write|Edit → tool_name only (no file_path leak)
#   other      → tool_name only
# Full command strings, error messages, file paths and stdin are NEVER captured.
#
# Both payload fields in ONE jq process (hook::jq_fields), not two: a jq spawn is
# ~140 ms of fork() emulation on Windows Git Bash. A missing jq or an unparsable
# payload returns non-zero here and skips, the same silent skip an absent
# tool_name takes below; an absent `.tool_input.command` arrives as the empty
# string the subject helper tolerates.
emit::tool_row() {
  local tool cmd subject data
  hook::jq_fields "$INPUT" '.tool_name' '.tool_input.command' || return 0
  tool="${HOOK_JQ_FIELDS[0]}"
  [[ -n "$tool" ]] || return 0
  cmd="${HOOK_JQ_FIELDS[1]}"
  subject=$(hook::extract_bash_subject "$tool" "$cmd")
  data=$(jq -nc --arg session_id "$SESSION_ID" --arg subject "$subject" --arg tool "$tool" \
    '{subject: $subject, tool: $tool} + (if $session_id == "" then {} else {session_id: $session_id} end)')
  hook::emit_telemetry "$1" "$2" "$3" "$START" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# The InstructionsLoaded row. Its subject is "<repo-relative-file>:<load_reason>"
# so query analysis can group loads by reason without parsing extra fields.
#
# Write-time filter: session_start loads are deterministic (the same always-load
# files fire every boot) and high-volume, so they are dropped by default. Opt
# back in for one-off debugging with
# CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_LOADED_AUDIT_LOG_SESSION_START=true.
emit::instructions_loaded_row() {
  local file_path load_reason file_disp project_dir subject data
  # Both payload fields in ONE jq process; see emit::tool_row for why.
  hook::jq_fields "$INPUT" '.file_path' '.load_reason' || return 0
  file_path="${HOOK_JQ_FIELDS[0]}"
  load_reason="${HOOK_JQ_FIELDS[1]}"

  # Need at least one of the two; a pure missing payload is a silent skip.
  [[ -n "$file_path$load_reason" ]] || return 0

  if [[ "$load_reason" == "session_start" &&
    "${CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_LOADED_AUDIT_LOG_SESSION_START:-false}" != "true" ]]; then
    return 0
  fi

  # Privacy: InstructionsLoaded `file_path` is absolute, so logging it verbatim
  # would leak local usernames / private directory names into the shared
  # observability store. Reduce to a repo-relative path when the file is under
  # the project root, else to its basename — never the absolute prefix.
  file_disp=""
  if [[ -n "$file_path" ]]; then
    project_dir=$(hook::repo_root "${CLAUDE_PROJECT_DIR:-.}")
    case "$file_path" in
    "$project_dir"/*) file_disp="${file_path#"$project_dir"/}" ;;
    *) file_disp="${file_path##*/}" ;;
    esac
  fi

  subject="${file_disp}:${load_reason}"
  data=$(jq -nc --arg session_id "$SESSION_ID" --arg subject "$subject" \
    '{subject: $subject} + (if $session_id == "" then {} else {session_id: $session_id} end)')
  hook::emit_telemetry "instructions-loaded-audit" "InstructionsLoaded" "ok" \
    "$START" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# The UserPromptExpansion row: user-typed slash-command / MCP-prompt
# invocations, the second producer of the skill-usage-audit signal. The
# PostToolUse/Skill producer (skill-usage-audit.sh, its own file on the hot
# per-tool-call path) only fires when the MODEL invokes the Skill tool, so a
# user who types "/skill" directly is missed by that path. The two events are
# disjoint, so no dedup is required; each carries a `source` field (`tool` vs
# `expansion`) so consumers can tell the paths apart, and both share one
# telemetry `hook` id and one store.
#
# Two outputs:
#   1. skill-usage.jsonl (SkillUse events), written UNCONDITIONALLY at the
#      scope-selected destination (skill_usage_scope: repo | user | data-dir;
#      skill_usage_dir, else .claude/observability, for the repo/user scopes).
#   2. The telemetry envelope, only when a consumer wires HOOK_TELEMETRY_SINK.
#
# Registered with NO matcher, so it fires for every expanded command; emission
# keys on command_name (always present). expansion_type (slash_command vs
# mcp_prompt) is recorded when present so the distinction is preserved
# downstream, but is never gated on — a CC build that omits it must still record
# the user-typed path rather than silently drop it.
#
# Captures the command name only — no argument body.
emit::skill_expansion_row() {
  local skill exp_type data
  skill=$(hook::jq_field "$INPUT" '.command_name') || return 0
  skill="${skill#/}"

  # Fed through `printf | jq` rather than a here-string: bash fills a
  # here-string's pipe itself, so a payload at or above the pipe capacity blocks
  # before jq runs.
  exp_type=$(printf '%s' "$INPUT" | jq -r '(.expansion_type // empty) | gsub("\r";"")' 2>/dev/null)

  claude_ops::record_skill_use "UserPromptExpansion" "skill-usage-expansion-audit" \
    "$INPUT" "$skill" "expansion" "$exp_type"

  hook::telemetry_enabled || return 0
  data=$(jq -nc --arg session_id "$SESSION_ID" --arg subject "Skill:$skill" --arg skill "$skill" --arg exp "$exp_type" \
    '{subject: $subject, skill: $skill, source: "expansion"}
     + (if $exp != "" then {expansion_type: $exp} else {} end) + (if $session_id == "" then {} else {session_id: $session_id} end)')
  hook::emit_telemetry "skill-usage-audit" "UserPromptExpansion" "ok" \
    "$START" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

case "$EVENT" in
StopFailure)
  # ADVISORY: StopFailure output and exit code are ignored. The subject is the
  # `error` type only: `error_details` may carry prompt fragments or session
  # metadata, so it is never captured.
  hook::is_enabled "API_ERROR_AUDIT" || exit 0
  hook::telemetry_enabled || exit 0
  emit::subject_row '.error' "api-error-audit" "StopFailure" "error"
  ;;
ConfigChange)
  # Settings/skills mutations. Matcher-scoped upstream to
  # user_settings|project_settings|local_settings|skills; policy_settings is
  # excluded there (cannot be blocked, low signal). The subject is the source
  # identifier, which is a path-free label.
  hook::is_enabled "CONFIG_CHANGE_AUDIT" || exit 0
  hook::telemetry_enabled || exit 0
  emit::subject_row '.source' "config-change-audit" "ConfigChange" "ok"
  ;;
PreCompact)
  # A compaction trigger (manual|auto), for diagnosing autocompact-loop
  # regressions and validating a CLAUDE_CODE_AUTO_COMPACT_WINDOW threshold.
  hook::is_enabled "PRE_COMPACT_AUDIT" || exit 0
  hook::telemetry_enabled || exit 0
  emit::subject_row '.trigger' "pre-compact-audit" "PreCompact" "ok"
  ;;
PostToolUseFailure)
  # Write/Edit/Bash failures. Complements the success-only PostToolUse
  # write-side hooks.
  hook::is_enabled "TOOL_FAILURE_AUDIT" || exit 0
  hook::telemetry_enabled || exit 0
  emit::tool_row "tool-failure-audit" "PostToolUseFailure" "error"
  ;;
PermissionDenied)
  # The auto-mode classifier blocking a tool call (distinct from
  # PermissionRequest, which fires on all permission dialogs). Never returns
  # retry:true — denials warrant human review, which is the whole point of the
  # classifier blocking the action.
  hook::is_enabled "PERMISSION_DENIED_AUDIT" || exit 0
  hook::telemetry_enabled || exit 0
  emit::tool_row "permission-denied-audit" "PermissionDenied" "blocked"
  ;;
InstructionsLoaded)
  # ADVISORY: InstructionsLoaded exit code is ignored, so this never gates a
  # load. Lets a consumer validate that `paths:` frontmatter is matching and
  # @-includes resolve (which rules actually load).
  hook::is_enabled "INSTRUCTIONS_LOADED_AUDIT" || exit 0
  hook::telemetry_enabled || exit 0
  emit::instructions_loaded_row
  ;;
UserPromptExpansion)
  # The only row with an output that does not need a sink, so it runs before
  # the telemetry gate. claude-ops-paths.sh is sourced here, not at the top:
  # the other six rows never touch the second store and must not parse it.
  hook::is_enabled "SKILL_USAGE_AUDIT" || exit 0
  # shellcheck source=claude-ops-paths.sh
  source "$HOOK_DIR/claude-ops-paths.sh"
  emit::skill_expansion_row
  ;;
*)
  # An event this script names no row for: a payload carrying no
  # hook_event_name, or a hooks.json entry registered ahead of its row. A
  # silent skip, like every other unmatched payload here.
  ;;
esac

exit 0
