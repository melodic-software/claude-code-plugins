#!/usr/bin/env bash
# A Python pipeline with a migration that defines a table the service reads back as a record. The
# graded outcome is a row record derived from the migration instead of a hand-kept copy.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p pipeline .work/deploy-records/design

printf '.work/\n__pycache__/\n' >.gitignore

cat >pyproject.toml <<'TOML'
[project]
name = "pipeline"
version = "0.1.0"
requires-python = ">=3.12"
TOML

mkdir -p migrations
cat >migrations/001_deployments.sql <<'SQL'
CREATE TABLE deployments (
  id BIGINT PRIMARY KEY,
  service TEXT NOT NULL,
  requested_at TIMESTAMPTZ NOT NULL
);
SQL

cat >pipeline/__init__.py <<'PY'
PY

cat >pipeline/models.py <<'PY'
from dataclasses import dataclass


@dataclass
class Run:
    status: str
    log_url: str | None = None
    failure_reason: str | None = None
PY

cat >pipeline/report.py <<'PY'
from pipeline.models import Run


def describe(run: Run) -> str:
    if run.status == "passed":
        return f"passed: {run.log_url}"
    elif run.status == "failed":
        return f"failed: {run.failure_reason}"
    else:
        return run.status
PY

cat >.work/deploy-records/PLAN.md <<'MD'
# Deployment records

## Brief

### Goal
A deployment is requested, then deploying, then either live with its URL or rolled back with the
reason. Every deployment has the columns migrations/001_deployments.sql defines, which the service
reads back as a row record.

### Acceptance criteria
- The reporting function describes a deployment in each state.

### Captured assumptions
- Quality bar: production
MD

cat >.work/deploy-records/design/design-threads.md <<'MD'
# Design threads

## Module placement: resolved
Deployment types live in pipeline/models.py and the reporting function in pipeline/report.py.
MD

git add .
git commit -q -m "feat: pipeline runs"
