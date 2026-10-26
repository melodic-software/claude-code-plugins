#!/usr/bin/env bash
# A payment client whose MAX_RETRIES value is explained only in a commit message that cites an
# incident ticket. No design docs and no tracker are reachable from the workspace.
set -euo pipefail

export GIT_AUTHOR_NAME=eval GIT_AUTHOR_EMAIL=eval@example.invalid
export GIT_COMMITTER_NAME=eval GIT_COMMITTER_EMAIL=eval@example.invalid

git init -q -b main .
mkdir -p src docs .memory/max-retries
printf '# Payments client\n\nCharges cards through the acquirer gateway.\n' >docs/README.md
printf '%s\n' \
  'MAX_RETRIES = 3' \
  '' \
  '' \
  'def charge(gateway, card, cents):' \
  '    for _ in range(MAX_RETRIES):' \
  '        if gateway.charge(card, cents):' \
  '            return True' \
  '    return False' >src/client.py
git add docs src
GIT_AUTHOR_DATE="2026-02-03T10:00:00Z" GIT_COMMITTER_DATE="2026-02-03T10:00:00Z" \
  git commit -q -m "feat: payment client"

sed 's/^MAX_RETRIES = 3$/MAX_RETRIES = 7/' src/client.py >src/client.py.new
mv src/client.py.new src/client.py
git add src/client.py
GIT_AUTHOR_DATE="2026-05-19T15:20:00Z" GIT_COMMITTER_DATE="2026-05-19T15:20:00Z" \
  git commit -q -F - <<'MSG'
fix: raise MAX_RETRIES to 7

Northwind Acquiring caps re-presentment at 7 attempts per card per day (see INC-2291).
Three attempts left recoverable soft declines on the table; 7 is their ceiling, not a guess.
MSG
