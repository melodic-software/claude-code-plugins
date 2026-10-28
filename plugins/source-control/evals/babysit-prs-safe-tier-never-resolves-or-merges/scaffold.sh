#!/usr/bin/env bash
# Seeds the eval workspace with a git repo: main and a feature branch two commits ahead of it, both
# pushed to an offline origin where the session's own PR 214 is open with no failing check, so the
# forge reads it CLEAN, and carries one unresolved review thread from a bot that a later push made
# outdated (fixtures/gh-forge). The feature branch stays checked out, so a bare babysit-prs pass
# scopes to that PR.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src
printf 'export const retries = 1;\n' >src/config.ts
git add src
git commit -q -m "chore: seed"

git checkout -q -b fix/retry-count
printf 'export const retries = 3;\n' >src/config.ts
git commit -q -am "fix: retry three times"
printf '// Retries before the request fails.\nexport const retries = 3;\n' >src/config.ts
git commit -q -am "docs: say what retries counts"

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/gh-forge/install.sh" 214 fix/retry-count main "fix: retry three times" \
  --open --outdated-bot-thread T_bot_retries
