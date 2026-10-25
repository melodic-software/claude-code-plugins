#!/usr/bin/env bash
# A draft plan for a 30-day log retention window whose file list writes the 30 into the cleanup
# job, the admin API view and the operator docs, each as its own literal, while the repo already
# keeps shared limits in app/settings.py. The plan reviewer should flag the spread fact.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p app/cleanup app/api docs .work/log-retention

cat >app/__init__.py <<'PY'
PY

cat >app/settings.py <<'PY'
MAX_UPLOAD_BYTES = 25 * 1024 * 1024
SESSION_TIMEOUT_MINUTES = 60
PY

cat >app/cleanup/__init__.py <<'PY'
PY

cat >app/cleanup/job.py <<'PY'
from app.settings import SESSION_TIMEOUT_MINUTES


def purge_sessions(store, now):
    store.delete_older_than(now, minutes=SESSION_TIMEOUT_MINUTES)
PY

cat >app/api/__init__.py <<'PY'
PY

cat >app/api/settings_view.py <<'PY'
from app.settings import MAX_UPLOAD_BYTES


def get_limits():
    return {"max_upload_bytes": MAX_UPLOAD_BYTES}
PY

cat >docs/operations.md <<'MD'
# Operations

Sessions expire after the timeout in `app/settings.py`.
MD

cat >.work/log-retention/PLAN.md <<'MD'
# Audit log retention

## Brief

### Goal
Delete audit log entries older than 30 days, show the window to admins, and document it for operators.

### Acceptance criteria
- A nightly job deletes audit log entries older than 30 days.
- GET /admin/limits reports the retention window.
- docs/operations.md states the retention window.

### Captured assumptions
- Quality bar: production

## Plan

### Phase 1: Retention job, API and docs
- `app/cleanup/job.py`: add `AUDIT_RETENTION_DAYS = 30` and `purge_audit_log(store, now)`, which
  deletes entries older than `AUDIT_RETENTION_DAYS`.
- `app/api/settings_view.py`: add `"audit_retention_days": 30` to the `get_limits()` response.
- `docs/operations.md`: add "Audit log entries are deleted after 30 days."
- **Sanity Check:** `pytest tests/test_cleanup.py` exits 0.

### Files affected
| File | Action |
|---|---|
| app/cleanup/job.py | modify: new constant and purge function |
| app/api/settings_view.py | modify: new response field |
| docs/operations.md | modify: new sentence |

### Test strategy
Unit test `purge_audit_log` with entries 29 and 31 days old.
MD

git add .
git commit -q -m "feat: settings and session cleanup"
