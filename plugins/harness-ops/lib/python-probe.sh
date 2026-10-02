# shellcheck shell=bash
# Python-floor interpreter probe for this plugin's test wrappers (sourceable;
# not invoked directly).
#
# Library only: no top-level execution, no exits, no output of its own. Each
# wrapper keeps its own `Exit:` taxonomy and its own message wording, which
# differ per script by design; only the probe is shared. Value-producing
# helpers write into a caller-named variable rather than print, so a call costs
# no subshell and a bare invocation keeps the caller's errexit in force. Every
# local carries the `_python_probe_` prefix: a nameref resolves its target in
# the scope where it is USED, so an unprefixed local sharing the caller's chosen
# out-var name would shadow that caller's variable for the rest of the call.
#
#   python_probe::floor_to <var> <engine>
#     Reads MIN_PYTHON out of <engine> into <var> as "major.minor", so the floor
#     has one origin and a bump cannot desync a wrapper from its engine. Leaves
#     <var> empty when <engine> declares no parseable MIN_PYTHON; the caller
#     decides what that means. Call it bare: under errexit an unreadable engine
#     stays fatal.
#
#   python_probe::interpreter_to <var>
#     Sets <var> to the first of python3, python that exists, empty when neither
#     does. Presence only, so a caller can tell "no interpreter" from "below the
#     floor".
#
#   python_probe::floor_met_to <var> <interpreter> <floor>
#     Sets <var> to "yes" when <interpreter> is at or above <floor>, empty
#     otherwise. Redirect the call itself to silence a broken interpreter.

python_probe::floor_to() {
  local -n _python_probe_floor="$1"
  _python_probe_floor="$(sed -n 's/^MIN_PYTHON = (\([0-9]*\), \([0-9]*\)).*/\1.\2/p' "$2")"
}

python_probe::interpreter_to() {
  local -n _python_probe_interpreter="$1"
  local _python_probe_candidate
  _python_probe_interpreter=""
  for _python_probe_candidate in python3 python; do
    if command -v "$_python_probe_candidate" >/dev/null 2>&1; then
      _python_probe_interpreter="$_python_probe_candidate"
      return 0
    fi
  done
}

python_probe::floor_met_to() {
  local -n _python_probe_met="$1"
  if "$2" -c "import sys; floor = tuple(int(p) for p in '$3'.split('.')); raise SystemExit(0 if sys.version_info >= floor else 1)"; then
    _python_probe_met=yes
  else
    _python_probe_met=""
  fi
}
