#!/usr/bin/env bash
# Seeds the eval workspace: each argument is <fixture>=<dest>, copying fixtures/<fixture>.txt to <dest>.
# Usage: su-seed.sh [--no-commit] <fixture>=<dest>...
#   default      git init (when absent), copy, add, and commit every pair once
#   --no-commit  copy only, leaving the files untracked in an existing repo
set -euo pipefail

fixtures="$(dirname "${BASH_SOURCE[0]}")"
commit=1
if [[ "${1:-}" == "--no-commit" ]]; then
  commit=0
  shift
fi
[[ -d .git ]] || git init -q
for pair in "$@"; do
  fixture="${pair%%=*}"
  dest="${pair#*=}"
  mkdir -p "$(dirname "$dest")"
  cp "$fixtures/$fixture.txt" "$dest"
  if ((commit)); then
    git add -f "$dest"
  fi
done
if ((commit)); then
  git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "add fixtures"
fi
