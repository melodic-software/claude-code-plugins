#!/usr/bin/env bash
# PreToolUse hook: advisory guard for direct `git commit` / `gh pr create`
# calls that bypass this marketplace's own canonical `/commit` and
# `/pull-request create` skills (source-control plugin).
# Triggered on Bash tool calls.
#
# SCOPE — only fires when the source-control plugin's skills are actually
# available in the consuming project (`enabledPlugins["source-control@…"]`
# resolves `true` in the consuming project's `.claude/settings.json`, with
# `.claude/settings.local.json` honored as an override only for a key that
# already exists in `settings.json` — CC ignores a local-only key). Uncertain
# state (no jq, no settings file, key absent) fails QUIET (exit 0, no
# advisory) — an advisory firing on unknown state is noise, not signal.
#
# WHAT IT FLAGS:
#   git commit  — invoked WITHOUT the canonical mechanic's two markers
#                 (`-F -` piping the message via stdin, and a `--trailer`
#                 carrying the Co-Authored-By line). A manual `git commit`
#                 that already replicates the canonical shape (e.g. a
#                 hand-typed heredoc form) stays quiet — the guard targets the
#                 anti-pattern (`git commit -m "..."`) /commit exists to
#                 prevent, not "you didn't literally type /commit".
#   gh pr create — invoked at all. /pull-request create's value is PROCESS
#                 (rebase onto default, unrelated-changes triage, closing-
#                 keyword gate, attribution footer) — there is no command-shape
#                 signature to gate on, so every direct invocation is flagged.
#                 Low-noise in practice: `gh pr create` runs once per PR.
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

# High-res start stamp for the telemetry envelope. EPOCHREALTIME is Bash 5.0+;
# on older bash it is unset, so default to empty and skip telemetry.
start=${EPOCHREALTIME:-}

# jq is required both to parse the tool payload and to read enabledPlugins.
# Fail OPEN (silent, advisory-only guard) when it is absent.
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# Read inherited fd0 directly (bare cat) — NEVER `</dev/stdin`: on Windows Git
# Bash, CC spawns hooks with stdin = a Win32 pipe that `/dev/stdin` cannot
# resolve (ENOENT → silent no-op).
INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null | tr -d '\r')
[[ -n "$COMMAND" ]] || exit 0

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

SUBJECT=$(bash_subject "$COMMAND")

# Emit one telemetry envelope per run. Advisory guards always report status
# "ok" (they never block); the finding signal rides in `data.forms` — category
# labels only ("git-commit-bypass" / "gh-pr-create-bypass"), never the matched
# command text.
emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local forms_json="[]"
  if ((${#FORMS[@]} > 0)); then
    forms_json=$(printf '%s\n' "${FORMS[@]}" | jq -R . | jq -s . 2>/dev/null) || forms_json="[]"
  fi
  local data
  data=$(jq -n --arg subject "$SUBJECT" --argjson forms "$forms_json" \
    '{tool:"Bash",subject:$subject,forms:$forms}' 2>/dev/null) ||
    data='{"tool":"Bash","subject":"","forms":[]}'
  hook::emit_telemetry "flag-commit-pr-skill-bypass" "PreToolUse" "ok" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# Is the source-control plugin's skills surface available to this session?
# Resolves the consuming project's own settings, never this plugin's cache
# location. Returns 1 (unknown/absent → stay silent) on any uncertain step.
source_control_enabled() {
  local root settings local_settings base_val local_val
  root=$(hook::repo_root "${CLAUDE_PROJECT_DIR:-.}")
  settings="$root/.claude/settings.json"
  local_settings="$root/.claude/settings.local.json"
  [[ -f "$settings" ]] || return 1

  base_val=$(jq -r '
    (.enabledPlugins // {}) | to_entries[]
    | select(.key | startswith("source-control@"))
    | .value
  ' "$settings" 2>/dev/null | head -1)
  [[ -n "$base_val" ]] || return 1

  local_val=""
  if [[ -f "$local_settings" ]]; then
    local_val=$(jq -r '
      (.enabledPlugins // {}) | to_entries[]
      | select(.key | startswith("source-control@"))
      | .value
    ' "$local_settings" 2>/dev/null | head -1)
  fi

  local effective="$base_val"
  [[ -n "$local_val" ]] && effective="$local_val"
  [[ "$effective" == "true" ]]
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
COMMAND_LC="${COMMAND,,}"

MESSAGES=()
FORMS=()

# `git commit` at a command position (start of string, or after a control
# operator), without the canonical `-F -` stdin-message form AND a `--trailer`
# carrying the Co-Authored-By line. Either marker present → the caller already
# replicates the skill's mechanic; stay quiet.
if [[ "$STRIPPED_LC" =~ (^|[[:space:];&|()]+)git[[:space:]]+commit([[:space:]]|$) ]]; then
  if ! [[ "$COMMAND_LC" =~ (^|[[:space:]])(-f|--file)[[:space:]]+-([[:space:]]|$) ]] ||
    ! [[ "$COMMAND_LC" =~ --trailer ]]; then
    MESSAGES+=("direct \`git commit\` (missing the canonical \`-F -\` stdin form + \`--trailer\` Co-Authored-By line) — prefer the \`/commit\` skill (source-control plugin), which encapsulates the heredoc mechanic, Conventional Commits pre-check, and attribution trailer.")
    FORMS+=("git-commit-bypass")
  fi
fi

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
