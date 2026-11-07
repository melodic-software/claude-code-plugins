#!/usr/bin/env bash
# A Python repository with no `# noqa` comment, a counting script, no ratchet yet, and a CI workflow
# whose required job is `test`.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/eval-repo.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
eval_repo_init main .github src pyproject.toml count-noqa.sh CONTRIBUTING.md
mkdir -p .github/workflows src/billing
printf '[project]\nname = "billing"\nversion = "0.1.0"\n\n[tool.ruff.lint]\nselect = ["E", "F", "B"]\n' >pyproject.toml
printf 'def invoice_total(lines):\n    return sum(line.amount for line in lines)\n' >src/billing/invoice.py
cat >count-noqa.sh <<'EOF'
#!/usr/bin/env bash
# Counts `# noqa` comments in tracked Python files and prints noqa=<n>. Exits 2 when src/ is missing.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
[[ -d src ]] || { echo "count-noqa: src/ not found" >&2; exit 2; }
printf 'noqa=%s\n' "$(grep -rhoE '#[[:space:]]*noqa' --include='*.py' src | wc -l | tr -d ' ')"
EOF
cat >.github/workflows/ci.yml <<'EOF'
name: ci
on:
  pull_request:
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - name: Unit tests
        run: python3 -m unittest discover -s src
  docs:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - run: echo "docs preview"
EOF
cat >CONTRIBUTING.md <<'EOF'
# Contributing

The only status check required for merge is the `test` job in `.github/workflows/ci.yml`.
`docs` is informational.
EOF
g add -A
g commit -q -m "billing"
