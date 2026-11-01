#!/usr/bin/env bash
# Seeds the eval workspace with a git repo: main and a feature branch one commit ahead of it, both
# pushed to an offline origin where PR 512 is an open draft (fixtures/gh-forge).
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src
printf 'export const me = () => null;\n' >src/app.ts
git add src
git commit -q -m "chore: seed"

git checkout -q -b fix/null-user
printf 'export const me = () => ({});\n' >src/app.ts
git commit -q -am "fix: return an empty user"

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/gh-forge/install.sh" 512 fix/null-user main "fix: return an empty user"

# The verify gate already passed on this head, as the prompt says: the record verify-gate.sh check
# reads before the flip (skills/pull-request/scripts/verify-gate.sh record).
gate="$(git rev-parse --path-format=absolute --git-common-dir)/ready-verify"
mkdir -p "$gate"
printf 'pass\n' >"$gate/$(git rev-parse HEAD)"
