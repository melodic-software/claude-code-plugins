#!/usr/bin/env bash
# Sourced by every shell entry point in this plugin: resolve a Python
# interpreter at or above the plugin's floor into the array PY, so a
# two-word launcher (`py -3` on Windows) is invoked correctly as
# "${PY[@]}". One copy, one policy (design T20).
#
#   source "$PLUGIN_ROOT/scripts/python-resolve.sh"
#   cm_resolve_python || { echo "..." >&2; exit 2; }
#   "${PY[@]}" "$PLUGIN_ROOT/scripts/report.py" ...
#
# cm_resolve_python reads MIN_PYTHON from report.py beside this file, tries
# python3, python, then `py -3`, skips the Windows Store App Execution Alias
# stub (a zero-length file under a WindowsApps path), and returns 1 when
# nothing at or above the floor runs. CM_PYTHON_FLOOR is exported for
# messages; CM_PY_NATIVE holds the interpreter itself, for messages that
# name it.
#
# Native Windows Python writes text-mode stdout with CRLF line endings, and
# `mapfile -t` and `read -r` strip only the LF, so every path, glob, and
# registry value bash reads back would keep a trailing CR: a file `a.sh`
# would arrive as `a.sh<CR>`, match no lane, and the audit would report
# measuring nothing with exit 0 (#6794). The floor probe prints one line, and
# when that line comes back CR-terminated PY becomes `cm_py_lf`, which runs
# the same interpreter and drops the CR before each LF. Every handoff is
# covered in this one place, including ones written later; an interpreter
# that writes LF runs unwrapped.
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
  local here candidate resolved lower probe out
  here="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
  CM_PYTHON_FLOOR="$(sed -n 's/^MIN_PYTHON = (\([0-9]*\), \([0-9]*\)).*/\1.\2/p' "$here/report.py")"
  [[ -n "$CM_PYTHON_FLOOR" ]] || CM_PYTHON_FLOOR="3.9"
  export CM_PYTHON_FLOOR
  probe="import sys; floor = tuple(int(p) for p in '$CM_PYTHON_FLOOR'.split('.')); print('ok'); raise SystemExit(0 if sys.version_info >= floor else 1)"
  PY=()
  CM_PY_NATIVE=()
  for candidate in python3 python; do
    resolved="$(command -v "$candidate" 2>/dev/null)" || continue
    lower="$(printf '%s' "$resolved" | tr '[:upper:]' '[:lower:]')"
    if [[ "$lower" == *windowsapps* && ! -s "$resolved" ]]; then
      continue
    fi
    if out="$("$candidate" -I -c "$probe" 2>/dev/null)"; then
      _cm_set_py "$out" "$candidate"
      return 0
    fi
  done
  if command -v py >/dev/null 2>&1 && out="$(py -3 -I -c "$probe" 2>/dev/null)"; then
    _cm_set_py "$out" py -3
    return 0
  fi
  return 1
}

# shellcheck disable=SC2034
_cm_set_py() {
  # _cm_set_py <probe output> <interpreter words...>
  local out="$1"
  shift
  CM_PY_NATIVE=("$@")
  if [[ "$out" == *$'\r' ]]; then
    PY=(cm_py_lf)
  else
    PY=("$@")
  fi
}
