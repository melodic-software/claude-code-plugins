#!/usr/bin/env python3
"""Managed (machine-scope) settings path resolution and drop-in loading.

Mirrors ``lib/managed-scope.sh`` platform base paths and alphabetical
``managed-settings.d/*.json`` drop-in enumeration (ignoring hidden files and
non-``.json`` files). Scoped to ``harness-ops`` read-only install-state audits.

Stdlib only; Python 3.11+.
"""

from __future__ import annotations

import dataclasses
import json
import os
import platform
from collections.abc import Mapping
from pathlib import Path

BASE_FILENAME = "managed-settings.json"
DROPIN_DIRNAME = "managed-settings.d"


@dataclasses.dataclass(frozen=True)
class ManagedSettingsEntry:
    path: Path
    data: object | None
    error: str | None


def base_file(
    override: str | os.PathLike | None = None,
    *,
    system: str | None = None,
    env: Mapping[str, str] | None = None,
) -> Path:
    """Absolute path to the platform ``managed-settings.json`` base file."""
    if override:
        return Path(override)
    sys_name = platform.system() if system is None else system
    env_map = os.environ if env is None else env
    if sys_name == "Darwin":
        return Path("/Library/Application Support/ClaudeCode") / BASE_FILENAME
    if sys_name == "Windows":
        program_files = (
            env_map.get("PROGRAMFILES")
            or env_map.get("ProgramFiles")
            or r"C:\Program Files"
        )
        return Path(program_files) / "ClaudeCode" / BASE_FILENAME
    return Path("/etc/claude-code") / BASE_FILENAME


def dropin_dir(
    override: str | os.PathLike | None = None,
    *,
    system: str | None = None,
    env: Mapping[str, str] | None = None,
) -> Path:
    """Absolute path to ``managed-settings.d`` beside the base file."""
    base = base_file(override, system=system, env=env)
    return base.parent / DROPIN_DIRNAME


def enumerate_files(base: Path) -> list[Path]:
    """Return existing managed settings files in load order: base, then alphabetical drop-ins.

    Hidden entries (names starting with ``.``) and entries not ending with ``.json``
    in ``managed-settings.d`` are ignored, matching Claude Code's documented drop-in rules.
    """
    files: list[Path] = []
    if base.is_file():
        files.append(base)
    dropins = base.parent / DROPIN_DIRNAME
    if dropins.is_dir():
        try:
            children = sorted(dropins.iterdir(), key=lambda p: p.name)
        except OSError:
            children = []
        for child in children:
            if (
                not child.name.startswith(".")
                and child.name.endswith(".json")
                and child.is_file()
            ):
                files.append(child)
    return files


def load_managed_settings(base: Path) -> list[ManagedSettingsEntry]:
    """Read and parse the base managed settings file and all ``managed-settings.d/*.json`` drop-ins."""
    entries: list[ManagedSettingsEntry] = []
    for path in enumerate_files(base):
        try:
            data = json.loads(path.read_text(encoding="utf-8", errors="strict"))
            entries.append(ManagedSettingsEntry(path=path, data=data, error=None))
        except (OSError, ValueError) as exc:
            entries.append(
                ManagedSettingsEntry(
                    path=path,
                    data=None,
                    error=f"{type(exc).__name__}: {exc}",
                )
            )
    return entries
