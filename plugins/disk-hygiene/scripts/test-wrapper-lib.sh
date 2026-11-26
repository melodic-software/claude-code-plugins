# shellcheck shell=bash

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
      break
    fi
  done
  return 0
}

test_wrapper::python_file_to() {
  local -n _test_wrapper_file="$1"
  local _test_wrapper_src="$2" _test_wrapper_converted
  _test_wrapper_file="$_test_wrapper_src"
  if command -v cygpath >/dev/null 2>&1; then
    _test_wrapper_converted="$(cygpath -m -- "$_test_wrapper_src" 2>/dev/null)" || return 0
    [[ -n "$_test_wrapper_converted" ]] && _test_wrapper_file="$_test_wrapper_converted"
  fi
  return 0
}
