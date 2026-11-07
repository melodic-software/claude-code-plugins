#!/usr/bin/env bash
# A committed git repository with an API directory and a .gitignore that does not cover the bugs
# personal override, and no bugs config at any layer.
set -euo pipefail
set -o noclobber
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/scaffold-guard.sh" .git .gitignore README.md docs src
git init -q
git config user.email eval@example.invalid
git config user.name eval
mkdir -p src/api
printf 'node_modules/\n' >.gitignore
printf '# Gateway\n' >README.md
printf 'export const health = () => "ok";\n' >src/api/health.ts
git add -A
git commit -q -m "chore: initial commit"
