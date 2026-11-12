#!/usr/bin/env bash
# An alerts package that pages for every alert at any hour, and a draft plan for quiet hours.
set -euo pipefail

mkdir -p .work/quiet-hours/design alerts ops
cat >README.md <<'EOF'
# alerts

Raises alerts, pages on-call through the outbox, and sends a morning digest.
EOF
: >alerts/__init__.py
cat >alerts/settings.py <<'EOF'
from datetime import time

QUIET_START = time(22, 0)
QUIET_END = time(7, 0)
DIGEST_AT = time(7, 30)
EOF
cat >alerts/rules.py <<'EOF'
from dataclasses import dataclass


@dataclass
class Alert:
    name: str
    severity: str  # "critical", "warning" or "info"
EOF
cat >alerts/outbox.py <<'EOF'
"""Pages are queued here; ops/schedule.txt runs flush() every minute, which sends them."""
QUEUE = []


def enqueue(alert):
    QUEUE.append(alert)


def flush(send):
    while QUEUE:
        send(QUEUE.pop(0))
EOF
cat >alerts/digest.py <<'EOF'
"""Morning digest, built at settings.DIGEST_AT from the alerts in DIGEST_QUEUE."""
DIGEST_QUEUE = []


def add(alert):
    DIGEST_QUEUE.append(alert)


def build_digest():
    lines = ["%s (%s)" % (alert.name, alert.severity) for alert in DIGEST_QUEUE]
    DIGEST_QUEUE.clear()
    return "\n".join(lines)
EOF
cat >alerts/evaluate.py <<'EOF'
from alerts import outbox


def dispatch(alert, now):
    outbox.enqueue(alert)
EOF
cat >ops/schedule.txt <<'EOF'
* * * * * python -m alerts.flush
30 7 * * * python -m alerts.send_digest
EOF
cat >.work/quiet-hours/PLAN.md <<'EOF'
# Quiet hours for alerts

## Brief

### Problem
On-call staff are paged at 3 a.m. for disk-usage warnings that could wait for the morning.

### Goal
Non-critical alerts raised in quiet hours wait for the morning digest instead of paging.

### Acceptance criteria
- AC1: A critical alert in quiet hours is enqueued as today.
- AC2: A warning or info alert raised between `QUIET_START` and `QUIET_END` is not enqueued.
- AC3: Each held alert appears in the next morning digest.
- AC4: Outside quiet hours every alert is enqueued as today.

### Out-of-scope
- Per-person quiet hours.
- Snoozing an alert.

## Design

Early exit (tier C): Changes existing functions and reads existing settings; no new types.

## Plan

### Behavior
- B1: Critical alerts page at any hour, and every alert pages outside quiet hours (AC1, AC4). Delivered by Phase 1.
- B2: Update `alerts/evaluate.py` to check quiet hours (AC2). Delivered by Phase 1.
- B3: Held alerts reach the morning digest (AC3). Delivered by Phase 2.

### Load-bearing assumptions

| Assumption | Source | Falsifying check | Response if false |
|---|---|---|---|
| The quiet window wraps midnight (22:00 to 07:00) | plan | Phase 1 Sanity Check | Moderate: flag and continue |

### Phase 1: Hold non-critical alerts [STATUS]
**Satisfies:** AC1, AC2, AC4
**Delivers:** B1, B2

- In `alerts/rules.py`, add `is_pageable(alert, now)`: true for a critical alert, or when `now` is outside the window from `settings.QUIET_START` to `settings.QUIET_END`, which wraps midnight.
- In `alerts/evaluate.py`, call `outbox.enqueue(alert)` only when `rules.is_pageable(alert, now)`.
- In `tests/test_rules.py`, cover 03:00 and 12:00 for a warning and a critical alert.

**Sanity Check:** `python -m unittest tests.test_rules` exits 0.

### Phase 2: Morning hand-off [STATUS]
**Satisfies:** AC3
**Delivers:** B3

- In `README.md`, describe quiet hours and which severities still page.
- In `tests/test_evaluate.py`, assert that a warning at 03:00 never reaches `outbox.enqueue`.

**Sanity Check:** `python -m unittest discover -s tests` exits 0.

### Files affected
| File | Action |
|---|---|
| `alerts/rules.py` | modify |
| `alerts/evaluate.py` | modify |
| `README.md` | modify |
| `tests/test_rules.py` | create |
| `tests/test_evaluate.py` | create |
EOF
cat >.work/quiet-hours/design/design-resolution.md <<'EOF'
outcome: early-exit
tier: C
reason: Changes existing functions and reads existing settings; no new types.
EOF
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/plan-reviewer-cut/init-repo.sh" feat/quiet-hours
