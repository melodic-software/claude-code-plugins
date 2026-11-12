#!/usr/bin/env bash
# A fetcher package whose retry backoff grows past the configured ceiling, and a draft bug-fix plan.
set -euo pipefail

mkdir -p .work/backoff-cap/design fetcher tests
cat >README.md <<'EOF'
# fetcher

HTTP fetcher with retries. Tunables live in fetcher/config.py.
EOF
: >fetcher/__init__.py
cat >fetcher/config.py <<'EOF'
"""Tunables for the HTTP fetcher."""
BASE_DELAY_SECONDS = 0.5
MAX_BACKOFF_SECONDS = 30.0
MAX_ATTEMPTS = 8
EOF
cat >fetcher/retry.py <<'EOF'
"""Retry delays for failed fetches."""
from fetcher import config


def backoff(attempt):
    """Seconds to wait before retry number `attempt` (1-based)."""
    return config.BASE_DELAY_SECONDS * 2 ** (attempt - 1)
EOF
cat >tests/test_retry.py <<'EOF'
import unittest

from fetcher.retry import backoff


class BackoffTest(unittest.TestCase):
    def test_doubles(self):
        self.assertEqual([backoff(n) for n in (1, 2, 3)], [0.5, 1.0, 2.0])


if __name__ == "__main__":
    unittest.main()
EOF
cat >.work/backoff-cap/PLAN.md <<'EOF'
# Cap retry backoff

## Brief

### Problem
With eight attempts, the last retries wait 32 and 64 seconds, past the 30-second ceiling the operations runbook promises, so a stuck fetch holds a worker for minutes.

### Goal
No retry waits longer than the configured ceiling.

### Acceptance criteria
- AC1: `backoff(n)` returns what it returns today while the doubled delay is at or under the ceiling.
- AC2: `backoff(n)` never returns more than the ceiling for any `n` of 1 or more.
- AC3: `backoff(0)` and negative attempts raise `ValueError`.

### Out-of-scope
- Adding jitter.
- Changing the number of attempts.

## Design

Early exit (tier C): A bound inside one existing function; no new types.

## Plan

### Behavior
- B1: Short delays keep doubling as today (AC1). Delivered by Phase 1.
- B2: No delay exceeds the ceiling (AC2). Delivered by Phase 1.
- B3: Attempt numbers below 1 are refused (AC3). Delivered by Phase 1.

### Load-bearing assumptions

| Assumption | Source | Falsifying check | Response if false |
|---|---|---|---|
| `BASE_DELAY_SECONDS` stays positive | plan | Phase 1 Sanity Check | Minor: proceed and note |

### Phase 1: Bound the delay [STATUS]
**Satisfies:** AC1, AC2, AC3
**Delivers:** B1, B2, B3

- In `fetcher/retry.py`, return `min(config.BASE_DELAY_SECONDS * 2 ** (attempt - 1), config.MAX_DELAY)`; `MAX_DELAY` is already defined in `fetcher/config.py` as the 30-second ceiling.
- Raise `ValueError` at the top of `backoff` when `attempt` is below 1.

**Sanity Check:** `python -c "from fetcher.retry import backoff; assert backoff(8) <= 30"` exits 0.

### Files affected
| File | Action |
|---|---|
| `fetcher/retry.py` | modify |
EOF
cat >.work/backoff-cap/design/design-resolution.md <<'EOF'
outcome: early-exit
tier: C
reason: A bound inside one existing function; no new types.
EOF
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/plan-reviewer-cut/init-repo.sh" fix/backoff-cap
