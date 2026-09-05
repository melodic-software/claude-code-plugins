#!/usr/bin/env bash
# Dispatcher: run several guardrails guards for ONE hook event inside ONE hook
# process, instead of registering each guard as its own always-on hook.
#
#   run-guards.sh [--lib <path-under-plugin-root>]... <guard-script>...
#
# Every guard named on the command line still ships as its own script with its
# own contract test, kill switch, and telemetry envelope; nothing about a guard's
# decision logic lives here. What this file owns is the per-event spawn shape
# (#1403, hook-budget convention): on this fleet the per-call cost that shows
# up as typing lag is process creation, not any one slow classifier. Eight
# always-on Bash guards meant eight bash processes, eight parses of the shared
# hook library, and eight jq spawns per Bash tool call. This runs them as one.
#
# HOW A GUARD RUNS UNCHANGED INSIDE ONE PROCESS
#
#   * stdin is read and validated ONCE (hook::buffer_stdin), then every guard's
#     own `hook::buffer_stdin` call is answered from that buffer with the same
#     return code the guard would have seen on its own (0 payload, 1 empty,
#     2 stalled/malformed), so each guard's fail-open / fail-closed posture on
#     bad stdin is exercised exactly as when it runs alone.
#   * The payload fields the guards read (`.tool_input.command`, `.tool_name`,
#     `.cwd`, the Write/Edit content fields, ...) are extracted with ONE jq
#     process; `hook::jq_fields` answers from that cache when every requested
#     filter is in it and the payload carried no NUL, and falls through to the
#     library's own jq path (byte-identical, saved under another name) otherwise.
#     A NUL-bearing payload therefore still reaches each guard's own NUL
#     handling through the real jq call.
#   * Each guard is `source`d in a command-substitution subshell. Its `exit`
#     ends that subshell only; its `source hook-utils.sh` returns at once on the
#     library's double-source guard, so the overrides above stay in force; its
#     `trap ... EXIT` runs at the subshell's exit; `BASH_SOURCE[0]` is the guard's
#     own path, so sibling libraries resolve as before. stdout is captured,
#     stderr passes straight through, unbuffered.
#
# AGGREGATION (the one deliberate delta from N separate hooks)
#
#   * Exit: 2 if any guard exited 2 (block); else the highest non-zero code any
#     guard returned; else 0. Every guard runs even after one has blocked, so a
#     command that trips two guards still shows both reasons, as it did when
#     the guards were separate hooks.
#   * stdout: a guard's stdout is a hook JSON document (`hookSpecificOutput` /
#     `systemMessage`). One emitter passes through verbatim. Several are merged
#     into one document (contexts joined by a blank line) because Claude Code
#     reads exactly one JSON document per hook process; as separate hooks each
#     document was delivered on its own. When jq is absent, or the merge fails,
#     the documents are never concatenated (two documents on stdout is invalid
#     hook output): the one carrying a blocking decision (`"decision":"block"`,
#     `"permissionDecision":"deny"`, then `"ask"`) is emitted, else the first,
#     and every dropped document is echoed to stderr with a `run-guards:`
#     prefix so it stays visible in debug output.
#
# The overrides are scoped to this process: a guard run directly (its tests,
# `bash hooks/<guard>.sh`) uses the library functions untouched.

set -uo pipefail

# `dirname` is an external program, and on Windows Git Bash one exec is ~80 ms.
# This helper answers the one argument shape used at the two call sites below
# (this file's own path) without the exec. It is deliberately NOT a function
# named `dirname`: a function of that name would be inherited by every guard
# sourced below and shadow the real command for the guard's own calls, with an
# answer that diverges from GNU for `/foo` (empty, not `/`) and for `/a/b//`
# (`/a/b`, not `/a`). Each guard's own `dirname` therefore stays the real one.
run_guards::script_dir() {
  local p="${1%/}"
  if [[ "$p" == */* ]]; then printf '%s\n' "${p%/*}"; else printf '.\n'; fi
}

# shellcheck source=hook-utils.sh
source "$(run_guards::script_dir "${BASH_SOURCE[0]}")/hook-utils.sh"

HOOK_DIR="$(cd "$(run_guards::script_dir "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$HOOK_DIR/.." && pwd)}"

GUARDS=()
while (($#)); do
  case "$1" in
  --lib)
    # A library several guards source (the PowerShell classifier). Its own
    # double-source guard makes every later `source` a no-op, so the parse is
    # paid once here instead of once per guard.
    # shellcheck disable=SC1090
    source "$PLUGIN_ROOT/$2"
    shift 2
    ;;
  *)
    GUARDS+=("$1")
    shift
    ;;
  esac
done
((${#GUARDS[@]})) || exit 0

# --- stdin once ---------------------------------------------------------------
RUN_GUARDS_STDIN_RC=0
RUN_GUARDS_INPUT=$(hook::buffer_stdin) || RUN_GUARDS_STDIN_RC=$?
# Nothing arrived: every guard would take its empty-stdin skip. Take it once.
((RUN_GUARDS_STDIN_RC == 1)) && exit 0

# shellcheck disable=SC2329  # invoked by every guard sourced below
hook::buffer_stdin() {
  ((RUN_GUARDS_STDIN_RC == 0)) || return "$RUN_GUARDS_STDIN_RC"
  printf '%s' "$RUN_GUARDS_INPUT"
}

# --- jq once ------------------------------------------------------------------
# Keep the library's implementation reachable under another name so the cache
# miss path is the library's own code, not a re-implementation of it.
eval "$(declare -f hook::jq_fields | sed '1s/^hook::jq_fields/hook::jq_fields_uncached/')"

RUN_GUARDS_PRIMED=0
RUN_GUARDS_FILTERS=()
RUN_GUARDS_VALUES=()
# Every field ANY registered guard asks for must be primed here. The cached
# hook::jq_fields below is all-or-nothing per call: one filter it cannot serve
# sends the whole call to an uncached jq spawn, so a guard that adds a field
# without adding it here costs a process on EVERY payload, not just the ones the
# field belongs to. `.tool_input.path` (the GitHub MCP write lane's file path,
# #3719) was measured doing exactly that — two extra spawns per Write/Edit,
# 50 ms to 60 ms on the reference host — before it was added.
PRIME_FILTERS=(
  '.tool_input.command' '.tool_name' '.cwd'
  '.tool_input.file_path' '.tool_input.notebook_path' '.tool_input.path'
  '.tool_input.content' '.tool_input.new_string' '.tool_input.new_source'
)
if ((RUN_GUARDS_STDIN_RC == 0)) && hook::jq_fields_uncached "$RUN_GUARDS_INPUT" "${PRIME_FILTERS[@]}" &&
  ((HOOK_JQ_FIELDS_NUL == 0)); then
  RUN_GUARDS_PRIMED=1
  RUN_GUARDS_FILTERS=("${PRIME_FILTERS[@]}")
  RUN_GUARDS_VALUES=("${HOOK_JQ_FIELDS[@]}")
fi

# shellcheck disable=SC2329  # invoked by every guard sourced below
hook::jq_fields() {
  local input="$1"
  shift
  (($#)) || return 1
  if ((RUN_GUARDS_PRIMED)) && [[ "$input" == "$RUN_GUARDS_INPUT" ]]; then
    local -a out=()
    local filter i hit
    for filter in "$@"; do
      hit=0
      for i in "${!RUN_GUARDS_FILTERS[@]}"; do
        if [[ "${RUN_GUARDS_FILTERS[i]}" == "$filter" ]]; then
          out+=("${RUN_GUARDS_VALUES[i]}")
          hit=1
          break
        fi
      done
      ((hit)) || break
    done
    if ((${#out[@]} == $#)); then
      HOOK_JQ_FIELDS=("${out[@]}")
      HOOK_JQ_FIELDS_NUL=0
      return 0
    fi
  fi
  hook::jq_fields_uncached "$input" "$@"
}

# --- run ----------------------------------------------------------------------
RC=0
OUTS=()
for guard in "${GUARDS[@]}"; do
  case "$guard" in
  */*) path="$guard" ;;
  *) path="$HOOK_DIR/$guard" ;;
  esac
  if [[ ! -f "$path" ]]; then
    echo "run-guards: guard not found: $path" >&2
    ((RC < 1)) && RC=1
    continue
  fi
  rc=0
  t0=${EPOCHREALTIME:-0}
  # shellcheck disable=SC1090
  guard_out=$(source "$path" </dev/null) || rc=$?
  # RUN_GUARDS_PROFILE=1 prints one line per guard to stderr (ms, rc, name);
  # this is how the README's budget accounting is measured.
  if [[ -n "${RUN_GUARDS_PROFILE:-}" && -n "${EPOCHREALTIME:-}" ]]; then
    t1=$EPOCHREALTIME
    printf 'run-guards: %5d ms rc=%d %s\n' "$(((${t1/./} - ${t0/./}) / 1000))" "$rc" "${path##*/}" >&2
  fi
  [[ -n "$guard_out" ]] && OUTS+=("$guard_out")
  if ((rc == 2)); then
    RC=2
  elif ((rc != 0 && RC != 2 && rc > RC)); then
    RC=$rc
  fi
done

# Several documents and no way to merge them: a hook process may emit exactly
# ONE JSON document, so pick one. A blocking decision must not be lost, so a
# document carrying `"decision":"block"` or `"permissionDecision":"deny"` wins,
# then one carrying `"permissionDecision":"ask"`, else the first document. The
# rest go to stderr, prefixed, so the drop is visible in debug output.
run_guards::emit_one() {
  local why="$1" pick=-1 i doc
  local re_block='"decision"[[:space:]]*:[[:space:]]*"block"'
  local re_deny='"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'
  local re_ask='"permissionDecision"[[:space:]]*:[[:space:]]*"ask"'
  for i in "${!OUTS[@]}"; do
    doc="${OUTS[i]}"
    if [[ "$doc" =~ $re_block || "$doc" =~ $re_deny ]]; then
      pick=$i
      break
    fi
    ((pick < 0)) && [[ "$doc" =~ $re_ask ]] && pick=$i
  done
  ((pick < 0)) && pick=0
  printf '%s\n' "${OUTS[pick]}"
  for i in "${!OUTS[@]}"; do
    ((i == pick)) && continue
    printf 'run-guards: dropped %s: %s\n' "$why" "${OUTS[i]}" >&2
  done
}

if ((${#OUTS[@]} == 1)); then
  printf '%s\n' "${OUTS[0]}"
elif ((${#OUTS[@]} > 1)); then
  if ! command -v jq >/dev/null 2>&1; then
    run_guards::emit_one "without jq"
  else
    merged=$(printf '%s\n' "${OUTS[@]}" | jq -cs '
      { hookSpecificOutput: {
          hookEventName: (map(.hookSpecificOutput.hookEventName // empty) | .[0] // ""),
          additionalContext: (map(.hookSpecificOutput.additionalContext // empty) | join("\n\n")) },
        systemMessage: (map(.systemMessage // empty) | join("\n\n")) }
      | if .systemMessage == "" then del(.systemMessage) else . end
      | if .hookSpecificOutput.additionalContext == "" then del(.hookSpecificOutput) else . end
      | if . == {} then empty else . end' 2>/dev/null)
    # The Windows jq build writes CRLF; a raw CR never belongs in a JSON document.
    merged="${merged//$'\r'/}"
    if [[ -n "$merged" ]]; then
      printf '%s\n' "$merged"
    else
      run_guards::emit_one "(merge failed)"
    fi
  fi
fi

exit "$RC"
