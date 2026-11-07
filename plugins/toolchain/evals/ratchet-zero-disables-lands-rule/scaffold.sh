#!/usr/bin/env bash
# A JavaScript repository that already uses the @eslint-community/eslint-comments plugin with its
# no-use rule off, no eslint-disable comment in the tree, a counting script and a required CI job.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/eval-repo.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
eval_repo_init main .github src package.json .eslintrc.json count-disables.sh
mkdir -p .github/workflows src
cat >package.json <<'EOF'
{
  "name": "storefront",
  "private": true,
  "scripts": { "lint": "eslint src" },
  "devDependencies": {
    "@eslint-community/eslint-plugin-eslint-comments": "4.4.1",
    "eslint": "8.57.1"
  }
}
EOF
cat >.eslintrc.json <<'EOF'
{
  "root": true,
  "env": { "es2022": true, "node": true },
  "parserOptions": { "sourceType": "module" },
  "plugins": ["@eslint-community/eslint-comments"],
  "rules": {
    "no-console": "error",
    "@eslint-community/eslint-comments/no-use": "off"
  }
}
EOF
printf 'export function total(items) {\n  return items.reduce((sum, item) => sum + item.price, 0);\n}\n' >src/cart.js
cat >count-disables.sh <<'EOF'
#!/usr/bin/env bash
# Counts eslint-disable comments under src/ and prints disables=<n>. Exits 2 when src/ is missing.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
[[ -d src ]] || { echo "count-disables: src/ not found" >&2; exit 2; }
printf 'disables=%s\n' "$(grep -rhoE 'eslint-disable' src | wc -l | tr -d ' ')"
EOF
cat >.github/workflows/ci.yml <<'EOF'
name: ci
on:
  pull_request:
permissions:
  contents: read
jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - run: npm ci && npm run lint
EOF
g add -A
g commit -q -m "storefront"
