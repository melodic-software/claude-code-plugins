#!/usr/bin/env bash
# Detect project ecosystem marker files without relying on ls exit status on missing globs.
set -euo pipefail

# Marker files live at the project root; the skill preamble may run from any
# cwd, so anchor there before globbing.
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
