# shellcheck shell=bash
# Shared Python-floor interpreter probe for the repo-tooling suites. Sourced,
# never executed.
#
# Three bash wrappers under scripts/ run a Python engine's unittest suite from a
# bash-only CI step, and each answered the same two questions for itself: what
# Python does this engine require, and is there an interpreter on this host that
# meets it. The three copies were byte-identical apart from the engine path, so
# a fix to either answer had to land three times to be true anywhere.
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
#
# CALL IT AS A BARE STATEMENT. It is the errexit context that carries an
# unreadable <engine> out as sed's own failure; calling it in an `if`, a `&&`,
# or after `!` would suppress errexit for the whole body and report a missing
# file as an unparsable floor instead.
#
# Every local carries the `_pp_` prefix. A bash nameref resolves its target in
# the scope where it is USED, so an unprefixed local sharing the caller's chosen
# out-var name shadows that caller's variable for the rest of the call; the same
# hazard is documented at length in scripts/lib/changed-files.sh, where two
# plausible out-var names came back silently empty. Do not introduce an
# unprefixed local here.

# python_probe::require_to <out-var> <engine>
#
# Assigns the first interpreter that satisfies <engine>'s MIN_PYTHON and
# returns. It does not return on either failure path, because all three callers
# hold the same policy and that policy is part of their CI contract: an
# unparsable floor prints `FAIL: ...` on stderr and exits 1, and a host with no
# interpreter at or above the floor prints `SKIP: Python <floor>+ not found` on
# stderr and exits 0.
python_probe::require_to() {
  local -n _pp_python_out="$1"
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

  local _pp_candidate _pp_resolved _pp_lower
  for _pp_candidate in python3 python; do
    _pp_resolved="$(command -v "$_pp_candidate" 2>/dev/null)" || continue
    _pp_lower="$(printf '%s' "$_pp_resolved" | tr '[:upper:]' '[:lower:]')"
    if [[ "$_pp_lower" == *windowsapps* && ! -s "$_pp_resolved" ]]; then
      continue
    fi
    if "$_pp_candidate" -c "import sys; floor = tuple(int(part) for part in '$_pp_floor'.split('.')); raise SystemExit(0 if sys.version_info >= floor else 1)"; then
      _pp_python_out="$_pp_candidate"
      return 0
    fi
  done

  echo "SKIP: Python ${_pp_floor}+ not found" >&2
  exit 0
}
