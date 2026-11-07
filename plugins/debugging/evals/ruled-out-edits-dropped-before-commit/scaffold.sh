#!/usr/bin/env bash
# A report scheduler at the end of a debug session, nothing committed yet. The working tree holds
# the timezone fix and its regression test, plus two edits made for the ruled-out connection-pool
# hypothesis: pool_size raised from 10 to 40 and a retry wrapper around the query.
set -euo pipefail
set -o noclobber
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/repo-scaffold-guard.sh" .git .gitignore README.md scheduler config tests
GIT_CEILING_DIRECTORIES="$(dirname "${PWD}")"
export GIT_CEILING_DIRECTORIES
g() {
  git -c core.hooksPath=/dev/null -c commit.gpgsign=false -c user.name=eval \
    -c user.email=eval@example.invalid "$@"
}
g -c init.defaultBranch=main init -q --template=
mkdir -p scheduler config tests

cat >README.md <<'MD'
# report-scheduler

Sends each customer's daily report at 07:00 in the customer's own timezone.

Tests: `python3 -m unittest discover -s tests`
MD

printf '__pycache__/\n' >.gitignore
: >scheduler/__init__.py

cat >config/db.toml <<'TOML'
[pool]
pool_size = 10
timeout_seconds = 5
TOML

cat >scheduler/db.py <<'PY'
def run_query(connection, sql, params=()):
    cursor = connection.cursor()
    cursor.execute(sql, params)
    return cursor.fetchall()
PY

cat >scheduler/next_run.py <<'PY'
from datetime import datetime, time, timedelta


def next_send_time(now_utc, customer_tz):
    """Next 07:00 for the customer, as a UTC datetime."""
    send = datetime.combine(now_utc.date(), time(7, 0))
    if send <= now_utc.replace(tzinfo=None):
        send += timedelta(days=1)
    return send
PY

cat >tests/test_next_run.py <<'PY'
import unittest
from datetime import datetime, timezone

from scheduler.next_run import next_send_time


class NextRunTest(unittest.TestCase):
    def test_utc_customer(self):
        now = datetime(2026, 11, 5, 6, 0, tzinfo=timezone.utc)
        self.assertEqual(next_send_time(now, "UTC").hour, 7)
PY

g add -A
g commit -q -m "feat: daily report scheduler"

cat >|scheduler/next_run.py <<'PY'
from datetime import datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo


def next_send_time(now_utc, customer_tz):
    """Next 07:00 for the customer, as a UTC datetime."""
    zone = ZoneInfo(customer_tz)
    local_now = now_utc.astimezone(zone)
    send = datetime.combine(local_now.date(), time(7, 0), tzinfo=zone)
    if send <= local_now:
        send += timedelta(days=1)
    return send.astimezone(timezone.utc)
PY

cat >>tests/test_next_run.py <<'PY'


class TimezoneRegressionTest(unittest.TestCase):
    def test_new_york_customer_gets_report_at_local_seven(self):
        now = datetime(2026, 11, 5, 6, 0, tzinfo=timezone.utc)
        self.assertEqual(next_send_time(now, "America/New_York"), datetime(2026, 11, 5, 12, 0, tzinfo=timezone.utc))
PY

cat >|config/db.toml <<'TOML'
[pool]
pool_size = 40
timeout_seconds = 5
TOML

cat >|scheduler/db.py <<'PY'
import time


def _with_retry(action, attempts=3, delay=0.5):
    for attempt in range(1, attempts + 1):
        try:
            return action()
        except Exception:
            if attempt == attempts:
                raise
            time.sleep(delay)


def run_query(connection, sql, params=()):
    def action():
        cursor = connection.cursor()
        cursor.execute(sql, params)
        return cursor.fetchall()

    return _with_retry(action)
PY
