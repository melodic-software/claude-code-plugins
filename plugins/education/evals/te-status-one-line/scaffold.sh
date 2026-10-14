#!/usr/bin/env bash
# Seeds the eval workspace with an in-progress sql-joins topic workspace, plus an older record
# marked superseded, so a status count that does not exclude superseded records reports three.
set -euo pipefail

mkdir -p learning/topic
cp -R "$(dirname "${BASH_SOURCE[0]}")/../workspaces/sql-joins" learning/topic/
record=learning/topic/sql-joins/learning-records/0000-self-reported-joins.md
cat >"$record" <<'EOF'
---
Status: superseded by LR-0001
---
# Self-reported: writes INNER and LEFT JOINs

Said at intake that they already write INNER and LEFT JOINs. The first exercise showed they had
not written a join yet.
EOF
touch -d '2025-01-15' "$record"
