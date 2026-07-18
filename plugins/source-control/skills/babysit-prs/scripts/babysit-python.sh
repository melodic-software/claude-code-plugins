#!/usr/bin/env bash
# Sourced by the babysit-prs bin/ wrappers (never executed directly). Defines
# babysit_python(), which execs a WORKING Python >= 3.11 with the given
# arguments, or exits 3 with a clear message when none is found. Probes by
# RUNNING each candidate rather than trusting PATH presence: Windows ships App
# Execution Alias stubs for `python` and `python3` that resolve on PATH yet fail
# at launch. The 3.11 floor is the engine's real minimum (it uses datetime.UTC).

_babysit_probe_python() {
  "$@" -c 'import sys; raise SystemExit(0 if sys.version_info[:2] >= (3, 11) else 1)' \
    >/dev/null 2>&1
}

babysit_python() {
  if _babysit_probe_python py -3; then
    exec py -3 "$@"
  elif _babysit_probe_python python3; then
    exec python3 "$@"
  elif _babysit_probe_python python; then
    exec python "$@"
  fi
  printf '%s\n' \
    'babysit-prs: no working Python 3.11+ interpreter on PATH (tried: py -3, python3, python).' \
    'The worker and autopilot tiers require Python; install 3.11+ or use the Python-free safe tier.' >&2
  exit 3
}
