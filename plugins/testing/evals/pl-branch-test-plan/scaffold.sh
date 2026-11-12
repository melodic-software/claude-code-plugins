#!/usr/bin/env bash
# Stages a small web service on main, then a branch adding a duration parser,
# an export route, a container registration, a type-only module, a parser of a hook payload read
# from another process, a client of a service whose build verifies its consumers' contracts and a
# client of a public third-party API.
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

cat >src/hook_payload.py <<'PY'
import json
import sys

REQUIRED = ("session_id", "tool_name", "tool_input")


def parse_hook_payload(raw):
    """Parse the JSON another process's hook runner writes to stdin. Raises ValueError otherwise."""
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ValueError(f"payload is not JSON: {exc}") from None
    if not isinstance(data, dict) or any(key not in data for key in REQUIRED):
        raise ValueError("payload is missing a required field")
    tool_input = data["tool_input"] if isinstance(data["tool_input"], dict) else {}
    return {"session": data["session_id"], "tool": data["tool_name"], "command": str(tool_input.get("command", ""))}


if __name__ == "__main__":
    print(parse_hook_payload(sys.stdin.read()))
PY

cat >src/billing_client.py <<'PY'
import json
from urllib import request


class BillingClient:
    """Client of the payments team's billing-service. That service's CI verifies the contracts its
    consumers publish before every deploy. Relies on POST /invoices returning 201 with
    {"invoice_id": str, "status": "open" | "paid"}."""

    def __init__(self, base_url="http://billing-service.internal", opener=request.urlopen):
        self._base = base_url
        self._open = opener

    def create_invoice(self, order_id, total_cents):
        body = json.dumps({"order_id": order_id, "amount_cents": total_cents}).encode()
        req = request.Request(
            f"{self._base}/invoices",
            data=body,
            method="POST",
            headers={"Content-Type": "application/json"},
        )
        with self._open(req) as resp:
            payload = json.load(resp)
        return payload["invoice_id"], payload["status"]
PY

cat >src/weather_client.py <<'PY'
import json
from urllib import parse, request


class WeatherClient:
    """Client of a public third-party forecast API; we have no access to its provider's build."""

    def __init__(self, base_url="https://api.weather.example/v1", opener=request.urlopen):
        self._base = base_url
        self._open = opener

    def forecast_c(self, city):
        url = f"{self._base}/forecast?{parse.urlencode({'city': city})}"
        with self._open(url) as resp:
            return float(json.load(resp)["temperature_c"])
PY

git -c user.name=dev -c user.email=dev@example.invalid add -A
git -c user.name=dev -c user.email=dev@example.invalid commit -q -m "Add report export, duration parsing, hook payloads and service clients"
printf '/.*\n' >>.git/info/exclude
