#!/usr/bin/env bash
set -euo pipefail

cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" 2>/dev/null || true

found=()
for f in *.slnx *.sln package.json pyproject.toml Cargo.toml go.mod; do
  [[ -e "$f" ]] && found+=("$f")
done

if [[ ${#found[@]} -eq 0 ]]; then
  echo "none detected"
else
  printf '%s\n' "${found[@]}"
fi
