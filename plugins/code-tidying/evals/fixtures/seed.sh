#!/usr/bin/env bash
# Seeds the eval workspace with fixtures/<name>.txt copied to <name>, committed once, and the
# run's home with the comment tooling (comment-tooling-seed.sh).
# Usage: seed.sh <name>...
set -euo pipefail

fixtures="$(dirname "${BASH_SOURCE[0]}")"
bash "$fixtures/comment-tooling-seed.sh"
git init -q
for name in "$@"; do
  mkdir -p "$(dirname "$name")"
  cp "$fixtures/$(basename "$name").txt" "$name"
  git add "$name"
done
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "add fixtures"
