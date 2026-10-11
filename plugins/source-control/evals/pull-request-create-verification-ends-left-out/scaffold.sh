#!/usr/bin/env bash
# Seeds the eval workspace with a git repo whose feature branch is one commit ahead of main, a bare
# local origin so the push step succeeds, and a team config that requires a Verification section.
set -euo pipefail

git init -q --bare ../eval-origin.git
git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
git remote add origin ../eval-origin.git
mkdir -p .claude src
printf 'export const me = () => null;\n' > src/app.ts
printf '# demo\n' > README.md
printf '# source-control configuration\n\n## pr_body_required_sections\n\n- Summary\n- Verification\n- Related\n' > .claude/source-control.md
git add .claude src README.md
git commit -q -m "chore: seed"
git push -q -u origin main

git checkout -q -b fix/null-user
printf 'export const me = () => ({});\n' > src/app.ts
git add src/app.ts
git commit -q -m "fix: return an empty user instead of null"
