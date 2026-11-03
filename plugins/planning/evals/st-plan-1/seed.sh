#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p library db config deploy bin tests .work/review-target/design

cat >pyproject.toml <<'TOML'
[project]
name = "branch-library"
version = "1.8.0"
requires-python = ">=3.11"

[tool.pytest.ini_options]
testpaths = ["tests"]
TOML

cat >library/loans.py <<'PY'
"""Loan records, checkouts and renewals."""
from datetime import date, timedelta
import sqlite3

LOAN_DAYS = 21
RENEWAL_DAYS = 14
MAX_RENEWALS = 2


class RenewalLimitReached(Exception):
    pass


def checkout(conn: sqlite3.Connection, member_id: int, copy_id: int, today: date) -> int:
    due = today + timedelta(days=LOAN_DAYS)
    cursor = conn.execute(
        "INSERT INTO loans (member_id, copy_id, checked_out_on, due_at) VALUES (?, ?, ?, ?)",
        (member_id, copy_id, today.isoformat(), due.isoformat()),
    )
    conn.commit()
    return cursor.lastrowid


def effective_due_date(conn: sqlite3.Connection, loan_id: int) -> date:
    row = conn.execute(
        """
        SELECT COALESCE(
            (SELECT MAX(extended_to) FROM loan_renewals WHERE loan_id = :id),
            (SELECT due_at FROM loans WHERE id = :id)
        )
        """,
        {"id": loan_id},
    ).fetchone()
    return date.fromisoformat(row[0])


def renew(conn: sqlite3.Connection, loan_id: int, today: date) -> date:
    count = conn.execute(
        "SELECT COUNT(*) FROM loan_renewals WHERE loan_id = ?", (loan_id,)
    ).fetchone()[0]
    if count >= MAX_RENEWALS:
        raise RenewalLimitReached(loan_id)
    extended = effective_due_date(conn, loan_id) + timedelta(days=RENEWAL_DAYS)
    conn.execute(
        "INSERT INTO loan_renewals (loan_id, renewed_on, extended_to) VALUES (?, ?, ?)",
        (loan_id, today.isoformat(), extended.isoformat()),
    )
    conn.commit()
    return extended


def give_back(conn: sqlite3.Connection, loan_id: int, today: date) -> None:
    conn.execute(
        "UPDATE loans SET returned_at = ? WHERE id = ?", (today.isoformat(), loan_id)
    )
    conn.commit()
PY

cat >library/notify.py <<'PY'
"""Member notices. Callers queue a row; flush_outbox delivers it."""
import json
import smtplib
import sqlite3
from email.message import EmailMessage


def queue_notice(conn: sqlite3.Connection, member_id: int, template: str, context: dict) -> None:
    conn.execute(
        "INSERT INTO notice_outbox (member_id, template, context_json) VALUES (?, ?, ?)",
        (member_id, template, json.dumps(context)),
    )


def flush_outbox(conn: sqlite3.Connection, smtp: smtplib.SMTP, sender: str) -> int:
    rows = conn.execute(
        """
        SELECT o.id, m.email, o.template, o.context_json
        FROM notice_outbox o JOIN members m ON m.id = o.member_id
        WHERE o.sent_at IS NULL
        ORDER BY o.id
        """
    ).fetchall()
    for notice_id, email, template, context_json in rows:
        message = EmailMessage()
        message["From"] = sender
        message["To"] = email
        message["Subject"] = template.replace("_", " ").capitalize()
        message.set_content(context_json)
        smtp.send_message(message)
        conn.execute(
            "UPDATE notice_outbox SET sent_at = datetime('now') WHERE id = ?", (notice_id,)
        )
        conn.commit()
    return len(rows)
PY

cat >db/schema.sql <<'SQL'
CREATE TABLE members (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT NOT NULL,
    tier TEXT NOT NULL CHECK (tier IN ('adult', 'child', 'senior'))
);

CREATE TABLE loans (
    id INTEGER PRIMARY KEY,
    member_id INTEGER NOT NULL REFERENCES members (id),
    copy_id INTEGER NOT NULL,
    checked_out_on TEXT NOT NULL,
    due_at TEXT NOT NULL,
    returned_at TEXT
);

CREATE TABLE loan_renewals (
    id INTEGER PRIMARY KEY,
    loan_id INTEGER NOT NULL REFERENCES loans (id),
    renewed_on TEXT NOT NULL,
    extended_to TEXT NOT NULL
);

CREATE TABLE member_ledger (
    id INTEGER PRIMARY KEY,
    member_id INTEGER NOT NULL REFERENCES members (id),
    loan_id INTEGER REFERENCES loans (id),
    kind TEXT NOT NULL,
    amount_pence INTEGER NOT NULL,
    posted_on TEXT NOT NULL
);

CREATE TABLE notice_outbox (
    id INTEGER PRIMARY KEY,
    member_id INTEGER NOT NULL REFERENCES members (id),
    template TEXT NOT NULL,
    context_json TEXT NOT NULL,
    sent_at TEXT
);
SQL

cat >config/fines.toml <<'TOML'
cap_pence = 1000

[tiers.adult]
rate_pence_per_day = 20

[tiers.senior]
rate_pence_per_day = 10

[tiers.child]
rate_pence_per_day = 5
TOML

cat >bin/run-job <<'SH'
#!/usr/bin/env bash
# Usage: run-job --retries N module:function
set -u
retries=0
if [ "$1" = "--retries" ]; then
  retries="$2"
  shift 2
fi
job="$1"
attempt=0
until python3 -m library.jobrunner "$job"; do
  attempt=$((attempt + 1))
  if [ "$attempt" -gt "$retries" ]; then
    logger -t library-jobs "$job failed after $attempt attempts"
    exit 1
  fi
  sleep 60
done
SH
chmod +x bin/run-job

cat >deploy/library-jobs.cron <<'CRON'
*/10 * * * * library /opt/library/bin/run-job --retries 3 library.notify:flush_outbox
15 1 * * * library /opt/library/bin/run-job --retries 3 library.reports:rebuild_popular_titles
CRON

cat >tests/test_loans.py <<'PY'
from datetime import date
import pathlib
import sqlite3

import pytest

from library import loans


@pytest.fixture
def conn():
    connection = sqlite3.connect(":memory:")
    connection.executescript(pathlib.Path("db/schema.sql").read_text())
    connection.execute(
        "INSERT INTO members (id, name, email, tier) VALUES (1, 'A', 'a@example.invalid', 'adult')"
    )
    return connection


def test_renew_extends_effective_due_date(conn):
    loan_id = loans.checkout(conn, 1, 10, date(2026, 1, 1))
    assert loans.renew(conn, loan_id, date(2026, 1, 20)) == date(2026, 2, 5)
    assert loans.effective_due_date(conn, loan_id) == date(2026, 2, 5)


def test_renewal_limit(conn):
    loan_id = loans.checkout(conn, 1, 10, date(2026, 1, 1))
    loans.renew(conn, loan_id, date(2026, 1, 20))
    loans.renew(conn, loan_id, date(2026, 2, 1))
    with pytest.raises(loans.RenewalLimitReached):
        loans.renew(conn, loan_id, date(2026, 2, 10))
PY

cat >.work/review-target/PLAN.md <<'MD'
# Overdue fines

## Brief

### Problem
Staff chase overdue loans by hand once a month. Fines live in a spreadsheet, nothing stops a member
with a large unpaid balance from borrowing more, and finance rekeys the totals each month.

### Goal
Fines accrue automatically, members hear about them, and the balance limits further borrowing.

### Acceptance criteria
- AC1: A nightly job adds one fine entry to `member_ledger` per overdue loan per day, at the rate
  for the member's tier in `config/fines.toml`.
- AC2: `checkout` refuses a member whose unpaid fines are at or above `cap_pence`.
- AC3: On the first of each month, finance receives a CSV of the previous month's fines with one
  row per member.
- AC4: A member gets an overdue notice on the first day a loan is overdue, then at most one a week
  while it stays overdue.

### Out-of-scope
- Taking payment for fines at the desk or online.
- Waiving fines.

### Captured assumptions
- Quality bar: production
- Rates and the cap change rarely and stay in `config/fines.toml`.

## Plan

### Phase 1: Accrual job [TODO]
**Satisfies:** AC1

- Add `library/fines.py` with `accrue_fines(conn, today)`.
- Select open loans with `due_at < :today AND returned_at IS NULL`, joined to `members` for the tier.
- Insert a `member_ledger` row with `kind = 'fine'`, the tier's rate and `posted_on = today`.
- Commit after each member, so a failure on one member keeps the work done for earlier members.
- Add a 01:30 line to `deploy/library-jobs.cron` that calls `bin/run-job --retries 3
  library.fines:accrue_fines`, the same way the other jobs run.

**Sanity Check:** seed an adult member with a loan three days past `due_at`, run `accrue_fines` once,
and confirm one `fine` row of 20 pence.

### Phase 2: Checkout block [TODO]
**Satisfies:** AC2

- Add `unpaid_fines(conn, member_id)` to `library/fines.py`, summing `member_ledger.amount_pence`.
- `loans.checkout` raises `FinesCapReached` when the sum is at or above `cap_pence`.
- The desk client already shows the message of any exception `checkout` raises.

**Sanity Check:** a member at 1000 pence gets `FinesCapReached`; a member at 980 pence checks out.

### Phase 3: Overdue notices [TODO]
**Satisfies:** AC4

- Add a `last_overdue_notice_on` column to `loans`.
- In `accrue_fines`, when that column is empty or seven days old, call `notify.queue_notice` with the
  `overdue_loan` template and set the column to `today`.
- The job writes only to `notice_outbox` and opens no SMTP connection. Delivery stays with the
  ten-minute `flush_outbox` line in `deploy/library-jobs.cron`.

**Sanity Check:** run `accrue_fines` for eight consecutive dates against one overdue loan and confirm
two rows in `notice_outbox`.

### Load-bearing assumptions
- A renewal moves `loans.due_at` forward, so the Phase 1 query needs only `due_at` and `returned_at`
  to find the overdue loans.
- Every value of `members.tier` allowed by `db/schema.sql` has a rate in `config/fines.toml`.
- `config/fines.toml` amounts are in pence, matching `member_ledger.amount_pence`.

### Test strategy
Unit tests in `tests/test_fines.py` run each function against an in-memory SQLite database built from
`db/schema.sql`, as `tests/test_loans.py` does. They cover each tier's rate, a returned loan, the cap
boundary and the notice interval.

### Files affected
| File | Action |
|---|---|
| `library/fines.py` | create |
| `library/loans.py` | modify: cap check in `checkout` |
| `db/schema.sql` | modify: `last_overdue_notice_on` column |
| `deploy/library-jobs.cron` | modify: nightly line |
| `tests/test_fines.py` | create |
MD

cat >.work/review-target/design/design-resolution.md <<'MD'
outcome: early-exit
tier: C
reason: The change follows the job, ledger and outbox shapes the project already has.
MD
