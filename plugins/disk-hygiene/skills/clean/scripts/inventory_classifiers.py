#!/usr/bin/env python3
"""Read-only liveness adapters and entry classifiers for deep_inventory.

Every adapter and classifier here is strictly read-only: no subprocess calls,
no locks acquired, no deletions, and no filesystem mutations.
"""

from __future__ import annotations

import dataclasses
import os
import re
import stat
import sys
from collections.abc import Iterable, Mapping, Sequence
from pathlib import Path
from typing import Any, Protocol, runtime_checkable

_LIB_DIR = Path(__file__).resolve().parents[3] / "lib"
if str(_LIB_DIR) not in sys.path:
    sys.path.insert(0, str(_LIB_DIR))

from claude_projects import (  # noqa: E402  (path set above; plugin-bundled module)
    ProjectSlugResolver,
    TranscriptReaderCwdAdapter,
)
from plugin_cache_versions import (  # noqa: E402  (path set above; plugin-bundled module)
    INSTALLED_PLUGINS,
    ORPHAN_SWEEP_DAYS,
    FsGuardedTextReader,
    inspect_plugin_cache,
)

DAY = 86400.0
TMP_MIN_AGE_DAYS = 7.0
VERSION_RE = re.compile(r"^v?(\d+(?:\.\d+)*)(?:([-+])[\w.+-]+)?$")
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


def _within(path: Path, root: Path) -> bool:
    return path == root or root in path.parents


def _overlaps(scope: Path, target: Path) -> bool:
    """Bidirectional containment: true when scope is inside target OR target is inside scope."""
    return _within(scope, target) or _within(target, scope)


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

    def __init__(
        self,
        *,
        env: Mapping[str, str] | None = None,
        min_temp_git_age_days: float = TMP_MIN_AGE_DAYS,
    ) -> None:
        self._env = env
        self.min_temp_git_age_days = min_temp_git_age_days
        self._by_path: dict[str, Classification] = {}

    def prepare(self, ctx: WalkContext) -> None:
        self._by_path.clear()
        if ctx.claude_dir is None:
            return
        claude_dir = ctx.claude_dir.resolve()
        target = ctx.target.resolve()

        cache_dir = claude_dir / "plugins" / "cache"
        if _overlaps(cache_dir, target):
            self.classify_plugin_cache(claude_dir, ctx)

        projects_dir = claude_dir / "projects"
        if _overlaps(projects_dir, target):
            self.classify_projects(projects_dir, ctx)

    def classify_plugin_cache(
        self, claude_dir: Path, ctx: WalkContext
    ) -> dict[str, Classification]:
        out: dict[str, Classification] = {}
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
            cls = Classification(
                producer=entry.plugin,
                category="plugin-cache-version",
                disposition=disposition,
                reason=reason,
                evidence=evidence,
            )
            out[str(entry.path)] = cls
            self._by_path[str(entry.path)] = cls

        for tg in inspection.temp_git_dirs:
            try:
                age = (ctx.now - os.lstat(tg.path).st_mtime) / DAY
            except OSError:
                continue
            used = ctx.liveness.running_match(tg.path)
            if used:
                disposition = "KEEP"
                reason = f"a running process uses {used}"
                evidence = {"running": used}
            elif age < self.min_temp_git_age_days:
                disposition = "KEEP"
                reason = (
                    f"changed {age:.1f} days ago, inside the "
                    f"{self.min_temp_git_age_days:g}-day window in which a live "
                    "Claude plugin clone may still use it"
                )
                evidence = None
            elif not ctx.liveness.available:
                disposition = "UNKNOWN"
                reason = (
                    f"Claude plugin temp_git staging clone unchanged for {age:.0f} days; "
                    "the process table was not read, so whether a clone is in progress "
                    "is not known"
                )
                evidence = None
            else:
                disposition = "CANDIDATE"
                reason = (
                    f"leaked Claude plugin temp_git staging clone unchanged for "
                    f"{age:.0f} days; no running process uses it"
                )
                evidence = None
            cls = Classification(
                producer="claude-code",
                category="plugin-cache-temp-git",
                disposition=disposition,
                reason=reason,
                evidence=evidence,
            )
            out[str(tg.path)] = cls
            self._by_path[str(tg.path)] = cls
        return out

    def classify_projects(
        self, projects_dir: Path, ctx: WalkContext
    ) -> dict[str, Classification]:
        out: dict[str, Classification] = {}
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
            cls = Classification(
                producer="claude-code",
                category="transcript-dir",
                disposition=disposition,
                reason=reason,
                evidence=evidence,
            )
            out[str(res.path)] = cls
            self._by_path[str(res.path)] = cls
        return out

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
        producers: tuple[tuple[str, str, str | None], ...] = (),
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

    def __init__(
        self,
        *,
        link_producers: tuple[tuple[str, str], ...] = (),
    ) -> None:
        self.link_producers = link_producers

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
            (p for hint, p in self.link_producers if hint in path.as_posix()), "unknown"
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


def default_classifiers(
    *,
    tmp_producers: tuple[tuple[str, str, str | None], ...] = (),
    link_producers: tuple[tuple[str, str], ...] = (),
) -> tuple[EntryClassifierPort, ...]:
    return (
        ClaudeHarnessClassifier(),
        TmpProducerClassifier(producers=tmp_producers),
        SupersededVersionClassifier(),
        DanglingSymlinkClassifier(link_producers=link_producers),
    )
