from __future__ import annotations

import json
import os
import sys
from pathlib import Path


def _setting(path: Path, *keys: str) -> object:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    for key in keys:
        if not isinstance(value, dict):
            return None
        value = value.get(key)
    return value


def managed_base() -> Path:
    """The managed-settings.json this platform reads, as lib/managed-scope.sh locates it."""
    if sys.platform == "darwin":
        return Path("/Library/Application Support/ClaudeCode/managed-settings.json")
    if sys.platform == "win32":
        return Path(os.environ.get("PROGRAMFILES") or "C:\\Program Files") / "ClaudeCode" / "managed-settings.json"
    return Path("/etc/claude-code/managed-settings.json")


def managed_files(base: Path) -> list[Path]:
    """The base file, then its managed-settings.d drop-ins in name order, hidden and non-JSON skipped."""
    try:
        dropins = sorted(
            p for p in (base.parent / "managed-settings.d").iterdir() if p.suffix == ".json" and not p.name.startswith(".")
        )
    except OSError:
        dropins = []
    return [base, *dropins]


def _managed_setting(files: list[Path], *keys: str) -> tuple[Path | None, object]:
    """The last managed file that sets the key, and its value: a later drop-in replaces a single value."""
    found: tuple[Path | None, object] = (None, None)
    for path in files:
        value = _setting(path, *keys)
        if value is not None:
            found = (path, value)
    return found


def launch_warnings(config_dir: Path, project: Path, managed: Path | None = None) -> list[str]:
    """One line per launch warning; `managed` replaces this platform's managed-settings.json."""
    user = config_dir / "settings.json"
    local, shared = project / ".claude" / "settings.local.json", project / ".claude" / "settings.json"
    managed_set = managed_files(managed or managed_base())
    warnings = []
    # A project or local file that sets the key turns the feature off when managed and user leave it
    # unset: https://code.claude.com/docs/en/settings-reference#autocontinueatusagelimit
    path, value = _managed_setting(managed_set, "autoContinueAtUsageLimit")
    if value is None:
        path, value = user, _setting(user, "autoContinueAtUsageLimit")
    if value is not None:
        off = path if value is False else None
    else:
        off = next((p for p in (local, shared) if _setting(p, "autoContinueAtUsageLimit") is not None), None)
    if off is not None:
        warnings.append(
            f"autoContinueAtUsageLimit is off ({off}): a usage limit ends the run instead of waiting for the reset."
        )
    path, value = _managed_setting(managed_set, "sandbox", "enabled")
    for candidate in (local, shared, user):
        if value is not None:
            break
        path, value = candidate, _setting(candidate, "sandbox", "enabled")
    if value is True:
        warnings.append(
            f"sandboxing is on ({path}): a sandboxed command's network prompt cannot be refused by a "
            "hook and will wait for the person."
        )
    warnings.append("keep the machine awake: after a long sleep the usage-limit resume waits for Enter.")
    return warnings
