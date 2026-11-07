#!/usr/bin/env bash
# An unconfigured repository whose package.json has both a `test` and a `test:ci` script and no
# linter config, beside a Python package that a typescript-scoped run must leave alone.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/eval-repo.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
eval_repo_init main .claude src tools package.json tsconfig.json pyproject.toml
mkdir -p src tools
cat >package.json <<'EOF'
{
  "name": "booking-web",
  "private": true,
  "scripts": {
    "test": "node --test",
    "test:ci": "node --test --test-reporter=junit --test-reporter-destination=junit.xml"
  },
  "devDependencies": { "typescript": "5.9.3" }
}
EOF
printf '{ "compilerOptions": { "strict": true }, "include": ["src"] }\n' >tsconfig.json
printf 'export const nights = (from: Date, to: Date): number => (to.getTime() - from.getTime()) / 86400000;\n' >src/nights.ts
printf '[project]\nname = "booking-tools"\nversion = "0.1.0"\n' >pyproject.toml
printf 'def export_bookings():\n    return []\n' >tools/export.py
g add -A
g commit -q -m "booking web"
