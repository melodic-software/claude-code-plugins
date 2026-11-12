#!/usr/bin/env bash
# A timesheet package that rejects or miscounts overnight shifts, and a draft bug-fix plan.
set -euo pipefail

mkdir -p .work/overnight-shifts/design tests timesheet
cat >README.md <<'EOF'
# timesheet

Parses shift lines and totals hours for payroll (timesheet/export.py writes the payroll file).
EOF
: >timesheet/__init__.py
cat >timesheet/models.py <<'EOF'
from dataclasses import dataclass
from datetime import date, time


@dataclass
class Shift:
    day: date
    start: time
    end: time
EOF
cat >timesheet/parse.py <<'EOF'
from datetime import date, time

from timesheet.models import Shift


def parse_line(line):
    """'2026-03-02 09:00-17:00' -> Shift."""
    day_text, span = line.split()
    start_text, end_text = span.split("-")
    start, end = time.fromisoformat(start_text), time.fromisoformat(end_text)
    if end <= start:
        raise ValueError("end before start: " + line)
    return Shift(date.fromisoformat(day_text), start, end)
EOF
cat >timesheet/totals.py <<'EOF'
from collections import defaultdict
from datetime import datetime


def hours(shift):
    start = datetime.combine(shift.day, shift.start)
    end = datetime.combine(shift.day, shift.end)
    return (end - start).total_seconds() / 3600


def weekly_hours(shifts):
    week = defaultdict(float)
    for shift in shifts:
        week[shift.day] += hours(shift)
    return dict(week)
EOF
cat >timesheet/export.py <<'EOF'
def fmt_hours(value):
    return "%.2f" % max(value, 0.0)


def payroll_rows(week):
    return [(day.isoformat(), fmt_hours(total)) for day, total in sorted(week.items())]
EOF
cat >tests/test_totals.py <<'EOF'
import unittest

from timesheet.parse import parse_line
from timesheet.totals import hours


class HoursTest(unittest.TestCase):
    def test_day_shift(self):
        self.assertEqual(hours(parse_line("2026-03-02 09:00-17:00")), 8.0)


if __name__ == "__main__":
    unittest.main()
EOF
cat >.work/overnight-shifts/PLAN.md <<'EOF'
# Count overnight shifts

## Brief

### Problem
Night staff lose pay: a 22:00-06:00 line is rejected as ending before it starts, and a hand-entered one totals -16 hours, which payroll zeroes.

### Goal
A shift that ends at or before its start time counts as ending the next day.

### Acceptance criteria
- AC1: `2026-03-02 22:00-06:00` parses and totals 8.0 hours.
- AC2: Day shifts total as today.
- AC3: `weekly_hours` counts an overnight shift on the day it starts.

### Out-of-scope
- Shifts longer than 24 hours.
- Daylight-saving adjustments.

### Captured assumptions
- Overnight shifts end before noon the next day: revisit if a site reports a shift ending after 12:00.

## Design

Early exit (tier C): Changes existing functions; no new types.

## Plan

### Behavior
- B1: An overnight line is accepted and counts the hours to its end the next morning (AC1, AC3). Delivered by Phase 1 and Phase 2.
- B2: Day shifts total as before (AC2). Delivered by Phase 2.

### Load-bearing assumptions

| Assumption | Source | Falsifying check | Response if false |
|---|---|---|---|
| Shift lines use 24-hour HH:MM times | plan | Phase 1 Sanity Check | Minor: proceed and note |

### Phase 1: Accept overnight lines [STATUS]
**Satisfies:** AC1
**Delivers:** B1

- In `timesheet/parse.py`, drop the `end before start` rejection.
- In `timesheet/models.py`, add a `Shift.ends_next_day` property that is true when `end <= start`.

**Sanity Check:** `python -c "from timesheet.parse import parse_line; assert parse_line('2026-03-02 22:00-06:00').ends_next_day"` exits 0.

### Phase 2: Count the hours [STATUS]
**Satisfies:** AC1, AC2, AC3
**Delivers:** B1, B2

- In `timesheet/totals.py`, build the end as `datetime.combine(shift.day, shift.end)` plus one day when `shift.ends_next_day`, and keep `weekly_hours` keyed on `shift.day`.

**Sanity Check:** `python -c "from timesheet.parse import parse_line; from timesheet.totals import hours; assert hours(parse_line('2026-03-02 22:00-06:00')) == 8.0"` exits 0.

### Files affected
| File | Action |
|---|---|
| `timesheet/parse.py` | modify |
| `timesheet/models.py` | modify |
| `timesheet/totals.py` | modify |
EOF
cat >.work/overnight-shifts/design/design-resolution.md <<'EOF'
outcome: early-exit
tier: C
reason: Changes existing functions; no new types.
EOF
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/plan-reviewer-cut/init-repo.sh" fix/overnight-shifts
