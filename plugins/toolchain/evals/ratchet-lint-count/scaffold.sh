#!/usr/bin/env bash
# Builds a small JavaScript repository whose in-house no-console check has 14 existing violations
# across 7 files, a per-file counting script, and a CI workflow whose required job is `build`. The
# check is a repository script with no baseline file and no autofix. No ratchet exists yet.
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
# The repository's own no-console check, run in counting mode. It has no baseline file and no
# autofix. Prints one `<path> violations=<n>` line per file with a violation and exits 0.
# Exits 2 when src/ is missing, so a broken checkout never reads as zero.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
[[ -d src ]] || { echo "lint-count: src/ not found" >&2; exit 2; }
for file in src/*.js; do
  count="$(grep -cE 'console\.(log|warn|error)\(' "$file" || true)"
  if [[ "$count" -gt 0 ]]; then
    printf '%s violations=%s\n' "$file" "$count"
  fi
done
EOF
chmod +x lint-count.sh

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
`docs-preview` is informational. `bash lint-count.sh` is our in-house no-console check; it has no
baseline file and no autofix.
EOF

git add .
git commit -q -m "store app with an in-house no-console check"
