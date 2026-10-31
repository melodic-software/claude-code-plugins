#!/usr/bin/env bash
# Builds a small JavaScript repository whose no-console rule has 14 existing violations,
# a counting script, and a CI workflow whose required job is `build`. No ratchet exists yet.
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

mkdir -p src .github/workflows
for module in cart checkout inventory search shipping users invoices; do
  {
    printf 'export function %sReady() {\n' "$module"
    printf '  console.log("%s: start");\n' "$module"
    printf '  console.log("%s: done");\n' "$module"
    printf '  return true;\n}\n'
  } >"src/$module.js"
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
    "no-console": "warn"
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
      - name: Unit tests
        run: node --test
  docs-preview:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - name: Build docs
        run: echo "docs preview"
EOF

cat >CONTRIBUTING.md <<'EOF'
# Contributing

The only status check required for merge is the `build` job in `.github/workflows/ci.yml`.
`docs-preview` is informational.
EOF

git add .
git commit -q -m "store app with a no-console rule at warning severity"
