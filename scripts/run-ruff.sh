#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
req="$repo_root/.github/requirements-ci.txt"

if [[ ! -f "$req" ]]; then
  echo "error: missing $req" >&2
  exit 2
fi

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
