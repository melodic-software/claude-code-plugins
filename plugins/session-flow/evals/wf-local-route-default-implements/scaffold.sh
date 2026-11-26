#!/usr/bin/env bash
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
git config commit.gpgsign false
printf '.work/\n' >.gitignore
cat >PLAN.md <<'EOF'
# Report currency

Brief: locked. Design: recorded. Plan: approved.

## Published work items (decompose done)

- #101 Filter report totals by currency. agent-ready.
- #102 Currency column in the CSV export. agent-ready.
EOF
git add .gitignore PLAN.md
git commit -q -m "plan and decompose report currency"
