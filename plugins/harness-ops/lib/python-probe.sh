# shellcheck shell=bash

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
