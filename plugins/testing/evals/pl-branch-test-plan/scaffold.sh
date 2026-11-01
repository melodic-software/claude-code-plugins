#!/usr/bin/env bash
# Stages a small web service on main, then a branch adding a duration parser,
# an export route, a container registration and a type-only module.
set -euo pipefail

mkdir -p src/api src/config src/models tests
: >src/__init__.py
: >src/api/__init__.py
: >src/config/__init__.py
: >src/models/__init__.py
: >tests/__init__.py

cat >src/api/routes.py <<'PY'
ROUTES = {}


def route(path):
    def register(fn):
        ROUTES[path] = fn
        return fn
    return register


@route("/reports/<id>")
def get_report(report_id, store):
    report = store.get(report_id)
    return (404, None) if report is None else (200, report)
PY

cat >src/config/container.py <<'PY'
def build(registry):
    registry["store"] = "postgres"
    return registry
PY

cat >tests/test_routes.py <<'PY'
from src.api.routes import get_report


def test_get_report_missing_returns_404():
    assert get_report("r1", {}) == (404, None)
PY

git init -q -b main
git -c user.name=dev -c user.email=dev@example.invalid add -A
git -c user.name=dev -c user.email=dev@example.invalid commit -q -m "Add report routes"
git checkout -q -b feat/report-export

cat >src/duration.py <<'PY'
import re

_PART = re.compile(r"(\d+)([hms])")
_UNIT = {"h": 3600, "m": 60, "s": 1}


def parse_duration(text):
    """Parse '1h30m', '45s' or '2h' into seconds. Raises ValueError on anything else."""
    if not text or not re.fullmatch(r"(?:\d+[hms])+", text):
        raise ValueError(f"not a duration: {text!r}")
    return sum(int(n) * _UNIT[u] for n, u in _PART.findall(text))
PY

cat >>src/api/routes.py <<'PY'


@route("/reports/<id>/export")
def export_report(report_id, store, exporter):
    report = store.get(report_id)
    if report is None:
        return (404, None)
    return (200, exporter.to_csv(report))
PY

cat >src/exporter.py <<'PY'
import csv
import io


class ReportExporter:
    def to_csv(self, report):
        buf = io.StringIO()
        writer = csv.writer(buf)
        writer.writerow(["id", "title", "total_cents"])
        writer.writerow([report["id"], report["title"], report["total_cents"]])
        return buf.getvalue()
PY

cat >src/config/container.py <<'PY'
from src.exporter import ReportExporter


def build(registry):
    registry["store"] = "postgres"
    registry["exporter"] = ReportExporter()
    return registry
PY

cat >src/models/types.py <<'PY'
from typing import TypedDict


class ReportRow(TypedDict):
    id: str
    title: str
    total_cents: int


class ExportRequest(TypedDict):
    report_id: str
    fmt: str
PY

git -c user.name=dev -c user.email=dev@example.invalid add -A
git -c user.name=dev -c user.email=dev@example.invalid commit -q -m "Add report export and duration parsing"
printf '/.*\n' >>.git/info/exclude
