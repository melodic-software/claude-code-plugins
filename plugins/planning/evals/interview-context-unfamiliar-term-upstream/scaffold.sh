#!/usr/bin/env bash
# Seeds a triage intake that files one issue per report and a vendored upstream README whose cluster step groups reports by a coined term.
set -euo pipefail

mkdir -p triage vendor/upstream-triage
cat >triage/__init__.py <<'PY'
PY
cat >triage/intake.py <<'PY'
from triage.tracker import Tracker


class Intake:
    """Turns each incoming crash report into a tracker issue."""

    def __init__(self, tracker: Tracker) -> None:
        self._tracker = tracker

    def receive(self, report: dict) -> str:
        # Every report becomes its own issue; nothing groups repeats.
        title = report["error"].splitlines()[0]
        return self._tracker.open_issue(title, report["body"])
PY
cat >triage/tracker.py <<'PY'
class Tracker:
    def __init__(self) -> None:
        self.issues = []

    def open_issue(self, title: str, body: str) -> str:
        self.issues.append((title, body))
        return f"ISSUE-{len(self.issues)}"
PY
cat >vendor/upstream-triage/README.md <<'MD'
# upstream-triage

Crash-report triage for small teams.

## Pipeline

1. Normalize: strip addresses, line numbers and temp paths from the first error line.
2. Cluster: compute the report's dedupe fingerprint, a SHA-1 of the normalized first error line,
   and attach the report to the open cluster with the same fingerprint instead of opening a new
   issue.
3. Escalate: a cluster that gains 10 reports in an hour pages the owner.

## Why clustering

Without the cluster step, one crash seen by many users opens one issue per user, and the real
count of distinct crashes is hidden under duplicates.

## Limits

A fingerprint ignores everything below the first error line, so two different crashes with the
same first line share a cluster. Teams split such a cluster by hand.
MD
