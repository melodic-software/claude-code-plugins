#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Ingest Claude Code transcripts into the audit-sessions store.

    collect.py collect --data-dir D [--sources-file F] [--config-dir DIR ...] [--source NAME ...] [--since YYYY-MM-DD]
                       [--session ID ...] [--force] [--retention-days N] [--excerpt-chars N] [--excerpt-words N]
                       [--lock-name NAME]
    collect.py migrate [--dry-run] <the collect options>
    collect.py census --data-dir D [--version V] [--model M]
    collect.py drift --data-dir D [--min-count N] [--versions N] [--session-floor N] [--canaries FILE]

Reads each transcript source the sources file `F` lists (transcript_sources.py; unset, the local
configuration directory only) plus each `--config-dir` (the local source `dir-<hash of its path>`),
or only the `--source` ones, through `transcript_run.run`: one
reading child per source, on its own host over the source's via, under that host's limits. It
writes one `session-record/v2` file per main session (the main transcript plus its subagents) to
`D/audit-sessions/store/v2/<source>/p-<project>/<session>.json`, the store `sweep.py` reads, each
stamped with `provenance` (the source name and the reading host's own host, platform,
configuration directory and Claude Code version) and `status` (`StoreWriter` says how it moves);
a source's `history.jsonl` prompts whose session has no transcript are written as
`history-prompt/v1` under `<source>/history/`. A transcript Claude Code set aside
(`<session>.orphaned-*.jsonl`) is skipped and counted, not ingested, and a record an earlier
collector stored for one is deleted. A session whose fingerprint matches its stored record is
skipped, unless that record was written by a collector whose code or rules differ (the
COLLECTOR_INPUTS digest), under other excerpt limits, or with redaction failing closed where it now
works or the reverse. With a retention window, records and prompts that ended before it are pruned
and such sessions are not ingested. With `--retention-days` unset the retention is
`DEFAULT_RETENTION_DAYS` raised to the longest source `cleanupPeriodDays`, each
reader moving its own cutoff back to its own value; any value given is kept, and one shorter than a
source's `cleanupPeriodDays` warns. A source's `cleanupPeriodDays` is its reader's hello, else the last one its diagnostics
recorded, else Claude Code's default, the basis named in its diagnostics.

The old store, `store/v1/sessions/` (`V1_RECORD_SCHEMA`), is carried over by the reader: each
source's reader is sent an old store to read without writing (this data dir's for the source that
reads this host's own configuration directory, else the same plugin data dir under the source's
configuration directory) and returns each record whose transcript is gone or past the window as
`carried_over`, stored with status `carried-over` and `carried_from`, and an account of every old
file (`transcript_run._carry_over` holds the one rule). When the own source's run left no gap, its
reader accounted for every old file, everything it sent was stored and every record it named for
rebuilding is held, the old store is renamed, under the host locks, to `store/v1.quarantine-<date>/`,
which nothing reads and which is deleted once that date is older than the retention; a file it
could not read, of another schema or of another shape keeps the old store where it is. Another host's old store stays untouched and its source's
diagnostics carry the info line `old store pending local migration`. `migrate` collects only the
own source; `migrate --dry-run` lists it and reads the old store through a capped child, writing
nothing, and reports what a run would carry over, rebuild and quarantine.
Typed turns of at most `--excerpt-words` words right after an assistant message keep an excerpt,
redacted by redact.py and then cut to `--excerpt-chars`; when redaction fails closed no excerpt is
stored and the run warns. Both excerpt defaults are the userConfig defaults in plugin.json. Every
other stored string from a transcript is redacted too, and one longer than max(4096, 16 x
--excerpt-chars) is skipped and counted instead. Repo identity comes from lib/state-key.sh, run once
per distinct cwd on the reading host. An unreachable, busy, partial or unreadable source is a gap in
the envelope's `gaps`, each with the `retry_argv` that re-collects exactly it, and in the run's
diagnostics record (`diagnostics_path`). Every reader takes the per-host lock `--lock-name` names
(`transcript_run.LOCK_NAME` by default), so two runs sharing a name never read one host at once.

`census` and `drift` read the store only, through census.py: the per-(version, model) aggregate
and its classified diff between Claude Code versions (exit 1 when drift is found).

Prints one JSON envelope on stdout; exit 0 pass, 1 warning, 2 error. Stdlib only; Python 3.10+.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import secrets
import shutil
import sys
import time
from collections import Counter
from collections.abc import Iterable, Mapping
from dataclasses import asdict, replace
from datetime import datetime, timezone
from pathlib import Path

PLUGIN_ROOT = Path(__file__).resolve().parents[1]
_PLUGIN_SCRIPTS = str(PLUGIN_ROOT / "scripts")
if _PLUGIN_SCRIPTS not in sys.path:
    sys.path.insert(0, _PLUGIN_SCRIPTS)

import census  # noqa: E402  (beside this script)
import redact  # noqa: E402  (beside this script)
import session_record  # noqa: E402  (beside this script)
import transcript_run  # noqa: E402  (beside this script)
import transcript_sources  # noqa: E402  (beside this script)
from session_record import ORPHANED, RECORD_SCHEMA, _obj, stored_policy  # noqa: E402  (beside this script)
from transcript_sources import SourceEntry, Sources  # noqa: E402  (beside this script)
from transcript_values import epoch  # noqa: E402  (beside this script)

SCHEMA = "audit-sessions.collect/v1"
V1_RECORD_SCHEMA = "session-record/v1"
QUARANTINE = re.compile(r"v1\.quarantine-(\d{4}-\d{2}-\d{2})(?:-[0-9a-f]{6})?")
DEFAULT_RETENTION_DAYS = 180
CENSUS_SCHEMA = "audit-sessions.census/v1"
DRIFT_SCHEMA = "audit-sessions.drift/v1"
COLLECTOR_INPUTS = (
    "scripts/collect.py",
    "scripts/census.py",
    *(f"scripts/{name}.py" for name in sorted(transcript_run.MODULES)),
    "vendor/gitleaks/gitleaks-rules.json",
    "lib/state-key.sh",
)


def emit(status: str, summary: str, data: dict, code: int, schema: str = SCHEMA) -> int:
    print(json.dumps({"schema": schema, "status": status, "summary": summary, "data": data}, indent=2))
    return code


def warn(message: str) -> None:
    print(f"collect.py: warning: {message}", file=sys.stderr)


def collector_version() -> str:
    version = _manifest().get("version")
    return version if isinstance(version, str) else "unknown"


def collector_digest() -> str:
    """SHA-256 over COLLECTOR_INPUTS in order, CRLF read as LF so a checkout's line endings do not count."""
    digest = hashlib.sha256()
    for relative in COLLECTOR_INPUTS:
        try:
            data = (PLUGIN_ROOT / relative).read_bytes().replace(b"\r\n", b"\n")
        except OSError:
            data = b"<missing>"
        digest.update(relative.encode("utf-8") + b"\0" + hashlib.sha256(data).digest())
    return digest.hexdigest()


def _manifest() -> dict:
    try:
        manifest = json.loads((PLUGIN_ROOT / ".claude-plugin" / "plugin.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return manifest if isinstance(manifest, dict) else {}


def declared_default(option: str) -> int | None:
    """The userConfig option's declared default, the one place the excerpt defaults live; None when unreadable."""
    spec = _obj(_obj(_manifest().get("userConfig")).get(option))
    value = spec.get("default")
    return value if isinstance(value, int) and not isinstance(value, bool) and value >= 0 else None


def option_default(option: str) -> int:
    """`declared_default`, or 0 (no excerpt) when unreadable."""
    return declared_default(option) or 0


class StoreWriter:
    """`transcript_run.run`'s consumer: each source's records and history prompts under `store/<source>/`.

    A record is stamped with its source's provenance from that source's `hello` and status `present`.
    A `carried_over` record from an old store (`v1` maps each source to the old store its reader
    was sent) is stamped the same way with status `carried-over` and `carried_from`, once per
    (source, session): one the source already holds is counted, not written again. A source's
    `listing` marks the held records it names gone `transcript-gone`. After the run, `finish`
    settles every other held record of each source read: one the listing saw on disk becomes
    `present` again; one the reader could not check (its source sent no listing, or its project
    directory could not be listed) becomes `presumed-gone-unverified` once it ended longer ago than
    that source's `cleanupPeriodDays`, and stays as it was before that. A carried-over record keeps
    its status. With `purge` unset nothing is deleted, so a dry run can list what is held.
    """

    def __init__(self, store: Path, v1: Mapping[str, str] | None = None, *, purge: bool = True) -> None:
        self.store = store
        self.v1 = dict(v1 or {})
        self.purge = purge
        self.index: dict[str, dict[Path, dict]] = {}
        self.hellos: dict[str, dict] = {}
        self.gone: dict[str, set[Path]] = {}
        self.unlisted: dict[str, set[str]] = {}
        self.failed: list[dict] = []
        self.ingested = self.purged = self.history_written = self.too_long = 0
        self.unknown_types: Counter = Counter()
        self.carried: Counter = Counter()
        self.v1_tallies: dict[str, dict] = {}

    def held(self, name: str) -> dict[Path, dict]:
        """The stored summary of each record of source `name`, by path; orphaned ones are purged first."""
        if name not in self.index:
            entries: dict[Path, dict] = {}
            for path in sorted((self.store / name).glob("p-*/*.json")):
                record = _read(path)
                if record is None or record.get("schema") != RECORD_SCHEMA:
                    continue
                if ORPHANED in path.stem:
                    if not self.purge:
                        continue
                    try:
                        path.unlink(missing_ok=True)
                        self.purged += 1
                    except OSError as exc:
                        self.failed.append({"session_id": path.stem, "reason": str(exc)})
                    continue
                entries[path] = _summary(record)
            self.index[name] = entries
        return self.index[name]

    def fingerprints(self, entry: SourceEntry) -> list[dict]:
        held = self.held(entry.name)
        return [
            {"project": path.parent.name, "session_id": path.stem, "fingerprint": s["fingerprint"], "policy": s["policy"]}
            for path, s in held.items()
        ]

    def __call__(self, entry: SourceEntry, message: dict) -> None:
        kind = message.get("kind")
        if kind == "hello":
            self.hellos[entry.name] = message
            return
        origin = session_record.provenance(entry.name, self.hellos.get(entry.name, {}), entry.platform)
        if kind == "record":
            target = self.store / entry.name / message["project"] / f"{message['session_id']}.json"
            record = session_record.stamp(message["record"], origin, "present")
            if self._write(target, record, message["session_id"]):
                self.held(entry.name)[target] = _summary(record)
                self.ingested += 1
                self.too_long += int(_obj(record.get("redaction")).get("skipped_too_long") or 0)
                self.unknown_types.update(_obj(_obj(record.get("unknown")).get("record_types")))
        elif kind == "carried_over":
            self._carry_over(entry, message, origin)
        elif kind == "v1":
            self.v1_tallies[entry.name] = message
        elif kind == "history_prompt":
            prompt = message["prompt"]
            target = self.store / entry.name / "history" / f"{prompt['key']}.json"
            payload = {**prompt, "provenance": origin}
            if _read(target) != payload and self._write(target, payload, prompt["key"]):
                self.history_written += 1
        elif kind == "listing":
            gone = self.gone.setdefault(entry.name, set())
            self.unlisted[entry.name] = set(message["unlisted"])
            for segment, session_id in message["gone"]:
                path = self.store / entry.name / segment / f"{session_id}.json"
                if path in self.held(entry.name):
                    gone.add(path)
                    self._set_status(entry.name, path, "transcript-gone")

    def _carry_over(self, entry: SourceEntry, message: dict, origin: dict) -> None:
        target = self.store / entry.name / message["project"] / f"{message['session_id']}.json"
        record = message["record"]
        if target in self.held(entry.name):
            self.carried[entry.name] += 1
            return
        if record.get("schema") != V1_RECORD_SCHEMA:
            self.failed.append({"session_id": message["session_id"], "reason": "a carried-over record that is not session-record/v1"})
            return
        carried_from = {
            "v1_store": self.v1.get(entry.name),
            "assumed_root": str(Path(entry.config_dir) / "projects"),
            "root_recorded": False,
        }
        record = session_record.stamp({**record, "schema": RECORD_SCHEMA, "carried_from": carried_from}, origin, "carried-over")
        if self._write(target, record, message["session_id"]):
            self.held(entry.name)[target] = _summary(record)
            self.carried[entry.name] += 1

    def finish(self, now: float, cleanup_days: Mapping[str, int]) -> None:
        """Settle each held record's status, judging a source by its `cleanup_days` entry, else the default."""
        for name, held in self.index.items():
            listed = name in self.unlisted
            unlisted = self.unlisted.get(name, set())
            gone = self.gone.get(name, set())
            cutoff = now - cleanup_days.get(name, transcript_run.DEFAULT_CLEANUP_DAYS) * 86400
            for path, summary in held.items():
                if path in gone:
                    continue
                if listed and path.parent.name not in unlisted:
                    if summary["status"] in ("transcript-gone", "presumed-gone-unverified"):
                        self._set_status(name, path, "present")
                elif summary["status"] == "present" and summary["end"] is not None and summary["end"] < cutoff:
                    self._set_status(name, path, "presumed-gone-unverified")

    def _set_status(self, name: str, path: Path, status: str) -> None:
        summary = self.held(name)[path]
        if summary["status"] in (status, "carried-over"):
            return
        record = _read(path)
        if record is not None and self._write(path, {**record, "status": status}, path.stem):
            summary["status"] = status

    def _write(self, target: Path, payload: dict, label: str) -> bool:
        try:
            if census.write_atomic(target, payload):
                return True
            reason = "the file stayed locked by a reader"
        except OSError as exc:
            reason = str(exc)
        self.failed.append({"session_id": label, "reason": reason})
        return False


def _read(path: Path) -> dict | None:
    try:
        record = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return record if isinstance(record, dict) else None


def _summary(record: dict) -> dict:
    return {
        "fingerprint": record.get("fingerprint"),
        "policy": stored_policy(record),
        "end": epoch(_obj(record.get("time")).get("end")),
        "status": record.get("status"),
    }


def prune(store: Path, cutoff: float, names: list[str]) -> int:
    """Delete each stored record and history prompt of the sources `names` that ended before `cutoff`."""
    pruned = 0
    for name in names:
        for pattern in ("p-*/*.json", "history/*.json"):
            for path in (store / name).glob(pattern):
                record = _read(path)
                end = epoch(_obj((record or {}).get("time")).get("end"))
                if end is not None and end < cutoff:
                    path.unlink(missing_ok=True)
                    pruned += 1
    return pruned


def dir_source(path: str) -> SourceEntry | None:
    """The local source `dir-<hash>` a `projects` directory, or the configuration directory holding one, names."""
    source = Path(path)
    config = source.parent if source.name == "projects" else source
    if not (config / "projects").is_dir():
        return None
    digest = hashlib.sha256(str(config.resolve()).encode("utf-8")).hexdigest()[:12]
    return SourceEntry(f"dir-{digest}", "local", transcript_sources.local_platform(), str(config))


def with_dirs(sources: Sources, dirs: list[str]) -> Sources | str:
    """`sources` plus each `--config-dir` source, or the first directory that holds no projects directory."""
    entries = list(sources.all())
    for path in dirs:
        entry = dir_source(path)
        if entry is None:
            return path
        if entry.name not in {e.name for e in entries}:
            entries.append(entry)
    return replace(sources, entries=tuple(entries))


def retry_command(args: argparse.Namespace) -> list[str]:
    argv = transcript_sources.retry_argv(__file__, ["collect", "--data-dir", args.data_dir])
    if args.sources_file:
        argv += ["--sources-file", args.sources_file]
    for path in args.config_dir or ():
        argv += ["--config-dir", path]
    if args.since:
        argv += ["--since", args.since]
    if args.session:
        argv += ["--session", *args.session]
    if args.retention_days is not None:
        argv += ["--retention-days", str(args.retention_days)]
    if args.lock_name != transcript_run.LOCK_NAME:
        argv += ["--lock-name", args.lock_name]
    return argv + [
        "--excerpt-chars", str(args.excerpt_chars),
        "--excerpt-words", str(args.excerpt_words),
    ]


def effective_retention(requested: int | None, cleanup_days: Iterable[int]) -> int:
    """The retention a run applies: the value the user set, or when unset `DEFAULT_RETENTION_DAYS` raised to
    the longest `cleanup_days`."""
    if requested is not None:
        return requested
    return max([DEFAULT_RETENTION_DAYS, *cleanup_days])


def v1_store(data_dir: Path) -> Path:
    """The old (v1) store's directory beside `store/v2`; its records sit under `sessions/`."""
    return census.store_dir(data_dir).parent / "v1"


def own_source(sources: Sources) -> SourceEntry | None:
    """The local source reading this host's own configuration directory, whose old store is this data dir's."""
    mine = _resolved(transcript_sources.local_config_dir(os.environ))
    return next((entry for entry in sources.local() if _resolved(entry.config_dir) == mine), None)


def _resolved(path: str) -> Path:
    try:
        return Path(path).expanduser().resolve()
    except (OSError, RuntimeError):
        return Path(path)


def v1_args(entry: SourceEntry, data_dir: Path, own: SourceEntry | None) -> dict:
    """The `v1` read arg for `entry`: this data dir's old store for the own source, else the same plugin data
    dir under the source's configuration directory (`${CLAUDE_PLUGIN_DATA}` is `<config dir>/plugins/data/<id>`)."""
    if entry == own:
        root = v1_store(data_dir)
    else:
        root = v1_store(Path(entry.config_dir) / "plugins" / "data" / data_dir.resolve().name)
    return {"store": str(root / "sessions"), "schema": V1_RECORD_SCHEMA, "own": entry == own}


def empty_tally(root: Path) -> dict | None:
    """The account of an old store with no `sessions/` directory, which holds no record; None when it has one."""
    if (root / "sessions").exists() or (root / "sessions").is_symlink():
        return None
    return {**dict.fromkeys(transcript_run.V1_TALLY, 0), "rebuild_keys": [], "entries": []}


def v1_changes(sessions: Path, tally: dict) -> str | None:
    """How `sessions` differs now from the entries its reader's tally was made from; None when it does not."""
    then = {tuple(entry) for entry in tally.get("entries") or ()}
    now = set(transcript_run.v1_entries(sessions)) if sessions.is_dir() else set()
    if now == then:
        return None
    changed = sorted(f"{path} ({kind})" for path, kind in now ^ then)
    shown = ", ".join(changed[:5]) + (f" and {len(changed) - 5} more" if len(changed) > 5 else "")
    return f"sessions/ changed since its reader's tally: {len(now - then)} entries added or changed, {len(then - now)} gone or changed: {shown}"


def v1_blockers(root: Path, tally: dict | None) -> list[str]:
    """Why the old store at `root` cannot be quarantined, from its reader's tally alone; empty when nothing blocks.

    Everything under `root` but `sessions/`, and every old file the reader could not account for as a
    record it carried, held or will rebuild, keeps the store where it is. A symlinked root or
    `sessions/` is never followed.
    """
    if root.is_symlink():
        return ["the old store is a symlink"]
    if tally is None:
        return ["its reader sent no account of the old store"]
    reasons = [f"{tally[name]} old files {name.replace('_', ' ')}" for name in transcript_run.V1_BLOCKERS if tally.get(name)]
    if (root / "sessions").is_symlink():
        reasons.append("sessions/ is a symlink")
    try:
        extra = sorted(path.name for path in root.iterdir() if path.name != "sessions")
    except OSError as exc:
        extra = [f"<unlistable: {type(exc).__name__}>"]
    if extra:
        reasons.append(f"entries beside sessions/: {', '.join(extra)}")
    return reasons


def quarantines(store_root: Path, retention: int, now: float) -> tuple[list[Path], list[str]]:
    """Each quarantined old store older than `retention` days by the date in its name (none while retention is 0),
    and the name of each whose date does not parse, which is left alone."""
    aged: list[Path] = []
    unparsed: list[str] = []
    for path in sorted(store_root.glob("v1.quarantine-*")):
        match = QUARANTINE.fullmatch(path.name)
        if not (match and path.is_dir()):
            continue
        try:
            dated = datetime.strptime(match.group(1), "%Y-%m-%d").replace(tzinfo=timezone.utc).timestamp()
        except ValueError:
            unparsed.append(path.name)
            continue
        if retention and dated < now - retention * 86400:
            aged.append(path)
    return aged, unparsed


def quarantine_name(now: float) -> str:
    return f"v1.quarantine-{datetime.fromtimestamp(now, timezone.utc):%Y-%m-%d}"


def settle_v1(
    data_dir: Path, writer: StoreWriter, own: SourceEntry | None, done: Iterable[str], retention: int, now: float,
    lock_name: str = transcript_run.LOCK_NAME,
) -> dict:
    """Quarantine the old store once the own source's run has no gap, its reader accounted for every old file,
    every record it sent was stored and every one it named for rebuilding is held; delete quarantines past
    `retention`. Both run under the host locks; before the rename the old store is listed again there,
    and any entry added, gone or changed in type since the reader's tally keeps it. The report names what happened and why."""
    root = v1_store(data_dir)
    report: dict = {"v1_store": str(root) if root.is_dir() else None, "state": "none", "reason": None, "quarantine": None}
    aged, unparsed = quarantines(root.parent, retention, now)
    if unparsed:
        report["unparsed_quarantines"] = unparsed
    migrate = root.is_dir()
    tally: dict | None = None
    if migrate:
        tally = writer.v1_tallies.get(own.name) if own is not None else None
        tally = tally or empty_tally(root)
        report.update(state="pending", tally={key: tally[key] for key in transcript_run.V1_TALLY} if tally else None)
        report["carried"] = writer.carried[own.name] if own is not None else 0
        reasons: list[str] = []
        if own is None:
            reasons.append("no source reads this host's configuration directory")
        elif own.name not in writer.index:
            reasons.append(f"the source {own.name} was not read")
        elif own.name not in done:
            reasons.append(f"the source {own.name} has a gap this run")
        else:
            reasons += v1_blockers(root, tally)
            if tally is not None and tally["carried"] != writer.carried[own.name]:
                reasons.append(f"{writer.carried[own.name]} of {tally['carried']} carried-over records were stored")
            held = writer.held(own.name)
            missing = [k for k in (tally or {}).get("rebuild_keys", ()) if writer.store / own.name / k[0] / f"{k[1]}.json" not in held]
            if missing:
                reasons.append(f"{len(missing)} old records whose transcripts remain were not rebuilt this run")
        report["reason"] = "; ".join(reasons) or None
        migrate = not reasons
    if not (migrate or aged):
        return report
    locks = transcript_run.host_locks(data_dir, lock_name)
    if isinstance(locks, transcript_run.HostLock):
        report["reason"] = locks.detail or "another reader holds the host lock"
        return report
    try:
        if migrate:
            recheck = v1_blockers(root, tally) if root.is_dir() else ["the old store is gone"]
            if not recheck and tally is not None and (changes := v1_changes(root / "sessions", tally)):
                recheck.append(changes)
            if recheck:
                report["reason"] = "; ".join(recheck)
                migrate = False
        if migrate:
            target = root.parent / quarantine_name(now)
            if target.exists():
                target = target.with_name(f"{target.name}-{secrets.token_hex(3)}")
            try:
                root.rename(target)
                report.update(state="quarantined", quarantine=str(target))
            except OSError as exc:
                report["reason"] = f"the old store could not be moved ({type(exc).__name__}: {exc})"
        report["deleted_quarantines"] = []
        for path in aged:
            if not path.is_dir():
                continue
            try:
                shutil.rmtree(path)
                report["deleted_quarantines"].append(str(path))
            except OSError as exc:
                report.setdefault("undeleted_quarantines", []).append(f"{path} ({type(exc).__name__})")
    finally:
        for lock in locks:
            lock.release()
    return report


def record_migration(path: Path | None, own: SourceEntry | None, migration: dict) -> str | None:
    """Write the old store's migration state and reason into the run's diagnostics record at `path`: its
    `v1_migration` section, and the own source's `v1` section when that source was read; a warning when
    the record cannot be rewritten."""
    if path is None or migration["state"] == "none" or (record := _read(path)) is None:
        return None
    outcome = {"state": migration["state"], "reason": migration["reason"]}
    record["v1_migration"] = outcome
    for source in record.get("sources") or ():
        if own is not None and isinstance(source, dict) and source.get("name") == own.name:
            source["v1"] = {**(source.get("v1") or {}), **outcome}
    staging = path.with_suffix(transcript_sources.STAGING_SUFFIX)
    try:
        staging.write_text(json.dumps(record, indent=1) + "\n", encoding="utf-8")
        os.replace(staging, path)
    except OSError as exc:
        return f"the diagnostics record could not take the old store's migration state ({type(exc).__name__}: {exc})"
    return None


def retention_warnings(retention: int, cleanup_days: Iterable[int], unparsed: Iterable[str]) -> list[str]:
    """The warnings a run's retention raises: each quarantine left alone for its name, and a retention
    below the longest of the sources' `cleanup_days`."""
    warnings = [f"a quarantine name whose date does not parse was left alone: {name}" for name in unparsed]
    longest = max(cleanup_days, default=None)
    if retention and longest is not None and retention < longest:
        warnings.append(
            f"store retention {retention} days is below a source's cleanupPeriodDays of {longest}; "
            "records are pruned while their transcripts still exist"
        )
    return warnings


SUMMED = ("scanned", "skipped_unchanged", "skipped_expired", "skipped_orphaned")


def collect_into(args: argparse.Namespace, sources: Sources) -> tuple[str, str, dict, int]:
    """Collect `sources` into the store under `args.data_dir`; (status, summary, data, exit code)."""
    started = time.monotonic()
    data_dir = Path(args.data_dir)
    store = census.store_dir(data_dir)
    try:
        store.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        return "error", f"data dir not usable: {exc}", {"data_dir": args.data_dir}, 2
    since = None
    if args.since:
        try:
            since = datetime.strptime(args.since, "%Y-%m-%d").replace(tzinfo=timezone.utc).timestamp()
        except ValueError:
            return "error", f"--since is not YYYY-MM-DD: {args.since}", {}, 2
    unknown = sorted(set(args.source or ()) - {entry.name for entry in sources.all()})
    if unknown:
        return "error", f"--source names no configured source: {', '.join(unknown)}", {"unknown": unknown}, 2
    now = time.time()
    read = [entry for entry in sources.all() if not args.source or entry.name in args.source]
    prior = transcript_run.last_cleanup_days(store / transcript_sources.DIAGNOSTICS_DIR)
    retention = effective_retention(args.retention_days, [prior[e.name] for e in read if e.name in prior])
    cutoff = now - retention * 86400 if retention else None
    own = own_source(sources)
    v1 = {entry.name: v1_args(entry, data_dir, own) for entry in read}
    redactor = redact.load_redactor()
    writer = StoreWriter(store, {name: arg["store"] for name, arg in v1.items()})
    options = {
        "collector_version": collector_version(),
        "collector_digest": collector_digest(),
        "excerpt_chars": args.excerpt_chars,
        "excerpt_words": args.excerpt_words,
        "since": since,
        "cutoff": cutoff,
        "retention_floor": args.retention_days is None,
        "sessions": list(args.session or ()),
        "history": True,
        "force": args.force,
    }
    result = transcript_run.run(
        sources,
        writer,
        store_dir=store,
        retry_argv=retry_command(args),
        retention_days=retention,
        only=args.source,
        fingerprints=writer.fingerprints,
        options=options,
        source_options=lambda entry: {"v1": v1[entry.name]},
        data_dir=args.data_dir,
        lock_name=args.lock_name,
    )
    diagnostics = _read(result.diagnostics_path) if result.diagnostics_path else None
    per_source = (diagnostics or {}).get("sources") or []
    cleanup = {
        s["name"]: s["cleanup_period_days"] for s in per_source
        if isinstance(s.get("name"), str) and isinstance(s.get("cleanup_period_days"), int)
    }
    writer.finish(now, cleanup)
    retention = max(retention, effective_retention(args.retention_days, cleanup.values()))
    cutoff = now - retention * 86400 if retention else None
    pruned = prune(store, cutoff, sorted(writer.index)) if cutoff is not None else 0
    migration = settle_v1(data_dir, writer, own, result.sources_done, retention, now, args.lock_name)
    warnings = [*sources.warnings, *((diagnostics or {}).get("warnings") or [])]
    if unrecorded := record_migration(result.diagnostics_path, own, migration):
        warnings.append(unrecorded)
    warnings += retention_warnings(retention, cleanup.values(), migration.get("unparsed_quarantines", ()))
    data = {
        "sources": [
            {key: source.get(key) for key in ("name", "host", "platform", "remote", "reported", *SUMMED, "history_prompts", "lock", "info")}
            for source in per_source
        ],
        **{key: sum(int(source.get(key) or 0) for source in per_source) for key in SUMMED},
        "ingested": writer.ingested,
        "carried_over": sum(writer.carried.values()),
        "history_prompts": writer.history_written,
        "purged_orphaned": writer.purged,
        "failed": writer.failed,
        "pruned": pruned,
        "retention": {
            "requested_days": args.retention_days,
            "days": retention,
            "floor_applied": args.retention_days is None and retention > DEFAULT_RETENTION_DAYS,
        },
        "migration": migration,
        "store_records": sum(1 for _ in store.glob(census.RECORD_GLOB)),
        "gaps": [asdict(gap) for gap in result.gaps],
        "diagnostics_path": str(result.diagnostics_path) if result.diagnostics_path else None,
        "warnings": warnings,
        "redaction": {
            "rules_loaded": redactor.rule_count,
            "rules_skipped": len(redactor.skipped),
            "excerpts_suppressed": redactor.fail_closed,
            "skipped_too_long": writer.too_long,
        },
        "unknown_record_types": dict(writer.unknown_types),
        "elapsed_s": round(time.monotonic() - started, 3),
    }
    for message in warnings:
        warn(message)
    for source in per_source:
        for message in source.get("warnings") or ():
            warn(f"{source.get('name')}: {message}")
    summary = f"ingested {writer.ingested} of {data['scanned']} sessions from {len(per_source)} sources"
    if redactor.fail_closed:
        warn(f"redaction rules skipped ({', '.join(sorted(redactor.skipped)) or 'none loaded'}); no excerpts stored")
        return "warning", summary + "; excerpts suppressed (redaction degraded)", data, 1
    if result.gaps:
        kinds = ", ".join(sorted({f"{gap.source} {gap.kind}" for gap in result.gaps}))
        return "warning", summary + f"; {len(result.gaps)} gaps ({kinds}), each with its retry_argv", data, 1
    if writer.failed:
        return "warning", summary + f"; {len(writer.failed)} failed", data, 1
    if warnings:
        return "warning", summary + f"; {len(warnings)} warnings", data, 1
    return "pass", summary, data, 0


def load_sources(args: argparse.Namespace) -> Sources | tuple[str, str, dict, int]:
    """The sources file's sources plus each `--config-dir` one, or the error envelope."""
    try:
        sources = transcript_sources.load(args.sources_file)
    except transcript_sources.SourcesError as exc:
        return "error", f"sources file not usable: {exc}", {"sources_file": exc.file}, 2
    extended = with_dirs(sources, args.config_dir or [])
    if isinstance(extended, str):
        return "error", f"--config-dir holds no projects directory: {extended}", {"config_dir": extended}, 2
    return extended


def collect_command(args: argparse.Namespace) -> tuple[str, str, dict, int]:
    """`collect` for parsed arguments; (status, summary, data, exit code)."""
    sources = load_sources(args)
    return sources if isinstance(sources, tuple) else collect_into(args, sources)


def migrate_command(args: argparse.Namespace) -> tuple[str, str, dict, int]:
    """`migrate`: collect the own source, which carries the old store over; with `--dry-run`, only report."""
    sources = load_sources(args)
    if isinstance(sources, tuple):
        return sources
    own = own_source(sources)
    if own is None:
        return "error", "no source reads this host's configuration directory, so its old store has no run to migrate it", {}, 2
    if args.dry_run:
        return migrate_dry_run(args, sources, own)
    args.source = [own.name]
    return collect_into(args, sources)


def migrate_dry_run(args: argparse.Namespace, sources: Sources, own: SourceEntry) -> tuple[str, str, dict, int]:
    """List the own source and read the old store, through a capped child that writes nothing, and predict the
    quarantine by the rule `settle_v1` applies, given that every rebuild a real run attempts succeeds."""
    data_dir = Path(args.data_dir)
    root = v1_store(data_dir)
    if not root.is_dir():
        return "pass", "no old store to migrate", {"dry_run": True, "v1_store": None}, 0
    now = time.time()
    store = census.store_dir(data_dir)
    prior = transcript_run.last_cleanup_days(store / transcript_sources.DIAGNOSTICS_DIR)
    retention = effective_retention(args.retention_days, [prior[own.name]] if own.name in prior else [])
    try:
        since = datetime.strptime(args.since, "%Y-%m-%d").replace(tzinfo=timezone.utc).timestamp() if args.since else None
    except ValueError:
        return "error", f"--since is not YYYY-MM-DD: {args.since}", {}, 2
    limits = sources.limits_for(own.host)
    read = transcript_run.read_remote(
        own,
        fingerprints=StoreWriter(store, purge=False).fingerprints(own),
        options={
            "capped": True,
            "list_only": True,
            "since": since,
            "sessions": list(args.session or ()),
            "cutoff": now - retention * 86400 if retention else None,
            "retention_floor": args.retention_days is None,
            "v1": v1_args(own, data_dir, own),
            "limits": asdict(limits),
        },
        timeout_s=limits.read_timeout_s,
    )
    cleanup, _basis = transcript_run.cleanup_days(read, prior.get(own.name))
    retention = max(retention, effective_retention(args.retention_days, [cleanup]))
    tally = read.v1 or empty_tally(root)
    gaps = [asdict(gap) for gap in read.gaps]
    reasons = (["the source has a gap"] if gaps else []) + v1_blockers(root, tally)
    if tally is not None and tally["filtered"]:
        reasons.append(f"--since or --session would leave {tally['filtered']} old records unrebuilt")
    aged, unparsed = quarantines(root.parent, retention, now)
    data = {
        "dry_run": True,
        "v1_store": str(root),
        "source": own.name,
        "tally": {key: tally[key] for key in transcript_run.V1_TALLY} if tally else None,
        "would_quarantine": not reasons,
        "reason": "; ".join(reasons) or None,
        "quarantine": str(root.parent / quarantine_name(now)) if not reasons else None,
        "quarantines_past_retention": [str(path) for path in aged],
        "unparsed_quarantines": unparsed,
        "retention_days": retention,
        "gaps": gaps,
        "warnings": retention_warnings(retention, [cleanup], unparsed),
    }
    counts = tally or dict.fromkeys(transcript_run.V1_TALLY, 0)
    summary = (
        f"would carry over {counts['carried']} old records and rebuild {counts['rebuild']} from transcripts; "
        + ("then, if every rebuild succeeds, quarantine the old store" if not reasons else f"the old store would stay: {data['reason']}")
    )
    for message in data["warnings"]:
        warn(message)
    if gaps or data["warnings"]:
        return "warning", summary + (f"; {len(data['warnings'])} warnings" if data["warnings"] else ""), data, 1
    return "pass", summary, data, 0


def collect_args(argv: list[str]) -> argparse.Namespace:
    """`argv` after `collect`, parsed by the CLI's own parser, so another script gets its defaults and checks."""
    return build_parser().parse_args(["collect", *argv])


def cmd_collect(args: argparse.Namespace) -> int:
    return emit(*collect_command(args))


def cmd_migrate(args: argparse.Namespace) -> int:
    return emit(*migrate_command(args))


def cmd_census(args: argparse.Namespace) -> int:
    try:
        records, skipped = census.load_records(Path(args.data_dir))
    except OSError as exc:
        return emit("error", str(exc), {"data_dir": args.data_dir}, 2, CENSUS_SCHEMA)
    rows = census.aggregate(records, version=args.version, model=args.model)
    data = {"sessions": len(records), "skipped_records": skipped, "census": rows}
    return emit("pass", f"{len(rows)} (version, model) buckets over {len(records)} sessions", data, 0, CENSUS_SCHEMA)


def cmd_drift(args: argparse.Namespace) -> int:
    try:
        records, skipped = census.load_records(Path(args.data_dir))
        canaries = census.load_canaries(Path(args.canaries))
    except (OSError, ValueError) as exc:
        return emit("error", str(exc), {"data_dir": args.data_dir, "canaries": args.canaries}, 2, DRIFT_SCHEMA)
    data = census.drift(
        records,
        canaries.get("canaries", []),
        min_count=args.min_count,
        versions=args.versions,
        session_floor=args.session_floor,
    )
    data["skipped_records"] = skipped
    found = ", ".join(f"{n} {cls}" for cls, n in data["counts"].items() if n)
    if found:
        return emit("warning", f"drift found: {found}", data, 1, DRIFT_SCHEMA)
    return emit("pass", f"no drift over {len(records)} sessions", data, 0, DRIFT_SCHEMA)


def _non_negative(value: str) -> int:
    number = int(value)
    if number < 0:
        raise argparse.ArgumentTypeError("must be 0 or more")
    return number


def _collect_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--data-dir", required=True)
    parser.add_argument("--sources-file", default="", help="the transcript_sources_file option; unset reads the local configuration directory")
    parser.add_argument("--source", action="append", help="only this configured source (repeatable), as a gap's retry names it")
    parser.add_argument(
        "--config-dir", action="append",
        help="also read this configuration directory, or projects directory, as the local source dir-<hash> (repeatable)",
    )
    parser.add_argument("--since", help="only transcripts modified on or after this UTC date (YYYY-MM-DD)")
    parser.add_argument("--session", nargs="+", action="extend", help="only these session ids")
    parser.add_argument("--force", action="store_true", help="re-ingest sessions whose fingerprint is unchanged")
    parser.add_argument(
        "--retention-days", type=_non_negative, default=None,
        help="0 keeps every record; unset, the option's default raised to the longest source cleanupPeriodDays",
    )
    parser.add_argument(
        "--excerpt-chars", type=_non_negative, default=option_default("audit_sessions_excerpt_chars"), help="0 stores no excerpt text"
    )
    parser.add_argument("--excerpt-words", type=_non_negative, default=option_default("audit_sessions_excerpt_words"))
    parser.add_argument(
        "--lock-name", type=transcript_run.checked_lock_name, default=transcript_run.LOCK_NAME,
        help="the per-host reader lock's name; runs that share a name never read one host at once",
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Ingest Claude Code transcripts into the audit-sessions store.")
    sub = parser.add_subparsers(dest="command", required=True)
    collect = sub.add_parser("collect", help="ingest transcripts into the store")
    _collect_options(collect)
    collect.set_defaults(func=cmd_collect)
    migrate = sub.add_parser("migrate", help="collect this host's own source, which carries the old store over")
    _collect_options(migrate)
    migrate.add_argument("--dry-run", action="store_true", help="report what would be carried over and quarantined; change nothing")
    migrate.set_defaults(func=cmd_migrate)
    aggregate = sub.add_parser("census", help="sum stored census rows per (version, model)")
    aggregate.add_argument("--data-dir", required=True)
    aggregate.add_argument("--version", help="only this Claude Code version")
    aggregate.add_argument("--model", help="only this model (`*` for non-assistant records)")
    aggregate.set_defaults(func=cmd_census)
    drift = sub.add_parser("drift", help="classify census changes between Claude Code versions")
    drift.add_argument("--data-dir", required=True)
    drift.add_argument("--min-count", type=census._positive, default=census.DEFAULT_MIN_COUNT)
    drift.add_argument("--versions", type=census._positive, default=census.DEFAULT_VERSIONS, help="vanish window, in versions")
    drift.add_argument("--session-floor", type=census._positive, default=census.DEFAULT_SESSION_FLOOR)
    drift.add_argument("--canaries", default=str(census.BUNDLED_CANARIES))
    drift.set_defaults(func=cmd_drift)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    try:
        args = parser.parse_args(argv)
    except SystemExit as exc:
        if exc.code == 0:
            raise
        words = sys.argv[1:] if argv is None else argv
        schema = {"census": CENSUS_SCHEMA, "drift": DRIFT_SCHEMA}.get(words[0] if words else "", SCHEMA)
        return emit("error", "bad arguments", {}, 2, schema)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
