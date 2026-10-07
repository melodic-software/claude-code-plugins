#!/usr/bin/env bash
# Seeds the eval workspace from fixture files, committed once.
# Usage: adc-seed.sh <fixture-file> <dest-path> [<fixture-file> <dest-path>]...
# Each fixture file is stored with a .txt suffix so no scanner or linter in the
# authoring repository reads it as source; it is copied to <dest-path>.
set -euo pipefail

fixtures="$(dirname "${BASH_SOURCE[0]}")"
git init -q
while [[ $# -ge 2 ]]; do
  src="$1" dest="$2"
  shift 2
  mkdir -p "$(dirname "$dest")"
  cp "$fixtures/$src" "$dest"
  case "$dest" in
    *.sh) chmod +x "$dest" ;;
    *) ;;
  esac
  git add "$dest"
done
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "add fixtures"
