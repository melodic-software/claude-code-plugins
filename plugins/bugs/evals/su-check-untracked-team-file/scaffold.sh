#!/usr/bin/env bash
# A git repository whose team layer docs/conventions/bugs.yaml exists but was never committed.
set -euo pipefail
git init -q
git config user.email eval@example.invalid
git config user.name eval
mkdir -p src/api docs/conventions
printf 'export const ping = () => "pong";\n' >src/api/ping.ts
printf '# Service\n' >README.md
git add README.md src
git commit -q -m "chore: initial commit"
cat >docs/conventions/bugs.yaml <<'YAML'
lanes:
  - name: entrypoints
    globs:
      - 'src/api/**/*.ts'
YAML
