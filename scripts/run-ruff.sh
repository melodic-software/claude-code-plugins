#!/usr/bin/env bash
# Run ruff at the version pinned in .github/requirements-ci.txt.
#
# CI installs that pin via hash-locked pip (Linux x64 wheels only). A workstation
# ruff at another version disagrees with CI in both directions: it reports
# findings on an unmodified main tree that CI accepts, and misses findings CI
# raises. A release can move a rule into or out of the default set, as 0.16.0
# did for eighteen E/F rules. This wrapper keeps local verification aligned
# with the pin without a mass lint cleanup for every ruff minor; plugin contract
# tests that lint Python (engine.test.sh) call it too. The pin is read at run
# time, so the wrapper carries no copy of its own.
#
# The pin is held equal to the fleet inventory in melodic-software/dotfiles
# (.chezmoidata/uv-tools.yaml), which installs a developer's local toolchain,
# so CI never lints with a ruff nobody runs. Bumping it is a deliberate
# Dependabot change; never "fix" a clean tree by adopting a newer ruff's new
# rules in an unrelated change.
#
# Resolution order:
#   1. `ruff` on PATH when it already reports the pinned version (CI path)
#   2. `uvx ruff==<pin>` when uv is available (cross-platform local path)
#   3. exit 2 if PATH ruff exists but drifts and uvx is unavailable
#   4. exit 127 if neither a matching ruff nor uvx is available
#
# Usage: scripts/run-ruff.sh [ruff-args...]
# Example: scripts/run-ruff.sh check plugins/source-control
# By hand: uvx ruff==<pin from .github/requirements-ci.txt> check <paths>
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

ruff_on_path=0
if command -v ruff >/dev/null 2>&1; then
  ruff_on_path=1
  # `ruff --version` prints "ruff X.Y.Z"; a failed probe reports as "unknown".
  got="unknown"
  if out="$(ruff --version 2>/dev/null)"; then
    got="${out##* }"
  fi
  if [[ "$got" == "$pin" ]]; then
    exec ruff "$@"
  fi
fi

if command -v uvx >/dev/null 2>&1; then
  exec uvx "ruff==${pin}" "$@"
fi

if ((ruff_on_path)); then
  echo "error: ruff on PATH is ${got}, but CI pins ruff==${pin} (.github/requirements-ci.txt)." >&2
  echo "error: install the pin, or install uv and re-run (uvx ruff==${pin} ...)." >&2
  exit 2
fi

echo "error: ruff==${pin} not available (no matching PATH ruff, no uvx)" >&2
exit 127
