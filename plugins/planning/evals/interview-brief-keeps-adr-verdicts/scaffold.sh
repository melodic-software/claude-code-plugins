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
import urllib.request


def send(url, event):
    """Post one event to a partner endpoint once; a failure is logged and dropped."""
    body = json.dumps(event).encode()
    request = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
    try:
        urllib.request.urlopen(request, timeout=10)
    except OSError as error:
        print(f"webhook failed: {url}: {error}")
PY

cat >tests/test_sender.py <<'PY'
def test_placeholder():
    assert True
PY

cat >.work/webhook-retries/interview-checklist.md <<'MD'
# /planning:interview Checklist

## Constraint ledger

- C1 | confirmed | Postgres is the only datastore this service may write to | user, round 1

## Open-question register

- Q1 | answered | round 1 | How many delivery attempts per event? | accepted: five attempts in total
- Q2 | answered | round 1 | What backoff between attempts? | accepted: exponential, starting at 30 seconds, capped at 30 minutes
- Q3 | answered | round 2 | Where are failed deliveries stored? | accepted: a failed_deliveries Postgres table (a Redis stream was weighed and rejected under C1)
- Q4 | answered | round 2 | Who is alerted when an event exhausts its attempts? | accepted: the integrations channel in chat
MD

git add .
git commit -q -m "feat: partner webhook sender"
