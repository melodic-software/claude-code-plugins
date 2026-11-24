#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p jobq tests
cat >README.md <<'MD'
# jobq

Workers poll `jobs` and claim one job at a time. A job is run by at most one worker, and a
claim held past its lease is released so another worker can take it.
MD
: >jobq/__init__.py
cat >jobq/claim.py <<'PY'
import time

LEASE_SECONDS = 30


def claim(store, job_id, worker_id, now=None):
    """Claim job_id for worker_id. At most one worker holds a job at a time."""
    now = time.time() if now is None else now
    job = store.get(job_id)
    if job["state"] == "done":
        return False
    if job["owner"] is not None and job["lease_until"] > now:
        return False
    # Compare-and-set on the version read above, so two workers that read the same
    # free job cannot both win.
    return store.compare_and_set(
        job_id,
        expected_version=job["version"],
        owner=worker_id,
        lease_until=now + LEASE_SECONDS,
    )


def finish(store, job_id, worker_id):
    job = store.get(job_id)
    if job["owner"] != worker_id:
        raise PermissionError("only the owner can finish a job")
    store.compare_and_set(job_id, expected_version=job["version"], state="done", owner=None)
PY
cat >jobq/store.py <<'PY'
import threading


class MemoryStore:
    def __init__(self):
        self._lock = threading.Lock()
        self._jobs = {}

    def add(self, job_id):
        self._jobs[job_id] = {"state": "queued", "owner": None, "lease_until": 0, "version": 0}

    def get(self, job_id):
        with self._lock:
            return dict(self._jobs[job_id])

    def compare_and_set(self, job_id, expected_version, **fields):
        with self._lock:
            job = self._jobs[job_id]
            if job["version"] != expected_version:
                return False
            job.update(fields)
            job["version"] += 1
            return True
PY
cat >tests/test_claim.py <<'PY'
import unittest

from jobq.claim import claim
from jobq.store import MemoryStore


class ClaimTest(unittest.TestCase):
    def test_second_claim_loses_while_lease_holds(self):
        store = MemoryStore()
        store.add("j1")
        self.assertTrue(claim(store, "j1", "w1", now=0))
        self.assertFalse(claim(store, "j1", "w2", now=10))


if __name__ == "__main__":
    unittest.main()
PY
git add .
git commit -q -m "jobq: claim with lease and compare-and-set"
