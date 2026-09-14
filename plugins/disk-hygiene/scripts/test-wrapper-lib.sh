# shellcheck shell=bash
# Shared pieces of this plugin's bash contract wrappers (sourceable; not invoked
# directly).
#
# Library only: no top-level execution, no exits, no output of its own. Each
# wrapper keeps its own `Exit:` taxonomy and its own skip wording, which differ
# per script by design, and the alias-stub probe keeps its own candidate ladder
# because it must inspect a candidate before executing it. Each helper writes
# into a caller-named variable rather than printing, so a call costs no subshell
# and a bare invocation keeps the caller's errexit in force. Every local carries
# the `_test_wrapper_` prefix: a nameref resolves its target in the scope where
# it is USED, so an unprefixed local sharing the caller's chosen out-var name
# would shadow that caller's variable for the rest of the call.
#
#   test_wrapper::floor_to <var> <engine>
#     Sets <var> to the "<major>.<minor>" MIN_PYTHON floor parsed out of
#     <engine>, the one origin for that number, and leaves it empty when the
#     line is absent. Returns 0 either way, so the caller decides what an empty
#     <var> means.
#
#   test_wrapper::floor_check_to <var> <floor>
#     Sets <var> to a Python program that exits 0 when the interpreter running
#     it is at or above <floor> and 1 when it is below.
#
#   test_wrapper::interpreter_to <var>
#     Sets <var> to the first of python, python3 that exists, and leaves it
#     empty when neither does. Presence is not the floor check: the caller runs
#     the program above to decide.

test_wrapper::floor_to() {
  local -n _test_wrapper_floor="$1"
  _test_wrapper_floor="$(sed -n 's/^MIN_PYTHON = (\([0-9]*\), \([0-9]*\)).*/\1.\2/p' "$2")"
}

test_wrapper::floor_check_to() {
  local -n _test_wrapper_check="$1"
  _test_wrapper_check="import sys; floor = tuple(int(part) for part in '$2'.split('.')); raise SystemExit(0 if sys.version_info >= floor else 1)"
}

test_wrapper::interpreter_to() {
  local -n _test_wrapper_interpreter="$1"
  local _test_wrapper_candidate
  _test_wrapper_interpreter=""
  for _test_wrapper_candidate in python python3; do
    if command -v "$_test_wrapper_candidate" >/dev/null 2>&1; then
      _test_wrapper_interpreter="$_test_wrapper_candidate"
      return 0
    fi
  done
  return 0
}
