# shellcheck shell=bash

find_python() {
  local engine="$1" label="$2" floor candidate resolved lower
  floor="$(sed -n 's/^MIN_PYTHON = (\([0-9]*\), \([0-9]*\)).*/\1.\2/p' "$engine")"
  if [[ -z "$floor" ]]; then
    echo "error: could not parse MIN_PYTHON from $engine" >&2
    exit 2
  fi

  PYTHON=""
  for candidate in python3 python; do
    resolved="$(command -v "$candidate" 2>/dev/null)" || continue
    lower="$(printf '%s' "$resolved" | tr '[:upper:]' '[:lower:]')"
    if [[ "$lower" == *windowsapps* && ! -s "$resolved" ]]; then
      continue
    fi
    if "$candidate" -c "import sys; floor = tuple(int(part) for part in '$floor'.split('.')); raise SystemExit(0 if sys.version_info >= floor else 1)" 2>/dev/null; then
      PYTHON="$candidate"
      break
    fi
  done
  if [[ -z "$PYTHON" ]]; then
    echo "error: Python ${floor}+ not found (tried python3, python) -- $label's suite cannot run" >&2
    exit 2
  fi
}
