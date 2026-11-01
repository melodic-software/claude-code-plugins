#!/usr/bin/env bash
# Seeds an interview ledger with round 1 answered and round 2's three questions open.
set -euo pipefail

mkdir -p .work/webhook-retries
cat >.work/webhook-retries/interview-checklist.md <<'MD'
# /planning:interview Checklist

## Constraint ledger

- C1 | confirmed | webhooks are delivered at least once | user, round 1

## Open-question register

- Q1 | answered | round 1 | What quality bar does this work meet? | production
- Q2 | answered | round 1 | What delivery guarantee do webhooks carry? | at least once
- Q3 | answered | round 1 | How do receivers handle a repeated delivery? | they deduplicate on the event_id header
- Q4 | open | round 2 | How many delivery attempts before the sender gives up? |
- Q5 | open | round 2 | What delay between delivery attempts? |
- Q6 | open | round 2 | What happens to an event after its last failed attempt? |

## Decision tree (`me` mode only)

- [x] quality bar: production (Q1)
- [x] delivery guarantee: at least once (Q2)
- [x] repeats: receivers deduplicate on event_id (Q3)
- [ ] attempt count (Q4)
- [ ] delay between attempts (Q5)
- [ ] after the last failed attempt (Q6)
MD
