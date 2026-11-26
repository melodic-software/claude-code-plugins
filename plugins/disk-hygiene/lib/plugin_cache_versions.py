# GENERATED from lib/plugin_cache_versions.py by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
"""Shared Claude Code install-tree layout, guarded reads, and plugin cache inspection.

Claude Code records every installed plugin in ``plugins/installed_plugins.json``,
keeps each cached version under ``plugins/cache/<marketplace>/<plugin>/<version>``,
and stages git clones under ``plugins/cache/temp_git_*``. A version no
``installPath`` names is orphaned: Claude Code stamps it with a ``.orphaned_at``
marker (epoch milliseconds) and removes it after a window.

This module is pure and read-only. Callers may pass either a ``GuardedTextReader``
or any ``Reader`` callable ``(relpath) -> str`` so each caller keeps its own read
policy. Zero cross-imports with ``lib/claude_projects.py``.

Python 3.11+, standard library only. The plugin copies are generated from
lib/plugin_cache_versions.py (scripts/shared-copies.txt).
"""

from __future__ import annotations

import datetime as dt
import fnmatch
import json
import os
from collections.abc import Callable, Iterable, Mapping
from pathlib import Path, PurePosixPath
from typing import Any, NamedTuple, Protocol, runtime_checkable

INSTALLED_PLUGINS = "plugins/installed_plugins.json"

ORPHAN_SWEEP_DAYS = 14

TEMP_GIT_PREFIX = "temp_git_"
DEFAULT_READ_LIMIT = 16_000_000

_DAY = 86400.0

Reader = Callable[[str], str]

SWEPT = "product-managed-swept"
KEPT = "product-managed-kept"
SESSION_SCOPED = "product-managed-session-scoped"
AUTHORED = "authored"
SECRET = "secret"
UNCLASSIFIED = "unclassified"

NEVER_READ_GLOBS: tuple[str, ...] = (
    ".credentials.json",
    "daemon/control.key",
    "daemon/pipe.key",
    "ide/*.lock",
    "*.key",
    "*.pem",
)

SURFACE_TABLE: dict[str, tuple[str, str]] = {
    "projects": (
        SWEPT,
        "Transcripts, subagent transcripts, spilled tool results, auto memory",
    ),
    "file-history": (SWEPT, "Pre-edit snapshots for checkpoint restore"),
    "plans": (SWEPT, "Plan files written during plan mode"),
    "debug": (SWEPT, "Per-session debug logs (--debug / /debug only)"),
    "paste-cache": (SWEPT, "Contents of large pastes"),
    "image-cache": (SWEPT, "Attached images"),
    "uploads": (SWEPT, "Uploads; see claude-directory#cleaned-up-automatically"),
    "dev-mods": (SWEPT, "Mods; see claude-directory#cleaned-up-automatically"),
    "usage-data": (SWEPT, "Usage data; see claude-directory#cleaned-up-automatically"),
    "session-env": (SWEPT, "Per-session environment metadata"),
    "tasks": (SWEPT, "Per-session task lists"),
    "shell-snapshots": (
        SWEPT,
        "Shell state captured at startup; removed on clean exit",
    ),
    "backups": (
        SWEPT,
        "~/.claude.json backups; see claude-directory#cleaned-up-automatically",
    ),
    "feedback-bundles": (SWEPT, "Redacted transcript archives written by /feedback"),
    "todos": (
        SWEPT,
        "Legacy; no longer written. Sweep removes contents then the directory",
    ),
    "statsig": (
        SWEPT,
        "Legacy; no longer written. Sweep removes contents then the directory",
    ),
    "logs": (
        SWEPT,
        "Legacy; no longer written. Sweep removes contents then the directory",
    ),
    "history.jsonl": (KEPT, "Every prompt typed, with timestamp and project path"),
    "stats-cache.json": (KEPT, "Aggregated token and cost counts shown by /usage"),
    "remote-settings.json": (
        KEPT,
        "Cached server-managed settings for your organization",
    ),
    "policy-limits.json": (
        KEPT,
        "Cached feature policy settings for your organization",
    ),
    "cache": (KEPT, "cache/changelog.md is a cached copy of the Claude Code changelog"),
    "jobs": (KEPT, "Background session state; see claude-directory#state-files-to-keep"),
    "remote": (
        KEPT,
        "Remote session state; see claude-directory#state-files-to-keep",
    ),
    "sessions": (
        SESSION_SCOPED,
        "One file per running session; removed at session exit, crash leftovers cleared at launch",
    ),
    "settings.json": (AUTHORED, "Primary user settings. Upstream: do not delete"),
    "settings.local.json": (AUTHORED, "Personal overrides"),
    "CLAUDE.md": (AUTHORED, "Global memory file"),
    "rules": (AUTHORED, "Topic-scoped instructions"),
    "skills": (AUTHORED, "User-scope skills"),
    "commands": (AUTHORED, "Legacy single-file prompts; same mechanism as skills"),
    "agents": (AUTHORED, "Subagent definitions"),
    "agent-memory": (AUTHORED, "Persistent memory for subagents"),
    "output-styles": (AUTHORED, "Custom system-prompt sections"),
    "workflows": (AUTHORED, "Dynamic workflow scripts saved from /workflows"),
    "themes": (AUTHORED, "Custom color themes"),
    "keybindings.json": (AUTHORED, "Custom keyboard shortcuts"),
    "hooks": (AUTHORED, "Hook scripts referenced from settings.json"),
    "plugins": (
        AUTHORED,
        "Marketplaces, installed versions, per-plugin data. Upstream: do not delete. "
        f"Orphaned versions are removed {ORPHAN_SWEEP_DAYS} days after update/uninstall; a removed "
        "marketplace's cache tree keeps its .orphaned_at markers and is swept on the same clock "
        "while any plugin stays installed. A version directory with no marker is never swept",
    ),
    ".credentials.json": (SECRET, "OAuth/API credentials -- never opened"),
    "daemon": (SECRET, "Contains control.key / pipe.key -- those two are never opened"),
}


class SecretReadRefused(RuntimeError):
    """Raised when a guarded reader is asked to read a secret or unallowlisted file."""


def _normalize_relpath(relpath: str) -> str:
    rel = relpath.replace("\\", "/")
    while rel.startswith("./"):
        rel = rel[2:]
    return rel


def is_never_read(relpath: str) -> bool:
    """True when ``relpath`` (POSIX-style, relative to the Claude root) is secret-bearing."""
    rel = _normalize_relpath(relpath)
    return any(fnmatch.fnmatchcase(rel, pat) for pat in NEVER_READ_GLOBS) or any(
        fnmatch.fnmatchcase(PurePosixPath(rel).name, pat) for pat in NEVER_READ_GLOBS
    )


def resolve_claude_dir(
    explicit: str | Path | None = None,
    *,
    env: Mapping[str, str] | None = None,
    home: Path | None = None,
) -> Path:
    """Resolve the Claude Code config directory: explicit > CLAUDE_CONFIG_DIR > ~/.claude."""
    if explicit is not None and str(explicit):
        return Path(explicit).expanduser()
    mapping = os.environ if env is None else env
    env_dir = mapping.get("CLAUDE_CONFIG_DIR")
    if env_dir:
        return Path(env_dir).expanduser()
    base = Path.home() if home is None else home
    return base / ".claude"


@runtime_checkable
class GuardedTextReader(Protocol):
    """Strict UTF-8, bounded, secret-refusing text reader over a Claude config tree."""

    def read_text(self, relpath: str, limit: int = DEFAULT_READ_LIMIT) -> str: ...

    def __call__(self, relpath: str, limit: int = DEFAULT_READ_LIMIT) -> str: ...


def _validate_safe_relpath(relpath: str) -> str:
    rel = _normalize_relpath(relpath)
    if not rel or rel.startswith("/") or ".." in PurePosixPath(rel).parts:
        raise OSError(f"unsafe relative path: {relpath}")
    return rel


class FsGuardedTextReader:
    """Strict UTF-8 filesystem reader enforcing NEVER_READ_GLOBS, symlink refusal, and a size cap."""

    def __init__(
        self,
        root: Path,
        *,
        allow_symlink_paths: Iterable[str] = (INSTALLED_PLUGINS,),
        limit: int = DEFAULT_READ_LIMIT,
    ) -> None:
        self.root = Path(root)
        self.allow_symlink_paths = frozenset(
            _normalize_relpath(p) for p in allow_symlink_paths
        )
        self.limit = limit

    def read_text(self, relpath: str, limit: int = DEFAULT_READ_LIMIT) -> str:
        rel = _normalize_relpath(relpath)
        if is_never_read(rel):
            raise SecretReadRefused(relpath)
        rel = _validate_safe_relpath(rel)
        path = self.root / rel
        if rel not in self.allow_symlink_paths and (
            path.is_symlink() or not path.is_file()
        ):
            raise OSError(f"{relpath} is not a regular file")
        cap = min(limit, self.limit)
        with path.open(encoding="utf-8", errors="strict") as fh:
            return fh.read(cap)

    def __call__(self, relpath: str, limit: int = DEFAULT_READ_LIMIT) -> str:
        return self.read_text(relpath, limit=limit)


class AllowlistGuardedReader:
    """Strict UTF-8 reader enforcing NEVER_READ_GLOBS, an explicit allowlist+globs, symlink refusal, and cap."""

    def __init__(
        self,
        root: Path,
        *,
        allowlist: Iterable[str],
        globs: Iterable[str] = (),
        limit: int = DEFAULT_READ_LIMIT,
        on_open: Callable[[str], None] | None = None,
    ) -> None:
        self.root = Path(root)
        self.allowlist = frozenset(_normalize_relpath(p) for p in allowlist)
        self.globs = tuple(globs)
        self.limit = limit
        self.on_open = on_open

    def may_read(self, relpath: str) -> bool:
        rel = _normalize_relpath(relpath)
        return rel in self.allowlist or any(
            fnmatch.fnmatchcase(rel, pat) for pat in self.globs
        )

    def read_text(self, relpath: str, limit: int = DEFAULT_READ_LIMIT) -> str:
        rel = _normalize_relpath(relpath)
        if is_never_read(rel) or not self.may_read(rel):
            raise SecretReadRefused(relpath)
        rel = _validate_safe_relpath(rel)
        path = self.root / rel
        if rel not in self.allowlist and (path.is_symlink() or not path.is_file()):
            raise OSError(f"{relpath} is not a regular file")
        cap = min(limit, self.limit)
        with path.open(encoding="utf-8", errors="strict") as fh:
            text = fh.read(cap)
        if self.on_open is not None:
            self.on_open(rel)
        return text

    def __call__(self, relpath: str, limit: int = DEFAULT_READ_LIMIT) -> str:
        return self.read_text(relpath, limit=limit)


class InMemoryTextReader:
    """Hermetic strict UTF-8 in-memory reader enforcing NEVER_READ_GLOBS and optional allowlist."""

    def __init__(
        self,
        files: Mapping[str, str | bytes],
        *,
        allowlist: Iterable[str] | None = None,
        globs: Iterable[str] = (),
        limit: int = DEFAULT_READ_LIMIT,
    ) -> None:
        self._files = {_normalize_relpath(k): v for k, v in files.items()}
        self._allowlist = (
            None
            if allowlist is None
            else frozenset(_normalize_relpath(p) for p in allowlist)
        )
        self._globs = tuple(globs)
        self.limit = limit

    def _may_read(self, rel: str) -> bool:
        if self._allowlist is None:
            return True
        return rel in self._allowlist or any(
            fnmatch.fnmatchcase(rel, pat) for pat in self._globs
        )

    def read_text(self, relpath: str, limit: int = DEFAULT_READ_LIMIT) -> str:
        rel = _normalize_relpath(relpath)
        if is_never_read(rel) or not self._may_read(rel):
            raise SecretReadRefused(relpath)
        if rel not in self._files:
            raise FileNotFoundError(relpath)
        raw = self._files[rel]
        text = raw.decode("utf-8", errors="strict") if isinstance(raw, bytes) else raw
        cap = min(limit, self.limit)
        return text[:cap]

    def __call__(self, relpath: str, limit: int = DEFAULT_READ_LIMIT) -> str:
        return self.read_text(relpath, limit=limit)


def _as_reader(read: Reader | GuardedTextReader) -> Reader:
    if isinstance(read, GuardedTextReader):
        return read.read_text
    return read


class Registry(NamedTuple):
    """What the registry says about this cache.

    ``doubt`` is empty when the registry can vouch for the cache. Otherwise it
    says why not, and no version may be called unreferenced: a missing registry
    is not evidence that every directory is orphaned. ``foreign`` marks the case
    where the registry parsed but none of its paths lies under this cache.
    """

    referenced: frozenset[Path]
    installs: bool
    doubt: str
    foreign: bool


class CachePathKind(NamedTuple):
    """Structural classification of a path inside ``plugins/cache/``."""

    kind: str
    temp_dir: str | None = None
    marketplace: str | None = None
    plugin: str | None = None
    version: str | None = None


class CacheVersionEntry(NamedTuple):
    """One depth-3 ``plugins/cache/<marketplace>/<plugin>/<version>`` directory."""

    marketplace: str
    plugin: str
    version: str
    path: Path
    relpath: str
    status: str
    marker: dict[str, Any] | None


class TempGitEntry(NamedTuple):
    """One depth-1 ``plugins/cache/temp_git_*`` staging clone directory."""

    name: str
    path: Path
    relpath: str


class PluginCacheInspection(NamedTuple):
    """Complete read-only inspection of ``<claude_dir>/plugins/cache/``."""

    registry: Registry
    versions: tuple[CacheVersionEntry, ...]
    temp_git_dirs: tuple[TempGitEntry, ...]


def classify_cache_relpath(relpath: str) -> CachePathKind:
    """Classify a root-relative or cache-relative path under ``plugins/cache/``.

    Separates depth-1 ``plugins/cache/temp_git_*`` staging directories (and all
    nested paths beneath them, such as ``.git/objects/pack``) from depth-3
    ``plugins/cache/<marketplace>/<plugin>/<version>`` entries.
    """
    rel = _normalize_relpath(relpath).strip("/")
    if not rel:
        return CachePathKind("other")
    parts = rel.split("/")
    if parts[0] == "plugins":
        if len(parts) < 3 or parts[1] != "cache":
            return CachePathKind("other")
        sub = parts[2:]
    else:
        sub = parts
    if not sub:
        return CachePathKind("other")
    if sub[0].startswith(TEMP_GIT_PREFIX):
        return CachePathKind("temp-git", temp_dir=sub[0])
    if len(sub) >= 3:
        return CachePathKind(
            "version",
            marketplace=sub[0],
            plugin=sub[1],
            version=sub[2],
        )
    return CachePathKind("other")


def install_paths(data: object) -> list[str]:
    """Every ``installPath`` in the parsed registry, whatever scope or project entry holds it."""
    if isinstance(data, dict):
        own = data.get("installPath")
        found = [own] if isinstance(own, str) else []
        return found + [p for v in data.values() for p in install_paths(v)]
    if isinstance(data, list):
        return [p for v in data for p in install_paths(v)]
    return []


def resolve(path: str | Path) -> Path | None:
    try:
        return Path(path).expanduser().resolve()
    except (OSError, RuntimeError):
        return None


def load_registry(
    read: Reader | GuardedTextReader,
    root: Path,
    label: str = INSTALLED_PLUGINS,
) -> Registry:
    """Read the registry under ``root`` and resolve the paths it references.

    ``label`` names the registry in ``doubt``.
    """
    read_fn = _as_reader(read)
    cache = root / "plugins" / "cache"
    try:
        data: Any = json.loads(read_fn(INSTALLED_PLUGINS))
    except (OSError, ValueError) as exc:
        return Registry(
            frozenset(), False, f"{label} unreadable ({type(exc).__name__})", False
        )
    if not isinstance(data, dict) or not isinstance(data.get("plugins"), dict):
        return Registry(frozenset(), False, f"{label} has no `plugins` object", False)
    referenced = frozenset(
        p for p in map(resolve, install_paths(data)) if p is not None
    )
    installs = bool(data["plugins"])
    cache_resolved = resolve(cache)
    if installs and not any(cache_resolved in p.parents for p in referenced):
        doubt = f"no installPath in {label} lies under {cache}"
        return Registry(referenced, installs, doubt, True)
    return Registry(referenced, installs, "", False)


def orphan_marker(
    read: Reader | GuardedTextReader,
    version_rel: str,
    now: float,
) -> dict[str, Any] | None:
    """The age of a version's ``.orphaned_at`` marker, or None when it is missing or unparsable."""
    read_fn = _as_reader(read)
    try:
        epoch = int(read_fn(f"{version_rel}/.orphaned_at").strip()) / 1000
        age = (now - epoch) / _DAY
        return {
            "orphaned_at": dt.datetime.fromtimestamp(epoch, dt.timezone.utc).isoformat(
                timespec="seconds"
            ),
            "marker_age_days": round(age, 1),
            "past_sweep_window": age >= ORPHAN_SWEEP_DAYS,
        }
    except (OSError, ValueError, OverflowError):
        return None


def _child_dirs(parent: Path) -> list[Path]:
    try:
        with os.scandir(parent) as entries:
            return sorted(
                Path(e.path) for e in entries if e.is_dir(follow_symlinks=False)
            )
    except OSError:
        return []


def inspect_plugin_cache(
    claude_dir: Path,
    read: Reader | GuardedTextReader,
    now: float,
    *,
    label: str = INSTALLED_PLUGINS,
) -> PluginCacheInspection:
    """Inspect ``plugins/cache/``, separating depth-1 ``temp_git_*`` dirs from depth-3 versions."""
    cache = claude_dir / "plugins" / "cache"
    temp_git_dirs: list[TempGitEntry] = []
    version_dirs: list[tuple[str, str, str, Path]] = []
    for top in _child_dirs(cache):
        if top.name.startswith(TEMP_GIT_PREFIX):
            temp_git_dirs.append(
                TempGitEntry(
                    name=top.name,
                    path=top,
                    relpath=f"plugins/cache/{top.name}",
                )
            )
            continue
        for plugin in _child_dirs(top):
            for version in _child_dirs(plugin):
                version_dirs.append((top.name, plugin.name, version.name, version))

    empty_registry = Registry(frozenset(), False, "", False)
    if not version_dirs:
        return PluginCacheInspection(empty_registry, (), tuple(temp_git_dirs))

    read_fn = _as_reader(read)
    registry = load_registry(read_fn, claude_dir, label=label)
    entries: list[CacheVersionEntry] = []
    for marketplace, plugin, version, path in version_dirs:
        rel = f"plugins/cache/{marketplace}/{plugin}/{version}"
        if registry.doubt:
            status = "unknown"
            marker = None
        elif resolve(path) in registry.referenced:
            status = "referenced"
            marker = None
        else:
            status = "unreferenced"
            marker = orphan_marker(read_fn, rel, now)
        entries.append(
            CacheVersionEntry(
                marketplace=marketplace,
                plugin=plugin,
                version=version,
                path=path,
                relpath=rel,
                status=status,
                marker=marker,
            )
        )
    return PluginCacheInspection(registry, tuple(entries), tuple(temp_git_dirs))
