#!/usr/bin/env bash
# Seeds the eval workspace with a git repo whose feature branch is one commit ahead of main, an
# offline forge (fixtures/gh-forge, --no-pr) that holds the head and opens the PR, and a team config
# that requires a Verification section.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p .claude src
printf 'export const me = () => null;\n' > src/app.ts
printf '# demo\n' > README.md
printf '# source-control configuration\n\n## pr_body_required_sections\n\n- Summary\n- Verification\n- Related\n' > .claude/source-control.md
git add .claude src README.md
git commit -q -m "chore: seed"

git checkout -q -b fix/null-user
printf 'export const me = () => ({});\n' > src/app.ts
git add src/app.ts
git commit -q -m "fix: return an empty user instead of null"
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/gh-forge/install.sh" 835 fix/null-user main "fix: return an empty user instead of null" --no-pr
