#!/usr/bin/env bash
# Builds a JavaScript repository with no no-console violations, the rule switched off,
# a counting script, and a CI workflow with no ratchet.
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

mkdir -p src .github/workflows
for module in billing ledger payouts; do
  printf 'export function %sTotal(rows) {\n  return rows.length;\n}\n' "$module" >"src/$module.js"
done

cat >lint-count.sh <<'EOF'
#!/usr/bin/env bash
# Counts no-console violations under src/ and prints violations=<n>.
# Exits 2 when src/ is missing, so a broken checkout never reads as zero.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
[[ -d src ]] || { echo "lint-count: src/ not found" >&2; exit 2; }
count="$(grep -rhoE 'console\.(log|warn|error)\(' src | wc -l | tr -d ' ')"
printf 'violations=%s\n' "$count"
EOF
chmod +x lint-count.sh

cat >.eslintrc.json <<'EOF'
{
  "root": true,
  "rules": {
    "no-console": "off"
  }
}
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
      - name: Lint
        run: npx eslint src
EOF

git add .
git commit -q -m "ledger service with no-console switched off"
