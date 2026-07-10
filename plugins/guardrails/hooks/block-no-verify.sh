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

# jq is required to parse the tool payload. Fail OPEN when it is absent, but make
# the degraded state visible rather than silently disabling the guard.
if ! command -v jq >/dev/null 2>&1; then
  echo "guardrails/block-no-verify: jq not found on PATH — guard disabled (install jq to enable)." >&2
  exit 0
fi

# Read inherited fd0 directly (bare cat) — NEVER `</dev/stdin`: on Windows Git
# Bash, CC spawns hooks with stdin = a Win32 pipe that `/dev/stdin` cannot
# resolve (ENOENT → silent no-op).
INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null | tr -d '\r')
[[ -n "$COMMAND" ]] || exit 0

# --- Argv-faithful command parser -------------------------------------------
# Shell quoting/escaping is removed before git parses argv, so quoting the git
# EXECUTABLE (`"git" commit …`), the SUBCOMMAND (`git "commit" …`), or the flag
# (`git commit "--no-verify"`, `git commit --no-\verify`) all defeat any regex
# over a flattened string. Parse the command the way the shell builds argv
# instead: split into top-level segments on UNQUOTED control operators, then
# tokenize each segment into argv words honoring '…', "…", and backslash escapes.

# Emit top-level segments (NUL-separated), split on unquoted ; & | ( ) ` and
# newline. An operator inside quotes does NOT split — so a quoted mention like
# `echo "a && git commit --no-verify"` stays one segment led by `echo`.
# shellcheck disable=SC1003  # '\' matches a literal backslash char, not a quote escape
emit_segments() {
  local s="$1" seg="" i len c nx in_s=0 in_d=0
  len=${#s}
  for ((i = 0; i < len; i++)); do
    c="${s:i:1}"
    if ((in_s)); then
      seg+="$c"
      [[ "$c" == "'" ]] && in_s=0
      continue
    fi
    if ((in_d)); then
      seg+="$c"
      if [[ "$c" == '\' ]]; then
        nx="${s:i+1:1}"
        seg+="$nx"
        ((i++))
      elif [[ "$c" == '"' ]]; then
        in_d=0
      fi
      continue
    fi
    case "$c" in
    "'")
      in_s=1
      seg+="$c"
      ;;
    '"')
      in_d=1
      seg+="$c"
      ;;
    '\')
      nx="${s:i+1:1}"
      seg+="$c$nx"
      ((i++))
      ;;
    ';' | '&' | '|' | '(' | ')' | '`' | $'\n')
      printf '%s\0' "$seg"
      seg=""
      ;;
    *) seg+="$c" ;;
    esac
  done
  printf '%s\0' "$seg"
}

# Tokenize a segment into argv words (NUL-separated), honoring '…', "…", and
# backslash escapes. Quoted whitespace stays WITHIN a word, so
# `-m "msg --no-verify"` yields the words `-m` and `msg --no-verify` (the flag
# text is inside the message value, not its own argv flag → not a bypass).
# shellcheck disable=SC1003  # '\' matches a literal backslash char, not a quote escape
argv_words() {
  local s="$1" word="" i len c nx in_s=0 in_d=0 have=0
  len=${#s}
  for ((i = 0; i < len; i++)); do
    c="${s:i:1}"
    if ((in_s)); then
      if [[ "$c" == "'" ]]; then in_s=0; else word+="$c"; fi
      continue
    fi
    if ((in_d)); then
      if [[ "$c" == '\' ]]; then
        nx="${s:i+1:1}"
        case "$nx" in
        '"' | '\' | '$' | '`')
          word+="$nx"
          ((i++))
          ;;
        *) word+="$c" ;;
        esac
      elif [[ "$c" == '"' ]]; then
        in_d=0
      else
        word+="$c"
      fi
      continue
    fi
    case "$c" in
    "'")
      in_s=1
      have=1
      ;;
    '"')
      in_d=1
      have=1
      ;;
    '\')
      nx="${s:i+1:1}"
      word+="$nx"
      ((i++))
      have=1
      ;;
    ' ' | $'\t')
      if ((have)); then
        printf '%s\0' "$word"
        word=""
        have=0
      fi
      ;;
    *)
      word+="$c"
      have=1
      ;;
    esac
  done
  ((have)) && printf '%s\0' "$word"
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

# Walk each top-level segment. A segment is a bypass only when its ARGV
# executable basenames to `git` AND its subcommand is `commit`/`push` — resolved
# from real argv words, so quoting the git or commit token no longer evades the
# gate, while a quoted mention in a non-git segment (echo "git commit
# --no-verify") never fires (its executable word is `echo`).
process_command() {
  local -a segs=()
  mapfile -d '' -t segs < <(emit_segments "$COMMAND")

  local s
  for s in "${segs[@]}"; do
    local -a w=()
    mapfile -d '' -t w < <(argv_words "$s")
    ((${#w[@]})) || continue

    # Skip env-assignment + wrapper prefixes to reach the executable word.
    # Env-assignment words are remembered for the hook-manager test.
    local idx=0 tok
    local -a envs=()
    while ((idx < ${#w[@]})); do
      tok="${w[idx]}"
      case "$tok" in
      sudo | env | command | time | exec | xargs)
        ((idx++))
        continue
        ;;
      *) ;;
      esac
      if [[ "$tok" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
        envs+=("$tok")
        ((idx++))
        continue
      fi
      break
    done
    ((idx < ${#w[@]})) || continue

    local bin="${w[idx]##*/}"
    [[ "$bin" == "git" ]] || continue

    # Resolve the subcommand: skip git global options after the bin. `-c`
    # consumes the next word (its k=v value); other options are single words.
    local j=$((idx + 1)) sub="" gw
    while ((j < ${#w[@]})); do
      gw="${w[j]}"
      case "$gw" in
      -c)
        ((j += 2))
        continue
        ;;
      -*)
        ((j++))
        continue
        ;;
      *)
        sub="$gw"
        break
        ;;
      esac
    done
    [[ "$sub" == "commit" || "$sub" == "push" ]] || continue

    # Real `git commit` / `git push`. Run the bypass tests over this segment's
    # argv words (env prefixes + command words).
    local x lc

    # Form 2: hook-manager env-var prefix (commit OR push).
    for x in "${envs[@]}"; do
      lc="${x,,}"
      if [[ "$lc" =~ ^lefthook[_a-z0-9]*=(0|false)$ ]]; then
        block "hook-manager-env" \
          "BLOCKED: hook-manager env-var bypass is not allowed with git commit/push." \
          "Fix the hook lane failure instead of bypassing."
      fi
    done

    # Form 1b: core.hooksPath assignment (commit OR push).
    for ((j = idx + 1; j < ${#w[@]}; j++)); do
      lc="${w[j],,}"
      [[ "$lc" == *core.hookspath=* ]] && block "hooksPath" \
        "BLOCKED: core.hooksPath assignment is not allowed with git commit/push." \
        "Fix the hook failure instead of bypassing git hooks."
    done

    # Form 1: --no-verify / -n (commit only). Test argv words for equality — a
    # `--no-verify` inside a quoted -m value is a single value word, not a flag.
    if [[ "$sub" == "commit" ]]; then
      for ((j = idx + 1; j < ${#w[@]}; j++)); do
        x="${w[j]}"
        if [[ "$x" == "--no-verify" ]] \
          || { [[ "$x" != --* ]] && [[ "$x" =~ ^-[A-Za-z]*n$ ]]; }; then
          block "no-verify" \
            "BLOCKED: --no-verify / -n flags are not allowed with git commit." \
            "Fix the issues that caused the hook failure instead of bypassing."
        fi
      done
    fi
  done
}

process_command

emit_tel "ok" ""
exit 0
