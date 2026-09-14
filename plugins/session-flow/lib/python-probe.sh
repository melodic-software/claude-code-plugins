# shellcheck shell=bash
# Python-floor interpreter probe for this plugin's arming hook and its bash test
# wrappers (sourceable; not invoked directly).
#
# Library only: no top-level execution, no exits, no output of its own. Each
# caller keeps its own `Exit:` taxonomy and its own skip wording, which differ
# per script by design; only the probe is shared. The helper writes into a
# caller-named variable rather than printing, so a call costs no subshell and a
# bare invocation keeps the caller's errexit in force. Every local carries the
# `_python_probe_` prefix: a nameref resolves its target in the scope where it is
# USED, so an unprefixed local sharing the caller's chosen out-var name would
# shadow that caller's variable for the rest of the call.
#
#   python_probe::floor_interpreter_to <var>
#     Sets <var> to the first of python3, python that both exists and reports
#     version_info >= (3, 10), and leaves it empty when neither does. Presence
#     alone is not enough: a bare `python` may be older than the floor. Returns
#     0 either way, so the caller decides what an empty <var> means.

python_probe::floor_interpreter_to() {
  local -n _python_probe_interpreter="$1"
  local _python_probe_candidate
  _python_probe_interpreter=""
  for _python_probe_candidate in python3 python; do
    if command -v "$_python_probe_candidate" >/dev/null 2>&1 &&
      "$_python_probe_candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; then
      _python_probe_interpreter="$_python_probe_candidate"
      return 0
    fi
  done
  return 0
}
