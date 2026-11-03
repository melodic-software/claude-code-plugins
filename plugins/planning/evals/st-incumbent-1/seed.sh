#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid

mkdir -p reminders config deploy docs/vendor .work/review-target/design

cat >requirements.txt <<'TXT'
httpx==0.27.2
pyyaml==6.0.2
tickwheel==2.8.1
TXT

cat >reminders/scheduler.py <<'PY'
"""Registers one daily reminder job per clinic and runs the wheel."""
import os
from zlib import crc32

import yaml
from tickwheel import Wheel

from reminders.sender import send_due_reminders


def clinics_for_shard(clinics, shard_index, shard_count):
    return [c for c in clinics if crc32(c["id"].encode()) % shard_count == shard_index]


def build_wheel(config_path="config/clinics.yaml"):
    with open(config_path, encoding="utf-8") as handle:
        clinics = yaml.safe_load(handle)["clinics"]
    shard_index = int(os.environ["SHARD_INDEX"])
    shard_count = int(os.environ["SHARD_COUNT"])
    wheel = Wheel()
    for clinic in clinics_for_shard(clinics, shard_index, shard_count):
        wheel.daily(
            send_due_reminders,
            at=clinic["send_at"],
            utc_offset=clinic["utc_offset"],
            args=(clinic["id"],),
        )
    return wheel


if __name__ == "__main__":
    build_wheel().run_forever()
PY

cat >reminders/sender.py <<'PY'
"""Sends one clinic's due reminders through the Postrider gateway."""
import os
import sqlite3
from collections import namedtuple

import httpx

BATCH_SIZE = 200
GATEWAY_URL = "https://gateway.postrider.example/v2/messages"

Reminder = namedtuple("Reminder", "id phone")


def _connect():
    return sqlite3.connect(os.environ["REMINDER_DB"])


def due_reminders(clinic_id):
    with _connect() as db:
        rows = db.execute(
            "SELECT id, phone FROM reminders"
            " WHERE clinic_id = ? AND sent_at IS NULL AND due_on = date('now')",
            (clinic_id,),
        ).fetchall()
    return [Reminder(*row) for row in rows]


def mark_sent(ids):
    with _connect() as db:
        db.executemany(
            "UPDATE reminders SET sent_at = datetime('now') WHERE id = ?",
            [(reminder_id,) for reminder_id in ids],
        )


def send_due_reminders(clinic_id):
    reminders = due_reminders(clinic_id)
    headers = {"Authorization": f"Bearer {os.environ['POSTRIDER_TOKEN']}"}
    with httpx.Client(timeout=20.0, headers=headers) as client:
        for start in range(0, len(reminders), BATCH_SIZE):
            batch = reminders[start : start + BATCH_SIZE]
            response = client.post(
                GATEWAY_URL,
                json={"recipients": [r.phone for r in batch], "template": "appointment"},
            )
            response.raise_for_status()
            mark_sent([r.id for r in batch])
PY

cat >config/clinics.yaml <<'YAML'
clinics:
  - id: maple-street
    display_name: Maple Street Veterinary
    timezone: America/Chicago
    utc_offset: "-06:00"
    send_at: "09:00"
  - id: harbor-road
    display_name: Harbor Road Animal Clinic
    timezone: America/New_York
    utc_offset: "-05:00"
    send_at: "09:00"
  - id: ridgeview
    display_name: Ridgeview Pet Care
    timezone: America/Denver
    utc_offset: "-07:00"
    send_at: "09:00"
YAML

cat >deploy/compose.yaml <<'YAML'
services:
  worker-0:
    image: registry.example/reminders:latest
    command: python -m reminders.scheduler
    environment:
      SHARD_INDEX: "0"
      SHARD_COUNT: "2"
      REMINDER_DB: /data/clinic.db
    volumes:
      - clinic-data:/data
  worker-1:
    image: registry.example/reminders:latest
    command: python -m reminders.scheduler
    environment:
      SHARD_INDEX: "1"
      SHARD_COUNT: "2"
      REMINDER_DB: /data/clinic.db
    volumes:
      - clinic-data:/data
volumes:
  clinic-data:
YAML

cat >docs/vendor/tickwheel-changelog.md <<'MD'
# Tickwheel changelog

## 3.0.0

- New `FileJobStore(path)`: pass as `Wheel(store=...)` to keep jobs across restarts.
- On start, the wheel loads every job in the store file and schedules it.
- A store file serves one Wheel at a time. The store takes no file lock.

## 2.8.1

- Fixed a drift of up to one second in `daily` triggers under load.

## 2.8.0

- `daily(fn, at, utc_offset)`: `utc_offset` is a literal value such as `-06:00`.
- The offset applies unchanged to every firing of the job.
- Tickwheel ships no zone database and does not read zone names.
MD

cat >docs/vendor/cadenza-notes.md <<'MD'
# Cadenza scheduler notes

Cadenza runs jobs from a schedule held in a message broker.

- Requires a running Starling broker; there is no brokerless mode.
- Triggers accept zone names such as `Europe/Paris`.
- One firing per job across all consumers of a queue.
- Python 3.11 or later.
MD

cat >docs/vendor/postrider-api.md <<'MD'
# Postrider gateway API, v2

`POST /v2/messages` sends one template to a list of recipients.

- `recipients`: at most 200 entries; a longer list is refused with HTTP 413.
- Rate limit: 20 requests per second per token.
- A request is accepted or refused as a whole.
MD

cat >.work/review-target/design/design-resolution.md <<'MD'
---
outcome: early-exit
tier: C
reason: the Brief names the scheduling decision and its options; no type or module design is open
---
MD

cat >.work/review-target/PLAN.md <<'MD'
# Appointment reminder scheduling

## Brief

### Problem

The reminder workers hold each day's schedule in memory. A redeploy between midnight and 09:00
drops that morning's jobs, and clinics find out when owners miss appointments. We have also been
asked whether Tickwheel is still the right scheduler, or whether this is the moment to move.

### Goal

Decide whether to keep Tickwheel, and make scheduled reminders dependable for all three clinics.

### Acceptance criteria

- AC1: Each clinic's reminders leave at 09:00 clinic-local time on every day of the year.
- AC2: Restarting or redeploying the workers neither loses nor repeats a scheduled reminder.
- AC3: A peak day of 40,000 reminders is fully sent by 09:30 clinic-local time.

### Out-of-scope

- Reminder wording and templates.
- New channels beyond SMS.
- The clinic portal.

### Captured assumptions

- Quality bar: production
- The workers stay in Python.
- Reminder volume stays within the peak in AC3 for the next year.

## Plan

### Decision

Keep Tickwheel. Turn on its persistent job store and leave the send path on Postrider as it is.

### Why

- Tickwheel's `daily` trigger takes a `utc_offset` per job, and `config/clinics.yaml` holds one for
  each clinic, so AC1 is met by the schedule we have today.
- The Tickwheel release in our image includes `FileJobStore`, which gives AC2 without new
  infrastructure: a job store on disk, read back when a worker starts.
- Cadenza is the main alternative. It needs a running Starling broker, and `deploy/compose.yaml`
  runs none, so moving means operating a new stateful service for three clinics.

### Phase 1: Persist the schedule [TODO]

**Satisfies:** AC2

Change `build_wheel` in `reminders/scheduler.py` to create
`Wheel(store=FileJobStore("/state/jobs.db"))`. Add a `reminders-state` volume in
`deploy/compose.yaml`, mounted at `/state` on the worker services.

**Sanity Check:** in staging, restart the workers at 08:00 and confirm the 09:00 jobs still fire.

### Phase 2: Stable job registration [TODO]

**Satisfies:** AC1, AC2

Give each `daily` job a stable id of `clinic:<id>` and register it with `replace=True`, so a worker
start refreshes a clinic's job instead of adding another. Keep `send_at` and `utc_offset` in
`config/clinics.yaml` as the single place a clinic's schedule is set.

**Sanity Check:** start a worker twice against one store and confirm the job list has one entry per
clinic.

### Phase 3: Peak-day send rate [TODO]

**Satisfies:** AC3

Keep `BATCH_SIZE` at 200 in `reminders/sender.py`, since the Postrider request limit in
`docs/vendor/postrider-api.md` is 200 recipients. Add a pause between requests that holds a worker
to 15 requests per second, under the gateway's rate limit. At that rate one worker sends 40,000
reminders in under 15 seconds.

**Sanity Check:** run 40,000 reminders against the gateway sandbox and record the finish time.

### Load-bearing assumptions

- A worker can read the job store as soon as its volume is mounted.
- `mark_sent` runs after each accepted batch, so a restart mid-send resumes from the unsent rows.

### Test strategy

- Unit: `build_wheel` registers one job per clinic for the shard, with the configured time and
  offset.
- Integration: a worker restart in staging keeps its jobs, checked with the store's job list.
- Load: the sandbox run in Phase 3 finishes inside the AC3 window.
MD
