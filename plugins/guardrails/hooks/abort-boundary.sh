# shellcheck shell=bash
# Abort boundary for the guardrails hooks (#3528). Sourced by every registered
# hook and by the dispatcher; never executed on its own.
#
# A hook has three outcomes, not two: allow (exit 0), block (exit 2, reason on
# stderr), and could-not-run. Before this file the third had no signal. A hook
# that died between its first line and its own final `exit` (an unbound
# variable under `set -u`, a helper that no longer exists, a `source` that
# failed) ended with whatever status the last command had, usually 1, and wrote
# nothing of its own. Claude Code treats any status other than 0 and 2 as a
# NON-BLOCKING error: the tool call proceeds, bash's one-line error goes to the
# debug log, and the transcript records "exit 1, stderr: (none)". A blocking
# guard enforced nothing and nobody was told. The boundary makes that outcome a
# deliberate one:
#
#   source "$_HOOK_SELF/abort-boundary.sh"
#   guard::abort_boundary <hook-name> <HookEventName> <open|closed> <chosen-status>...
#
# installs an EXIT trap that passes every CHOSEN status through untouched (the
# hook's own `exit 0` / `exit 2`, including the ones the shared helpers make on
# its behalf: hook::check_enabled, hook::require_jq, hook::require_jq_blocking)
# and treats any other status as "the guard did not run". For those it writes
# one line naming the hook and the status to stderr, and then applies the
# hook's declared posture:
#
#   open    exit 0, after emitting the same text as a hook JSON document on
#           stdout: `systemMessage` for the operator and `additionalContext`
#           for the agent, the two channels Claude Code reads when a hook exits
#           0 (stderr on exit 0 reaches only the debug log, see
#           docs/conventions/hook-observability/). The tool call proceeds, as
#           it did before, and the notice says it was not checked.
#   closed  exit 2 with the notice on stderr, the channel a blocking exit feeds
#           back to the agent. The tool call is denied.
#
# <HookEventName> is the event the hook is registered for (PreToolUse,
# PostToolUse); it names the `hookSpecificOutput` block. Pass an empty string
# when the event is not known at install time (the dispatcher serves both), and
# the notice carries `systemMessage` only.
#
# Why a trap and not `set -e`: errexit across the hook set would change
# behavior on every non-zero status a guard tests on purpose. The trap sees
# only the status the process actually terminates with.
#
# Handler discipline. `trap - EXIT` is the handler's first action so nothing it
# does can re-enter it. It uses builtins only, every variable it reads is set
# at install time, and it calls nothing from hook-utils.sh, because a failed
# `source hook-utils.sh` is one of the aborts it exists to report. A failure
# inside the handler ends the process once, with that failure's status, after
# the stderr line is already written.
#
# One EXIT trap per shell. Bash holds a single EXIT trap, so a hook that runs
# its own `trap ... EXIT` (or `trap - EXIT`) after the install line REPLACES
# this boundary and is back to the silent abort it exists to remove, with
# nothing at run time to say so. abort-boundary.test.sh fails on any `trap`
# naming EXIT in a registered hook or in a library it sources; this file is the
# only one allowed to touch it. No hook needs exit-time work today (each is
# builtins plus one jq read, nothing to clean up). The supported way for one
# that does is to chain through this library, not around it: fill the chain slot
# below (_GAB_CONTINUE) that guard::_abort_on_exit calls before it decides, the
# chained function under the same handler discipline (builtins only, never
# exits, never touches the trap), with a suite case beside the others, in the
# same change. A release on purpose goes through guard::abort_boundary_release.
#
# run-guards.sh is the one documented exception to that discipline, and it is
# an exception because it is not a hook's exit-time work: its
# run_guards::guard_died is the DISPATCHER settling a dead guard and then
# finishing the run the process still owes, so it forks a subshell for the
# guards left, spawns jq to merge their documents, and ends at `builtin exit`
# without returning. Nothing is left for the handler to decide, which is why
# the slot may swallow control here and nowhere else. Any other consumer keeps
# the discipline above: a chained function that RETURNS, so that
# guard::_abort_on_exit still settles the status and exits.
#
# Under run-guards.sh the guards are sourced into the dispatcher's own shell,
# and `exit` there is a function of the dispatcher's. A guard that ends through
# it, or by falling off its end, never reaches this trap: the dispatcher applies
# guard::_abort_settle to the status itself and merges the notice document with
# the other guards' output. The trap fires only for a guard that dies of a hard
# error, when the shell is exiting, and then hands the status to the chain slot
# below (_GAB_CONTINUE), which the dispatcher fills for the span of its guards.

[[ -n "${_GUARDRAILS_ABORT_BOUNDARY_LOADED:-}" ]] && return 0
readonly _GUARDRAILS_ABORT_BOUNDARY_LOADED=1

_GAB_NAME=""
_GAB_EVENT=""
_GAB_POSTURE="open"
_GAB_CHOSEN=" "

# guard::abort_boundary <hook-name> <HookEventName|""> <open|closed> <status>...
guard::abort_boundary() {
  _GAB_NAME="$1"
  _GAB_EVENT="$2"
  case "$3" in
  open | closed) _GAB_POSTURE="$3" ;;
  *)
    # A posture that is neither word is a defect in the hook's own prologue.
    # Say so and keep the status quo enforcement (fail-open) rather than
    # inventing a block the hook never declared.
    printf 'guardrails %s: abort boundary posture %q is not open or closed; using open\n' "$1" "$3" >&2
    _GAB_POSTURE="open"
    ;;
  esac
  shift 3
  _GAB_CHOSEN=" $* "
  trap guard::_abort_on_exit EXIT
}

# guard::abort_boundary_release: uninstall the trap. For a process whose final
# status is computed rather than written as a literal (the dispatcher's
# aggregated exit): release right before that deliberate `exit`, so a status
# reached on purpose is never reported as an abort.
guard::abort_boundary_release() {
  trap - EXIT
}

# JSON-escape $2 into the variable named by $1: backslash, double quote, and the
# three line-structure control bytes. The notice text is built from install-time
# literals and a status number, so nothing else can occur in it; the escape is
# here so a hook name or event containing a quote cannot break the document.
guard::_abort_json_escape_to() {
  local __gab_s="$2"
  __gab_s="${__gab_s//\\/\\\\}"
  __gab_s="${__gab_s//\"/\\\"}"
  __gab_s="${__gab_s//$'\n'/\\n}"
  __gab_s="${__gab_s//$'\r'/\\r}"
  __gab_s="${__gab_s//$'\t'/\\t}"
  printf -v "$1" '%s' "$__gab_s"
}

# The chain slot. run-guards.sh runs its guards inside its own process, so a
# guard that dies of a hard error takes the dispatcher's shell down with it
# and this handler is what runs. With a function name here the handler hands
# that guard's status to it instead of deciding the process's fate itself; the
# dispatcher settles the guard's boundary, runs the guards still owed, and
# exits on the aggregate. run-guards.sh is the one consumer that does not
# return from here, and the header above says why it may; a chained function
# that DOES return hands control back and the handler settles the status as
# documented there. Empty (every guard run alone), the handler decides as
# documented above.
_GAB_CONTINUE=""

guard::_abort_on_exit() {
  local rc=$?
  trap - EXIT
  if [[ -n "$_GAB_CONTINUE" ]]; then
    "$_GAB_CONTINUE" "$rc"
  fi
  guard::_abort_settle "$rc" && return 0
  [[ -n "$_GAB_DOC" ]] && printf '%s\n' "$_GAB_DOC"
  exit "$_GAB_RC"
}

# guard::_abort_settle <status>: the decision, apart from the exit. Returns 0
# when <status> is one the hook chose, and nothing else happens. Otherwise
# writes the notice line to stderr, leaves the stdout document (empty for the
# closed posture) in _GAB_DOC and the status the posture maps to in _GAB_RC,
# and returns 1. The trap handler above exits on those; run-guards.sh, which
# runs each guard in its own process, records them for that guard and carries
# on with the next.
_GAB_DOC=""
_GAB_RC=0
guard::_abort_settle() {
  local rc="$1"
  _GAB_DOC=""
  _GAB_RC=0
  [[ "$_GAB_CHOSEN" == *" $rc "* ]] && return 0
  local msg
  if [[ "$_GAB_POSTURE" == closed ]]; then
    msg="guardrails ${_GAB_NAME}: guard did not run (internal error, rc=${rc}); fail-closed: this tool call is denied because the guard could not check it. The failing line is on the hook's stderr."
    printf '%s\n' "$msg" >&2
    _GAB_RC=2
    return 1
  fi
  msg="guardrails ${_GAB_NAME}: guard did not run (internal error, rc=${rc}); fail-open: this tool call was not checked by this guard. The failing line is on the hook's stderr (claude --debug)."
  printf '%s\n' "$msg" >&2
  local esc ev
  guard::_abort_json_escape_to esc "$msg"
  if [[ -n "$_GAB_EVENT" ]]; then
    guard::_abort_json_escape_to ev "$_GAB_EVENT"
    _GAB_DOC='{"hookSpecificOutput":{"hookEventName":"'"$ev"'","additionalContext":"'"$esc"'"},"systemMessage":"'"$esc"'"}'
  else
    _GAB_DOC='{"systemMessage":"'"$esc"'"}'
  fi
  return 1
}
