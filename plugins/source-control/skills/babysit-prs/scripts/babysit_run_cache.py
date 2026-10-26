"""Reads one pr-merge run shares across its gate processes.

pr-merge.yml runs babysit_merge.py once per candidate and names a file in
`ENV`. A reader looks a value up here before asking GitHub and saves what it
read; with no file named, nothing is shared and every read happens as before.
A caller passes the oldest value it accepts (`MAX_AGE` for anything that can
change during a run, None for a value that cannot). A missing, malformed or
unwritable file, or an entry too old or dated in the future, is a miss, so
the reader asks GitHub: the file never refuses or allows anything itself.
"""

from __future__ import annotations

import contextlib
import copy
import hashlib
import json
import os
from collections.abc import Iterator
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

ENV = "BABYSIT_RUN_CACHE"
# The oldest shared value that can change during a run, and the oldest
# artifact listing the verdict reader judges on (judgment): pr-verify is not a
# required check, so a queued entry whose FAIL lands mid-run must be held
# before the merge queue can land it. enable-auto-merge's reader lifts the
# listing bound (`evidence --shared-listing`): ci-status runs the reader again
# in the merge queue instead.
MAX_AGE = timedelta(minutes=2)
# What gh reads its credentials from: these variables and hosts.yml.
CREDENTIAL_ENV = (
    "GH_TOKEN",
    "GITHUB_TOKEN",
    "GH_ENTERPRISE_TOKEN",
    "GITHUB_ENTERPRISE_TOKEN",
    "GH_HOST",
    "GH_CONFIG_DIR",
)


def now() -> datetime:
    return datetime.now(UTC)


def _path() -> Path | None:
    name = os.environ.get(ENV)
    return Path(name) if name else None


def _load(path: Path) -> dict[str, Any] | None:
    """The file's contents, {} when malformed, None when it could not be read."""
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return None
    try:
        data = json.loads(text)
    except ValueError:
        return {}
    return data if isinstance(data, dict) else {}


# This process's parse of the file, by path, with the stat it was read at. A
# memo is current only while the stat matching means the file is unchanged:
# pr-merge.yml runs its gate processes one after another, and every writer
# renames a new file into place (`put`, carry-run-cache.mjs), so another
# process's write brings a new inode. A writer that rewrote the file in place
# within one mtime tick at the same size, or a gate process running beside
# this one, would be served the stale parse.
_memo: dict[str, tuple[tuple[int, int, int, int], dict[str, Any]]] = {}


def _stamp(stat: os.stat_result) -> tuple[int, int, int, int]:
    return stat.st_dev, stat.st_ino, stat.st_mtime_ns, stat.st_size


def _read(path: Path) -> dict[str, Any] | None:
    """The file's contents ({} with no file), parsed again only when it changed
    on disk, or None when it exists but could not be read. Only a parse is
    kept, so a failed read is tried again. The result is shared: callers copy
    before changing or serving it."""
    try:
        stamp = _stamp(path.stat())
    except FileNotFoundError:
        _memo.pop(str(path), None)
        return {}
    except OSError:
        _memo.pop(str(path), None)
        return None
    memo = _memo.get(str(path))
    if memo is not None and memo[0] == stamp:
        return memo[1]
    data = _load(path)
    if data is None:
        _memo.pop(str(path), None)
    else:
        _memo[str(path)] = (stamp, data)
    return data


# The open `track()` lists.
_trackers: list[list[datetime]] = []


@contextlib.contextmanager
def track() -> Iterator[list[datetime]]:
    """Collect, while open, when each read a reader serves was taken
    (`note`), so a judgment can be dated by its oldest input."""
    taken: list[datetime] = []
    _trackers.append(taken)
    try:
        yield taken
    finally:
        _trackers.remove(taken)


def note(at: datetime) -> None:
    """Record that a value read at `at` was just served."""
    for taken in _trackers:
        taken.append(at)


def get(section: str, key: str, max_age: timedelta | None) -> Any:
    """The value saved under `section` and `key` at most `max_age` ago (None:
    any time this run), or None."""
    dated = get_dated(section, key, max_age)
    return None if dated is None else dated[0]


def get_dated(
    section: str, key: str, max_age: timedelta | None
) -> tuple[Any, datetime] | None:
    """`get`, with when the value was saved."""
    path = _path()
    if path is None:
        return None
    entry = (_read(path) or {}).get(section, {})
    entry = entry.get(key) if isinstance(entry, dict) else None
    if not isinstance(entry, dict):
        return None
    try:
        at = datetime.fromisoformat(entry["at"])
    except (KeyError, TypeError, ValueError):
        return None
    if at.tzinfo is None:
        return None
    age = now() - at
    if age < timedelta(0) or (max_age is not None and age > max_age):
        return None
    return copy.deepcopy(entry.get("value")), at


def put(section: str, key: str, value: Any, at: datetime | None = None) -> None:
    """Save `value`, read at `at` (now by default), replacing the file whole.
    Best effort: a failed write leaves the next process to read GitHub, and a
    file that could not be read is left as it is rather than replaced by this
    entry alone."""
    path = _path()
    if path is None:
        return
    current = _read(path)
    if current is None:
        return
    data = dict(current)
    entries = data.get(section)
    entries = dict(entries) if isinstance(entries, dict) else {}
    entries[key] = {"at": (at or now()).isoformat(), "value": value}
    data[section] = entries
    text = json.dumps(data)
    tmp = path.with_name(f"{path.name}.{os.getpid()}.tmp")
    try:
        tmp.write_text(text, encoding="utf-8")
        stamp = _stamp(tmp.stat())
        os.replace(tmp, path)
    except OSError:
        _memo.pop(str(path), None)
        return
    # The parse keeps what was written apart from the caller's `value`.
    entries[key] = json.loads(json.dumps(entries[key]))
    _memo[str(path)] = (stamp, data)


def credentials() -> str:
    """A digest of everything gh reads its credentials from, so a value read
    with one set of credentials is never reused under another."""
    digest = hashlib.sha256()
    for name in CREDENTIAL_ENV:
        digest.update(f"{name}={os.environ.get(name, '')}\0".encode())
    config = os.environ.get("GH_CONFIG_DIR") or str(
        Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "gh"
    )
    with contextlib.suppress(OSError):
        digest.update(Path(config, "hosts.yml").read_bytes())
    return digest.hexdigest()
