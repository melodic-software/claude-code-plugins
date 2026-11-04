#!/usr/bin/env bash
# Seeds the eval workspace as an out-of-tree orchestrator sees it: this checkout stays on main, and a
# worker's branch, one commit ahead of main and pushed to an offline origin with no PR yet
# (fixtures/gh-forge, --no-pr), is checked out in a linked worktree at ../eval-worker. The worker
# pushed without -u, so the branch has no upstream. The worktree has its own FETCH_HEAD, so the
# pushed-at-HEAD check can compare against a real fetch.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src
printf 'export const cell = (v) => String(v);\n' >src/csv.ts
printf '# demo\n' >README.md
git add src README.md
git commit -q -m "chore: seed"

git checkout -q -b feat/csv-quote-cells
# shellcheck disable=SC2016 # ${String(v)...} is a JavaScript template expression, not a shell one
printf 'export const cell = (v) => (/[",\\n]/.test(String(v)) ? `"${String(v).replaceAll("\\"", "\\"\\"")}"` : String(v));\n' >src/csv.ts
git commit -q -am "feat: quote CSV cells holding a comma, quote or line break"
git checkout -q main

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/gh-forge/install.sh" 841 feat/csv-quote-cells main \
  "feat: quote CSV cells holding a comma, quote or line break" --no-pr

git worktree add -q ../eval-worker feat/csv-quote-cells
git -C ../eval-worker branch --unset-upstream
