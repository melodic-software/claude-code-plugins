# shellcheck shell=bash
# Shared Python-floor interpreter probe for the repo-tooling suites. Sourced,
# never executed.
#
# THE FLOOR HAS ONE ORIGIN: `MIN_PYTHON` in the engine itself (needed because
# `from __future__ import annotations` requires 3.7+). It is parsed out rather
# than restated here, so the wrappers cannot disagree with the engine they run.
#
# WINDOWSAPPS STUBS. A zero-length candidate under a WindowsApps path component
# is the Store's App Execution Alias stub -- executing it opens the Microsoft
# Store (or hangs) instead of running an interpreter, so each candidate is
# inspected before anything executes it. A candidate that is real but below the
# floor does not end the search either: the next candidate may satisfy it (e.g.
# an old `python` alongside a current `python3`).
#
# Usage:
#
#   python_probe::require_to <out-var> <engine>
#   python_probe::find_to <out-var> <floor>
#
# CALL require_to AS A BARE STATEMENT. It is the errexit context that carries an
# unreadable <engine> out as sed's own failure; calling it in an `if`, a `&&`,
# or after `!` would suppress errexit for the whole body and report a missing
# file as an unparsable floor instead.
#
# Every local carries the `_pp_` prefix. `printf -v` assigns the out-var by name
# in the scope where it runs, so an unprefixed local sharing the caller's chosen
# out-var name would take the result instead of that caller's variable. Do not
# introduce an unprefixed local here.

# python_probe::find_to <out-var> <floor>
#
# Assigns the first of python3 and python that runs at or above <floor> (a
# `major.minor` string) and returns 0; with none, assigns the empty string and
# returns 1. A candidate's own stderr passes through: redirect the call to drop
# it.
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

# python_probe::require_to <out-var> <engine>
#
# Assigns the first interpreter that satisfies <engine>'s MIN_PYTHON and
# returns. It does not return on either failure path, because all three callers
# hold the same policy and that policy is part of their CI contract: an
# unparsable floor prints `FAIL: ...` on stderr and exits 1, and a host with no
# interpreter at or above the floor prints `SKIP: Python <floor>+ not found` on
# stderr and exits 0.
python_probe::require_to() {
  local _pp_engine="$2"

  # Declared before it is assigned, never `local _pp_floor=$(...)`: the builtin
  # would replace sed's exit status with its own 0 and an engine that cannot be
  # read would fall through to the parse diagnostic instead of aborting here.
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
