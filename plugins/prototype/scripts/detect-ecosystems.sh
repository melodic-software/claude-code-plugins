#!/usr/bin/env bash
# Detect project ecosystem marker files without relying on ls exit status on missing globs.
set -euo pipefail

found=()
for f in *.slnx *.sln package.json pyproject.toml Cargo.toml go.mod; do
  [[ -e "$f" ]] && found+=("$f")
done

if [[ ${#found[@]} -eq 0 ]]; then
  echo "none detected"
else
  printf '%s\n' "${found[@]}"
fi
