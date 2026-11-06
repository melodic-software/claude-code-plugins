#!/usr/bin/env bash
# A structured-markdown Big Picture export in a repository whose default branch sets
# verification: light for the event-storming plugin.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p docs/conventions
printf '.work/\n' >.gitignore
printf 'verification: light\n' >docs/conventions/event-storming.yaml
cat >board-export.md <<'MD'
# Big Picture: neighborhood bakery online ordering

## Timeline (orange, domain events)

| x | Event | Author |
|---|---|---|
| 1 | Order Placed | Customer Rep |
| 2 | Payment Captured | Finance Lead |
| 3 | Bake Slot Reserved | Head Baker |
| 4 | Order Ready For Pickup | Counter Staff |
| 5 | Order Collected | Counter Staff |

## Hot spots (pink)

- Head Baker disagrees: slots fill before payment clears
- Finance Lead disagrees: refunds for unpicked orders are manual

## Milestones (above the timeline)

- Morning bake cutoff
MD

git add -A
git commit -q -m "feat: big picture export"

# The level is read from the default branch on origin, so push main to a local bare origin.
mkdir -p .work/origin.git
git init -q --bare -b main .work/origin.git
git remote add origin "$PWD/.work/origin.git"
git push -q origin main
