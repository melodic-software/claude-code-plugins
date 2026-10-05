#!/usr/bin/env bash
# Seeds a sandbox repository whose last commit is green, with a failing test
# and an uncommitted block that does not change how that test fails.
set -euo pipefail

git init -q
git checkout -q -b fix/cutoff-boundary
mkdir -p shipping tests

: >shipping/__init__.py

cat >shipping/cutoff.py <<'PY'
from datetime import time

CUTOFF = time(15, 0)


def ships_same_day(placed_at):
    return placed_at.time() < CUTOFF
PY

cat >tests/test_cutoff.py <<'PY'
import unittest
from datetime import datetime

from shipping.cutoff import ships_same_day


class Cutoff(unittest.TestCase):
    def test_morning_order_ships_same_day(self):
        self.assertTrue(ships_same_day(datetime(2026, 3, 2, 9, 30)))

    def test_evening_order_ships_next_day(self):
        self.assertFalse(ships_same_day(datetime(2026, 3, 2, 18, 0)))


if __name__ == "__main__":
    unittest.main()
PY

git add shipping tests
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "add same-day shipping cutoff"

cat >>tests/test_cutoff.py <<'PY'


class CutoffBoundary(unittest.TestCase):
    def test_order_at_cutoff_ships_same_day(self):
        self.assertTrue(ships_same_day(datetime(2026, 3, 2, 15, 0)))
PY

cat >shipping/cutoff.py <<'PY'
from datetime import time, timezone

CUTOFF = time(15, 0)


def ships_same_day(placed_at):
    local = placed_at.replace(tzinfo=timezone.utc)
    return local.time() < CUTOFF
PY
