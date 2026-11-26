# shellcheck shell=bash

python_probe::find_to() {
  local _pp_floor="$2" _pp_candidate _pp_resolved _pp_lower
  printf -v "$1" '%s' ""
  for _pp_candidate in python3 python; do
    _pp_resolved="$(command -v "$_pp_candidate" 2>/dev/null)" || continue
    _pp_lower="$(printf '%s' "$_pp_resolved" | tr '[:upper:]' '[:lower:]')"
    if [[ "$_pp_lower" == *windowsapps* && ! -s "$_pp_resolved" ]]; then
      continue
    fi
    if "$_pp_candidate" -c "import sys; floor = tuple(int(part) for part in '$_pp_floor'.split('.')); raise SystemExit(0 if sys.version_info >= floor else 1)"; then
      printf -v "$1" '%s' "$_pp_candidate"
      return 0
    fi
  done
  return 1
}

python_probe::require_to() {
  local _pp_engine="$2"

  local _pp_floor
  _pp_floor="$(sed -n 's/^MIN_PYTHON = (\([0-9]*\), \([0-9]*\)).*/\1.\2/p' "$_pp_engine")"
  if [[ -z "$_pp_floor" ]]; then
    echo "FAIL: could not parse MIN_PYTHON from $_pp_engine" >&2
    exit 1
  fi

  if python_probe::find_to "$1" "$_pp_floor"; then
    return 0
  fi

  echo "SKIP: Python ${_pp_floor}+ not found" >&2
  exit 0
}
