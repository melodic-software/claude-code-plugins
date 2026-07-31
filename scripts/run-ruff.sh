#!/usr/bin/env bash
# Run ruff at the version pinned in .github/requirements-ci.txt.
#
# CI installs that pin via hash-locked pip (Linux x64 wheels only). Local
# workstations often carry a newer global ruff that auto-upgraded past the pin;
# a bare `ruff check` then reports findings CI does not (and that are out of
# scope for an ordinary lane). This wrapper keeps local verification aligned
# with the pin without requiring a mass lint cleanup for every ruff minor.
#
# Resolution order:
#   1. `ruff` on PATH when it already reports the pinned version (CI path)
#   2. `uvx ruff==<pin>` when uv is available (cross-platform local path)
#   3. exit 2 if PATH ruff exists but drifts and uvx is unavailable
#   4. exit 127 if neither a matching ruff nor uvx is available
#
# Usage: scripts/run-ruff.sh [ruff-args...]
# Example: scripts/run-ruff.sh check plugins/source-control
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
req="$repo_root/.github/requirements-ci.txt"

if [[ ! -f "$req" ]]; then
  echo "error: missing $req" >&2
  exit 2
fi

# First `ruff==VERSION` line; ignore trailing backslashes / hash pins.
pin="$(awk '/^ruff==/ {
  sub(/^ruff==/, "")
  sub(/[[:space:]\\].*$/, "")
  print
  exit
}' "$req")"

if [[ -z "$pin" ]]; then
  echo "error: could not parse ruff==VERSION from $req" >&2
  exit 2
fi

if command -v ruff >/dev/null 2>&1; then
  # Probe PATH ruff outside conditionals so SC2310 does not fire on set -e.
  set +e
  out="$(ruff --version 2>/dev/null)"
  rc=$?
  set -e
  got=""
  if [[ $rc -eq 0 ]]; then
    got="${out##* }"
  fi
  if [[ "$got" == "$pin" ]]; then
    exec ruff "$@"
  fi
fi

if command -v uvx >/dev/null 2>&1; then
  exec uvx "ruff==${pin}" "$@"
fi

if command -v ruff >/dev/null 2>&1; then
  set +e
  out="$(ruff --version 2>/dev/null)"
  rc=$?
  set -e
  got="unknown"
  if [[ $rc -eq 0 ]]; then
    got="${out##* }"
  fi
  echo "error: ruff on PATH is ${got}, but CI pins ruff==${pin} (.github/requirements-ci.txt)." >&2
  echo "error: install the pin, or install uv and re-run (uvx ruff==${pin} ...)." >&2
  exit 2
fi

echo "error: ruff==${pin} not available (no matching PATH ruff, no uvx)" >&2
exit 127
