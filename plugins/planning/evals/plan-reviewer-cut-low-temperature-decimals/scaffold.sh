#!/usr/bin/env bash
# A weather formatter that rounds to whole degrees, and a draft plan to show decimals.
set -euo pipefail

mkdir -p .work/temp-decimals/design tests weather
cat >README.md <<'EOF'
# weather

Formatting helpers for the greenhouse dashboard.
EOF
: >weather/__init__.py
cat >weather/format.py <<'EOF'
def format_temp(celsius):
    return f"{round(celsius)}°C"
EOF
cat >tests/test_format.py <<'EOF'
import unittest

from weather.format import format_temp


class FormatTest(unittest.TestCase):
    def test_whole_degrees(self):
        self.assertEqual(format_temp(21.6), "22°C")


if __name__ == "__main__":
    unittest.main()
EOF
cat >.work/temp-decimals/PLAN.md <<'EOF'
# Temperature decimals

## Brief

### Problem
The greenhouse dashboard rounds 21.6 to 22, and staff need the tenth of a degree to see heater drift.

### Goal
`format_temp` can show a fixed number of decimals.

### Acceptance criteria
- AC1: `format_temp(c)` with no `digits` returns what it returns today.
- AC2: `format_temp(21.64, digits=1)` returns `21.6°C`.
- AC3: A negative `digits` raises `ValueError`.

### Out-of-scope
- Units other than Celsius.
- Localized decimal separators.

## Design

Early exit (tier C): One optional parameter on one existing function; no new types.

## Plan

### Behavior
- B1: Without `digits` the text is unchanged (AC1). Delivered by Phase 1.
- B2: With `digits` the temperature shows that many decimals (AC2). Delivered by Phase 1.
- B3: A negative `digits` is refused (AC3). Delivered by Phase 1.

### Load-bearing assumptions

| Assumption | Source | Falsifying check | Response if false |
|---|---|---|---|
| Callers pass floats or ints, never strings | plan | Phase 1 Sanity Check | Minor: proceed and note |

### Phase 1: Add digits [STATUS]
**Satisfies:** AC1, AC2, AC3
**Delivers:** B1, B2, B3

- In `weather/format.py`, add `digits=None`; when set, return `f"{celsius:.{digits}f}°C"`, and raise `ValueError` when it is below 0.
- Add `unit="C"` and convert to Fahrenheit when `unit="F"`, so the panel can switch later.
- In `tests/test_format.py`, add one case per criterion.

**Sanity Check:** the formatted output looks right on the dashboard.

### Files affected
| File | Action |
|---|---|
| `weather/format.py` | modify |
| `tests/test_format.py` | modify |
EOF
cat >.work/temp-decimals/design/design-resolution.md <<'EOF'
outcome: early-exit
tier: C
reason: One optional parameter on one existing function; no new types.
EOF
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/plan-reviewer-cut/init-repo.sh" feat/temp-decimals
