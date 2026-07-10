#!/usr/bin/env bash
# PreToolUse hook: block git hook-bypass attempts on git commit and git push.
# Triggered on Bash tool calls.
#
# Catches three bypass surfaces:
#   1. --no-verify / -n flags on git commit (skips pre-commit + commit-msg hooks)
#   2. core.hooksPath assignment on git commit/push (disables all git hooks)
#   3. GIT hook-manager env-var prefix (LEFTHOOK=0 / LEFTHOOK=false /
#      LEFTHOOK_*=0|false) on git commit or git push (disables the hook manager
#      for one invocation)
#
# Deny rules in settings.json have known bypasses via compound commands. This
# hook sees the full command string and catches all forms including:
#   cd foo && LEFTHOOK=0 git commit -m "msg"
#
# BLOCKING: exits 2 on any bypass form (stderr shown to Claude as feedback).
# The kill switch (HOOK_BLOCK_NO_VERIFY_ENABLED=false) is the ONLY supported
# bypass — do not use --no-verify or an env-var prefix.

set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "BLOCK_NO_VERIFY"

# High-res start stamp for the telemetry envelope. EPOCHREALTIME is Bash 5.0+;
# on older bash it is unset, so default to empty and skip telemetry (the block
# still fires). Referencing it bare under `set -u` would abort before exit.
start=${EPOCHREALTIME:-}

# Read inherited fd0 directly (bare cat) — NEVER `</dev/stdin`: on Windows Git
# Bash, CC spawns hooks with stdin = a Win32 pipe that `/dev/stdin` cannot
# resolve (ENOENT → silent no-op).
INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null | tr -d '\r')
[[ -n "$COMMAND" ]] || exit 0

# Strip heredoc bodies and single/double-quoted string literals so a bypass
# token QUOTED inside a commit message or echo argument (e.g.
# `echo "git commit --no-verify is banned"`) is not treated as a real flag.
# Only the executable portion outside quotes is inspected.
strip_literals() {
  local cmd="$1" line result="" in_heredoc=0 delim=""
  local heredoc_start_re='<<-?[[:space:]]*([^[:space:]]+)'

  while IFS= read -r line || [[ -n "$line" ]]; do
    if ((in_heredoc)); then
      [[ "$line" =~ ^[[:space:]]*"$delim"[[:space:]]*$ ]] && in_heredoc=0
      continue
    fi
    if [[ "$line" =~ $heredoc_start_re ]]; then
      delim="${BASH_REMATCH[1]}"
      delim="${delim#\'}"
      delim="${delim%\'}"
      delim="${delim#\"}"
      delim="${delim%\"}"
      line="${line%%<<*}"
      in_heredoc=1
    fi
    line=$(printf '%s' "$line" | sed "s/'[^']*'//g" | sed -E 's/"([^"\\]|\\.)*"//g')
    result+="${line}"$'\n'
  done <<<"$cmd"
  printf '%s' "${result%$'\n'}"
}

# Privacy-safe telemetry subject: `Bash:<first-token>` with leading `sudo` /
# env-assignment prefixes stripped and the token basenamed. Never the full
# command.
bash_subject() {
  local cmd="$1" tok
  tok="${cmd%%[[:space:]]*}"
  while [[ "$tok" == "sudo" || "$tok" == *=* ]] \
    && [[ -n "$cmd" && "$cmd" == *[[:space:]]* ]]; do
    cmd="${cmd#*[[:space:]]}"
    cmd="${cmd#"${cmd%%[![:space:]]*}"}"
    tok="${cmd%%[[:space:]]*}"
  done
  printf 'Bash:%s' "${tok##*/}"
}

SUBJECT=$(bash_subject "$COMMAND")

# Emit one telemetry envelope: $1 status, $2 form ("" when not blocked). Gated
# on the high-res start stamp and the opt-in sink, so the unwired default path
# spawns no telemetry-only subprocess.
emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local data
  data=$(jq -n --arg subject "$SUBJECT" --arg form "$2" \
    '{tool:"Bash",subject:$subject,form:$form}' 2>/dev/null) || data='{"tool":"Bash","subject":"","form":""}'
  hook::emit_telemetry "block-no-verify" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

block() {
  local form="$1" msg1="$2" msg2="$3"
  echo "$msg1" >&2
  echo "$msg2" >&2
  emit_tel "blocked" "$form"
  exit 2
}

EXECUTABLE=$(strip_literals "$COMMAND")
COMMAND_LC="${EXECUTABLE,,}"

# Form 1: --no-verify / -n on git commit (word-boundaried git token)
if [[ "$COMMAND_LC" =~ (^|[[:space:];|&()]+)git[[:space:]]+commit([[:space:]]|-|$) ]]; then
  if [[ "$EXECUTABLE" == *"--no-verify"* ]] \
    || [[ "$EXECUTABLE" =~ (^|[[:space:];|&()]+)git[[:space:]]+commit.*[[:space:]]+-[a-zA-Z]*n([[:space:]]|$) ]]; then
    block "no-verify" \
      "BLOCKED: --no-verify / -n flags are not allowed with git commit." \
      "Fix the issues that caused the hook failure instead of bypassing."
  fi
fi

# Form 1b: core.hooksPath assignment bypasses all git hooks.
if [[ "$COMMAND_LC" =~ core\.hookspath= ]] \
  && [[ "$COMMAND_LC" =~ (^|[[:space:];|&()]+)git[[:space:]]+ ]] \
  && [[ "$COMMAND_LC" =~ (^|[[:space:];|&()]+)git[[:space:]]+.*[[:space:]]+(commit|push)([[:space:]]|-|$) ]]; then
  block "hooksPath" \
    "BLOCKED: core.hooksPath assignment is not allowed with git commit/push." \
    "Fix the hook failure instead of bypassing git hooks."
fi

# Form 2: hook-manager env-var bypass on git commit OR git push.
# Matches LEFTHOOK=0, LEFTHOOK=false (any case), and LEFTHOOK_*=0|false
# prefixes. The env var must combine with a git commit/push to fire — a bare
# `LEFTHOOK=0 echo foo` is not blocked.
if [[ "$COMMAND_LC" =~ (^|[[:space:];|&()]+)git[[:space:]]+(commit|push)([[:space:]]|-|$) ]]; then
  if [[ "$COMMAND_LC" =~ lefthook[_a-z]*=(0|false)([[:space:]]|$) ]]; then
    block "hook-manager-env" \
      "BLOCKED: hook-manager env-var bypass is not allowed with git commit/push." \
      "Fix the hook lane failure instead of bypassing."
  fi
fi

emit_tel "ok" ""
exit 0
