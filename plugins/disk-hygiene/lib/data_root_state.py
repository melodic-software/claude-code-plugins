"""Data-root ownership checks, ASCII session-ID sanitization, and clean-run state.

Single owner of the engine-owned directory/file table, strict ASCII session-ID
sanitization matching ``hooks/run-python-hook.sh`` and ``hooks/resume-notice.mjs``,
and the ``clean-runs`` marker lock and lifecycle.
"""

from __future__ import annotations

import json
import os
import re
import time
from collections.abc import Callable, Iterator
from contextlib import contextmanager, suppress
from pathlib import Path

RUN_MARKER_DIRNAME = "clean-runs"
ENGINE_OWNED_DIRS = frozenset(
    {
        "guard-decisions",
        "guard-launch-monitor",
        RUN_MARKER_DIRNAME,
        "inventory",
        "clean-invoked",
        "guard-no-interpreter",
    }
)
ENGINE_OWNED_FILES = frozenset({"catalog.json", "catalog.md"})

RUN_IDLE_TIMEOUT_SECONDS = 3600.0
RUN_LOCK_FILENAME = ".lock"

_SESSION_ID_DISALLOWED = re.compile(r"[^A-Za-z0-9_-]")


class DataRootError(Exception):
    """Raised when a path escapes the data root or targets engine-owned state."""


def sanitize_session_id(session_id: str, *, fallback: str = "") -> str:
    """Sanitize a session ID using strict ASCII ``[^A-Za-z0-9_-]`` -> ``_``."""
    safe = _SESSION_ID_DISALLOWED.sub("_", session_id)
    return safe if safe else fallback


def run_marker_filename(session_id: str) -> str:
    """The run marker's file name under ``RUN_MARKER_DIRNAME`` for one session."""
    return f"{sanitize_session_id(session_id)}.json"


def _set_run_marker_lock(fd: int, take: bool) -> None:
    if os.name == "nt":
        import msvcrt

        os.lseek(fd, 0, os.SEEK_SET)
        msvcrt.locking(fd, msvcrt.LK_LOCK if take else msvcrt.LK_UNLCK, 1)
    else:
        import fcntl

        fcntl.flock(fd, fcntl.LOCK_EX if take else fcntl.LOCK_UN)


@contextmanager
def run_marker_lock(runs: str | os.PathLike[str]) -> Iterator[None]:
    """Hold the exclusive run-marker lock in ``runs``, creating both if absent.

    Best effort: when the lock file cannot be opened or locked, the body runs
    unlocked, so a lock failure never costs the marker write it guards.
    """
    os.makedirs(runs, exist_ok=True)
    fd: int | None = None
    try:
        fd = os.open(
            os.path.join(runs, RUN_LOCK_FILENAME), os.O_RDWR | os.O_CREAT, 0o600
        )
        _set_run_marker_lock(fd, True)
    except OSError:
        if fd is not None:
            os.close(fd)
        fd = None
    try:
        yield
    finally:
        if fd is not None:
            with suppress(OSError):
                _set_run_marker_lock(fd, False)
            os.close(fd)


def is_engine_owned(relative: str) -> bool:
    """True when a data-root-relative path is the root or engine-owned state.

    Names compare case-folded, with a trailing dot or space and any NTFS stream
    suffix dropped, so a spelling a case-insensitive or Windows file system
    resolves to the same entry is refused too.
    """
    keys = [
        part.split(":", 1)[0].rstrip(" .").casefold()
        for part in re.split(r"[/\\]", relative)
        if part not in ("", ".")
    ]
    if not keys:
        return True
    return keys[0] in ENGINE_OWNED_DIRS or (
        len(keys) == 1 and keys[0] in ENGINE_OWNED_FILES
    )


def is_within(path: Path, parent: Path) -> bool:
    try:
        return os.path.commonpath(
            [os.path.normcase(path), os.path.normcase(parent)]
        ) == os.path.normcase(parent)
    except ValueError:
        return False


class CleanRunStore:
    """Lock-protected ``clean-runs`` marker store under one data root."""

    def __init__(
        self,
        data_root: str | os.PathLike[str],
        *,
        idle_timeout_seconds: float = RUN_IDLE_TIMEOUT_SECONDS,
    ) -> None:
        self.root = Path(data_root)
        self.idle_timeout_seconds = idle_timeout_seconds

    @property
    def runs_dir(self) -> Path:
        return self.root / RUN_MARKER_DIRNAME

    def marker_path(self, session_id: str) -> Path:
        return self.runs_dir / run_marker_filename(session_id)

    def is_open(
        self, session_id: str | None, *, now: float | None = None
    ) -> bool:
        if not session_id:
            return True
        try:
            written = self.marker_path(session_id).stat().st_mtime
        except FileNotFoundError:
            return False
        except Exception:  # noqa: BLE001 - an unreadable marker holds the belt
            return True
        current = time.time() if now is None else now
        return current - written < self.idle_timeout_seconds

    def manual_lane_open(
        self, session_id: str, *, now: float | None = None
    ) -> bool:
        if not self.is_open(session_id, now=now):
            return False
        try:
            return (
                json.loads(self.marker_path(session_id).read_text(encoding="utf-8"))[
                    "ends_with"
                ]
                is None
            )
        except Exception:  # noqa: BLE001 - an unreadable marker keeps the run
            return True

    def record_step(
        self,
        session_id: str | None,
        ends_with: str | None,
        *,
        touch_only: bool = False,
        manual_lane_check: Callable[[Path], bool] | None = None,
    ) -> None:
        if not session_id:
            return
        try:
            marker = self.marker_path(session_id)
            if touch_only:
                if self.is_open(session_id):
                    os.utime(marker)
                return
            with run_marker_lock(marker.parent):
                manual_open = (
                    manual_lane_check(marker)
                    if manual_lane_check is not None
                    else self.manual_lane_open(session_id)
                )
                if ends_with is not None and manual_open:
                    os.utime(marker)
                    return
                marker.write_text(
                    json.dumps({"version": 1, "ends_with": ends_with}),
                    encoding="utf-8",
                )
        except Exception:  # noqa: BLE001 - run bookkeeping never changes a verdict
            pass


class DataRoot:
    """Explicit data-root boundary enforcing containment and engine-owned exclusion."""

    def __init__(
        self,
        root: str | os.PathLike[str],
        *,
        plugin_root: Path | None = None,
    ) -> None:
        self.root = Path(root).expanduser().resolve(strict=False)
        self.plugin_root = (
            plugin_root.resolve(strict=False) if plugin_root is not None else None
        )

    def contains(self, path: str | os.PathLike[str]) -> bool:
        resolved = Path(path).expanduser().resolve(strict=False)
        return is_within(resolved, self.root)

    def refuse_engine_owned(self, path: Path) -> Path:
        relative = os.path.relpath(os.path.normcase(path), os.path.normcase(self.root))
        if is_engine_owned(relative):
            raise DataRootError(
                "a file argument must not name the data root or engine-owned state"
            )
        return path

    def state_output_path(self, path: Path) -> Path:
        resolved = path.expanduser().resolve(strict=False)
        if self.plugin_root is not None and is_within(resolved, self.plugin_root):
            raise DataRootError(
                "generated state must not be written inside the plugin install directory"
            )
        if not is_within(resolved, self.root):
            raise DataRootError("generated state must stay inside the data root")
        return resolved

    def state_input_path(self, path: Path) -> Path:
        resolved = path.expanduser().resolve(strict=False)
        if not is_within(resolved, self.root):
            raise DataRootError("engine inputs must be read from inside the data root")
        return self.refuse_engine_owned(resolved)

    def model_output_path(self, value: str | os.PathLike[str]) -> Path:
        return self.refuse_engine_owned(self.state_output_path(Path(value)))

    def is_authorized_file(self, value: str) -> bool:
        if not os.path.isabs(value):
            return False
        try:
            path = os.path.normcase(os.path.realpath(value))
            root = os.path.normcase(os.path.realpath(self.root))
            return os.path.commonpath([path, root]) == root and not is_engine_owned(
                os.path.relpath(path, root)
            )
        except (OSError, ValueError):
            return False

    def clean_runs(
        self, *, idle_timeout_seconds: float = RUN_IDLE_TIMEOUT_SECONDS
    ) -> CleanRunStore:
        return CleanRunStore(self.root, idle_timeout_seconds=idle_timeout_seconds)
