#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Ingest Claude Code transcripts into the audit-sessions store.

    collect.py collect --data-dir D [--projects-root P]

Writes one `session-record/v1` file per main session under `D/audit-sessions/store/v1/`, the
machine-wide store `sweep.py` reads. Prints one JSON envelope on stdout; exit 0 pass, 1 warning,
2 error. Stdlib only; Python 3.10+.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

PLUGIN_ROOT = Path(__file__).resolve().parents[3]
_PLUGIN_SCRIPTS = str(PLUGIN_ROOT / "scripts")
if _PLUGIN_SCRIPTS not in sys.path:
    sys.path.insert(0, _PLUGIN_SCRIPTS)

import transcript_reader  # noqa: E402  (plugin-level scripts/transcript_reader.py)

SCHEMA = "audit-sessions.collect/v1"
RECORD_SCHEMA = "session-record/v1"


def emit(status: str, summary: str, data: dict, code: int) -> int:
    print(json.dumps({"schema": SCHEMA, "status": status, "summary": summary, "data": data}, indent=2))
    return code


def default_projects_root() -> Path:
    config_dir = os.environ.get("CLAUDE_CONFIG_DIR")
    return (Path(config_dir) if config_dir else Path.home() / ".claude") / "projects"


def collector_version() -> str:
    try:
        manifest = json.loads((PLUGIN_ROOT / ".claude-plugin" / "plugin.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return "unknown"
    return manifest.get("version", "unknown")


def store_dir(data_dir: Path) -> Path:
    return data_dir / "audit-sessions" / "store" / "v1" / "sessions"


def project_segment(project_dir: str) -> str:
    return "p-" + hashlib.sha256(project_dir.encode("utf-8")).hexdigest()[:12]


def write_atomic(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            json.dump(payload, handle, indent=2, sort_keys=True)
            handle.write("\n")
        os.replace(tmp, path)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


def build_record(transcript: Path, version: str) -> dict:
    stats: dict[str, int] = {"files": 1, "records": 0, "bad_lines": 0}
    main = transcript_reader.UsageLedger()
    turns = 0
    for record in transcript_reader.iter_records(transcript, stats):
        if record.get("type") == "assistant":
            main.add(record)
        elif transcript_reader.is_typed_turn(record):
            turns += 1
    return {
        "schema": RECORD_SCHEMA,
        "collector_version": version,
        "ingested_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "session_id": transcript.stem,
        "project_dir": transcript.parent.name,
        "tokens": {"main": main.totals(), "sub": transcript_reader.UsageLedger().totals()},
        "human": {"turns": turns, "flagged": []},
        "parse": stats,
    }


def cmd_collect(args: argparse.Namespace) -> int:
    started = time.monotonic()
    root = Path(args.projects_root) if args.projects_root else default_projects_root()
    if not root.is_dir():
        return emit("error", f"projects root not readable: {root}", {"projects_root": str(root)}, 2)
    store = store_dir(Path(args.data_dir))
    version = collector_version()
    scanned = ingested = 0
    failed: list[dict] = []
    for transcript in sorted(root.glob("*/*.jsonl")):
        scanned += 1
        try:
            record = build_record(transcript, version)
            write_atomic(store / project_segment(transcript.parent.name) / f"{transcript.stem}.json", record)
        except OSError as exc:
            failed.append({"session_id": transcript.stem, "reason": str(exc)})
            continue
        ingested += 1
    data = {
        "projects_root": str(root),
        "scanned": scanned,
        "ingested": ingested,
        "skipped_unchanged": 0,
        "failed": failed,
        "store_records": sum(1 for _ in store.glob("p-*/*.json")) if store.is_dir() else 0,
        "elapsed_s": round(time.monotonic() - started, 3),
    }
    status, code = ("warning", 1) if failed else ("pass", 0)
    return emit(status, f"ingested {ingested} of {scanned} sessions", data, code)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Ingest Claude Code transcripts into the audit-sessions store.")
    sub = parser.add_subparsers(dest="command", required=True)
    collect = sub.add_parser("collect", help="ingest transcripts into the store")
    collect.add_argument("--data-dir", required=True)
    collect.add_argument("--projects-root")
    collect.set_defaults(func=cmd_collect)
    try:
        args = parser.parse_args(argv)
    except SystemExit as exc:
        if exc.code == 0:
            raise
        return emit("error", "bad arguments", {}, 2)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
