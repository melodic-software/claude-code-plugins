#!/usr/bin/env bash
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
git config commit.gpgsign false
printf '.work/\n' >.gitignore
mkdir -p docs/conventions
printf 'implementation_route: factory\n' >docs/conventions/session-flow.yaml
cat >PLAN.md <<'EOF'
# Report currency

Brief: locked. Design: recorded. Plan: approved.

## Published work items (decompose done)

- #101 Filter report totals by currency. agent-ready.
- #102 Currency column in the CSV export. agent-ready.
- #103 Re-run the currency backfill on the owner's on-premises reporting host. Labels:
  agent-ready, session-owned. Needs that host, which only this machine can reach.
EOF
git add .gitignore docs PLAN.md
git commit -q -m "plan and decompose report currency"
