#!/usr/bin/env bash
# Builds a repository whose only measurement is a wall-clock time for its end-to-end suite.
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

mkdir -p e2e .github/workflows
for spec in login signup checkout refund; do
  printf 'test("%s", () => {});\n' "$spec" >"e2e/$spec.spec.js"
done

cat >time-e2e.sh <<'EOF'
#!/usr/bin/env bash
# Prints the end-to-end suite's wall time from the last CI run.
set -euo pipefail
printf 'seconds=212\n'
EOF
chmod +x time-e2e.sh

cat >.github/workflows/ci.yml <<'EOF'
name: ci
on:
  pull_request:
permissions:
  contents: read
jobs:
  e2e:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - name: End-to-end suite
        run: node --test e2e
EOF

git add .
git commit -q -m "end-to-end suite with a wall-time script"
