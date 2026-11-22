#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src/webhooks tests .work/webhook-retries

cat >src/webhooks/__init__.py <<'PY'
PY

cat >src/webhooks/sender.py <<'PY'
import json
import time
import urllib.request

ATTEMPTS = 5


def send(url, event, store_failure, alert, sleep=time.sleep):
    """Post one event, retrying with exponential backoff; an exhausted event is stored and alerted."""
    body = json.dumps(event).encode()
    delay = 30
    for attempt in range(1, ATTEMPTS + 1):
        request = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
        try:
            urllib.request.urlopen(request, timeout=10)
            return True
        except OSError:
            if attempt == ATTEMPTS:
                store_failure(url, event)
                alert(url, event)
                return False
            sleep(delay)
            delay = min(delay * 2, 1800)
PY

cat >tests/test_sender.py <<'PY'
def test_placeholder():
    assert True
PY

cat >.work/webhook-retries/PLAN.md <<'MD'
## Brief

### TLDR
- Retries for the partner webhook sender, with failed deliveries stored and alerted.

### Problem
- Gap: an event is dropped when a partner endpoint fails once.
- Who: every partner integration, several times a week.
- Evidence: partner support tickets (rated: stated by the user).

### Goal
Partners stop losing events when their endpoint fails for a short time.
- Intent (why, in the user's words): "partners stop losing events when their endpoint blips"
- Vision (where this heads): none stated
- When goals conflict, prefer: none stated
- Finish line: merged, checked by the user via the PR

### Work size
- Small: one function and its test.

### Constraints
- Postgres is the only datastore this service may write to.

### Acceptance criteria
- AC1: an event is retried up to five attempts with exponential backoff from 30 seconds, capped at 30 minutes.
- AC2: an exhausted event lands in failed_deliveries and posts one alert to the integrations channel.

### Captured assumptions
- Quality bar: internal

### Out-of-scope
- Replaying stored failed deliveries.

### ADR verdicts
- Q1 attempt count: no ADR; no real alternative weighed
- Q2 backoff schedule: no ADR; no real alternative weighed
- Q3 failed-delivery storage: no ADR; a Postgres table was weighed against a Redis stream, and the adr skill judged it easy to reverse
- Q4 alert channel: no ADR; a process decision

### Deferred questions
- none

## Plan

### Behavior
- B1: a failed post is retried with growing delays until five attempts are spent (AC1)
- B2: an exhausted event is stored and alerted once (AC2)

### Phase 1: retry loop, storage and alert [DONE]
**Satisfies:** AC1, AC2
**Delivers:** B1, B2
`src/webhooks/sender.py`: retry loop with backoff; `store_failure` and `alert` callbacks.

## Blast radius
LOW: one module, no schema change beyond the existing failed_deliveries table.

## Stress-test summary
Skipped: blast radius LOW, no triggers matched

## Handoff to implementation

Approval: approved by the user on 2026-11-10
Reader depth: step-by-step (default)

### User-approval gates
None.

### Mechanical work
One commit per phase.
MD

git add .
git commit -q -m "feat: retry partner webhooks"
