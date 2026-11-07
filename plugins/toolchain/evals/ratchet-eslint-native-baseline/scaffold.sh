#!/usr/bin/env bash
# A TypeScript repository on ESLint's flat config with typescript-eslint, the no-floating-promises
# rule off, and a required CI job. No packages are installed.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/eval-repo.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
eval_repo_init main .github src package.json eslint.config.mjs tsconfig.json
mkdir -p .github/workflows src
cat >package.json <<'EOF'
{
  "name": "orders-api",
  "private": true,
  "type": "module",
  "scripts": { "lint": "eslint ." },
  "devDependencies": {
    "eslint": "9.39.0",
    "typescript": "5.9.3",
    "typescript-eslint": "8.46.2"
  }
}
EOF
cat >eslint.config.mjs <<'EOF'
import tseslint from "typescript-eslint";

export default tseslint.config(...tseslint.configs.recommendedTypeChecked, {
  languageOptions: { parserOptions: { projectService: true } },
  rules: {
    "@typescript-eslint/no-floating-promises": "off",
  },
});
EOF
printf '{ "compilerOptions": { "strict": true, "module": "nodenext", "target": "es2022" }, "include": ["src"] }\n' >tsconfig.json
printf 'export async function save(order: { id: string }): Promise<void> {\n  await Promise.resolve(order);\n}\n\nexport function handle(order: { id: string }): void {\n  save(order);\n}\n' >src/orders.ts
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
g commit -q -m "orders api"
