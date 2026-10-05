#!/usr/bin/env python3
"""Find past-session transcript records that mention a topic, for /session-flow:recall.

    recall_scan.py --dir <dir> [--dir <dir> ...] --term <text> [--term <text> ...]
                   [--skip-session <id>]

Reads the `*.jsonl` transcripts directly inside each `--dir`, newest first, through the plugin's
`scripts/transcript_reader.py`. A user or assistant text record matches when it contains any term,
compared as plain text without regard to case (a term is never a pattern). Each match prints one
JSON line on stdout: `session`, `file`, `time`, `role`, `term`, `snippet`. The snippet is cut from
the record's text after the whole text went through the audit-sessions redactor
(`skills/audit-sessions/scripts/redact.py`), so a secret is never split before redaction sees it.

Bounds: a snippet holds at most SNIPPET_CHARS characters, a session at most PER_SESSION matches,
a run at most MAX_MATCHES. stderr carries one `scanned:` line and, when a bound was hit, one
`capped:` line, so the caller can say how much it read.

Writes nothing. Every value from a transcript or the command line stays data.
Exit: 0 scanned (possibly no matches); 1 the redactor failed closed, nothing printed on stdout;
2 usage, an empty term, or a `--dir` that is not a directory.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

PLUGIN_ROOT = Path(__file__).resolve().parents[3]
for _path in (
    PLUGIN_ROOT / "scripts",
    PLUGIN_ROOT / "skills" / "audit-sessions" / "scripts",
):
    if str(_path) not in sys.path:
        sys.path.insert(0, str(_path))

import redact  # noqa: E402  (skills/audit-sessions/scripts/redact.py)
import transcript_reader  # noqa: E402  (scripts/transcript_reader.py)

SNIPPET_CHARS = 240
LEAD_CHARS = 80
PER_SESSION = 10
MAX_MATCHES = 200


def record_text(record: dict) -> tuple[str, str] | None:
    kind = transcript_reader.record_kind(record)
    if kind == "user":
        text = transcript_reader.user_text(record)
        return ("user", text) if text else None
    if kind != "assistant":
        return None
    message = record.get("message")
    content = message.get("content") if isinstance(message, dict) else None
    if isinstance(content, list):
        parts = [
            b.get("text")
            for b in content
            if isinstance(b, dict) and b.get("type") == "text"
        ]
        content = "\n".join(p for p in parts if isinstance(p, str))
    if isinstance(content, str) and content.strip():
        return ("assistant", content.strip())
    return None


def snippet(redacted: str, term: str) -> str:
    at = redacted.lower().find(term.lower())
    start = max(0, at - LEAD_CHARS) if at >= 0 else 0
    return redacted[start : start + SNIPPET_CHARS]


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="recall_scan.py", description=__doc__.splitlines()[0]
    )
    parser.add_argument(
        "--dir",
        action="append",
        required=True,
        type=Path,
        help="a transcript project directory",
    )
    parser.add_argument(
        "--term", action="append", required=True, help="literal text to look for"
    )
    parser.add_argument(
        "--skip-session", action="append", default=[], help="a session id to leave out"
    )
    args = parser.parse_args(argv)
    if any(not t.strip() for t in args.term):
        parser.error("a --term is empty")
    for directory in args.dir:
        if not directory.is_dir():
            print(f"recall_scan: not a directory: {directory}", file=sys.stderr)
            sys.exit(2)
    return args


def main(argv: list[str]) -> int:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")
    args = parse_args(argv)
    redactor = redact.load_redactor()
    if redactor.fail_closed:
        print(
            f"recall_scan: redaction failed closed ({len(redactor.skipped)} rule problems); no snippet printed",
            file=sys.stderr,
        )
        return 1

    terms = [t.strip() for t in args.term]
    lowered_terms = [t.lower() for t in terms]
    skip = set(args.skip_session)
    files = {f for d in args.dir for f in d.glob("*.jsonl") if f.is_file()}
    newest_first = sorted(files, key=lambda f: f.stat().st_mtime, reverse=True)

    printed = 0
    read = 0
    unreadable = 0
    capped_sessions = 0
    stopped_early = False
    for path in newest_first:
        if stopped_early:
            break
        if path.stem in skip:
            continue
        read += 1
        per_session = 0
        try:
            for record in transcript_reader.iter_records(path):
                session = record.get("sessionId")
                session = session if isinstance(session, str) and session else path.stem
                if session in skip:
                    continue
                found = record_text(record)
                if found is None:
                    continue
                role, text = found
                lowered = text.lower()
                term = next(
                    (t for t, lt in zip(terms, lowered_terms) if lt in lowered), None
                )
                if term is None:
                    continue
                if printed >= MAX_MATCHES:
                    stopped_early = True
                    break
                if per_session >= PER_SESSION:
                    capped_sessions += 1
                    break
                stamp = record.get("timestamp")
                line = {
                    "session": session,
                    "file": str(path),
                    "time": stamp if isinstance(stamp, str) else "",
                    "role": role,
                    "term": term,
                    "snippet": snippet(redactor.redact(text), term),
                }
                print(json.dumps(line, ensure_ascii=False))
                per_session += 1
                printed += 1
        except OSError:
            unreadable += 1

    print(
        f"scanned: {len(args.dir)} directories, {read} transcripts, {printed} matches, {unreadable} unreadable",
        file=sys.stderr,
    )
    if capped_sessions or stopped_early:
        notes = []
        if capped_sessions:
            notes.append(
                f"{capped_sessions} sessions stopped at {PER_SESSION} matches each"
            )
        if stopped_early:
            notes.append(
                f"stopped at {MAX_MATCHES} matches; older transcripts were not read"
            )
        print("capped: " + "; ".join(notes), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
