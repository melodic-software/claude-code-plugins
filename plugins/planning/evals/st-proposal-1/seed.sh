#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid

mkdir -p reminders config deploy tests .work/review-target/design

cat > reminders/gateway.py <<'EOF'
"""Client for the SMS provider's HTTP API."""
import json
import socket
import time
import urllib.error
import urllib.request


class GatewayError(Exception):
    pass


def send_sms(cfg, to, body):
    gateway = cfg["gateway"]
    request = urllib.request.Request(
        gateway["url"],
        data=json.dumps({"to": to, "body": body}).encode(),
        headers={
            "Authorization": "Bearer " + gateway["token"],
            "Content-Type": "application/json",
        },
    )
    last_error = None
    for attempt in range(gateway["attempts"]):
        try:
            with urllib.request.urlopen(
                request, timeout=gateway["timeout_seconds"]
            ) as response:
                return json.load(response)["message_id"]
        except (socket.timeout, urllib.error.URLError) as exc:
            last_error = exc
            time.sleep(2**attempt)
    raise GatewayError(str(last_error))
EOF

cat > reminders/appointments.py <<'EOF'
"""Reads the practice system's nightly and hourly appointment export."""
import csv
from dataclasses import dataclass
from datetime import datetime


@dataclass(frozen=True)
class Appointment:
    appointment_id: str
    patient_phone: str
    clinician: str
    start: datetime


def load_export(path):
    with open(path, newline="", encoding="utf-8") as handle:
        return [
            Appointment(
                appointment_id=row["id"],
                patient_phone=row["phone"],
                clinician=row["clinician"],
                start=datetime.fromisoformat(row["start"]),
            )
            for row in csv.DictReader(handle)
        ]
EOF

cat > reminders/sender.py <<'EOF'
"""Hourly reminder job: text each patient whose appointment enters a window."""
import logging
import sys
import tomllib
from datetime import datetime, timedelta

from reminders.appointments import load_export
from reminders.gateway import GatewayError, send_sms

log = logging.getLogger("reminders")


def due_reminders(appointments, windows, now):
    for appointment in appointments:
        for name, hours in windows.items():
            lead = appointment.start - now
            if timedelta(hours=hours - 1) < lead <= timedelta(hours=hours):
                yield appointment, name


def render(appointment):
    when = appointment.start.strftime("%a %d %b at %H:%M")
    return f"Reminder: you are seeing {appointment.clinician} on {when}."


def run(cfg, now):
    appointments = load_export(cfg["export"]["path"])
    failures = 0
    for appointment, name in due_reminders(appointments, cfg["windows"], now):
        try:
            send_sms(cfg, appointment.patient_phone, render(appointment))
            log.info("sent %s %s", appointment.appointment_id, name)
        except GatewayError:
            failures += 1
            log.exception("gateway error for %s", appointment.appointment_id)
    return failures


def main():
    logging.basicConfig(level=logging.INFO)
    with open(sys.argv[1], "rb") as handle:
        cfg = tomllib.load(handle)
    sys.exit(1 if run(cfg, datetime.now()) else 0)


if __name__ == "__main__":
    main()
EOF

cat > config/settings.toml <<'EOF'
[export]
path = "/var/lib/reminders/appointments.csv"

[windows]
day_before = 24
two_days_before = 48

[gateway]
url = "https://sms.example.invalid/v1/messages"
token = "set-by-environment-file"
attempts = 3
timeout_seconds = 5

[storage]
data_dir = "/var/lib/reminders"
EOF

cat > deploy/reminders.service <<'EOF'
[Unit]
Description=Appointment reminder job
After=network-online.target

[Service]
Type=oneshot
User=reminders
WorkingDirectory=/opt/reminders
StateDirectory=reminders
ExecStart=/opt/reminders/venv/bin/python -m reminders.sender /opt/reminders/config/settings.toml
EOF

cat > deploy/reminders.timer <<'EOF'
[Unit]
Description=Run the appointment reminder job hourly

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
EOF

cat > tests/test_sender.py <<'EOF'
from datetime import datetime

from reminders.appointments import Appointment
from reminders.sender import due_reminders

NOW = datetime(2026, 3, 2, 9, 0)
WINDOWS = {"day_before": 24, "two_days_before": 48}


def appointment(start):
    return Appointment("a-1", "+15550100", "Dr Vale", start)


def test_inside_day_before_window():
    due = list(due_reminders([appointment(datetime(2026, 3, 3, 8, 30))], WINDOWS, NOW))
    assert [name for _, name in due] == ["day_before"]


def test_outside_every_window():
    assert not list(due_reminders([appointment(datetime(2026, 3, 9, 8, 0))], WINDOWS, NOW))
EOF

cat > .work/review-target/PLAN.md <<'EOF'
# Plan: reminder send ledger

## Brief

### Problem

The reminder job in `reminders/sender.py` keeps no record of what it has sent. It works out what is
due from the clock and the export alone, so when an operator starts the job by hand after a gateway
outage, every patient already texted that hour gets the same text. Front-desk staff took eleven
complaints about this last quarter. They also cannot answer "did this patient get a reminder?"
without asking the provider.

The practice system keeps an appointment's id when staff move it to a new time, and about one
appointment in twelve moves at least once.

### Goal

Each reminder reaches a patient exactly once per window, and staff can look up what was sent.

### Acceptance criteria

- AC1: A patient gets at most one SMS per appointment per window, including when an operator starts
  the job by hand after a failed hourly run.
- AC2: An appointment moved to a new time gets the reminders for that new time, including a window
  it already had a reminder in.
- AC3: The change adds no server process to the reminders host.
- AC4: Staff can list every reminder sent in the last 30 days with its appointment, window and
  provider message id.

### Out-of-scope

- Delivery receipts from the provider.
- Patient opt-out handling.
- Changes to the reminder wording.

### Captured assumptions

- Quality bar: production
- The job stays on the one reminders host, started by `deploy/reminders.timer`.

## Proposal

### Recommendation

Add a send ledger: a SQLite database at `<data_dir>/ledger.sqlite3`, opened by `reminders/sender.py`
at the start of each run, with one table:

```sql
CREATE TABLE sent_reminders (
  appointment_id TEXT NOT NULL,
  window_name    TEXT NOT NULL,
  message_id     TEXT NOT NULL,
  sent_at        TEXT NOT NULL,
  PRIMARY KEY (appointment_id, window_name)
);
```

For each item from `due_reminders`, the job looks up `(appointment_id, window_name)`. A row present
means the reminder has gone out and the job moves on to the next item. Otherwise it calls `send_sms`
and, once that returns a message id, inserts the row and commits.

A small `python -m reminders.ledger list --days 30` command prints the table for staff, and each run
deletes rows older than 90 days.

### Why this approach

The ledger gives the job the memory it lacks while leaving `due_reminders` as it is: the window
arithmetic stays pure and its tests stay valid. A primary key on the pair makes the rule "one per
appointment per window" a property of the schema.

The insert follows the send so that the ledger records only what the provider accepted. A gateway
outage then leaves no row behind, and the next hand-started run picks up exactly the patients the
outage missed.

### Alternatives considered

- **Postgres or another database server.** It would need a server process on the host, which AC3
  excludes, and nothing else in this project talks to one.
- **Ask the provider what it has sent.** Its search API would make the job depend on a second
  endpoint being up, and it answers by phone number, with no appointment or window attached.
- **A JSON file per day.** It needs its own atomic-replace and pruning code, and staff lookups would
  mean a script reading many files. SQLite's standard-library module gives both for free.

### Load-bearing assumptions

- `tomllib` and `sqlite3` come with the Python on the host, so no new package is needed.
- One `send_sms` call produces one request to the provider, so a row maps to one text the patient
  received.
- `<data_dir>` is persistent across host restarts, since `deploy/reminders.service` declares it as
  the state directory.

### Rollout

1. Ship the ledger module and the job change behind `storage.ledger_enabled = false`.
2. Enable it on the host and watch one day of hourly runs, comparing ledger rows against the
   provider's dashboard.
3. Tell front-desk staff about the list command and retire the provider-dashboard lookup.
EOF

cat > .work/review-target/design/design-resolution.md <<'EOF'
outcome: early-exit
tier: C
reason: One small module with no new contract between components.
EOF
