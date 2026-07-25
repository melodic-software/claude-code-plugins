#!/usr/bin/env bash
# PreToolUse hook: block git hook-bypass attempts on git commit and git push.
# Triggered on Bash tool calls.
#
# Catches three bypass surfaces on a real `git commit` / `git push`:
#   1. --no-verify / -n on git commit (skips pre-commit + commit-msg hooks)
#      and --no-verify on git push (skips pre-push hook)
#   2. core.hooksPath assignment on git commit/push (disables all git hooks)
#   3. hook-manager env-var prefix (e.g. LEFTHOOK=0 / LEFTHOOK_*=0|false,
#      HUSKY=0) on git commit/push (disables the hook manager for one
#      invocation). The manager set is configurable via the
#      block_no_verify_hook_manager_prefixes userConfig; the default covers the
#      common managers so a consumer using a different one is not silently
#      unguarded.
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
# (block_no_verify_enabled userConfig option set to false).
#
# BLOCKING: exits 2 on any detected bypass form.

set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "BLOCK_NO_VERIFY"

# Bundled PowerShell-command classifier — the git guards are matched on both the
# Bash and the (opt-in) PowerShell tool, whose command arrives in the same
# tool_input.command field with PowerShell grammar. Resolved under the plugin
# root (CC sets CLAUDE_PLUGIN_ROOT; the BASH_SOURCE fallback keeps the contract
# tests working when it is unset).
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/powershell/ps-command.sh
source "$PLUGIN_ROOT/lib/powershell/ps-command.sh"

# High-res start stamp for the telemetry envelope. EPOCHREALTIME is Bash 5.0+;
# on older bash it is unset, so default to empty and skip telemetry (the block
# still fires). Referencing it bare under `set -u` would abort before exit.
start=${EPOCHREALTIME:-}

# hook::buffer_stdin encapsulates the Win32-pipe-safe bounded fd0 read. rc 1
# (empty stdin) skips like the empty-COMMAND guard below; rc 2 (read timed out
# before a complete payload) FAILS CLOSED — the guard cannot evaluate the tool
# call, and a silent skip would pass exactly the traffic this guard exists to
# stop. buffer_stdin already printed the BLOCKED reason to stderr. Buffering
# does not require jq (hook::buffer_stdin's own JSON-completeness check is
# jq-optional), so it runs before the jq gate below — hook::require_jq needs
# the buffered input for its once-per-session notice scoping.
INPUT=$(hook::buffer_stdin) || {
  rc=$?
  ((rc == 2)) && exit 2
  exit 0
}

# jq is required to parse the tool payload. hook::require_jq fails OPEN
# (advisory hooks never block over a missing prerequisite) but makes the
# degraded state visible to both the user (systemMessage) and the agent
# (additionalContext), once per session — see docs/conventions/hook-observability/.
hook::require_jq "PreToolUse" "guardrails-block-no-verify" "$INPUT"

hook::jq_fields "$INPUT" '.tool_name // "Bash"' '.tool_input.command // ""'
TOOL_NAME=${HOOK_JQ_FIELDS[0]}
COMMAND=${HOOK_JQ_FIELDS[1]}
[[ -n "$COMMAND" ]] || exit 0

# Above this length the command is not parsed — a pathologically long command is
# assumed to be obfuscation and blocked FAIL-CLOSED (generous cap; real git
# commands are well under it). The linear parser keeps normal commands cheap.
MAX_COMMAND_LEN=16384

SUBJECT=$(hook::extract_bash_subject "$TOOL_NAME" "$COMMAND")

# Hook-manager env-var disable prefixes, built once into a regex alternation.
# The default set covers the common managers; a consumer extends it via the
# block_no_verify_hook_manager_prefixes userConfig (comma-separated, read from
# the hook-process mirror). Each prefix matches `PREFIX…=0|false`
# (LEFTHOOK=0, HUSKY=0, LEFTHOOK_VERIFY=false, …). Entries are reduced to
# identifier chars so a value can never smuggle regex metacharacters into the
# alternation spliced below.
HM_ALT=""
IFS=',' read -ra _hm_list <<<"${CLAUDE_PLUGIN_OPTION_BLOCK_NO_VERIFY_HOOK_MANAGER_PREFIXES:-lefthook,husky,pre_commit,simple_git_hooks}"
for _hm in "${_hm_list[@]}"; do
  _hm="${_hm//[^a-zA-Z0-9_]/}"
  _hm="${_hm,,}"
  [[ -n "$_hm" ]] && HM_ALT="${HM_ALT:+$HM_ALT|}$_hm"
done
[[ -n "$HM_ALT" ]] || HM_ALT="lefthook" # never leave the guard patternless

# Emit one telemetry envelope: $1 status, $2 form ("" when not blocked). Gated
# on the high-res start stamp and the opt-in sink, so the unwired default path
# spawns no telemetry-only subprocess.
emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local data
  data=$(jq -n --arg tool "$TOOL_NAME" --arg subject "$SUBJECT" --arg form "$2" \
    '{tool:$tool,subject:$subject,form:$form}' 2>/dev/null) || data='{"tool":"Bash","subject":"","form":""}'
  hook::emit_telemetry "block-no-verify" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

block() {
  local form="$1" msg1="$2" msg2="$3"
  echo "$msg1" >&2
  echo "$msg2" >&2
  emit_tel "blocked" "$form"
  exit 2
}

# Inspect one already-tokenized segment (its argv words passed as "$@"). Blocks
# when the segment is a real `git commit`/`git push` carrying a bypass token.
# Parsing spine (tokenizer, git resolver, subcommand walk) lives in
# hook-utils.sh; only the bypass-form matching is this guard's own.
# shellcheck disable=SC1003  # '\' compares a literal backslash char, not a quote escape
# shellcheck disable=SC2329  # invoked indirectly as the hook::bash_parse_segments callback
check_segment() {
  local -a w=("$@")
  local nseg gi k x lc ch rest sub sub_idx cv

  # A shell -c wrapper (`bash -lc 'git commit --no-verify'`) executes its
  # operand as a full shell command — re-parse it with the same tokenizer so
  # the wrapped invocation is checked faithfully.
  if hook::shell_c_operand "$@"; then
    hook::bash_parse_segments "$HOOK_SHELL_C_OPERAND" check_segment
    return 0
  fi

  hook::git_resolve_index "${w[@]}" || return 0
  gi=$HOOK_GIT_RESOLVED_GI
  # env -S splicing may have rewritten the argv — match on the resolved words.
  w=("${HOOK_GIT_RESOLVED_WORDS[@]}")
  nseg=${#w[@]}

  # core.hooksPath is checked only on git config arguments (collected by the
  # subcommand walk from -c/--config/--config-env), never commit messages or
  # pathspecs. The check applies whether or not a subcommand was found — the
  # hooksPath block below still needs commit/push, so gate after.
  hook::git_resolve_subcommand "$gi" "${w[@]}" || return 0
  sub=$HOOK_GIT_SUB
  sub_idx=$HOOK_GIT_SUB_IDX
  [[ "$sub" == "commit" || "$sub" == "push" ]] || return 0

  for cv in ${HOOK_GIT_CONFIG_VALUES[@]+"${HOOK_GIT_CONFIG_VALUES[@]}"}; do
    lc="${cv,,}"
    [[ "$lc" == *core.hookspath=* ]] && block "hooksPath" \
      "BLOCKED: core.hooksPath assignment is not allowed with git commit/push." \
      "Fix the hook failure instead of bypassing git hooks."
  done

  # Form 2: hook-manager env-var prefix (commit OR push) — only leading env
  # assignments before the git executable (not commit messages or pathspecs).
  for ((k = 0; k < gi; k++)); do
    lc="${w[k],,}"
    [[ "$lc" =~ ^(${HM_ALT})[_a-z0-9]*=(0|false)$ ]] && block "hook-manager-env" \
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
      *) ;;
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

if ((${#COMMAND} > MAX_COMMAND_LEN)); then
  block "too-long" \
    "BLOCKED: command too long to parse safely (> $MAX_COMMAND_LEN chars)." \
    "Shorten the command, or set the guardrails block_no_verify_enabled option to false (/plugin configure) to bypass."
fi

# Reduce a PowerShell command to a Bash-tokenizer-faithful form, or fail closed.
# For the Bash tool this is a no-op (COMMAND unchanged).
ps::classify_git_command "$TOOL_NAME" "$COMMAND"
case $? in
2)
  ps::print_unparsable_block_message
  emit_tel "blocked" "powershell-unparsable"
  exit 2
  ;;
1) exit 0 ;; # non-commit PowerShell with an A2b-deferred construct — not this guard's proven surface
*) COMMAND="$PS_SAFE_COMMAND" ;;
esac

hook::bash_parse_segments "$COMMAND" check_segment

emit_tel "ok" ""
exit 0
