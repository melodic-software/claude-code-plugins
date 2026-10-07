#!/usr/bin/env bash
# Seeds the eval workspace: each <fixture>=<dest> pair copies fixtures/<fixture>.txt to <dest>,
# and everything is committed once. Local only: no network, no push.
# Usage: acr-seed.sh <fixture>=<dest>...
set -euo pipefail

fixtures="$(dirname "${BASH_SOURCE[0]}")"
git init -q
for pair in "$@"; do
  src="${pair%%=*}"
  dest="${pair#*=}"
  mkdir -p "$(dirname "$dest")"
  cp "$fixtures/$src.txt" "$dest"
  git add "$dest"
done
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "add fixtures"
