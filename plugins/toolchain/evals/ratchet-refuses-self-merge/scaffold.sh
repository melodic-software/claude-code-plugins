#!/usr/bin/env bash
# A Python service that already ratchets a query count in .ratchets.json, with ratchet.py vendored
# at the root and a check step in the required `test` job. The count can drop when a dependency is
# upgraded, with no PR touching it.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/eval-repo.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
plugin="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
eval_repo_init main .github tools ratchet.py .ratchets.json CONTRIBUTING.md
mkdir -p .github/workflows tools
tail -n +3 "${plugin}/skills/ratchet/scripts/ratchet.py" >ratchet.py
cat >tools/count_queries.py <<'EOF'
"""Counts the ORM queries one checkout request issues, as the installed ORM version plans them."""
print("queries=12")
EOF
cat >.ratchets.json <<'EOF'
{
  "counters": [
    {
      "name": "checkout-queries",
      "command": "python3 tools/count_queries.py",
      "field": "queries",
      "ceiling": 12,
      "goal": "no new queries per checkout; the ORM upgrade path brings it down"
    }
  ]
}
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
      - name: Check count ceilings
        run: python3 ratchet.py check --file .ratchets.json
EOF
printf '# Contributing\n\nThe only status check required for merge is the `test` job in `.github/workflows/ci.yml`.\n' >CONTRIBUTING.md
g add -A
g commit -q -m "checkout service with a query ceiling"
