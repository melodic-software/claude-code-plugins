#!/usr/bin/env bash
# PreToolUse hook: block git hook-bypass attempts on git commit and git push.
# Triggered on Bash tool calls.
#
# Catches three bypass surfaces on a real `git commit` / `git push`:
#   1. --no-verify / -n on git commit (skips pre-commit + commit-msg hooks)
#      and --no-verify on git push (skips pre-push hook)
#   2. core.hooksPath assignment on git commit/push (disables all git hooks)
#   3. hook-manager env-var prefix (LEFTHOOK=0 / LEFTHOOK_*=0|false) on git
#      commit/push (disables the hook manager for one invocation)
#
# Detection is ARGV-GRAMMAR-FAITHFUL: the command is parsed the way the shell
# builds argv — top-level segments split on unquoted control operators, each
# tokenized into argv words honoring '…', "…", $'…' (ANSI-C), and backslash
# escapes — then a real git executable (basename `git`, case/.exe-folded on
# Windows) is found at the segment's command position — after leading env-var
# assignments and known wrappers (`env -i git …`, `nice git …`, `sudo -u x git …`
# are transparent) — its subcommand resolved
# past git global options (including arg-consuming ones like `-C <dir>`), and
# the bypass tokens matched on the parsed argv.
#
# SCOPE (documented residual): this is a static matcher over the literal
# command string. It does NOT evaluate shell variable / command substitution
# ($VAR, $(…), $IFS) — a determined author can construct an expansion-based
# bypass. It is a friction guard against accidental/casual bypass, not a
# sandbox. The ONLY supported deliberate bypass is the kill switch
# (HOOK_BLOCK_NO_VERIFY_ENABLED=false).
#
# BLOCKING: exits 2 on any detected bypass form.

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

# Above this length the command is not parsed — a pathologically long command is
# assumed to be obfuscation and blocked FAIL-CLOSED (generous cap; real git
# commands are well under it). The linear parser keeps normal commands cheap.
MAX_COMMAND_LEN=16384

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

# Does an argv word name the git executable? Basename compared exactly on POSIX;
# on Windows/MSYS also case-folded and `.exe`-stripped (mirrors the OS-gate in
# hook-utils normalize_path) so `GIT` / `git.exe` are caught there but a
# case-variant stays distinct on a case-sensitive POSIX filesystem.
is_git_bin() {
  local b="${1##*/}"
  b="${b##*\\}"
  case "${OSTYPE:-}" in
  msys* | cygwin* | win32)
    local lc="${b,,}"
    lc="${lc%.exe}"
    [[ "$lc" == "git" ]]
    ;;
  *) [[ "$b" == "git" ]] ;;
  esac
}

# Decode an ANSI-C `$'…'` body to its literal bytes (\xHH, \NNN octal, \uHHHH,
# \n, \\, …). %-escaped so the body can never act as a printf format specifier;
# `--` guards a body that begins with `-`. Errors are swallowed (fail-open on a
# malformed body — the raw text still flows through the caller unchanged).
ansi_c_decode() {
  local b="${1//%/%%}"
  # shellcheck disable=SC2059  # the body IS the format — that is how ANSI-C escapes decode; %-escaped above so it cannot inject a specifier
  printf -- "$b" 2>/dev/null
}

# Return the argv index of a real `git` executable at the segment's command
# position (after env-var prefixes and known wrappers), or return 1 when absent.
# shellcheck disable=SC1003  # '\' compares a literal backslash char, not a quote escape
resolve_git_index() {
  local -a w=("$@")
  local n=${#w[@]} i=0 tok

  while ((i < n)); do
    tok="${w[i]}"
    if [[ "$tok" == *=* ]]; then
      ((i++))
      continue
    fi

    case "${tok##*/}" in
    env)
      ((i++))
      while ((i < n)) && [[ "${w[i]}" == -* ]]; do
        case "${w[i]}" in
        -u | -C | --chdir) ((i += 2)) ;;
        -*) ((i++)) ;;
        *) ((i++)) ;;
        esac
      done
      continue
      ;;
    nice | nohup)
      ((i++))
      while ((i < n)) && [[ "${w[i]}" == -* ]]; do
        case "${w[i]}" in
        -n | --adjustment) ((i += 2)) ;;
        --adjustment=*) ((i++)) ;;
        -*) ((i++)) ;;
        *) break ;;
        esac
      done
      if ((i < n)) && [[ "${w[i]}" =~ ^-?[0-9]+$ ]]; then
        ((i++))
      fi
      continue
      ;;
    sudo)
      ((i++))
      while ((i < n)) && [[ "${w[i]}" == -* ]]; do
        case "${w[i]}" in
        -u | -g | -h | -p | -C | -D | -R | -T | --user | --group | --chdir) ((i += 2)) ;;
        -*) ((i++)) ;;
        *) ((i++)) ;;
        esac
      done
      continue
      ;;
    timeout)
      ((i++))
      while ((i < n)) && [[ "${w[i]}" == -* ]]; do
        case "${w[i]}" in
        -s | --signal | -k | --kill-after) ((i += 2)) ;;
        --preserve-status | --foreground | --verbose) ((i++)) ;;
        -*) ((i++)) ;;
        *) break ;;
        esac
      done
      if ((i < n)) && [[ "${w[i]}" =~ ^[0-9]+([.][0-9]+)?(s|m|h|d)?$ ]]; then
        ((i++))
      fi
      continue
      ;;
    command | exec | builtin | !)
      ((i++))
      continue
      ;;
    time)
      ((i++))
      if ((i < n)) && [[ "${w[i]}" == "-p" ]]; then
        ((i++))
      fi
      continue
      ;;
    if | while | until | for | case | select | coproc | '{' | '}')
      ((i++))
      continue
      ;;
    *)
      if is_git_bin "$tok"; then
        echo "$i"
        return 0
      fi
      return 1
      ;;
    esac
  done
  return 1
}

# Inspect one already-tokenized segment (its argv words passed as "$@"). Blocks
# when the segment is a real `git commit`/`git push` carrying a bypass token.
# shellcheck disable=SC1003  # '\' compares a literal backslash char, not a quote escape
check_segment() {
  local -a w=("$@")
  local nseg=${#w[@]} gi j k x lc ch rest sub sub_idx gw

  gi=$(resolve_git_index "${w[@]}") || return 0

  # Resolve the subcommand: walk words after the git executable, skipping git
  # global options. The listed options consume the FOLLOWING word as their
  # value (two-word form); their =-forms and every other option are single
  # words handled by the generic `-*` skip. core.hooksPath is checked only on
  # git config arguments (-c/--config/--config-env), not commit messages or
  # pathspecs.
  sub=""
  sub_idx=-1
  j=$((gi + 1))
  while ((j < nseg)); do
    gw="${w[j]}"
    case "$gw" in
    -c | --config | --config-env)
      if ((j + 1 < nseg)); then
        lc="${w[j + 1],,}"
        [[ "$lc" == *core.hookspath=* ]] && block "hooksPath" \
          "BLOCKED: core.hooksPath assignment is not allowed with git commit/push." \
          "Fix the hook failure instead of bypassing git hooks."
      fi
      ((j += 2))
      ;;
    --config=*|--config-env=*)
      lc="${gw#*=}"
      lc="${lc,,}"
      [[ "$lc" == *core.hookspath=* ]] && block "hooksPath" \
        "BLOCKED: core.hooksPath assignment is not allowed with git commit/push." \
        "Fix the hook failure instead of bypassing git hooks."
      ((j++))
      ;;
    -C | --git-dir | --work-tree | --namespace | --super-prefix | --attr-source | --exec-path)
      ((j += 2))
      ;;
    -*)
      ((j++))
      ;;
    *)
      sub="$gw"
      sub_idx=$j
      break
      ;;
    esac
  done
  [[ "$sub" == "commit" || "$sub" == "push" ]] || return 0

  # Form 2: hook-manager env-var prefix (commit OR push) — only leading env
  # assignments before the git executable (not commit messages or pathspecs).
  for ((k = 0; k < gi; k++)); do
    lc="${w[k],,}"
    [[ "$lc" =~ ^lefthook[_a-z0-9]*=(0|false)$ ]] && block "hook-manager-env" \
      "BLOCKED: hook-manager env-var bypass is not allowed with git commit/push." \
      "Fix the hook lane failure instead of bypassing."
  done

  # Form 1: --no-verify / -n (commit or push) — words after the subcommand,
  # skipping values consumed by commit/push options (e.g. -m message text).
  # In a short-option bundle, `n` counts only when it precedes the first
  # argument-taking short (m/F/c/C/t/u/S/G) — so `-nm msg` blocks but `-mn`
  # (m takes value "n") does not.
  if [[ "$sub" == "commit" || "$sub" == "push" ]]; then
    k=$((sub_idx + 1))
    while ((k < nseg)); do
      x="${w[k]}"
      case "$x" in
      -m | --message | -F | --file | -t | --template | -c | -C | --author | --date)
        ((k += 2))
        continue
        ;;
      --message=* | --file=* | --template=* | --author=* | --date=*)
        ((k++))
        continue
        ;;
      esac
      [[ "$x" == "--no-verify" ]] && block "no-verify" \
        "BLOCKED: --no-verify / -n flags are not allowed with git $sub." \
        "Fix the issues that caused the hook failure instead of bypassing."
      if [[ "$sub" == "commit" && "$x" =~ ^-[A-Za-z]+$ ]]; then
        rest="${x#-}"
        for ((ch = 0; ch < ${#rest}; ch++)); do
          case "${rest:ch:1}" in
          n) block "no-verify" \
            "BLOCKED: --no-verify / -n flags are not allowed with git commit." \
            "Fix the issues that caused the hook failure instead of bypassing." ;;
          m | F | c | C | t | u | S | G)
            if ((ch + 1 < ${#rest})); then
              ((k++))
            elif ((k + 1 < nseg)); then
              ((k += 2))
            else
              ((k++))
            fi
            continue 2
            ;;
          *) ;;
          esac
        done
      fi
      ((k++))
    done
  fi

  return 0
}

# Single linear pass: read the command into a char array once (O(n)), then walk
# it splitting top-level segments on UNQUOTED control operators and tokenizing
# each segment into argv words honoring '…', "…", $'…', and backslash escapes
# (including backslash-newline continuation). Each completed segment is checked
# as it closes, so no full segment list is retained.
# shellcheck disable=SC1003  # '\' compares a literal backslash char, not a quote escape
parse_and_check() {
  local -a chars=()
  local c nx
  while IFS= read -rN1 c; do chars+=("$c"); done < <(printf '%s' "$COMMAND")
  local n=${#chars[@]} i
  local word="" have=0
  local -a seg=()

  for ((i = 0; i < n; i++)); do
    c="${chars[i]}"
    case "$c" in
    "'")
      ((i++))
      while ((i < n)) && [[ "${chars[i]}" != "'" ]]; do
        word+="${chars[i]}"
        ((i++))
      done
      have=1
      ;;
    '"')
      ((i++))
      while ((i < n)) && [[ "${chars[i]}" != '"' ]]; do
        if [[ "${chars[i]}" == '\' ]] && ((i + 1 < n)); then
          nx="${chars[i + 1]}"
          case "$nx" in
          '"' | '\' | '$' | '`')
            word+="$nx"
            ((i += 2))
            continue
            ;;
          $'\n')
            ((i += 2))
            continue
            ;;
          *) ;;
          esac
        fi
        word+="${chars[i]}"
        ((i++))
      done
      have=1
      ;;
    '$')
      if ((i + 1 < n)) && [[ "${chars[i + 1]}" == "'" ]]; then
        i=$((i + 2))
        local body=""
        while ((i < n)) && [[ "${chars[i]}" != "'" ]]; do
          if [[ "${chars[i]}" == '\' ]] && ((i + 1 < n)); then
            body+="${chars[i]}${chars[i + 1]}"
            ((i += 2))
            continue
          fi
          body+="${chars[i]}"
          ((i++))
        done
        word+="$(ansi_c_decode "$body")"
        have=1
      else
        word+="$c"
        have=1
      fi
      ;;
    '\')
      if ((i + 1 < n)); then
        nx="${chars[i + 1]}"
        if [[ "$nx" == $'\n' ]]; then
          ((i++))
        else
          word+="$nx"
          ((i++))
          have=1
        fi
      else
        have=1
      fi
      ;;
    ' ' | $'\t')
      if ((have)); then
        seg+=("$word")
        word=""
        have=0
      fi
      ;;
    ';' | '&' | '|' | '(' | ')' | '`' | $'\n')
      if ((have)); then
        seg+=("$word")
        word=""
        have=0
      fi
      if ((${#seg[@]})); then
        check_segment "${seg[@]}"
        seg=()
      fi
      ;;
    *)
      word+="$c"
      have=1
      ;;
    esac
  done
  if ((have)); then seg+=("$word"); fi
  if ((${#seg[@]})); then check_segment "${seg[@]}"; fi
}

if ((${#COMMAND} > MAX_COMMAND_LEN)); then
  block "too-long" \
    "BLOCKED: command too long to parse safely (> $MAX_COMMAND_LEN chars)." \
    "Shorten the command, or set HOOK_BLOCK_NO_VERIFY_ENABLED=false to bypass."
fi

parse_and_check

emit_tel "ok" ""
exit 0
