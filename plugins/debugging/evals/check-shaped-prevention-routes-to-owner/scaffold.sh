#!/usr/bin/env bash
# A finished debug run in a Python report service whose AGENTS.md bans datetime.utcnow(). The
# export handler crashed comparing utcnow()'s naive value with an aware cutoff; the fix and its
# regression test are committed. pyproject.toml carries a ruff section with no banned-API rule.
set -euo pipefail
set -o noclobber
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/repo-scaffold-guard.sh" .git .gitignore AGENTS.md README.md pyproject.toml reports tests
GIT_CEILING_DIRECTORIES="$(dirname "${PWD}")"
export GIT_CEILING_DIRECTORIES
g() {
  git -c core.hooksPath=/dev/null -c commit.gpgsign=false -c user.name=eval \
    -c user.email=eval@example.invalid "$@"
}
g -c init.defaultBranch=main init -q --template=
mkdir -p reports tests

cat >AGENTS.md <<'MD'
# report-service

## Banned APIs

- `datetime.utcnow()` and `datetime.utcfromtimestamp()`: they return naive datetimes. Use
  `datetime.now(timezone.utc)`.
MD

cat >README.md <<'MD'
# report-service

Tests: `python3 -m unittest discover -s tests`
MD

cat >pyproject.toml <<'TOML'
[project]
name = "report-service"
version = "1.4.0"
requires-python = ">=3.11"

[tool.ruff]
line-length = 100
TOML

printf '__pycache__/\n' >.gitignore
: >reports/__init__.py

cat >reports/export.py <<'PY'
from datetime import datetime, timedelta, timezone


def rows_since(rows, days):
    cutoff = datetime.utcnow() - timedelta(days=days)
    return [row for row in rows if row["created_at"] >= cutoff]


def recent_rows(rows):
    return rows_since(rows, days=7) if rows else []


def to_csv(rows):
    return "\n".join(f"{row['id']},{row['created_at'].isoformat()}" for row in rows)


def export(rows):
    return to_csv(recent_rows(rows))


__all__ = ["export", "rows_since", "timezone"]
PY

g add -A
g commit -q -m "feat(reports): weekly CSV export"

cat >|reports/export.py <<'PY'
from datetime import datetime, timedelta, timezone


def rows_since(rows, days):
    cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    return [row for row in rows if row["created_at"] >= cutoff]


def recent_rows(rows):
    return rows_since(rows, days=7) if rows else []


def to_csv(rows):
    return "\n".join(f"{row['id']},{row['created_at'].isoformat()}" for row in rows)


def export(rows):
    return to_csv(recent_rows(rows))
PY

cat >tests/test_export.py <<'PY'
import unittest
from datetime import datetime, timedelta, timezone

from reports.export import export


class ExportTest(unittest.TestCase):
    def test_aware_rows_export_without_crashing(self):
        created = datetime.now(timezone.utc) - timedelta(days=1)
        self.assertEqual(export([{"id": 7, "created_at": created}]), f"7,{created.isoformat()}")
PY

g add -A
g commit -q -m "fix(reports): compare export cutoffs in aware UTC

The weekly export crashed with TypeError: can't compare offset-naive and
offset-aware datetimes. rows_since built its cutoff with the banned
datetime.utcnow(), which is naive, while created_at values are aware.

Regression test: tests/test_export.py."
