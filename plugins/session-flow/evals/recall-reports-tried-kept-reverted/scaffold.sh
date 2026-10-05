#!/usr/bin/env bash
# Seeds the eval workspace with a git repository whose history tries a token-bucket rate limiter,
# reverts it, then lands a sliding-window one that stays.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src
printf 'const hits = new Map();\nexport const allow = (key) => true;\n' >src/limiter.ts
git add src
git commit -q -m "feat(limits): in-memory rate limiter"

printf 'export const allow = (key) => bucket(key).take();\n' >src/limiter.ts
git commit -q -am "feat(limits): token-bucket rate limiter replacing the in-memory map"
bucket="$(git rev-parse HEAD)"

git revert --no-edit "$bucket" >/dev/null
git commit -q --amend -m "Revert \"feat(limits): token-bucket rate limiter replacing the in-memory map\"" \
  -m "This reverts commit $bucket." \
  -m "The bucket dropped legitimate requests during traffic bursts."

printf 'export const allow = (key) => slidingWindow(key, 60).under(100);\n' >src/limiter.ts
git commit -q -am "feat(limits): sliding-window rate limiter"
