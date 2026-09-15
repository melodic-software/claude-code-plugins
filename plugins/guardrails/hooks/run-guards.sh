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
# hook library, and eight jq spawns per Bash tool call. This runs them as one
# process, and on the common payload that process spawns nothing at all.
#
# HOW A GUARD RUNS UNCHANGED INSIDE ONE PROCESS
#
#   * stdin is read and validated ONCE (hook::buffer_stdin), then every guard's
#     own `hook::buffer_stdin` call is answered from that buffer with the same
#     return code the guard would have seen on its own (0 payload, 1 empty,
#     2 stalled/malformed), so each guard's fail-open / fail-closed posture on
#     bad stdin is exercised exactly as when it runs alone.
#   * The payload fields the guards read (`.tool_input.command`, `.tool_name`,
#     `.cwd`, the Write/Edit content fields, ...) are extracted ONCE, by the
#     library's builtin parser when it can prove the answer and by one jq
#     process otherwise; `hook::jq_fields` answers from that cache when every
#     requested filter is in it and the payload carried no NUL, and falls
#     through to the library's own hook::jq_fields_uncached otherwise. A
#     NUL-bearing payload therefore still reaches each guard's own NUL handling
#     through the real jq call.
#   * Each guard is `source`d in THIS shell, not in a subshell: on Windows Git
#     Bash every fork is a Win32 process creation, so eight command-substitution
#     subshells were eight processes per tool call. A sourced guard ends by
#     calling `exit`, which here is a shell function: it records the guard's
#     status and runs the NEXT guard from inside that call, so the chain never
#     returns into a guard that has exited. A guard that falls off its end
#     returns from `source` and is recorded the same way. Inside a real subshell
#     (`$(...)`, `( )`, a pipeline, `&`) the function sees a different BASHPID
#     and exits that subshell as the builtin would. Its `source hook-utils.sh`
#     returns at once on the library's double-source guard, so the overrides
#     stay in force; `BASH_SOURCE[0]` is the guard's own path, so sibling
#     libraries resolve as before. stderr passes straight through, unbuffered.
#   * A guard's stdout is a hook JSON document, and every document a guard
#     emits goes through hook::emit_document (hook::emit_channels included).
#     That one function is overridden here to collect the documents; nothing
#     is captured from the process's stdout. A guard that printed a document
#     with its own printf would bypass the collection: keep to the helper.
#   * A guard's abort boundary (abort-boundary.sh) still decides what a status
#     the guard did not choose means. When the guard ends through `exit` or by
#     falling off its end, guard::_abort_settle is applied to its status here,
#     and the notice document it builds joins the collected output. When the
#     guard dies of a hard error (an unbound variable under `set -u`, a failed
#     `source`), the shell itself is exiting and bash runs the guard's EXIT
#     trap, which is this file's handler: the same settle, and the guards that
#     have not run yet run in ONE subshell from inside that handler, because a
#     second hard error in a dying shell would end the process with no result.
#     That subshell reports its documents and status back on its stdout; a
#     further hard error there costs one more subshell, never the result.
#   * Guards share one process, so a guard's functions and globals remain
#     defined while the later guards run, and a guard that exits from inside a
#     function leaves that function's locals visible to them. Every guard
#     assigns what it reads before it reads it; a guard must not read a global
#     it did not set expecting it unset.
#
# AGGREGATION (the one deliberate delta from N separate hooks)
#
#   * Exit: 2 if any guard exited 2 (block); else the highest non-zero code any
#     guard returned; else 0. Every guard runs even after one has blocked, so a
#     command that trips two guards still shows both reasons, as it did when
#     the guards were separate hooks.
#   * stdout: one emitter passes through verbatim. Several are merged into one
#     document (contexts joined by a blank line) because Claude Code reads
#     exactly one JSON document per hook process; as separate hooks each
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

# Do NOT define a function named `dirname`. A function of that name would be
# inherited by every guard sourced below and shadow the real command, with an
# answer that diverges from GNU for `/foo` (empty, not `/`) and for `/a/b//`
# (`/a/b`, not `/a`). Each guard's own `dirname` therefore stays the real one.
#
# The dispatcher's own directory is derived with parameter expansion rather than
# `dirname` or `$(helper)`. GNU Bash forks a subshell for every command
# substitution even when the body is only builtins (Command Substitution, Bash
# Reference Manual; https://mywiki.wooledge.org/CommandSubstitution). On Windows
# Git Bash that fork is a process. `${BASH_SOURCE[0]%/*}` equals `dirname`
# for every shape BASH_SOURCE takes; the fallback covers a bare filename, where
# the strip is a no-op and dirname answers `.`. Claude Code (and this suite)
# invoke with an absolute path, so the strip is already absolute; `cd && pwd`
# is kept only for a relative spelling.
_RG_DIR="${BASH_SOURCE[0]%/*}"
[[ "$_RG_DIR" == "${BASH_SOURCE[0]}" ]] && _RG_DIR=.
# shellcheck source=abort-boundary.sh
source "$_RG_DIR/abort-boundary.sh"
# Could-not-run posture (#3528): fail-open with a visible notice. This covers
# the dispatcher's own code, before and after the guards: stdin, the field
# priming, the classifier load, the merge. An abort here would otherwise skip
# EVERY guard of the event with a bare status and no line of its own. The
# event is filled in once the payload is read (it names the additionalContext
# block; until then the notice is systemMessage only), and the trap is
# released right before the deliberate aggregated exit, so a non-block status
# a guard returned still surfaces exactly as it did.
guard::abort_boundary run-guards "" open 0 2
# shellcheck source=hook-utils.sh
source "$_RG_DIR/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it

case "$_RG_DIR" in
/* | ?:[/\\]*) HOOK_DIR="$_RG_DIR" ;;
*) HOOK_DIR="$(cd "$_RG_DIR" && pwd)" ;;
esac

GUARDS=()
LIBS=()
while (($#)); do
  case "$1" in
  --lib)
    # A library several guards source (the PowerShell classifier). Collect
    # the path now; the parse itself waits until tool_name is known. On a
    # Bash payload the classifier's first real statement is
    # `[[ "$tool" == "PowerShell" ]] || return 0`, so loading ~41 KB here
    # was a pure tax on the common path. The include guard still makes every
    # later `source` a no-op, so the parse is paid once per PowerShell fire.
    LIBS+=("$2")
    shift 2
    ;;
  *)
    GUARDS+=("$1")
    shift
    ;;
  esac
done
((${#GUARDS[@]})) || exit 0

# --- stdin once, fields once --------------------------------------------------
RUN_GUARDS_PRIMED=0
declare -A RUN_GUARDS_FIELD=()
# The union of every field the guards of this plugin declared in
# hooks/guard-requires.sh, which is where a guard states what it consumes.
# This array is that declaration's PROJECTION, not a second opinion about it:
# run-guards.test.sh derives the union from the declaration and fails when the
# two disagree, in either direction.
#
# Both directions cost. The cached hook::jq_fields below is all-or-nothing per
# call, so ONE declared field missing here sends every call of that lane to an
# uncached extraction — `.tool_input.path` (the GitHub MCP write lane's file
# path) was measured doing exactly that, two extra spawns per Write/Edit,
# 50 ms to 60 ms on the reference host. A field here that no guard declares is
# the opposite: parse work on every payload of every lane that nothing reads.
PRIME_FILTERS=(
  '.tool_input.command' '.tool_name' '.cwd'
  '.tool_input.file_path' '.tool_input.notebook_path' '.tool_input.path'
  '.tool_input.content' '.tool_input.new_string' '.tool_input.new_source'
  '.hook_event_name'
)

# Fused capture: GNU Bash forks a subshell for INPUT=$(hook::buffer_stdin)
# even when the body is builtins (Command Substitution;
# https://mywiki.wooledge.org/CommandSubstitution). Passing PRIME_FILTERS
# makes the completeness check and the field extract one step: the library's
# builtin parser on the common payload, one jq process on one it cannot prove.
#
# Dest is initialized here so ShellCheck SC2154 sees the assignment.
# printf -v through a nameref inside hook::buffer_stdin_to is a dynamic
# assignment the checker does not track
# (https://www.shellcheck.net/wiki/SC2154, Exceptions: "explicitly
# initialize/declare it with var="" or declare var").
RUN_GUARDS_INPUT=""
RUN_GUARDS_STDIN_RC=0
hook::buffer_stdin_to RUN_GUARDS_INPUT "${PRIME_FILTERS[@]}" || RUN_GUARDS_STDIN_RC=$?
# Nothing arrived: every guard would take its empty-stdin skip. Take it once.
((RUN_GUARDS_STDIN_RC == 1)) && exit 0
# The payload was cut short at EOF (rc 3): a transport fault, so every guard
# would skip with the same notice. Say it once and stop. The event name is
# not known here (this dispatcher is wired under PreToolUse and PostToolUse
# alike), so the notice goes out on systemMessage and stderr only; a guard
# run alone adds the agent channel itself. This exit precedes every guard,
# which is why the lib keeps rc 3 to the early-EOF arm only: a stall on the
# same prefix is rc 2, falls through here, and every blocking guard denies
# on it.
if ((RUN_GUARDS_STDIN_RC == 3)); then
  hook::stdin_cut_short_notice "" "guardrails"
  exit 0
fi

# shellcheck disable=SC2329  # invoked by every guard sourced below
hook::buffer_stdin() {
  ((RUN_GUARDS_STDIN_RC == 0)) || return "$RUN_GUARDS_STDIN_RC"
  printf '%s' "$RUN_GUARDS_INPUT"
}

# shellcheck disable=SC2329  # invoked by every guard sourced below
hook::buffer_stdin_to() {
  # `__rg_dest`, not `dest`: an unprefixed local would collide with a guard
  # that called `hook::buffer_stdin_to dest` and `printf -v` would write
  # this frame's local, return 0, and leave the guard's dest unset
  # (the `_to` helper convention at lib/hook-utils.sh).
  local __rg_dest="$1"
  ((RUN_GUARDS_STDIN_RC == 0)) || return "$RUN_GUARDS_STDIN_RC"
  printf -v "$__rg_dest" '%s' "$RUN_GUARDS_INPUT"
}

if ((RUN_GUARDS_STDIN_RC == 0)) &&
  ((${#HOOK_JQ_FIELDS[@]} == ${#PRIME_FILTERS[@]})) &&
  ((HOOK_JQ_FIELDS_NUL == 0)); then
  RUN_GUARDS_PRIMED=1
  # The primed values are keyed by the FILTER that produced them, so every
  # later read is by name. A position is not a name: a filter added ahead of
  # another silently hands its neighbour's value to whatever read the index,
  # and nothing at run time says so. The dispatcher itself reads two of these
  # (`.tool_name` below, `.hook_event_name` here); abort-boundary.test.sh
  # inserts a filter ahead of them on a copy and checks both still resolve.
  for _rg_i in "${!PRIME_FILTERS[@]}"; do
    RUN_GUARDS_FIELD["${PRIME_FILTERS[_rg_i]}"]="${HOOK_JQ_FIELDS[_rg_i]}"
  done
  unset _rg_i
  # The event name rides in the same extraction and lets the dispatcher's own
  # abort notice name the event.
  [[ "${RUN_GUARDS_FIELD['.hook_event_name']-}" =~ ^[A-Za-z]+$ ]] &&
    _GAB_EVENT="${RUN_GUARDS_FIELD['.hook_event_name']}"
fi

# The cache in front of the library's extractor. The miss path is the
# library's own function under its second name, so nothing is copied here.
# shellcheck disable=SC2329  # invoked by every guard sourced below
hook::jq_fields() {
  local input="$1"
  shift
  (($#)) || return 1
  if ((RUN_GUARDS_PRIMED)) && [[ "$input" == "$RUN_GUARDS_INPUT" ]]; then
    local -a out=()
    local filter
    for filter in "$@"; do
      # `+x`, not a non-empty test: a primed field whose value is the empty
      # string is served, not treated as a miss.
      [[ -n "${RUN_GUARDS_FIELD[$filter]+x}" ]] || break
      out+=("${RUN_GUARDS_FIELD[$filter]}")
    done
    if ((${#out[@]} == $#)); then
      HOOK_JQ_FIELDS=("${out[@]}")
      HOOK_JQ_FIELDS_NUL=0
      return 0
    fi
  fi
  hook::jq_fields_uncached "$input" "$@"
}

# --- PowerShell classifier, once, and only on that tool -----------------------
# A Bash payload must not parse ps-command.sh at all; an unprimed payload still
# loads it so a PowerShell command whose field cache missed cannot reach a guard
# with `ps::` unbound.
#
# `--lib` in hooks.json is the wiring's cue that this event's guards declare a
# library at all, which keeps the Bash hot path at one array test and reads
# nothing. WHAT to load comes from each guard's own declaration in
# guard-requires.sh, satisfied here ONCE for the event; a guard run alone
# satisfies the same declaration itself through guard::require_libs, so a row
# that omits the cue costs a repeated load and never a verdict. A `--lib` path
# is loaded as well, so an explicit argument still preloads a library no guard
# declared.
_rg_tool="${RUN_GUARDS_FIELD['.tool_name']-}"
if ((${#LIBS[@]})) && [[ "$_rg_tool" != "Bash" ]]; then
  # shellcheck source=guard-requires.sh
  source "$_RG_DIR/guard-requires.sh"
  for _rg_guard in "${GUARDS[@]}"; do
    guard::require_libs "${_rg_guard##*/}"
  done
  unset _rg_guard
  for _rg_lib in "${LIBS[@]}"; do
    guard::require_lib "$_rg_lib"
  done
  unset _rg_lib
fi
unset _rg_tool

# --- run ----------------------------------------------------------------------
RC=0
OUTS=()
# The guard being run: an index into GUARDS, or -1 while the dispatcher's own
# code runs (before the first guard, and again from the merge onward). The
# EXIT-trap handler below reads it to tell a guard's hard error from the
# dispatcher's own abort.
RUN_GUARDS_CUR=-1
# The process the chain runs in. `exit` below compares BASHPID against it: a
# guard's `exit` inside a real subshell must end that subshell, not run the
# next guard there.
RUN_GUARDS_PID=$BASHPID
RUN_GUARDS_T0=""

# Every document a guard emits is collected, not printed (hook-utils.sh,
# hook::emit_document).
# shellcheck disable=SC2329  # invoked by every guard sourced below
hook::emit_document() {
  OUTS+=("$1")
}

# `exit` for the sourced guards. The status a guard exits with is recorded
# and the chain continues from inside this call, so control never returns to
# the guard. No argument means the status of the guard's last command, as the
# builtin does.
# shellcheck disable=SC2329  # invoked by every guard sourced below
exit() {
  local __rg_rc="${1:-$?}"
  [[ "$BASHPID" == "$RUN_GUARDS_PID" ]] || builtin exit "$__rg_rc"
  ((RUN_GUARDS_CUR >= 0)) || builtin exit "$__rg_rc"
  run_guards::guard_done "$__rg_rc"
}

# A guard died of a hard error: the shell is exiting, and the EXIT trap the
# guard installed through guard::abort_boundary handed the status here (the
# library's chain slot, _GAB_CONTINUE, set right before the first guard runs
# and cleared before the merge). A deliberate `exit` in a guard never comes
# this way; that is the function above. Never returns.
# shellcheck disable=SC2329  # invoked through _GAB_CONTINUE by the trap handler
run_guards::guard_died() {
  RUN_GUARDS_DYING=1
  run_guards::guard_done "$1"
}
RUN_GUARDS_DYING=0

# run_guards::record <rc>: the guard at RUN_GUARDS_CUR ended with <rc>. Applies
# its abort boundary (when it installed one: a stub that never called
# guard::abort_boundary keeps its raw status, as it did in its own subshell,
# which had no trap), collects the notice document, prints the profile line,
# and folds the status into RC.
run_guards::record() {
  local __rg_rc="$1" __rg_path="${GUARDS[RUN_GUARDS_CUR]}"
  if [[ -n "$_GAB_NAME" ]] && ! guard::_abort_settle "$__rg_rc"; then
    [[ -n "$_GAB_DOC" ]] && OUTS+=("$_GAB_DOC")
    __rg_rc=$_GAB_RC
  fi
  # RUN_GUARDS_PROFILE=1 prints one line per guard to stderr (ms, rc, name);
  # this is how the README's budget accounting is measured.
  if [[ -n "${RUN_GUARDS_PROFILE:-}" && -n "${EPOCHREALTIME:-}" && -n "$RUN_GUARDS_T0" ]]; then
    local __rg_t1=$EPOCHREALTIME
    printf 'run-guards: %5d ms rc=%d %s\n' "$(((${__rg_t1/./} - ${RUN_GUARDS_T0/./}) / 1000))" "$__rg_rc" "${__rg_path##*/}" >&2
  fi
  if ((__rg_rc == 2)); then
    RC=2
  elif ((__rg_rc != 0 && RC != 2 && __rg_rc > RC)); then
    RC=$__rg_rc
  fi
}

# run_guards::guard_done <rc>: record the guard that just ended and run the
# rest. Never returns.
run_guards::guard_done() {
  run_guards::record "$1"
  if ((RUN_GUARDS_DYING)); then
    run_guards::run_rest_in_subshell "$((RUN_GUARDS_CUR + 1))"
    run_guards::finish
  fi
  run_guards::run_from "$((RUN_GUARDS_CUR + 1))"
}

# run_guards::run_from <index>: run the guards from <index> on, then finish.
# Never returns: a guard's `exit` continues the chain from inside the call,
# and a guard that falls off its end is recorded right here.
run_guards::run_from() {
  local __rg_i
  for ((__rg_i = $1; __rg_i < ${#GUARDS[@]}; __rg_i++)); do
    RUN_GUARDS_CUR=$__rg_i
    local __rg_path
    case "${GUARDS[__rg_i]}" in
    */*) __rg_path="${GUARDS[__rg_i]}" ;;
    *) __rg_path="$HOOK_DIR/${GUARDS[__rg_i]}" ;;
    esac
    if [[ ! -f "$__rg_path" ]]; then
      echo "run-guards: guard not found: $__rg_path" >&2
      ((RC < 1)) && RC=1
      continue
    fi
    # The guard's own boundary sets this; a guard that never installs one is
    # recorded on its raw status.
    _GAB_NAME=""
    # A fresh hook process has no alias memo; the guard before this one may
    # have armed it on the same command, and a memo hit is "already analyzed".
    hook::reset_analysis_state
    RUN_GUARDS_T0=${EPOCHREALTIME:-}
    # shellcheck disable=SC1090
    source "$__rg_path" </dev/null
    run_guards::guard_done "$?"
  done
  run_guards::finish
}

# The remaining guards, from inside a dying shell's EXIT trap: one subshell,
# same chain, its collected documents and status reported on its stdout as
# <doc>RS ... RS<doc>RS RC=<n>. RS (0x1e) cannot occur inside a document (JSON
# escapes every control byte). Inside the subshell the chain is its own
# process, so RUN_GUARDS_PID moves with it and a further hard error there
# costs one more subshell from its own trap, never the result.
run_guards::run_rest_in_subshell() {
  local __rg_rest="" __rg_doc
  # shellcheck disable=SC2030  # the subshell's own OUTS and RC come back on its stdout
  __rg_rest=$(
    RUN_GUARDS_PID=$BASHPID
    RUN_GUARDS_DYING=0
    RUN_GUARDS_REPORT=1
    OUTS=()
    RC=0
    run_guards::run_from "$1"
  )
  while [[ "$__rg_rest" == *$'\x1e'* ]]; do
    __rg_doc=${__rg_rest%%$'\x1e'*}
    __rg_rest=${__rg_rest#*$'\x1e'}
    # shellcheck disable=SC2031  # this is the parent's OUTS, fed from the report
    OUTS+=("$__rg_doc")
  done
  if [[ "$__rg_rest" =~ ^RC=([0-9]+)$ ]]; then
    __rg_doc=${BASH_REMATCH[1]}
    if ((__rg_doc == 2)); then
      RC=2
    elif ((__rg_doc != 0 && RC != 2 && __rg_doc > RC)); then
      RC=$__rg_doc
    fi
  else
    echo "run-guards: the guards after a hard error reported no status; their verdict is lost" >&2
    ((RC < 1)) && RC=1
  fi
}
RUN_GUARDS_REPORT=0

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

# run_guards::finish: emit the aggregated result and exit. Never returns.
run_guards::finish() {
  RUN_GUARDS_CUR=-1
  _GAB_CONTINUE=""
  if ((RUN_GUARDS_REPORT)); then
    local __rg_doc
    for __rg_doc in ${OUTS[@]+"${OUTS[@]}"}; do
      printf '%s\x1e' "$__rg_doc"
    done
    printf 'RC=%d' "$RC"
    builtin exit 0
  fi
  # The dispatcher's own boundary again, for the merge below: the last guard's
  # boundary is what the trap holds at this point.
  guard::abort_boundary run-guards "$_GAB_EVENT" open 0 2
  if ((${#OUTS[@]} == 1)); then
    printf '%s\n' "${OUTS[0]}"
  elif ((${#OUTS[@]} > 1)); then
    if ! command -v jq >/dev/null 2>&1; then
      run_guards::emit_one "without jq"
    else
      local merged
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
  # The aggregated status is the dispatcher's deliberate answer, whatever number
  # it is (a guard-not-found 1 is already loud on stderr above; a stub's 3 is the
  # contract test's). Release the boundary so it is not reported as an abort.
  guard::abort_boundary_release
  builtin exit "$RC"
}

_GAB_CONTINUE=run_guards::guard_died
run_guards::run_from 0
