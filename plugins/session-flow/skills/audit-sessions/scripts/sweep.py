#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Report measured session metrics from the audit-sessions store.

    sweep.py --data-dir D [--format json|md]

Reads only the `session-record/v1` files `collect.py` wrote; it never opens a transcript. Prints
one JSON envelope (or markdown) on stdout; exit 0 pass, 1 warning, 2 error. Stdlib only; Python
3.10+.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

SCHEMA = "audit-sessions.sweep/v1"
RECORD_SCHEMA = "session-record/v1"


def load_records(data_dir: Path) -> list[dict]:
    store = data_dir / "audit-sessions" / "store" / "v1" / "sessions"
    records = []
    for path in sorted(store.glob("p-*/*.json")):
        record = json.loads(path.read_text(encoding="utf-8"))
        if record.get("schema") != RECORD_SCHEMA:
            raise ValueError(f"{path}: schema {record.get('schema')!r}, expected {RECORD_SCHEMA}")
        records.append(record)
    return records


def build_data(records: list[dict]) -> dict:
    return {
        "window": {"since": None, "until": None, "sessions": len(records), "cc_versions": []},
        "scope": "machine",
        "metrics": {
            "tokens.main.output": {
                "value": sum(r["tokens"]["main"]["output"] for r in records),
                "unit": "tokens",
                "n": len(records),
            },
        },
        "findings": [],
        "drift": None,
        "unchecked": [],
        "suggestions": [],
    }


def render_md(data: dict) -> str:
    lines = [f"# Session audit ({data['scope']})", "", f"Sessions: {data['window']['sessions']}", ""]
    lines += ["| Metric | Value | Unit | n |", "|---|---|---|---|"]
    for metric, row in data["metrics"].items():
        lines.append(f"| {metric} | {row['value']} | {row['unit']} | {row['n']} |")
    return "\n".join(lines) + "\n"


def emit(fmt: str, status: str, summary: str, data: dict, code: int) -> int:
    if fmt == "md" and status != "error":
        sys.stdout.write(render_md(data))
    else:
        print(json.dumps({"schema": SCHEMA, "status": status, "summary": summary, "data": data}, indent=2))
    return code


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Report measured session metrics from the audit-sessions store.")
    parser.add_argument("--data-dir", required=True)
    parser.add_argument("--format", choices=("json", "md"), default="json")
    try:
        args = parser.parse_args(argv)
    except SystemExit as exc:
        if exc.code == 0:
            raise
        return emit("json", "error", "bad arguments", {}, 2)
    try:
        records = load_records(Path(args.data_dir))
    except (OSError, ValueError) as exc:
        return emit(args.format, "error", str(exc), {}, 2)
    data = build_data(records)
    return emit(args.format, "pass", f"{len(records)} sessions", data, 0)


if __name__ == "__main__":
    sys.exit(main())
