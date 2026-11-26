#!/usr/bin/env python3
"""Deep-inventory categories, adapters, KEEP-reason validator, and standalone CLI.

Read-only. Every function takes its paths, clock, and liveness/classifier ports
as arguments and only reads; nothing here deletes, moves, or modifies target
files. A candidate row is a finding, not a deletion plan: removal stays behind
the engine's own gates.

Row schema (one dict per inventoried entry, shared by every producer of a
machine listing):

    name         absolute path of the entry
    ext          file suffix, "" for a directory
    size         bytes; a directory is the sum of the files beneath it, links not followed
    mtime        modification time, ISO-8601 UTC
    owner        owning user name, or the numeric uid when it has no name
    producer     the tool that made the entry ("unknown" when no rule attributes it)
    category     the named category that produced the row
    disposition  KEEP | CANDIDATE | UNKNOWN
    reason       who produced it, what uses it, why it stays or may go
    evidence     optional dict of proof. {"tool": ..., "references": ...} shows the named
                 tool still references the entry, which is what lets a KEEP rest on a
                 category phrase such as "managed by <tool>"

``validate_report`` fails a report whose KEEP row has an empty reason, or one
that is only a category phrase without such evidence.
"""

from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import functools
import json
import os
import re
import stat
import sys
import tempfile
from collections.abc import Iterable, Mapping, Sequence
from pathlib import Path
from typing import Any, Protocol, runtime_checkable

_LIB_DIR = Path(__file__).resolve().parents[3] / "lib"
if str(_LIB_DIR) not in sys.path:
    sys.path.insert(0, str(_LIB_DIR))

from claude_projects import (  # noqa: E402  (path set above; plugin-bundled module)
    PROJECT_NAME_CAP,
    ProjectSlugResolver,
    TranscriptReaderCwdAdapter,
)
from plugin_cache_versions import (  # noqa: E402  (path set above; plugin-bundled module)
    INSTALLED_PLUGINS,
    ORPHAN_SWEEP_DAYS,
    FsGuardedTextReader,
    inspect_plugin_cache,
    load_registry,
    orphan_marker,
    resolve,
    resolve_claude_dir,
)

try:
    import pwd
except ImportError:  # Windows
    pwd = None

ROW_COLUMNS = (
    "name",
    "ext",
    "size",
    "mtime",
    "owner",
    "producer",
    "category",
    "disposition",
    "reason",
    "evidence",
)
DISPOSITIONS = ("KEEP", "CANDIDATE", "UNKNOWN")
DAY = 86400.0
TMP_MIN_AGE_DAYS = 7.0
TMP_PRODUCERS = (
    ("pytest-of-", "pytest", None),
    ("claude-", "claude-code", None),
    ("npm-", "npm", None),
    ("uv-", "uv", None),
    ("playwright", "playwright", None),
    ("codex-", "codex", None),
    ("cursor-", "cursor-agent", None),
    (
        "systemd-private-",
        "systemd",
        "private /tmp of a service unit; removing it breaks the running unit until it restarts",
    ),
    (
        ".X11-unix",
        "xorg",
        "socket directory of the running X server; clients cannot connect without it",
    ),
    ("ssh-", "ssh-agent", "socket directory of a running ssh-agent"),
)
LINK_PRODUCERS = (
    ("/mise/", "mise"),
    ("/.claude/", "claude-code"),
    ("/.npm/", "npm"),
    ("/uv/", "uv"),
)
VERSION_RE = re.compile(r"^v?(\d+(?:\.\d+)*)(?:([-+])[\w.+-]+)?$")
_TOKEN = r"[\w.@/+-]+"
_NAMED_TOOL = re.compile(
    rf"(?:managed|owned) by (?:the )?({_TOKEN}(?: {_TOKEN}){{0,2}})"
)
_CATEGORY_PHRASE = re.compile(
    rf"(?:(?:tool|os|system|app|vendor)[- ]?(?:managed|owned)|{_NAMED_TOOL.pattern})"
)
FILE_ATTRIBUTE_REPARSE_POINT = 0x0400
UNCLASSIFIED = {
    "producer": "unknown",
    "category": "unclassified",
    "disposition": "UNKNOWN",
    "reason": "no category rule attributes this entry",
}

_UNSET: Any = object()


@dataclasses.dataclass(frozen=True)
class Classification:
    """Category metadata for one path; sizing is owned separately by the walker."""

    producer: str
    category: str
    disposition: str
    reason: str
    evidence: dict[str, Any] | None = None


@dataclasses.dataclass(frozen=True)
class VersionUse:
    """Read-only liveness reading for a versioned binary or directory."""

    status: str
    kind: str | None = None
    detail: str | None = None


@runtime_checkable
class VersionLivenessPort(Protocol):
    """Strictly read-only probe answering whether a path or version is currently in use."""

    @property
    def available(self) -> bool: ...

    def running_match(self, entry: Path) -> str | None: ...

    def version_use(self, version_path: Path) -> VersionUse: ...


@dataclasses.dataclass(frozen=True)
class WalkContext:
    """Immutable configuration supplied to classifiers at the start of one inventory walk."""

    target: Path
    home: Path
    tmp_dir: Path
    claude_dir: Path | None
    now: float
    liveness: VersionLivenessPort
    fs_root: Path = Path("/")


@runtime_checkable
class EntryClassifierPort(Protocol):
    """Pluggable read-only metadata classifier; never computes sizes or modifies disk."""

    def prepare(self, ctx: WalkContext) -> None: ...

    def classify_directory(
        self, directory: Path, entries: Sequence[os.DirEntry[str]]
    ) -> dict[str, Classification]: ...

    def classify_entry(
        self, path: Path, st: os.stat_result
    ) -> Classification | None: ...


def _iso(epoch: float) -> str:
    return dt.datetime.fromtimestamp(epoch, dt.timezone.utc).isoformat(
        timespec="seconds"
    )


@functools.lru_cache(maxsize=None)
def _owner(uid: int) -> str:
    if pwd is not None:
        try:
            return pwd.getpwuid(uid).pw_name
        except KeyError:
            pass
    return str(uid)


def _descends(st: os.stat_result) -> bool:
    return stat.S_ISDIR(st.st_mode) and not (
        getattr(st, "st_file_attributes", 0) & FILE_ATTRIBUTE_REPARSE_POINT
    )


def _within(path: Path, root: Path) -> bool:
    return path == root or root in path.parents


def _overlaps(scope: Path, target: Path) -> bool:
    """Bidirectional containment: true when scope is inside target OR target is inside scope."""
    return _within(scope, target) or _within(target, scope)


def _tree_size(
    path: Path,
    mounts: frozenset[str] = frozenset(),
    root_dev: int | None = None,
) -> int:
    if root_dev is None:
        try:
            root_dev = os.lstat(path).st_dev
        except OSError:
            return 0
    total, stack = 0, [path]
    while stack:
        current = stack.pop()
        try:
            with os.scandir(current) as entries:
                for entry in entries:
                    try:
                        st = entry.stat(follow_symlinks=False)
                    except OSError:
                        continue
                    if _descends(st):
                        if entry.path in mounts or (
                            root_dev and st.st_dev and st.st_dev != root_dev
                        ):
                            continue
                        stack.append(Path(entry.path))
                    else:
                        total += st.st_size
        except OSError:
            pass
    return total


def make_row(
    path: Path,
    *,
    producer: str,
    category: str,
    disposition: str,
    reason: str,
    evidence: dict[str, Any] | None = None,
    mounts: frozenset[str] = frozenset(),
) -> dict[str, Any]:
    """One schema row for ``path``, measured with lstat so a link is never followed."""
    st = os.lstat(path)
    return _stat_row(
        path,
        st,
        _tree_size(path, mounts=mounts, root_dev=st.st_dev)
        if _descends(st)
        else st.st_size,
        producer=producer,
        category=category,
        disposition=disposition,
        reason=reason,
        evidence=evidence,
    )


def _stat_row(
    path: Path,
    st: os.stat_result,
    size: int,
    *,
    producer: str,
    category: str,
    disposition: str,
    reason: str,
    evidence: dict[str, Any] | None = None,
) -> dict[str, Any]:
    row: dict[str, Any] = {
        "name": str(path),
        "ext": "" if stat.S_ISDIR(st.st_mode) else path.suffix,
        "size": size,
        "mtime": _iso(st.st_mtime),
        "owner": _owner(st.st_uid),
        "producer": producer,
        "category": category,
        "disposition": disposition,
        "reason": reason,
    }
    if evidence is not None:
        row["evidence"] = evidence
    return row


def _child_dirs(parent: Path) -> list[Path]:
    try:
        with os.scandir(parent) as entries:
            return sorted(
                Path(e.path) for e in entries if e.is_dir(follow_symlinks=False)
            )
    except OSError:
        return []


def running_paths(proc_root: Path = Path("/proc")) -> set[str] | None:
    """Resolved executable, working-directory and open-descriptor targets of every process under ``proc_root``.

    A deleted target reads ``<path> (deleted)``; the suffix is dropped so the
    superseded directory it came from still matches. Descriptors that are not
    paths (``socket:[1]``, ``pipe:[1]``) never match an entry. A process another
    user owns is unreadable here and contributes nothing. None means the process
    table could not be read (no ``/proc``, as on macOS and Windows), which is not
    the same as an empty set: nothing was checked.
    """
    found: set[str] = set()
    try:
        pids = [p for p in proc_root.iterdir() if p.name.isdigit()]
    except OSError:
        return None
    for pid in pids:
        links = [pid / "exe", pid / "cwd"]
        try:
            links += [Path(e.path) for e in os.scandir(pid / "fd")]
        except OSError:
            pass
        for link in links:
            try:
                found.add(os.readlink(link).removesuffix(" (deleted)"))
            except OSError:
                pass
    return found


def _in_use(entry: Path, running: Iterable[str]) -> str | None:
    prefix = str(entry)
    return next(
        (r for r in running if r == prefix or r.startswith(prefix + os.sep)), None
    )


def _read_proc_locks(proc_root: Path) -> set[tuple[int, int, int]] | None:
    """Parse ``<proc_root>/locks`` into ``{(major, minor, inode)}`` tuples, read-only."""
    locks_file = proc_root / "locks"
    try:
        text = locks_file.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    locked: set[tuple[int, int, int]] = set()
    for line in text.splitlines():
        parts = line.split()
        for field in parts[4:7]:
            pieces = field.split(":")
            if len(pieces) == 3:
                try:
                    maj = int(pieces[0], 16)
                    minor = int(pieces[1], 16)
                    ino = int(pieces[2], 10)
                except ValueError:
                    continue
                locked.add((maj, minor, ino))
                break
    return locked


def _stat_dev_ino(path: Path) -> tuple[int, int, int] | None:
    if not hasattr(os, "major") or not hasattr(os, "minor"):
        return None
    try:
        st = path.lstat()
    except OSError:
        return None
    if not stat.S_ISREG(st.st_mode):
        return None
    return (os.major(st.st_dev), os.minor(st.st_dev), st.st_ino)


def _candidate_lock_files(version_path: Path) -> tuple[Path, ...]:
    parent = version_path.parent
    name = version_path.name
    return (
        parent / f"{name}.lock",
        parent / "locks" / f"{name}.lock",
        parent.parent / "locks" / f"{name}.lock",
    )


class UnavailableLivenessAdapter:
    """Fallback liveness adapter when no process/lock table can be inspected."""

    @property
    def available(self) -> bool:
        return False

    def running_match(self, entry: Path) -> str | None:
        return None

    def version_use(self, version_path: Path) -> VersionUse:
        return VersionUse("unknown")


class InMemoryLivenessAdapter:
    """Hermetic read-only liveness adapter for unit tests."""

    def __init__(
        self,
        running: Iterable[str] | None = (),
        locked_paths: Mapping[str, str] | Iterable[str] = (),
        in_use_pids: Mapping[str, str] | None = None,
    ) -> None:
        self._running = None if running is None else set(running)
        if isinstance(locked_paths, Mapping):
            self._locks = {str(k): str(v) for k, v in locked_paths.items()}
        else:
            self._locks = {str(p): str(p) for p in locked_paths}
        self._in_use_pids = {str(k): str(v) for k, v in (in_use_pids or {}).items()}

    @property
    def available(self) -> bool:
        return self._running is not None

    def running_match(self, entry: Path) -> str | None:
        if self._running is None:
            return None
        return _in_use(entry, self._running)

    def version_use(self, version_path: Path) -> VersionUse:
        key = str(version_path)
        if self._running is not None:
            used = _in_use(version_path, self._running)
            if used:
                return VersionUse("in-use", "running", used)
        if key in self._locks:
            return VersionUse("in-use", "lock", self._locks[key])
        if key in self._in_use_pids:
            return VersionUse("in-use", "in_use_pid", self._in_use_pids[key])
        if self._running is None:
            return VersionUse("unknown")
        return VersionUse("not-in-use")


class ProcLivenessAdapter:
    """Strictly read-only Linux ``/proc`` + ``/proc/locks`` liveness and version-lock adapter.

    Never acquires ``flock(LOCK_EX)`` or writes any file. Inspects open
    executable/cwd/fd paths from ``/proc/<pid>`` and matches sibling version
    lock files (``<ver>.lock``, ``locks/<ver>.lock``, ``../locks/<ver>.lock``)
    by ``(major, minor, inode)`` against ``/proc/locks`` and open FD targets,
    plus ``.in_use/<pid>`` liveness. Degrades gracefully to ``unknown`` when
    ``/proc`` is unavailable.
    """

    def __init__(
        self,
        proc_root: Path = Path("/proc"),
        *,
        running: Iterable[str] | None | Any = _UNSET,
    ) -> None:
        self._proc_root = Path(proc_root)
        if running is _UNSET:
            self._running = running_paths(self._proc_root)
        else:
            self._running = None if running is None else set(running)
        self._proc_locks: set[tuple[int, int, int]] | None = (
            _read_proc_locks(self._proc_root) if self._running is not None else None
        )
        self._live_pids: set[str] | None = None
        if self._running is not None:
            try:
                self._live_pids = {
                    p.name for p in self._proc_root.iterdir() if p.name.isdigit()
                }
            except OSError:
                self._live_pids = None

    @property
    def available(self) -> bool:
        return self._running is not None

    def running_match(self, entry: Path) -> str | None:
        if self._running is None:
            return None
        return _in_use(entry, self._running)

    def _lock_is_held(self, lock_file: Path) -> bool:
        if self._running is not None:
            if str(lock_file) in self._running:
                return True
            try:
                resolved = str(lock_file.resolve())
                if resolved in self._running:
                    return True
            except OSError:
                pass
        if self._proc_locks:
            dev_ino = _stat_dev_ino(lock_file)
            if dev_ino is not None and dev_ino in self._proc_locks:
                return True
        return False

    def _in_use_pid_match(self, version_path: Path) -> str | None:
        in_use_dir = version_path / ".in_use"
        if not in_use_dir.is_dir():
            return None
        try:
            with os.scandir(in_use_dir) as entries:
                for entry in entries:
                    if not entry.name.isdigit():
                        continue
                    if self._live_pids is not None and entry.name in self._live_pids:
                        return entry.path
        except OSError:
            return None
        return None

    def version_use(self, version_path: Path) -> VersionUse:
        if self._running is None:
            return VersionUse("unknown")
        used = _in_use(version_path, self._running)
        if used:
            return VersionUse("in-use", "running", used)
        for lock_file in _candidate_lock_files(version_path):
            if lock_file.is_file() and not lock_file.is_symlink():
                if self._lock_is_held(lock_file):
                    return VersionUse("in-use", "lock", str(lock_file))
        pid_marker = self._in_use_pid_match(version_path)
        if pid_marker is not None:
            return VersionUse("in-use", "in_use_pid", pid_marker)
        return VersionUse("not-in-use")


def _liveness_from_running(
    running: Iterable[str] | None,
    liveness: VersionLivenessPort | None = None,
) -> VersionLivenessPort:
    if liveness is not None:
        return liveness
    if running is None:
        return UnavailableLivenessAdapter()
    return ProcLivenessAdapter(running=running)


def _link_targets(directories: Iterable[Path]) -> dict[str, str]:
    found: dict[str, str] = {}
    for directory in directories:
        try:
            with os.scandir(directory) as entries:
                for entry in entries:
                    if entry.is_symlink():
                        found.setdefault(os.path.realpath(entry.path), entry.path)
        except OSError:
            pass
    return found


def _dotted_versions(names: Iterable[str]) -> bool:
    dotted = (VERSION_RE.match(name) for name in names)
    return sum(1 for m in dotted if m and "." in m.group(1)) >= 2


def _orphan_reason(registry: str, marker: dict[str, Any] | None, sweeping: bool) -> str:
    base = f"no installPath in {registry} references this version"
    if not sweeping:
        return (
            f"{base}, and {registry} records no install, so Claude Code's "
            "removal of orphaned versions does not run"
        )
    if marker is None:
        return f"{base}, and it has no readable .orphaned_at marker"
    age = marker["marker_age_days"]
    if marker["past_sweep_window"]:
        return (
            f"{base}; its .orphaned_at marker is {age} days old, past the "
            f"{ORPHAN_SWEEP_DAYS}-day window after which Claude Code removes an "
            "orphaned version, so it has not been swept"
        )
    return (
        f"{base}; its .orphaned_at marker is {age} days old, inside the "
        f"{ORPHAN_SWEEP_DAYS}-day window, so Claude Code removes it itself"
    )


class ClaudeHarnessClassifier:
    """Classifies ``plugins/cache/`` versions, ``temp_git_*`` dirs, and ``projects/`` slugs."""

    def __init__(self, *, env: Mapping[str, str] | None = None) -> None:
        self._env = env
        self._by_path: dict[str, Classification] = {}

    def prepare(self, ctx: WalkContext) -> None:
        self._by_path.clear()
        if ctx.claude_dir is None:
            return
        claude_dir = ctx.claude_dir.resolve()
        target = ctx.target.resolve()

        cache_dir = claude_dir / "plugins" / "cache"
        if _overlaps(cache_dir, target):
            self._prepare_plugin_cache(claude_dir, ctx)

        projects_dir = claude_dir / "projects"
        if _overlaps(projects_dir, target):
            self._prepare_projects(projects_dir, ctx)

    def _prepare_plugin_cache(self, claude_dir: Path, ctx: WalkContext) -> None:
        reader = FsGuardedTextReader(claude_dir)
        registry_path = claude_dir / INSTALLED_PLUGINS
        inspection = inspect_plugin_cache(
            claude_dir, reader, ctx.now, label=registry_path.name
        )
        for entry in inspection.versions:
            evidence: dict[str, Any] | None = None
            if entry.status == "unknown":
                disposition = "UNKNOWN"
                reason = (
                    f"{inspection.registry.doubt}; the registry cannot show "
                    "whether this version is installed"
                )
            elif entry.status == "referenced":
                disposition = "KEEP"
                reason = (
                    f"an installPath in {registry_path.name} points at this "
                    "installed version"
                )
                evidence = {"tool": "claude-code", "references": str(registry_path)}
            else:
                evidence = entry.marker
                disposition = "CANDIDATE"
                reason = _orphan_reason(
                    registry_path.name, evidence, inspection.registry.installs
                )
            self._by_path[str(entry.path)] = Classification(
                producer=entry.plugin,
                category="plugin-cache-version",
                disposition=disposition,
                reason=reason,
                evidence=evidence,
            )

        for tg in inspection.temp_git_dirs:
            used = ctx.liveness.running_match(tg.path)
            if used:
                disposition = "KEEP"
                reason = f"a running process uses {used}"
                evidence = {"running": used}
            elif not ctx.liveness.available:
                disposition = "UNKNOWN"
                reason = (
                    "Claude plugin temp_git staging clone; the process table was not "
                    "read, so whether a clone is in progress is not known"
                )
                evidence = None
            else:
                disposition = "CANDIDATE"
                reason = (
                    "leaked Claude plugin temp_git staging clone; no running process "
                    "uses it"
                )
                evidence = None
            self._by_path[str(tg.path)] = Classification(
                producer="claude-code",
                category="plugin-cache-temp-git",
                disposition=disposition,
                reason=reason,
                evidence=evidence,
            )

    def _prepare_projects(self, projects_dir: Path, ctx: WalkContext) -> None:
        resolver = ProjectSlugResolver(
            fs_root=ctx.fs_root,
            cwd_port=TranscriptReaderCwdAdapter(),
            env=self._env,
        )
        for res in resolver.resolve_all(projects_dir):
            evidence: dict[str, Any] | None = None
            if res.status == "exists":
                disposition = "KEEP"
                reason = res.reason
                evidence = {"tool": "claude-code", "references": res.source_path}
            elif res.status == "pinned":
                disposition = "KEEP"
                reason = res.reason
            elif res.status == "orphan":
                disposition = "CANDIDATE"
                reason = res.reason
            else:
                disposition = "UNKNOWN"
                reason = res.reason
            self._by_path[str(res.path)] = Classification(
                producer="claude-code",
                category="transcript-dir",
                disposition=disposition,
                reason=reason,
                evidence=evidence,
            )

    def classify_directory(
        self, directory: Path, entries: Sequence[os.DirEntry[str]]
    ) -> dict[str, Classification]:
        return {}

    def classify_entry(
        self, path: Path, st: os.stat_result
    ) -> Classification | None:
        return self._by_path.get(str(path))


class TmpProducerClassifier:
    """Classifies top-level ``/tmp`` (or OS temp root) entries by producer prefix."""

    def __init__(
        self,
        *,
        min_age_days: float = TMP_MIN_AGE_DAYS,
        producers: tuple[tuple[str, str, str | None], ...] = TMP_PRODUCERS,
    ) -> None:
        self.min_age_days = min_age_days
        self.producers = producers
        self._by_path: dict[str, Classification] = {}

    def prepare(self, ctx: WalkContext) -> None:
        self._by_path.clear()
        tmp_dir = ctx.tmp_dir.resolve()
        target = ctx.target.resolve()
        if not _overlaps(tmp_dir, target):
            return
        try:
            entries = sorted(tmp_dir.iterdir())
        except OSError:
            return
        for path in entries:
            match = next(
                (p for p in self.producers if path.name.startswith(p[0])), None
            )
            try:
                age = (ctx.now - os.lstat(path).st_mtime) / DAY
            except OSError:
                continue
            used = ctx.liveness.running_match(path)
            _, producer, keep_reason = match or (None, "unknown", None)
            if match is None:
                disposition = "UNKNOWN"
                reason = "no producer prefix rule matches this name"
            elif keep_reason:
                disposition, reason = "KEEP", keep_reason
            elif used:
                disposition, reason = "KEEP", f"a running process uses {used}"
            elif age < self.min_age_days:
                disposition = "KEEP"
                reason = (
                    f"changed {age:.1f} days ago, inside the {self.min_age_days:g}-day window "
                    f"in which a live {producer} run may still use it"
                )
            elif not ctx.liveness.available:
                disposition = "UNKNOWN"
                reason = (
                    f"{producer} leftover unchanged for {age:.0f} days; the process table "
                    "was not read, so whether a process uses it is not known"
                )
            else:
                disposition = "CANDIDATE"
                reason = f"{producer} leftover unchanged for {age:.0f} days; no running process uses it"
            self._by_path[str(path)] = Classification(
                producer=producer,
                category="tmp-producer",
                disposition=disposition,
                reason=reason,
            )

    def classify_directory(
        self, directory: Path, entries: Sequence[os.DirEntry[str]]
    ) -> dict[str, Classification]:
        return {}

    def classify_entry(
        self, path: Path, st: os.stat_result
    ) -> Classification | None:
        return self._by_path.get(str(path))


class SupersededVersionClassifier:
    """Classifies sibling version entries; indexes ``launcher_dirs`` once in ``prepare``."""

    def __init__(self, launcher_dirs: Iterable[Path] | None = None) -> None:
        self._explicit_launchers = (
            None if launcher_dirs is None else tuple(launcher_dirs)
        )
        self._launcher_links: dict[str, str] = {}
        self._liveness: VersionLivenessPort = UnavailableLivenessAdapter()

    def prepare(self, ctx: WalkContext) -> None:
        dirs = (
            self._explicit_launchers
            if self._explicit_launchers is not None
            else (ctx.home / ".local" / "bin", ctx.home / "bin")
        )
        self._launcher_links = _link_targets(dirs)
        self._liveness = ctx.liveness

    def classify_parent(
        self,
        parent: Path,
        entries: Sequence[os.DirEntry[str]] | None = None,
        *,
        require_dotted: bool = False,
    ) -> dict[str, Classification]:
        versions: list[tuple[tuple[tuple[int, ...], int], str, Path]] = []
        if entries is None:
            try:
                with os.scandir(parent) as it:
                    raw = list(it)
            except OSError:
                return {}
        else:
            raw = list(entries)
        if require_dotted and not _dotted_versions(e.name for e in raw):
            return {}
        for entry in raw:
            match = VERSION_RE.match(entry.name)
            try:
                is_link = entry.is_symlink()
            except OSError:
                continue
            if match and not is_link:
                numbers = tuple(int(n) for n in match.group(1).split("."))
                key = (numbers, 0 if match.group(2) == "-" else 1)
                versions.append((key, entry.name, Path(entry.path)))
        if len(versions) < 2:
            return {}
        versions.sort()
        newest = versions[-1][1]
        holder = (
            parent.parent.name
            if parent.name in {"versions", "releases", "bin"}
            else parent.name
        )
        links = dict(self._launcher_links)
        for target_real, link_path in _link_targets((parent, parent.parent)).items():
            links[target_real] = link_path

        out: dict[str, Classification] = {}
        for _, name, path in versions:
            use = self._liveness.version_use(path)
            target = _in_use(Path(os.path.realpath(path)), links)
            disposition = "KEEP"
            evidence: dict[str, Any] | None = None
            if name == newest:
                reason = f"newest of {len(versions)} versions beside it in {parent}"
            elif use.status == "in-use":
                if use.kind == "lock":
                    reason = f"held by an active lock file at {use.detail}"
                    evidence = {"lock": use.detail}
                elif use.kind == "in_use_pid":
                    reason = f"a live process holds marker {use.detail}"
                    evidence = {"in_use": use.detail}
                else:
                    reason = f"a running process executes {use.detail}"
                    evidence = {"running": use.detail}
            elif target:
                reason = f"the symlink {links[target]} points at it"
                evidence = {"symlink": links[target]}
            elif use.status == "unknown" or not self._liveness.available:
                disposition = "UNKNOWN"
                reason = (
                    f"superseded by {newest}; the process table was not read, "
                    "so whether a process executes it is not known"
                )
            else:
                disposition = "CANDIDATE"
                reason = (
                    f"superseded by {newest}; no running process executes it and "
                    "no symlink beside it or in a launcher directory points at it"
                )
            out[str(path)] = Classification(
                producer=holder,
                category="superseded-version",
                disposition=disposition,
                reason=reason,
                evidence=evidence,
            )
        return out

    def classify_directory(
        self, directory: Path, entries: Sequence[os.DirEntry[str]]
    ) -> dict[str, Classification]:
        return self.classify_parent(directory, entries, require_dotted=True)

    def classify_entry(
        self, path: Path, st: os.stat_result
    ) -> Classification | None:
        return None


class DanglingSymlinkClassifier:
    """Classifies symlinks whose target does not exist."""

    def prepare(self, ctx: WalkContext) -> None:
        return None

    def classify_directory(
        self, directory: Path, entries: Sequence[os.DirEntry[str]]
    ) -> dict[str, Classification]:
        return {}

    def classify_entry(
        self, path: Path, st: os.stat_result
    ) -> Classification | None:
        if not stat.S_ISLNK(st.st_mode) or path.exists():
            return None
        producer = next(
            (p for hint, p in LINK_PRODUCERS if hint in path.as_posix()), "unknown"
        )
        return Classification(
            producer=producer,
            category="dangling-symlink",
            disposition="CANDIDATE",
            reason=f"points to {os.readlink(path)}, which does not exist",
        )


class DictClassifierAdapter:
    """Adapter wrapping a static ``{path: Classification | row_dict}`` map."""

    def __init__(
        self, mapping: Mapping[str, Classification | Mapping[str, Any]]
    ) -> None:
        self._by_path: dict[str, Classification] = {}
        for key, value in mapping.items():
            if isinstance(value, Classification):
                self._by_path[str(key)] = value
            else:
                self._by_path[str(key)] = Classification(
                    producer=str(value["producer"]),
                    category=str(value["category"]),
                    disposition=str(value["disposition"]),
                    reason=str(value["reason"]),
                    evidence=value.get("evidence"),
                )

    def prepare(self, ctx: WalkContext) -> None:
        return None

    def classify_directory(
        self, directory: Path, entries: Sequence[os.DirEntry[str]]
    ) -> dict[str, Classification]:
        return {}

    def classify_entry(
        self, path: Path, st: os.stat_result
    ) -> Classification | None:
        return self._by_path.get(str(path))


def superseded_versions(
    parents: Iterable[Path],
    running: Iterable[str] | None = (),
    launcher_dirs: Iterable[Path] = (),
    *,
    liveness: VersionLivenessPort | None = None,
) -> list[dict[str, Any]]:
    """Sibling entries under each parent whose names parse as versions."""
    live = _liveness_from_running(running, liveness)
    classifier = SupersededVersionClassifier(launcher_dirs=tuple(launcher_dirs))
    ctx = WalkContext(
        target=Path("/"),
        home=Path.home(),
        tmp_dir=tmp_root(),
        claude_dir=None,
        now=0.0,
        liveness=live,
    )
    classifier.prepare(ctx)
    rows: list[dict[str, Any]] = []
    for parent in parents:
        classified = classifier.classify_parent(parent, require_dotted=False)
        for path_str, cls in classified.items():
            rows.append(
                make_row(
                    Path(path_str),
                    producer=cls.producer,
                    category=cls.category,
                    disposition=cls.disposition,
                    reason=cls.reason,
                    evidence=cls.evidence,
                )
            )
    return rows


def plugin_cache_versions(claude_dir: Path, now: float) -> list[dict[str, Any]]:
    """Rows for ``plugins/cache/<marketplace>/<plugin>/<version>`` under ``claude_dir``.

    Excludes depth-1 ``plugins/cache/temp_git_*`` staging clones from plugin
    version rows via ``inspect_plugin_cache``.
    """
    reader = FsGuardedTextReader(claude_dir)
    registry_path = claude_dir / INSTALLED_PLUGINS
    inspection = inspect_plugin_cache(
        claude_dir, reader, now, label=registry_path.name
    )
    rows: list[dict[str, Any]] = []
    for entry in inspection.versions:
        evidence: dict[str, Any] | None = None
        if entry.status == "unknown":
            disposition = "UNKNOWN"
            reason = (
                f"{inspection.registry.doubt}; the registry cannot show "
                "whether this version is installed"
            )
        elif entry.status == "referenced":
            disposition = "KEEP"
            reason = (
                f"an installPath in {registry_path.name} points at this "
                "installed version"
            )
            evidence = {"tool": "claude-code", "references": str(registry_path)}
        else:
            evidence = entry.marker
            disposition = "CANDIDATE"
            reason = _orphan_reason(
                registry_path.name, evidence, inspection.registry.installs
            )
        rows.append(
            make_row(
                entry.path,
                producer=entry.plugin,
                category="plugin-cache-version",
                disposition=disposition,
                reason=reason,
                evidence=evidence,
            )
        )
    return rows


def tmp_entries(
    tmp_dir: Path,
    now: float,
    running: Iterable[str] | None = (),
    min_age_days: float = TMP_MIN_AGE_DAYS,
    producers: tuple[tuple[str, str, str | None], ...] = TMP_PRODUCERS,
) -> list[dict[str, Any]]:
    """One row per top-level entry of ``tmp_dir``, attributed by producer name prefix."""
    live = _liveness_from_running(running)
    classifier = TmpProducerClassifier(min_age_days=min_age_days, producers=producers)
    ctx = WalkContext(
        target=tmp_dir,
        home=Path.home(),
        tmp_dir=tmp_dir,
        claude_dir=None,
        now=now,
        liveness=live,
    )
    classifier.prepare(ctx)
    rows: list[dict[str, Any]] = []
    try:
        entries = sorted(tmp_dir.resolve().iterdir())
    except OSError:
        return rows
    for path in entries:
        cls = classifier._by_path.get(str(path))
        if cls is None:
            continue
        rows.append(
            make_row(
                path,
                producer=cls.producer,
                category=cls.category,
                disposition=cls.disposition,
                reason=cls.reason,
                evidence=cls.evidence,
            )
        )
    return rows


def decode_project(encoded: str, fs_root: Path = Path("/")) -> str | None:
    """The existing path under ``fs_root`` whose encoding is ``encoded``, or None."""
    return ProjectSlugResolver(fs_root=fs_root).decode_slug(encoded)


def project_transcripts(
    projects_dir: Path, fs_root: Path = Path("/")
) -> list[dict[str, Any]]:
    """Rows for ``~/.claude/projects/<encoded>`` using one shared cached resolver."""
    resolver = ProjectSlugResolver(
        fs_root=fs_root, cwd_port=TranscriptReaderCwdAdapter()
    )
    rows: list[dict[str, Any]] = []
    for res in resolver.resolve_all(projects_dir):
        evidence: dict[str, Any] | None = None
        if res.status == "exists":
            disposition = "KEEP"
            evidence = {"tool": "claude-code", "references": res.source_path}
        elif res.status == "pinned":
            disposition = "KEEP"
        elif res.status == "orphan":
            disposition = "CANDIDATE"
        else:
            disposition = "UNKNOWN"
        rows.append(
            make_row(
                res.path,
                producer="claude-code",
                category="transcript-dir",
                disposition=disposition,
                reason=res.reason,
                evidence=evidence,
            )
        )
    return rows


def dangling_row(path: Path) -> dict[str, Any]:
    """The candidate row for one symlink whose target does not exist."""
    producer = next(
        (p for hint, p in LINK_PRODUCERS if hint in path.as_posix()), "unknown"
    )
    return make_row(
        path,
        producer=producer,
        category="dangling-symlink",
        disposition="CANDIDATE",
        reason=f"points to {os.readlink(path)}, which does not exist",
    )


def tmp_root() -> Path:
    """The directory the ``tmp-producer`` category covers.

    ``/tmp`` on POSIX, not ``$TMPDIR``, which may name a subdirectory of it and
    would then attribute that subdirectory's children instead of ``/tmp``'s own
    entries. Elsewhere the OS temp directory.
    """
    return Path("/tmp" if os.name == "posix" else tempfile.gettempdir()).resolve()


def category_rows(
    target: Path,
    *,
    home: Path,
    tmp_dir: Path,
    now: float,
    running: set[str] | None,
    claude_dir: Path | None | Any = _UNSET,
) -> dict[str, dict[str, Any]]:
    """Rows of each category overlapping ``target``, keyed by path string."""
    rows: list[dict[str, Any]] = []
    resolved_claude = (
        resolve_claude_dir(home=home) if claude_dir is _UNSET else claude_dir
    )
    if resolved_claude is not None:
        if _overlaps(resolved_claude / "plugins" / "cache", target):
            rows += plugin_cache_versions(resolved_claude, now)
        if _overlaps(resolved_claude / "projects", target):
            rows += project_transcripts(resolved_claude / "projects")
    if _overlaps(tmp_dir, target):
        rows += tmp_entries(tmp_dir, now, running)
    return {row["name"]: row for row in rows}


_ORIGINAL_CATEGORY_ROWS = category_rows


def _default_classifiers() -> tuple[EntryClassifierPort, ...]:
    return (
        ClaudeHarnessClassifier(),
        TmpProducerClassifier(),
        SupersededVersionClassifier(),
        DanglingSymlinkClassifier(),
    )


def inventory_rows(
    target: Path,
    *,
    deep: bool,
    home: Path,
    tmp_dir: Path,
    now: float,
    running: Iterable[str] | None = (),
    skip: frozenset[str] = frozenset(),
    mounts: frozenset[str] = frozenset(),
    claude_dir: Path | None | Any = _UNSET,
    liveness: VersionLivenessPort | None = None,
    classifiers: Sequence[EntryClassifierPort] | None = None,
    fs_root: Path = Path("/"),
) -> Iterable[dict[str, Any]]:
    """Yield one row per entry of ``target``, the target itself last.

    Single-pass mount-safe and ``st_dev``-safe sizing: classifiers return
    ``Classification`` metadata only and never pre-walk sizes. A directory that
    cannot be read, or that is a mount point (another device, or a path in
    ``mounts``, which also catches a bind mount on the same device), is one
    UNKNOWN row and is not entered. Paths in ``skip`` (the report being written)
    are left out.
    """
    live = _liveness_from_running(running, liveness)
    resolved_claude: Path | None
    if claude_dir is _UNSET:
        resolved_claude = resolve_claude_dir(home=home)
    elif claude_dir is None:
        resolved_claude = None
    else:
        resolved_claude = Path(claude_dir).expanduser()

    ctx = WalkContext(
        target=target,
        home=home,
        tmp_dir=tmp_dir,
        claude_dir=resolved_claude,
        now=now,
        liveness=live,
        fs_root=fs_root,
    )

    active_classifiers: list[EntryClassifierPort]
    if classifiers is not None:
        active_classifiers = list(classifiers)
    elif category_rows is not _ORIGINAL_CATEGORY_ROWS:
        patched = category_rows(
            target,
            home=home,
            tmp_dir=tmp_dir,
            now=now,
            running=None if running is None else set(running),
        )
        active_classifiers = [
            DictClassifierAdapter(patched),
            SupersededVersionClassifier(),
            DanglingSymlinkClassifier(),
        ]
    else:
        active_classifiers = list(_default_classifiers())

    for clf in active_classifiers:
        clf.prepare(ctx)

    dir_classifications: dict[str, Classification] = {}

    def children(directory: Path) -> list[tuple[Path, os.stat_result | None, str]]:
        with os.scandir(directory) as it:
            entries = sorted(it, key=lambda e: e.name, reverse=True)
        for clf in active_classifiers:
            for key, cls in clf.classify_directory(directory, entries).items():
                dir_classifications.setdefault(key, cls)
        found: list[tuple[Path, os.stat_result | None, str]] = []
        for entry in entries:
            if entry.path in skip:
                continue
            try:
                found.append((Path(entry.path), entry.stat(follow_symlinks=False), ""))
            except OSError as exc:
                found.append((Path(entry.path), None, f"{type(exc).__name__}: {exc}"))
        return found

    def classify(path: Path, st: os.stat_result) -> Classification | None:
        for clf in active_classifiers:
            hit = clf.classify_entry(path, st)
            if hit is not None:
                return hit
        return dir_classifications.get(str(path))

    def row(path: Path, st: os.stat_result, size: int) -> dict[str, Any]:
        cls = classify(path, st)
        if cls is not None:
            return _stat_row(
                path,
                st,
                size,
                producer=cls.producer,
                category=cls.category,
                disposition=cls.disposition,
                reason=cls.reason,
                evidence=cls.evidence,
            )
        return _stat_row(path, st, size, **UNCLASSIFIED)

    def not_entered(path: Path, st: os.stat_result, why: str) -> dict[str, Any]:
        return _stat_row(
            path,
            st,
            0,
            producer="unknown",
            category="not-walked",
            disposition="UNKNOWN",
            reason=f"{why}; its contents and size are not counted",
        )

    target = Path(target).resolve()
    root_st = os.lstat(target)
    try:
        stack = [(target, root_st, children(target), [0])]
    except OSError as exc:
        yield not_entered(target, root_st, f"unreadable ({type(exc).__name__}: {exc})")
        return
    while stack:
        directory, dir_st, pending, total = stack[-1]
        if not pending:
            stack.pop()
            if stack:
                stack[-1][3][0] += total[0]
            yield row(directory, dir_st, total[0])
            continue
        path, st, error = pending.pop()
        if st is None:
            yield {
                "name": str(path),
                "ext": path.suffix,
                "size": 0,
                "mtime": None,
                "owner": None,
                **UNCLASSIFIED,
                "category": "not-walked",
                "reason": f"cannot be read ({error})",
            }
            continue
        if _descends(st) and (
            str(path) in mounts or (st.st_dev and st.st_dev != root_st.st_dev)
        ):
            yield not_entered(path, st, "another filesystem is mounted here")
            continue
        if deep and _descends(st):
            try:
                stack.append((path, st, children(path), [0]))
            except OSError as exc:
                yield not_entered(path, st, f"unreadable ({type(exc).__name__}: {exc})")
            continue
        size = (
            _tree_size(path, mounts=mounts, root_dev=root_st.st_dev)
            if _descends(st)
            else st.st_size
        )
        total[0] += size
        yield row(path, st, size)


def _category_only(reason: str) -> bool:
    parts = [
        p for p in re.split(r"\s*(?:[;,.]|\band\b)\s*", reason.strip().lower()) if p
    ]
    return not parts or all(_CATEGORY_PHRASE.fullmatch(p) for p in parts)


def _shows_reference(reason: str, evidence: object) -> bool:
    if not isinstance(evidence, dict):
        return False
    tool = str(evidence.get("tool") or "").strip().lower()
    return bool(
        tool
        and str(evidence.get("references") or "").strip()
        and any(
            tool in m.group(1).split() for m in _NAMED_TOOL.finditer(reason.lower())
        )
    )


def validate_report(rows: Iterable[dict[str, Any]]) -> list[str]:
    """Failures of a report; an empty list means it passes.

    Every row needs the schema columns except the optional ``evidence`` and a
    valid disposition. A KEEP row fails when its reason is empty, which names no
    tool, so no evidence can stand in for it. It also fails when its reason is
    only a category phrase ("tool-managed", "OS-owned", "managed by <tool>"),
    unless the phrase names a tool ("managed by <tool>") and the row's evidence
    shows that tool still references the entry.
    """
    failures = []
    for index, row in enumerate(rows):
        label = str(row.get("name") or f"row {index}")
        missing = [c for c in ROW_COLUMNS if c != "evidence" and c not in row]
        if missing:
            failures.append(f"{label}: missing columns {', '.join(missing)}")
            continue
        if row["disposition"] not in DISPOSITIONS:
            failures.append(
                f"{label}: disposition {row['disposition']!r} is not one of {DISPOSITIONS}"
            )
            continue
        if row["disposition"] != "KEEP":
            continue
        reason = str(row["reason"] or "")
        if not reason.strip():
            failures.append(f"{label}: KEEP reason is empty")
        elif _category_only(reason) and not _shows_reference(
            reason, row.get("evidence")
        ):
            failures.append(
                f"{label}: KEEP reason {reason!r} is only a category phrase "
                "and no evidence shows the named tool still references the entry"
            )
    return failures


def _linux_mount_points(mountinfo: Path = Path("/proc/self/mountinfo")) -> frozenset[str]:
    """Read Linux mount points for standalone CLI runs; empty set when unavailable."""
    try:
        text = mountinfo.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return frozenset()
    found: set[str] = set()
    for line in text.splitlines():
        parts = line.split()
        if len(parts) < 5:
            continue
        point = re.sub(
            r"\\([0-7]{3})", lambda m: chr(int(m.group(1), 8)), parts[4]
        )
        found.add(point)
    return frozenset(found)


def main(argv: Sequence[str] | None = None) -> int:
    """Standalone read-only JSONL inventory CLI (zero ``--data-root``, zero writes by default)."""
    parser = argparse.ArgumentParser(
        prog="deep_inventory.py",
        description="Read-only deep disk inventory streaming validated JSONL rows.",
    )
    parser.add_argument("target", help="Directory to inventory.")
    depth = parser.add_mutually_exclusive_group()
    depth.add_argument(
        "--deep",
        action="store_true",
        help="Walk every nested directory (default when TARGET is $HOME).",
    )
    depth.add_argument(
        "--shallow",
        action="store_true",
        help="Emit only immediate children (and TARGET itself).",
    )
    parser.add_argument(
        "--out",
        default=None,
        help="Write JSONL rows to PATH instead of stdout.",
    )
    parser.add_argument(
        "--claude-dir",
        default=None,
        help="Claude config directory (default: $CLAUDE_CONFIG_DIR or ~/.claude).",
    )
    parser.add_argument(
        "--no-claude",
        action="store_true",
        help="Disable Claude harness classifiers.",
    )
    parser.add_argument(
        "--no-validate",
        action="store_true",
        help="Skip KEEP-reason validation.",
    )
    args = parser.parse_args(list(argv) if argv is not None else None)

    target_input = Path(args.target).expanduser()
    if not target_input.is_dir():
        print(f"error: target is not an existing directory: {args.target}", file=sys.stderr)
        return 2
    target = target_input.resolve()
    home = Path.home().resolve()
    if args.deep:
        deep = True
    elif args.shallow:
        deep = False
    else:
        deep = target == home

    claude_dir: Path | None
    if args.no_claude:
        claude_dir = None
    elif args.claude_dir:
        claude_dir = Path(args.claude_dir).expanduser()
    else:
        claude_dir = resolve_claude_dir(home=home)

    out_path = Path(args.out).expanduser().resolve() if args.out else None
    skip = frozenset({str(out_path)}) if out_path is not None else frozenset()
    mounts = _linux_mount_points()
    liveness = ProcLivenessAdapter()
    now = dt.datetime.now(dt.timezone.utc).timestamp()

    failures: list[str] = []
    stream_rows = inventory_rows(
        target,
        deep=deep,
        home=home,
        tmp_dir=tmp_root(),
        now=now,
        liveness=liveness,
        skip=skip,
        mounts=mounts,
        claude_dir=claude_dir,
    )

    if out_path is not None:
        try:
            with out_path.open("w", encoding="utf-8") as fh:
                for item in stream_rows:
                    fh.write(json.dumps(item, sort_keys=True) + "\n")
                    if not args.no_validate:
                        failures.extend(validate_report([item]))
        except OSError as exc:
            print(f"error: cannot write --out {out_path}: {exc}", file=sys.stderr)
            return 2
    else:
        try:
            for item in stream_rows:
                sys.stdout.write(json.dumps(item, sort_keys=True) + "\n")
                if not args.no_validate:
                    failures.extend(validate_report([item]))
        except BrokenPipeError:
            return 0

    if failures:
        for msg in failures:
            print(f"validation error: {msg}", file=sys.stderr)
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
