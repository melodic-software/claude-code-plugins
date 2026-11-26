#!/usr/bin/env bash
set -euo pipefail

topic=.work/webhook-retries
mkdir -p "$topic"
cat >"$topic/interview-checklist.md" <<'MD'
# /planning:interview Checklist

Planning version: 5.19.0

## Steps

- [x] Step 1: Survey before you ask
- [x] Step 1.5: Auto-detect: routed to the Q&A loop
- [ ] Step 2: Drive the rounds loop

## Constraint ledger

- C1 | confirmed | webhooks are delivered at least once | user, round 1

## Open-question register

- Q1 | answered | round 1 | What problem should retries and alerting solve? | failed deliveries are lost and nobody hears about them kind:: discovery topic:: the problem
- Q2 | answered | round 1 | Who is this work for? | the receiving teams and our on-call engineers kind:: discovery topic:: users
- Q3 | answered | round 1 | Which quality bar is this for? | production topic:: quality bar
- Q4 | answered | round 2 | How many delivery attempts before giving up? | five topic:: attempt count
- Q5 | answered | round 2 | What delay between attempts? | exponential backoff from 30 seconds topic:: retry delay
- Q6 | answered | round 2 | What happens to an event after its last failed attempt? | a dead-letter table an operator can replay topic:: after the last attempt
- Q7 | answered | round 2 | How do receivers handle a repeated delivery? | they deduplicate on event_id topic:: duplicates
MD
printf 'Round 1\n\nThe round as it was shown.\n' >"$topic/round-1.md"
printf 'Round 2\n\nThe round as it was shown.\n' >"$topic/round-2.md"
