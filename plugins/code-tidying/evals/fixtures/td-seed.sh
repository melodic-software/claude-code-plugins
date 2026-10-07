#!/usr/bin/env bash
# Seeds the eval workspace: each SRC=DEST copies fixtures/SRC.txt to DEST, then
# one commit on main. Usage: td-seed.sh SRC=DEST...
set -euo pipefail

fixtures="$(dirname "${BASH_SOURCE[0]}")"
git init -q
git symbolic-ref HEAD refs/heads/main
for pair in "$@"; do
  src="${pair%%=*}"
  dest="${pair#*=}"
  mkdir -p "$(dirname "$dest")"
  cp "$fixtures/$src.txt" "$dest"
  git add "$dest"
done
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "add fixtures"
