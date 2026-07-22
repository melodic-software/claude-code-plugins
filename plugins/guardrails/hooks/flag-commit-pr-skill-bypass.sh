#!/usr/bin/env bash
# PreToolUse hook: advisory guard for direct `gh pr create` calls that bypass
# this marketplace's own canonical `/pull-request create` skill
# (source-control plugin).
# Triggered on Bash tool calls.
#
# SCOPE — only fires when the source-control plugin is actually enabled for this
# session. Claude Code merges `enabledPlugins` across scopes, so enablement is
# resolved across user-global (`~/.claude/settings.json`), project
# (`<repo>/.claude/settings.json`), and local (`.claude/settings.local.json`) in
# precedence order (user-global is the base, project overrides it, local
# overrides that) — a plugin enabled ONLY at user-global (a common install) is
# active in every project, so a probe reading the project file alone
# false-negatives and this advisory never fires. Uncertain state (no jq, no
# value at any scope) fails QUIET (exit 0, no advisory) — an advisory firing on
# unknown state is noise, not signal.
#
# WHAT IT FLAGS:
#   gh pr create — invoked at all. /pull-request create's value is PROCESS
#                 (rebase onto default, unrelated-changes triage, closing-
#                 keyword gate, attribution footer) — there is no command-shape
#                 signature to gate on, so every direct invocation is flagged.
#                 Low-noise in practice: `gh pr create` runs once per PR.
#
# `git commit` is NOT handled here — it moved to block-noncanonical-commit.sh,
# which BLOCKS on the stdin-form mechanic. Keeping a duplicate advisory would
# double-fire on one command. That hook also drops the `--trailer` conjunct this
# one used to require: /commit omits the trailer under trailer_policy `none`, so
# demanding it flagged the skill's own conformant output.
#
# NON-BLOCKING (advisory): exits 0 always. Emits additionalContext naming the
# skill to prefer; never blocks the call — create.md itself documents a
# legitimate inline fallback when skill discovery is broken, so blocking here
# would be wrong.
#
# SCOPE (documented residual, same posture as block-hook-bypass's stripper):
# detection is a literal-stripped top-level regex match, not a full argv-
# grammar parser (contrast block-no-verify.sh) — proportionate to an advisory
# that never blocks. It does not evaluate shell variable / command
# substitution, and a determined author can construct a form that evades the
# match. This is a nudge toward the canonical skills, not an enforcement gate.
#
# Kill switch: flag_commit_pr_skill_bypass_enabled userConfig option

set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "FLAG_COMMIT_PR_SKILL_BYPASS"

# Bundled PowerShell-command classifier — this guard is matched on both the Bash
# and the (opt-in) PowerShell tool. Resolved under the plugin root (CC sets
# CLAUDE_PLUGIN_ROOT; the BASH_SOURCE fallback keeps the contract tests working
# when it is unset).
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/powershell/ps-command.sh
source "$PLUGIN_ROOT/lib/powershell/ps-command.sh"

# High-res start stamp for the telemetry envelope. EPOCHREALTIME is Bash 5.0+;
# on older bash it is unset, so default to empty and skip telemetry.
start=${EPOCHREALTIME:-}

# jq is required both to parse the tool payload and to read enabledPlugins.
# Fail OPEN when it is absent, but make the degraded state visible rather than
# silently disabling the advisory (this hook never blocks either way).
if ! command -v jq >/dev/null 2>&1; then
  echo "guardrails/flag-commit-pr-skill-bypass: jq not found on PATH — advisory disabled (install jq to enable)." >&2
  exit 0
fi

# hook::buffer_stdin encapsulates the Win32-pipe-safe bounded fd0 read; empty
# or timed-out stdin skips this advisory hook.
INPUT=$(hook::buffer_stdin) || exit 0
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null | tr -d '\r')
[[ -n "$COMMAND" ]] || exit 0
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // "Bash"' 2>/dev/null | tr -d '\r')
# On the PowerShell tool, neutralize here-strings first so a `gh pr create`
# mention inside message text is inert and a real invocation after a here-string
# is still seen. Advisory-only: never blocks, so best-effort is proportionate.
if [[ "$TOOL_NAME" == "PowerShell" ]]; then
  ps::blank_herestrings "$COMMAND"
  COMMAND="$PS_BLANKED"
fi

# Privacy-safe telemetry subject: `Bash:<first-token>` with leading `sudo` /
# env-assignment prefixes stripped and the token basenamed. Never the full
# command.
bash_subject() {
  local cmd="$1" tok
  tok="${cmd%%[[:space:]]*}"
  while [[ "$tok" == "sudo" || "$tok" == *=* ]] &&
    [[ -n "$cmd" && "$cmd" == *[[:space:]]* ]]; do
    cmd="${cmd#*[[:space:]]}"
    cmd="${cmd#"${cmd%%[![:space:]]*}"}"
    tok="${cmd%%[[:space:]]*}"
  done
  printf 'Bash:%s' "${tok##*/}"
}

if [[ "$TOOL_NAME" == "Bash" ]]; then
  SUBJECT=$(bash_subject "$COMMAND")
else
  SUBJECT="$TOOL_NAME"
fi

# Emit one telemetry envelope per run. Advisory guards always report status
# "ok" (they never block); the finding signal rides in `data.forms` — category
# labels only ("gh-pr-create-bypass"), never the matched
# command text.
emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local forms_json="[]"
  if ((${#FORMS[@]} > 0)); then
    forms_json=$(printf '%s\n' "${FORMS[@]}" | jq -R . | jq -s . 2>/dev/null) || forms_json="[]"
  fi
  local data
  data=$(jq -n --arg tool "$TOOL_NAME" --arg subject "$SUBJECT" --argjson forms "$forms_json" \
    '{tool:$tool,subject:$subject,forms:$forms}' 2>/dev/null) ||
    data='{"tool":"Bash","subject":"","forms":[]}'
  hook::emit_telemetry "flag-commit-pr-skill-bypass" "PreToolUse" "ok" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# The source-control@ plugin keys declared in one settings file (empty when the
# file is absent). A settings file can carry more than one — e.g. after moving
# the plugin between marketplaces — so enablement is resolved PER exact key.
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
  # `has($k)` so a boolean `false` is read as "false", not collapsed to empty by
  # jq's `//` (which treats false as absent).
  jq -r --arg k "$key" '(.enabledPlugins // {}) | if has($k) then (.[$k] | tostring) else empty end' "$file" 2>/dev/null | head -1
}

# Is any source-control@ plugin enabled for this session? Resolves EACH exact
# key across scopes (user-global base, project override, local override only for
# a key the project already declares) and returns true when ANY resolves enabled
# — collapsing distinct keys to one value would wrongly decide a mixed migration
# state. Uncertain/absent -> return 1 (stay silent).
source_control_enabled() {
  local root user_settings settings local_settings keys key uval bval lval effective
  root=$(hook::repo_root "${CLAUDE_PROJECT_DIR:-.}")
  # User-global settings live at $CLAUDE_CONFIG_DIR/settings.json when that is
  # set (Claude Code's relocatable config dir), else ~/.claude/settings.json.
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
    # A local override counts only for a key the project settings already declare.
    [[ -n "$bval" && -n "$lval" ]] && effective="$lval"
    [[ "$effective" == "true" ]] && return 0 # any enabled key -> skill available
  done <<<"$keys"
  return 1
}

source_control_enabled || exit 0

# Strip single- and double-quoted literal spans, and drop heredoc bodies
# wholesale, so the top-level invocation scan below sees shell syntax, not
# payload text (a commit body mentioning "git commit -m" in prose is not a
# false positive). Same posture as block-hook-bypass.sh's stripper.
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
    line=$(printf '%s' "$line" | sed "s/'[^']*'//g" | sed -E 's/"([^"\\]|\\.)*"//g')
    result+="${line}"$'\n'
  done <<<"$cmd"
  printf '%s' "${result%$'\n'}"
}

STRIPPED_LC="$(strip_literals "$COMMAND")"
STRIPPED_LC="${STRIPPED_LC,,}"

MESSAGES=()
FORMS=()

# `gh pr create` at a command position. No command-shape signature separates
# skill-driven from ad hoc — /pull-request create's value is process (rebase,
# unrelated-changes triage, closing-keyword gate, attribution footer), so any
# direct invocation is flagged.
if [[ "$STRIPPED_LC" =~ (^|[[:space:];&|()]+)gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$) ]]; then
  MESSAGES+=("direct \`gh pr create\` — prefer \`/pull-request create\` (source-control plugin), which rebases onto the default branch, triages unrelated uncommitted changes, gates on a closing-issue keyword, and assembles the attribution footer before creating the PR.")
  FORMS+=("gh-pr-create-bypass")
fi

if ((${#MESSAGES[@]} == 0)); then
  emit_tel
  exit 0
fi

CONTEXT="Commit/PR skill composition (advisory): "
for m in "${MESSAGES[@]}"; do
  CONTEXT+="$m "
done
hook::emit_additional_context PreToolUse "${CONTEXT% }"

emit_tel
exit 0
