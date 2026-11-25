# shellcheck shell=bash

python_probe::floor_interpreter_to() {
  local _python_probe_candidate
  printf -v "$1" '%s' ""
  for _python_probe_candidate in python3 python; do
    if command -v "$_python_probe_candidate" >/dev/null 2>&1 &&
      "$_python_probe_candidate" -I -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; then
      printf -v "$1" '%s' "$_python_probe_candidate"
      return 0
    fi
  done
  return 0
}
