#!/usr/bin/env python3
"""Find past-session transcript records that mention a topic, for /session-flow:recall.

    recall_scan.py --dir <dir> [--dir <dir> ...] --term <text> [--term <text> ...]
                   [--skip-session <id>] [--sources-file <file>] [--redact-identifiers <list>]
                   [--data-dir <dir>] [--lock-name <name>]

Reads the `*.jsonl` transcripts directly inside each `--dir`, newest first, through the plugin's
`scripts/transcript_reader.py`, holding the per-host reader lock (`transcript_run.host_locks`,
named by `--lock-name`) for the whole read. A lock another reader holds is waited for up to the
local host's `lock_timeout_s` (`--sources-file` limits); past it nothing is read, the gap is
printed and, with `--data-dir` holding a store, written as a `lookup` diagnostics record, and the exit is 1.
With `--data-dir` (the plugin data directory audit-sessions collects into) it then reads the
store's history-only prompts (`history-prompt/v1`: prompts whose session has no transcript), and
its header (`transcript_sources.report_header`) names the gaps and stale sources the store's last
collections left. Each header line goes to stderr before the `scanned:` line, as it is, so its
retry command runs verbatim; it is local output, not published text.
A user or assistant text record, or a history-only prompt, matches when it contains any term,
compared as plain text without regard to case (a term is never a pattern). Each match prints one
JSON line on stdout: `session`, `file`, `time`, `role`, `term`, `snippet`, and for a history-only
prompt `"history": true` with `file` `history.jsonl`. The snippet is cut from
the record's text after the whole text went through the publish redactor (`publish.publisher`
over `--sources-file` and `--redact-identifiers`), so a secret is never split before redaction sees
it; the `file` path goes through it too. When that redactor fails closed, nothing is printed on
stdout and the exit is 2.

Bounds: a snippet holds at most SNIPPET_CHARS characters, a session at most PER_SESSION matches,
a run at most MAX_MATCHES. stderr carries one `scanned:` line and, when a bound was hit, one
`capped:` line, so the caller can say how much it read.

Writes nothing but a lookup diagnostics record for a lock gap. Every value from a transcript or the
command line stays data.
Exit: 0 scanned (possibly no matches); 1 a lock gap, nothing read; 2 usage, an empty term, a `--dir`
that is not a directory, or the publish redactor failing closed.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

PLUGIN_ROOT = Path(__file__).resolve().parents[3]
if str(PLUGIN_ROOT / "scripts") not in sys.path:
    sys.path.insert(0, str(PLUGIN_ROOT / "scripts"))

import census  # noqa: E402  (scripts/census.py)
import publish  # noqa: E402  (scripts/publish.py)
import transcript_reader  # noqa: E402  (scripts/transcript_reader.py)
import transcript_run  # noqa: E402  (scripts/transcript_run.py)
import transcript_sources  # noqa: E402  (scripts/transcript_sources.py)

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
    parser.add_argument(
        "--sources-file", default="", help="the transcript_sources_file option"
    )
    parser.add_argument(
        "--redact-identifiers", default="", help="the redact_identifiers option"
    )
    parser.add_argument(
        "--data-dir", type=Path, help="the audit-sessions data dir: history prompts and header"
    )
    parser.add_argument(
        "--lock-name",
        type=transcript_run.checked_lock_name,
        default=transcript_run.LOCK_NAME,
        help="the per-host reader lock's name",
    )
    args = parser.parse_args(argv)
    if any(not t.strip() for t in args.term):
        parser.error("a --term is empty")
    for directory in args.dir:
        if not directory.is_dir():
            print(f"recall_scan: not a directory: {directory}", file=sys.stderr)
            sys.exit(2)
    return args


def local_reader(sources: transcript_sources.Sources) -> tuple[str, float]:
    """The local source the read stands for and its host's `lock_timeout_s`."""
    local = sources.local()
    if not local:
        return transcript_sources.DEFAULT_NAME, sources.defaults.lock_timeout_s
    return local[0].name, sources.limits_for(local[0].host).lock_timeout_s


def header_lines(args: argparse.Namespace, sources: transcript_sources.Sources, gaps: list) -> list[str]:
    """The report header: this run's lock gap, else the store's last collections' gaps and stale sources."""
    store = None if args.data_dir is None else census.store_dir(args.data_dir)
    if gaps:
        written = None
        if store is not None and store.is_dir():
            written = transcript_sources.write_lookup(store / transcript_sources.DIAGNOSTICS_DIR, gaps)
        return transcript_sources.report_header(written, gaps, [])
    return [] if store is None else transcript_sources.store_header(store, sources)


def history_matches(data_dir: Path | None, terms: list[str], skip: set[str]) -> list[tuple[dict, str]]:
    """Each stored history-only prompt holding a term, with that term, newest first."""
    if data_dir is None:
        return []
    try:
        prompts, _skipped = census.load_history(data_dir)
    except OSError:
        return []
    found = []
    for prompt in prompts:
        text = prompt.get("excerpt")
        if not isinstance(text, str) or prompt.get("session_id") in skip:
            continue
        term = next((t for t in terms if t.lower() in text.lower()), None)
        if term is not None:
            found.append((prompt, term))
    found.sort(key=lambda item: str((item[0].get("time") or {}).get("start") or ""), reverse=True)
    return found


def main(argv: list[str]) -> int:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")
    args = parse_args(argv)
    sources = transcript_sources.load_reported(args.sources_file)
    try:
        publisher = publish.publisher(args.sources_file, args.redact_identifiers, sources=sources)
    except publish.PublishError as exc:
        print(f"recall_scan: {exc}", file=sys.stderr)
        return 2
    if sources is None:
        return 2
    source, wait_s = local_reader(sources)
    locks = transcript_run.host_locks(None, args.lock_name, wait_s=wait_s)
    if isinstance(locks, transcript_run.HostLock):
        refusal = transcript_run.lock_refusal(locks, waited_s=wait_s)
        gap = transcript_sources.Gap(
            source, refusal["gap"], refusal["detail"], refusal["holder_pid"], tuple(transcript_sources.retry_argv(__file__, argv)),
        )
        for line in header_lines(args, sources, [gap]):
            print(line, file=sys.stderr)
        return 1
    try:
        return scan(args, publisher, sources)
    finally:
        for lock in locks:
            lock.release()


def scan(args: argparse.Namespace, publisher, sources: transcript_sources.Sources) -> int:
    for line in header_lines(args, sources, []):
        print(line, file=sys.stderr)

    terms = [t.strip() for t in args.term]
    lowered_terms = [t.lower() for t in terms]
    skip = set(args.skip_session)
    files = {f for d in args.dir for f in d.glob("*.jsonl") if f.is_file()}
    newest_first = sorted(files, key=lambda f: f.stat().st_mtime, reverse=True)

    printed = read = unreadable = capped_sessions = 0
    stopped_early = False
    for path in newest_first:
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
                    "file": publisher.redact(str(path)),
                    "time": stamp if isinstance(stamp, str) else "",
                    "role": role,
                    "term": term,
                    "snippet": snippet(publisher.redact(text), term),
                }
                print(json.dumps(line, ensure_ascii=False))
                per_session += 1
                printed += 1
        except OSError:
            unreadable += 1
        if stopped_early:
            break

    history = 0
    for prompt, term in history_matches(args.data_dir, terms, skip):
        if printed >= MAX_MATCHES:
            stopped_early = True
            break
        line = {
            "session": prompt.get("session_id"),
            "file": "history.jsonl",
            "time": str((prompt.get("time") or {}).get("start") or ""),
            "role": "user",
            "term": term,
            "snippet": snippet(publisher.redact(prompt["excerpt"]), term),
            "history": True,
        }
        print(json.dumps(line, ensure_ascii=False))
        printed += 1
        history += 1

    print(
        f"scanned: {len(args.dir)} directories, {read} transcripts, {history} history prompts matched,"
        f" {printed} matches, {unreadable} unreadable",
        file=sys.stderr,
    )
    notes = []
    if capped_sessions:
        notes.append(f"{capped_sessions} sessions stopped at {PER_SESSION} matches each")
    if stopped_early:
        notes.append(f"stopped at {MAX_MATCHES} matches; older transcripts were not read")
    if notes:
        print("capped: " + "; ".join(notes), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
