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
import hashlib
import json
import os
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

ENV = "BABYSIT_RUN_CACHE"
# The oldest shared value that can change during a run, and the oldest
# artifact listing the verdict reader judges on (judgment): pr-verify is not a
# required check, so a queued entry whose FAIL lands mid-run must be held
# before the merge queue can land it.
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


def _load(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def get(section: str, key: str, max_age: timedelta | None) -> Any:
    """The value saved under `section` and `key` at most `max_age` ago (None:
    any time this run), or None."""
    path = _path()
    if path is None:
        return None
    entry = _load(path).get(section, {})
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
    return entry.get("value")


def put(section: str, key: str, value: Any) -> None:
    """Save `value`, replacing the file whole. Best effort: a failed write
    leaves the next process to read GitHub."""
    path = _path()
    if path is None:
        return
    data = _load(path)
    entries = data.get(section)
    if not isinstance(entries, dict):
        entries = data[section] = {}
    entries[key] = {"at": now().isoformat(), "value": value}
    tmp = path.with_name(f"{path.name}.{os.getpid()}.tmp")
    with contextlib.suppress(OSError):
        tmp.write_text(json.dumps(data), encoding="utf-8")
        os.replace(tmp, path)


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
