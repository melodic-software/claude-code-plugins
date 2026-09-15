# shellcheck shell=bash
# Python-floor interpreter probe for this plugin's arming hook and its bash test
# wrappers (sourceable; not invoked directly).
#
# Library only: no top-level execution, no exits, no output of its own. Each
# caller keeps its own `Exit:` taxonomy and its own skip wording, which differ
# per script by design; only the probe is shared. The helper writes into a
# caller-named variable rather than printing, so a call costs no subshell and a
# bare invocation keeps the caller's errexit in force. The write is
# `printf -v "$1"`, not a `local -n` nameref: namerefs arrived in bash 4.3 and
# the arming hook runs in Claude Code's Bash-tool shell on every platform,
# which on macOS is the stock bash 3.2. Every local carries the
# `_python_probe_` prefix so a caller's chosen out-var name can never be
# shadowed by one of them.
#
#   python_probe::floor_interpreter_to <var>
#     Sets <var> to the first of python3, python that both exists and reports
#     version_info >= (3, 10), and leaves it empty when neither does. Presence
#     alone is not enough: a bare `python` may be older than the floor. Returns
#     0 either way, so the caller decides what an empty <var> means.

python_probe::floor_interpreter_to() {
  local _python_probe_candidate
  printf -v "$1" '%s' ""
  for _python_probe_candidate in python3 python; do
    if command -v "$_python_probe_candidate" >/dev/null 2>&1 &&
      "$_python_probe_candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; then
      printf -v "$1" '%s' "$_python_probe_candidate"
      return 0
    fi
  done
  return 0
}
