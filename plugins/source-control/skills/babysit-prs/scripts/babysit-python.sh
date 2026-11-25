#!/usr/bin/env bash

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
