#!/usr/bin/env bash
# shellcheck shell=bash

# cm_py_lf runs the resolved interpreter with its stdout line endings
# normalized to LF and returns the interpreter's own exit status. The sed
# script holds a literal CR ($'...'), which BSD and GNU sed both match.
cm_py_lf() {
  "${CM_PY_NATIVE[@]}" "$@" | sed $'s/\r$//'
  return "${PIPESTATUS[0]}"
}

# PY is consumed by the sourcing script, not here.
# shellcheck disable=SC2034
cm_resolve_python() {
  # The scripts use mapfile and associative arrays, so bash 3.2 (the macOS
  # default) stops here with the remediation instead of a syntax error later.
  if ((BASH_VERSINFO[0] < 4)); then
    printf 'code-metrics needs bash 4 or later (this is %s); macOS: brew install bash; Windows: run under Git Bash\n' "$BASH_VERSION" >&2
    return 2
  fi
  local here candidate resolved probe
  here="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
  CM_PYTHON_FLOOR="$(sed -n 's/^MIN_PYTHON = (\([0-9]*\), \([0-9]*\)).*/\1.\2/p' "$here/report.py")"
  [[ -n "$CM_PYTHON_FLOOR" ]] || CM_PYTHON_FLOOR="3.9"
  export CM_PYTHON_FLOOR
  probe="import sys; floor = tuple(int(p) for p in '$CM_PYTHON_FLOOR'.split('.')); print('ok'); raise SystemExit(0 if sys.version_info >= floor else 1)"
  PY=()
  CM_PY_NATIVE=()
  for candidate in python3 python; do
    resolved="$(command -v "$candidate" 2>/dev/null)" || continue
    [[ "${resolved,,}" == *windowsapps* && ! -s "$resolved" ]] && continue
    _cm_probe "$probe" "$candidate" && return 0
  done
  command -v py >/dev/null 2>&1 && _cm_probe "$probe" py -3
}

# shellcheck disable=SC2034
_cm_probe() {
  # _cm_probe <probe> <interpreter words...>: run the floor probe and, when it
  # passes, set PY and CM_PY_NATIVE. The line is read with mapfile, as the
  # consumers read theirs: Git Bash's $(...) drops a trailing CR, so a
  # command substitution would never see one.
  local probe="$1" lines
  shift
  mapfile -t lines < <("$@" -I -c "$probe" 2>/dev/null; printf '%s\n' "$?")
  [[ "${lines[${#lines[@]} - 1]}" == 0 ]] || return 1
  CM_PY_NATIVE=("$@")
  if [[ "${lines[0]}" == *$'\r' ]]; then
    PY=(cm_py_lf)
  else
    PY=("$@")
  fi
}
