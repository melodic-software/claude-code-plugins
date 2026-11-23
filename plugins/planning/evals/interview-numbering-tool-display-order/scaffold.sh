#!/usr/bin/env bash
set -euo pipefail

mkdir -p .work/webhook-retries
cat >.work/webhook-retries/interview-checklist.md <<'MD'
# /planning:interview Checklist

## Constraint ledger

- C1 | confirmed | webhooks are delivered at least once | user, round 1

## Open-question register

- Q1 | answered | round 1 | What problem does this solve? | failed deliveries are lost and nobody hears about them
- Q2 | answered | round 1 | Who uses it? | the receiving teams and our on-call engineers
- Q3 | answered | round 1 | What quality bar does this work meet? | production
- Q4 | answered | round 2 | How many delivery attempts before the sender gives up? | five
- Q5 | answered | round 2 | What delay between delivery attempts? | exponential backoff from 30 seconds
- Q6 | answered | round 2 | What happens to an event after its last failed attempt? | it moves to a dead-letter table
- Q7 | answered | round 2 | Do receivers deduplicate repeated deliveries? | yes, on the event_id header
MD
