# -*- coding: utf-8 -*-
"""Transcript sources: one Claude Code configuration directory on one host and platform.

Public interface:

- `SourceEntry(name, host, platform, config_dir, via=None)`: `platform` is one of `PLATFORMS`;
  `via` is the argv prefix that reaches the host, its last argument taking one shell command
  string (`("ssh", "host-a")`), or None for this host.
- `resolve(text, env, *, file="<stdin>", platform=None) -> Sources` is the sources named by the
  sources file `text`, or with `text` None the one local source `DEFAULT_NAME` at
  `CLAUDE_CONFIG_DIR`, else `~/.claude`, from `env`; `platform` defaults to `local_platform()`.
  A local source's `config_dir` starting with `~` is expanded to `env`'s home directory here, so
  no caller expands it; a remote one is kept as written, for its own host. A file that cannot be
  used raises `SourcesError`, whose message starts with `file`.
- `load(path, env=os.environ, *, platform=None) -> Sources` reads the file at `path` (the
  `transcript_sources_file` option), a leading `~` expanded to the home directory. An unset or
  empty path is the default with no warning; a missing file is the default with one warning in
  `Sources.warnings`, which the caller prints to stderr.
- `load_reported(path, *, stream=sys.stderr) -> Sources | None` is `load` once per run for a
  reader that goes on without the file: its warnings are printed to `stream`, and a malformed
  file is None.
- `first_local_config_dir(sources, env=os.environ) -> Path` is the configuration directory a
  one-root reader reads: the first local source's, else the local default.
- `retry_argv(script, argv, *, interpreter="python3") -> list[str]` is the command that runs
  `script` again with `argv`, verbatim.
- `Sources`: `all()`, `local()` (the entries with no via), `by_host()`, `limits_for(host)`, and
  `origin` (`file` or `default`).
- `HostLimits`: the per-host limits, one field each, whose metadata holds the field's meaning
  (`doc`) and the range a sources file may set (`rule`, a `LimitRule`); `LIMIT_RULES` is read
  from those fields. The file's `defaults` overrides the built-in values and `hosts.<host>`
  overrides those; a layer that sets one memory key clears the other.

Diagnostics and report headers, for every transcript-mining skill:

- `Gap(source, kind, detail, holder_pid=None, retry_argv=())` is one missed collection; a
  diagnostics record holds each as a dict of these fields.
- `write_diagnostics(diagnostics_dir, record, started, retention_days, *, now=None) -> Path`
  writes one `DIAGNOSTICS_SCHEMA` record to `<run-date>-<run-id>.json` in `diagnostics_dir`
  (`<store>/DIAGNOSTICS_DIR`) and deletes records there older than `retention_days` (0 keeps
  every one) and staging files a crashed write left; `read_diagnostics(diagnostics_dir)` yields
  `(path, record)` for each readable record, in name order.
- `lookup_gaps(sources, retry_argv) -> list[Gap]` is an `unreadable` gap for each local source
  whose `projects` directory exists but cannot be listed, retried by `retry_argv`, the same
  invocation verbatim. A source with no `projects` directory has nothing to read and no gap.
- `write_lookup(diagnostics_dir, gaps, *, retention_days=LOOKUP_RETENTION_DAYS, now=None)` writes
  those gaps as one `kind: lookup` record through `write_diagnostics`; a clean lookup writes
  nothing. A caller with no retention of its own keeps `LOOKUP_RETENTION_DAYS`, the session
  store's default retention.
- `lookup_report(sources_file, retry_argv, diagnostics_dir=None, *, stream=sys.stderr)
  -> LookupReport(sources, gaps, header)` is a one-host reader's whole report header: it loads
  the sources once, prints their warnings to `stream`, takes the lookup gaps, writes them when
  `diagnostics_dir` is given, and renders them; a malformed file raises `SourcesError`.
- `run_status(diagnostics_dir, names=None, *, now=None) -> RunStatus(path, gaps, stale)` reads a
  store's `ingest` diagnostics records: `path` the latest, `gaps` each source's gaps from the
  latest record that read it, `stale` each source (of `names`, else every one read) with no read
  free of gaps within half its `cleanupPeriodDays` (`STALE_FRACTION`), or none at all. A
  timestamp with no zone is UTC.
- `store_header(store_dir, sources, *, now=None) -> list[str]` is the header of a report read
  from a store: `run_status` over its diagnostics, judging `sources` (None: every source read).
- `report_header(diagnostics, gaps, stale) -> list[str]` renders one `Gap:` line per gap (a `Gap`
  or its dict) with its retry command, one `Stale:` line per stale source, and the diagnostics
  record's path; no lines when there is neither gap nor stale source. `report_header_md(lines)`
  is those lines as markdown list items and a blank line, or nothing.

The sources file, schema `transcript-sources/v1`:

    {"schema": "transcript-sources/v1",
     "defaults": {"slow_read_s": 60},
     "hosts": {"host-b": {"memory_bytes": 2000000000}},
     "sources": [{"name": "host-a-wsl", "host": "host-a", "platform": "wsl", "config_dir": "/srv/a/.claude"},
                 {"name": "host-a-windows", "host": "host-a", "platform": "windows",
                  "config_dir": "/mnt/c/Users/a/.claude"},
                 {"name": "host-b-wsl", "host": "host-b", "platform": "wsl", "config_dir": "/srv/b/.claude",
                  "via": ["ssh", "host-b"]}]}

Unknown keys are refused. A source name is a store directory name, so it is letters, digits, `.`,
`_` and `-`, unique, and not one of `RESERVED_NAMES` (the store's own directories). A `windows`
source is read from WSL, so it needs a `wsl` source with the same host and via.

CLI, exit 0 or 2 with the reason on stderr:

    transcript_sources.py check FILE|-                   validate a file, or stdin as `<stdin>`
    transcript_sources.py local-config-dir [--sources-file F]
                                                         print each local source's configuration
                                                         directory, one per line, in file order

Callers put this directory on `sys.path` and `import transcript_sources`. Stdlib only; Python 3.10+.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import secrets
import shlex
import sys
import time
from collections.abc import Iterable, Iterator, Mapping, Sequence
from dataclasses import asdict, dataclass, field, fields, replace
from datetime import datetime, timezone
from pathlib import Path
from typing import Literal, NamedTuple, TypeVar, cast, get_args

_T = TypeVar("_T")

Platform = Literal["windows", "wsl", "linux", "macos"]
PLATFORMS: tuple[str, ...] = get_args(Platform)
DEFAULT_NAME = "local"
SCHEMA = "transcript-sources/v1"
TOP_KEYS = frozenset({"schema", "sources", "defaults", "hosts"})
SOURCE_KEYS = frozenset({"name", "host", "platform", "config_dir", "via"})
STORE_DIR_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}")
DIAGNOSTICS_SCHEMA = "transcript-run.diagnostics/v1"
DIAGNOSTICS_DIR = "diagnostics"
RESERVED_NAMES = frozenset({DIAGNOSTICS_DIR})
NUMBER = (int, float)
STAGING_SUFFIX = ".json.tmp"
STAGING_ORPHAN_S = 3600
LOOKUP_RETENTION_DAYS = 180
# Claude Code's default `cleanupPeriodDays`: https://code.claude.com/docs/en/settings-reference#cleanupperioddays
DEFAULT_CLEANUP_DAYS = 30
STALE_FRACTION = 0.5


class LimitRule(NamedTuple):
    types: type | tuple[type, ...]
    low: float
    high: float | None = None
    low_excluded: bool = False


def _limit(default: _T, rule: LimitRule, doc: str) -> _T:
    return cast(_T, field(default=default, metadata={"rule": rule, "doc": doc}))


MISSING_WARNING = "transcript_sources: sources file {path} not found; reading only the local configuration directory"


class SourcesError(ValueError):
    """A sources file that cannot be used; the message starts with the file it names."""

    def __init__(self, file: str, reason: str) -> None:
        super().__init__(f"{file}: {reason}")
        self.file = file


def as_platform(value: str) -> Platform:
    if value not in PLATFORMS:
        raise ValueError(f"platform {value!r} is not one of {', '.join(PLATFORMS)}")
    return cast(Platform, value)


@dataclass(frozen=True)
class SourceEntry:
    name: str
    host: str
    platform: Platform
    config_dir: str
    via: tuple[str, ...] | None = None

    def __post_init__(self) -> None:
        as_platform(self.platform)
        if self.via is not None:
            if isinstance(self.via, str) or not all(isinstance(arg, str) for arg in self.via):
                raise ValueError("via must be a sequence of strings")
            object.__setattr__(self, "via", tuple(self.via))

    @property
    def is_local(self) -> bool:
        return self.via is None


@dataclass(frozen=True)
class HostLimits:
    memory_bytes: int | None = _limit(
        None, LimitRule(int, 0, low_excluded=True), "a fixed resident-memory ceiling; when None, memory_fraction sets it"
    )
    memory_fraction: float | None = _limit(
        0.25, LimitRule(NUMBER, 0, 1, low_excluded=True), "the share of available memory the ceiling is"
    )
    check_every_records: int = _limit(5000, LimitRule(int, 1), "records read between two memory checks")
    lock_timeout_s: float = _limit(300, LimitRule(NUMBER, 0), "the longest a reader waits for the host lock")
    slow_read_s: float = _limit(120, LimitRule(NUMBER, 0, low_excluded=True), "a read past this wall time adds a warning")
    read_timeout_s: float = _limit(
        1800, LimitRule(NUMBER, 0, low_excluded=True), "the wall time one source's read may take before it is stopped"
    )
    peak_headroom: float = _limit(
        1.5,
        LimitRule(NUMBER, 1),
        "the multiple of a source's prior peak resident memory that becomes its ceiling, never above the configured one",
    )
    backstop_ratio: float = _limit(
        2.0, LimitRule(NUMBER, 1), "the multiple of the ceiling the address space may grow by before the Unix backstop"
    )
    nice: int = _limit(10, LimitRule(int, 0, 19), "the reader's CPU priority increment")

    def merged(self, layer: Mapping[str, object]) -> HostLimits:
        values = {**self.__dict__, **layer}
        if "memory_bytes" in layer:
            values["memory_fraction"] = None
        elif "memory_fraction" in layer:
            values["memory_bytes"] = None
        return HostLimits(**values)


LIMIT_RULES: dict[str, LimitRule] = {limit.name: limit.metadata["rule"] for limit in fields(HostLimits)}
LIMIT_KEYS = frozenset(LIMIT_RULES)


@dataclass(frozen=True)
class Sources:
    entries: tuple[SourceEntry, ...]
    origin: Literal["file", "default"]
    defaults: HostLimits = HostLimits()
    limits_by_host: Mapping[str, HostLimits] = field(default_factory=dict)
    warnings: tuple[str, ...] = ()

    def all(self) -> tuple[SourceEntry, ...]:
        return self.entries

    def local(self) -> tuple[SourceEntry, ...]:
        return tuple(entry for entry in self.entries if entry.is_local)

    def by_host(self) -> dict[str, tuple[SourceEntry, ...]]:
        groups: dict[str, list[SourceEntry]] = {}
        for entry in self.entries:
            groups.setdefault(entry.host, []).append(entry)
        return {host: tuple(group) for host, group in groups.items()}

    def limits_for(self, host: str) -> HostLimits:
        return self.limits_by_host.get(host, self.defaults)


def local_platform() -> Platform:
    if sys.platform == "win32":
        return "windows"
    if sys.platform == "darwin":
        return "macos"
    try:
        release = Path("/proc/sys/kernel/osrelease").read_text(encoding="utf-8")
    except OSError:
        return "linux"
    return "wsl" if "microsoft" in release.lower() else "linux"


def _home(env: Mapping[str, str]) -> str:
    return env.get("HOME") or env.get("USERPROFILE") or str(Path.home())


def _expanded(path: str, env: Mapping[str, str]) -> str:
    """`path` with a leading `~` or `~/` replaced by `env`'s home directory."""
    if path == "~" or path.startswith(("~/", "~\\")):
        return _home(env) + path[1:]
    return path


def local_config_dir(env: Mapping[str, str]) -> str:
    if env.get("CLAUDE_CONFIG_DIR"):
        return _expanded(env["CLAUDE_CONFIG_DIR"], env)
    return str(Path(_home(env)) / ".claude")


def load_reported(path: str | None, *, stream=None) -> Sources | None:
    try:
        sources = load(path)
    except SourcesError:
        return None
    for warning in sources.warnings:
        print(warning, file=sys.stderr if stream is None else stream)
    return sources


def first_local_config_dir(sources: Sources, env: Mapping[str, str] | None = None) -> Path:
    local = sources.local()
    return Path(local[0].config_dir if local else local_config_dir(os.environ if env is None else env))


def retry_argv(script: str, argv: Sequence[str], *, interpreter: str = "python3") -> list[str]:
    return [interpreter, str(Path(script).resolve()), *argv]


def resolve(
    text: str | None, env: Mapping[str, str], *, file: str = "<stdin>", platform: str | None = None
) -> Sources:
    if text is None:
        local = as_platform(platform) if platform else local_platform()
        entry = SourceEntry(DEFAULT_NAME, DEFAULT_NAME, local, local_config_dir(env))
        return Sources((entry,), "default")
    try:
        data = json.loads(text)
    except ValueError as error:
        raise SourcesError(file, f"not JSON ({error})") from None
    return _parse(data, file, env)


def load(path: str | None, env: Mapping[str, str] | None = None, *, platform: str | None = None) -> Sources:
    env = os.environ if env is None else env
    if not path:
        return resolve(None, env, platform=platform)
    path = _expanded(path, env)
    text = _read(path)
    sources = resolve(text, env, file=path, platform=platform)
    if text is None:
        return replace(sources, warnings=(MISSING_WARNING.format(path=path),))
    return sources


def _read(path: str) -> str | None:
    try:
        return Path(path).read_text(encoding="utf-8")
    except FileNotFoundError:
        return None
    except (OSError, UnicodeDecodeError) as error:
        raise SourcesError(path, f"cannot be read ({type(error).__name__})") from None


def _parse(data: object, file: str, env: Mapping[str, str]) -> Sources:
    if not isinstance(data, dict):
        raise SourcesError(file, "the top level is not an object")
    _keys(data, TOP_KEYS, {"schema", "sources"}, file, "the file")
    if data["schema"] != SCHEMA:
        raise SourcesError(file, f"schema {data['schema']!r} is not {SCHEMA!r}")
    items = data["sources"]
    if not isinstance(items, list) or not items:
        raise SourcesError(file, "sources is not a non-empty list")
    entries = tuple(_entry(item, index, file, env) for index, item in enumerate(items))
    names = [entry.name for entry in entries]
    for name in names:
        if names.count(name) > 1:
            raise SourcesError(file, f"source name {name!r} appears more than once")
    for entry in entries:
        if entry.platform == "windows" and not any(
            other.platform == "wsl" and other.host == entry.host and other.via == entry.via for other in entries
        ):
            raise SourcesError(file, f"windows source {entry.name!r} has no wsl source with the same host and via to read it")
    defaults = HostLimits().merged(_limits(data.get("defaults", {}), file, "defaults"))
    hosts = data.get("hosts", {})
    if not isinstance(hosts, dict):
        raise SourcesError(file, "hosts is not an object")
    known = {entry.host for entry in entries}
    for host in hosts:
        if host not in known:
            raise SourcesError(file, f"hosts names {host!r}, which no source uses")
    limits = {host: defaults.merged(_limits(hosts.get(host, {}), file, f"hosts.{host!r}")) for host in known}
    return Sources(entries, "file", defaults, limits)


def _keys(item: dict, allowed: frozenset[str], required: set[str], file: str, where: str) -> None:
    for key in item:
        if key not in allowed:
            raise SourcesError(file, f"{where} has unknown key {key!r}")
    for key in sorted(required):
        if key not in item:
            raise SourcesError(file, f"{where} has no {key!r}")


def _entry(item: object, index: int, file: str, env: Mapping[str, str]) -> SourceEntry:
    where = f"sources[{index}]"
    if not isinstance(item, dict):
        raise SourcesError(file, f"{where} is not an object")
    _keys(item, SOURCE_KEYS, set(SOURCE_KEYS - {"via"}), file, where)
    for key in ("name", "host", "platform", "config_dir"):
        if not isinstance(item[key], str) or not item[key]:
            raise SourcesError(file, f"{where}.{key} is not a non-empty string")
    if not STORE_DIR_NAME.fullmatch(item["name"]):
        raise SourcesError(file, f"{where}.name {item['name']!r} is not letters, digits, '.', '_' and '-'")
    if item["name"] in RESERVED_NAMES:
        raise SourcesError(file, f"{where}.name {item['name']!r} is reserved for the store's own directories")
    via = item.get("via")
    if via is not None and (not isinstance(via, list) or not via or not all(isinstance(arg, str) and arg for arg in via)):
        raise SourcesError(file, f"{where}.via is not a non-empty list of non-empty strings")
    try:
        platform = as_platform(item["platform"])
        config_dir = item["config_dir"] if via is not None else _expanded(item["config_dir"], env)
        return SourceEntry(item["name"], item["host"], platform, config_dir, None if via is None else tuple(via))
    except ValueError as error:
        raise SourcesError(file, f"{where}: {error}") from None


def _limits(layer: object, file: str, where: str) -> dict:
    if not isinstance(layer, dict):
        raise SourcesError(file, f"{where} is not an object")
    _keys(layer, LIMIT_KEYS, set(), file, where)
    if "memory_bytes" in layer and "memory_fraction" in layer:
        raise SourcesError(file, f"{where} sets both memory_bytes and memory_fraction")
    for key, value in layer.items():
        rule = LIMIT_RULES[key]
        if isinstance(value, bool) or not isinstance(value, rule.types):
            raise SourcesError(file, f"{where}.{key} is not a number of the right kind")
        if value < rule.low or (rule.low_excluded and value == rule.low) or (rule.high is not None and value > rule.high):
            raise SourcesError(file, f"{where}.{key} {value!r} is out of range")
    return layer


@dataclass(frozen=True)
class Gap:
    source: str
    kind: str
    detail: str
    holder_pid: int | None = None
    retry_argv: tuple[str, ...] = ()


class RunStatus(NamedTuple):
    path: Path | None
    gaps: list[dict]
    stale: list[dict]


class LookupReport(NamedTuple):
    sources: Sources
    gaps: list[Gap]
    header: list[str]


def iso(epoch: float, timespec: str = "seconds") -> str:
    return datetime.fromtimestamp(epoch, timezone.utc).isoformat(timespec=timespec).replace("+00:00", "Z")


def _epoch(text: object) -> float | None:
    try:
        parsed = datetime.fromisoformat(str(text).replace("Z", "+00:00"))
    except ValueError:
        return None
    return (parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)).timestamp()


def write_diagnostics(
    diagnostics_dir: str | Path, record: dict, started: float, retention_days: float, *, now: float | None = None,
) -> Path:
    directory = Path(diagnostics_dir)
    directory.mkdir(parents=True, exist_ok=True)
    now = time.time() if now is None else now
    cutoffs = [(f"*{STAGING_SUFFIX}", now - STAGING_ORPHAN_S)]
    if retention_days:
        cutoffs.append(("*.json", now - retention_days * 86400))
    for pattern, cutoff in cutoffs:
        for old in directory.glob(pattern):
            try:
                if old.stat().st_mtime < cutoff:
                    old.unlink()
            except OSError:
                continue
    run_id = secrets.token_hex(6)
    record = {**record, "run_id": run_id}
    path = directory / f"{datetime.fromtimestamp(started, timezone.utc):%Y-%m-%d}-{run_id}.json"
    staging = path.with_suffix(STAGING_SUFFIX)
    staging.write_text(json.dumps(record, indent=1) + "\n", encoding="utf-8")
    os.replace(staging, path)
    return path


def read_diagnostics(diagnostics_dir: str | Path) -> Iterator[tuple[Path, dict]]:
    directory = Path(diagnostics_dir)
    for path in sorted(directory.glob("*.json")) if directory.is_dir() else ():
        try:
            record = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if isinstance(record, dict):
            yield path, record


def lookup_gaps(sources: Sources, retry_argv: Sequence[str]) -> list[Gap]:
    gaps = []
    for entry in sources.local():
        try:
            with os.scandir(Path(entry.config_dir) / "projects"):
                pass
        except FileNotFoundError:
            continue
        except OSError as error:
            gaps.append(Gap(entry.name, "unreadable", f"its projects directory could not be listed ({type(error).__name__})",
                            None, tuple(retry_argv)))
    return gaps


def write_lookup(
    diagnostics_dir: str | Path, gaps: Sequence[Gap], *, retention_days: float = LOOKUP_RETENTION_DAYS, now: float | None = None,
) -> Path | None:
    if not gaps:
        return None
    started = time.time() if now is None else now
    record = {"schema": DIAGNOSTICS_SCHEMA, "kind": "lookup", "started_at": iso(started), "finished_at": iso(started),
              "sources": [], "gaps": [_gap_dict(gap) for gap in gaps], "warnings": []}
    return write_diagnostics(diagnostics_dir, record, started, retention_days, now=now)


def lookup_report(
    sources_file: str, retry_argv: Sequence[str], diagnostics_dir: str | Path | None = None, *, stream=None,
) -> LookupReport:
    sources = load(sources_file)
    for warning in sources.warnings:
        print(warning, file=sys.stderr if stream is None else stream)
    gaps = lookup_gaps(sources, retry_argv)
    path = write_lookup(diagnostics_dir, gaps) if diagnostics_dir else None
    return LookupReport(sources, gaps, report_header(path, gaps, []))


def run_status(diagnostics_dir: str | Path, names: Iterable[str] | None = None, *, now: float | None = None) -> RunStatus:
    now = time.time() if now is None else now
    records = sorted(
        ((str(record.get("finished_at") or ""), path, record) for path, record in read_diagnostics(diagnostics_dir)
         if record.get("schema") == DIAGNOSTICS_SCHEMA and record.get("kind") == "ingest"),
        key=lambda item: (_epoch(item[0]) or 0.0, item[1].name),
    )
    latest: dict[str, dict] = {}
    last_ok: dict[str, str] = {}
    cleanup: dict[str, int] = {}
    for finished, _path, record in records:
        for source in record.get("sources") or ():
            name = source.get("name") if isinstance(source, dict) else None
            if not isinstance(name, str):
                continue
            latest[name] = record
            if source.get("gaps") == 0:
                last_ok[name] = finished
            days = source.get("cleanup_period_days")
            if isinstance(days, int) and not isinstance(days, bool) and days >= 1:
                cleanup[name] = days
    gaps = [
        gap for name, record in latest.items() for gap in record.get("gaps") or ()
        if isinstance(gap, dict) and gap.get("source") == name
    ]
    stale = []
    for name in list(dict.fromkeys(names)) if names is not None else list(latest):
        days = cleanup.get(name, DEFAULT_CLEANUP_DAYS)
        ok = _epoch(last_ok[name]) if name in last_ok else None
        if ok is None or now - ok > days * STALE_FRACTION * 86400:
            stale.append({"source": name, "last_ok": last_ok.get(name), "cleanup_period_days": days})
    return RunStatus(records[-1][1] if records else None, gaps, stale)


def store_header(store_dir: str | Path, sources: Sources | None, *, now: float | None = None) -> list[str]:
    names = None if sources is None else [entry.name for entry in sources.all()]
    status = run_status(Path(store_dir) / DIAGNOSTICS_DIR, names, now=now)
    return report_header(status.path, status.gaps, status.stale)


def _gap_dict(gap: Gap | Mapping) -> dict:
    return asdict(gap) if isinstance(gap, Gap) else dict(gap)


def report_header(diagnostics: str | Path | None, gaps: Sequence[Gap | Mapping], stale: Sequence[dict]) -> list[str]:
    lines = []
    for gap in map(_gap_dict, gaps):
        lines.append(
            f"Gap: {gap.get('source')} {gap.get('kind')}: {gap.get('detail')}. Retry: {shlex.join(gap.get('retry_argv') or ())}"
        )
    for source in stale:
        if source.get("last_ok"):
            lines.append(
                f"Stale: {source['source']} was last collected without a gap at {source['last_ok']}, "
                f"past half its cleanupPeriodDays of {source['cleanup_period_days']}."
            )
        else:
            lines.append(f"Stale: {source['source']} has no collection without a gap in the retained diagnostics.")
    if lines and diagnostics:
        lines.append(f"Diagnostics: {diagnostics}")
    return lines


def report_header_md(lines: Sequence[str]) -> list[str]:
    return [*(f"- {line}" for line in lines), ""] if lines else []


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="transcript_sources.py")
    commands = parser.add_subparsers(dest="command", required=True)
    check = commands.add_parser("check", help="validate a sources file, or stdin with -; exit 0 valid, 2 not")
    check.add_argument("file")
    local = commands.add_parser("local-config-dir", help="print each local source's configuration directory")
    local.add_argument("--sources-file", default="")
    args = parser.parse_args(argv)
    try:
        if args.command == "check":
            label = "<stdin>" if args.file == "-" else args.file
            text = sys.stdin.read() if args.file == "-" else _read(args.file)
            if text is None:
                raise SourcesError(label, "not found")
            sources = resolve(text, os.environ, file=label)
            print(f"{label}: {len(sources.all())} sources on {len(sources.by_host())} hosts")
            return 0
        sources = load(args.sources_file)
    except SourcesError as error:
        print(f"transcript_sources: {error}", file=sys.stderr)
        return 2
    for warning in sources.warnings:
        print(warning, file=sys.stderr)
    for entry in sources.local():
        print(entry.config_dir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
