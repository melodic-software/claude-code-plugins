"""Which plugin cache version directories does no installPath reference?

Claude Code records every installed plugin in ``plugins/installed_plugins.json``
and keeps each version under ``plugins/cache/<marketplace>/<plugin>/<version>``.
A version no ``installPath`` names is orphaned: Claude Code stamps it with a
``.orphaned_at`` marker (epoch milliseconds) and removes it after a window.

This module reads the registry and the markers and answers that question. It is
pure and read-only: every read goes through a caller-supplied ``read`` function
taking a path relative to the Claude directory, so each caller keeps its own
read guard. Its callers shape the answer into their own rows.

Python 3.11+, standard library only. This file is carried byte-identical by
every plugin that uses it (scripts/cross-plugin-source-registry.txt).
"""

from __future__ import annotations

import datetime as dt
import json
from collections.abc import Callable
from pathlib import Path
from typing import Any, NamedTuple

INSTALLED_PLUGINS = "plugins/installed_plugins.json"

# Days after an update or uninstall that Claude Code removes an orphaned plugin
# version, counted from its `.orphaned_at` marker. Basis:
# https://code.claude.com/docs/en/plugins/loading.md ("Cleanup of previous versions"),
# verified 2026-09-30; recheck when that section or a Claude Code changelog entry
# changes the window.
ORPHAN_SWEEP_DAYS = 14

_DAY = 86400.0

Reader = Callable[[str], str]


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


def install_paths(data: object) -> list[str]:
    """Every `installPath` in the parsed registry, whatever scope or project entry holds it."""
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


def load_registry(read: Reader, root: Path, label: str = INSTALLED_PLUGINS) -> Registry:
    """Read the registry under ``root`` and resolve the paths it references.

    ``label`` names the registry in ``doubt``.
    """
    cache = root / "plugins" / "cache"
    try:
        data: Any = json.loads(read(INSTALLED_PLUGINS))
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


def orphan_marker(read: Reader, version_rel: str, now: float) -> dict[str, Any] | None:
    """The age of a version's ``.orphaned_at`` marker, or None when it is missing or unparsable."""
    try:
        epoch = int(read(f"{version_rel}/.orphaned_at").strip()) / 1000
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
# CI probe: an unmapped .py must run the Python corpus. Never merged.
