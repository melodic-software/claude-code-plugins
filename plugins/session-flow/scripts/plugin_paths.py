# -*- coding: utf-8 -*-
"""Paths and file writes the session-flow scripts share.

- `data_root(env, plugin_root)` is the plugin data directory: `CLAUDE_PLUGIN_DATA` when its last
  path segment is `session-flow` or starts with `session-flow-` (another plugin's hook can export
  its own directory under that name, and a `--plugin-dir` run gets `session-flow-inline`), else
  derived from an installed plugin root `<config>/plugins/cache/<marketplace>/<plugin>/<version>`
  as `<config>/plugins/data/<plugin@marketplace>` with every character outside `[A-Za-z0-9_-]`
  replaced by `-`, else None. A Bash-tool command never receives `CLAUDE_PLUGIN_DATA`, so the
  derivation is the normal case there (plugins manifest reference, "Environment variables").
- `write_atomic(path, text)` writes through a private temp file beside `path` and `os.replace`,
  retrying while Windows refuses the replace because a reader holds the target open; False when
  that outlasts the retries. The file is created 0600.
- `run_git(directory, *args, timeout=None)` is `git -C <directory> <args>` as a completed process,
  or None when git cannot start or runs past `timeout`.

Stdlib only; Python 3.10+.
"""

from __future__ import annotations

import os
import re
import subprocess
import tempfile
import time
from collections.abc import Mapping
from pathlib import Path

PLUGIN_NAME = "session-flow"
REPLACE_RETRIES = 20
REPLACE_RETRY_SECONDS = 0.05


def data_root(env: Mapping[str, str], plugin_root: str | os.PathLike | None) -> Path | None:
    configured = env.get("CLAUDE_PLUGIN_DATA", "")
    segment = Path(configured.rstrip("/\\")).name if configured else ""
    if segment == PLUGIN_NAME or segment.startswith(f"{PLUGIN_NAME}-"):
        return Path(configured).expanduser()
    if plugin_root is None:
        return None
    version_dir = Path(plugin_root)
    plugin_dir = version_dir.parent
    marketplace_dir = plugin_dir.parent
    cache_dir = marketplace_dir.parent
    if cache_dir.name != "cache" or cache_dir.parent.name != "plugins":
        return None
    plugin_id = re.sub(r"[^A-Za-z0-9_-]", "-", f"{plugin_dir.name}@{marketplace_dir.name}")
    return cache_dir.parent / "data" / plugin_id


def write_atomic(path: Path, text: str) -> bool:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        for _ in range(REPLACE_RETRIES):
            try:
                os.replace(tmp, path)
                return True
            except PermissionError:
                time.sleep(REPLACE_RETRY_SECONDS)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise
    Path(tmp).unlink(missing_ok=True)
    return False


def run_git(directory: str | os.PathLike, *args: str, timeout: float | None = None) -> subprocess.CompletedProcess | None:
    try:
        return subprocess.run(
            ["git", "-C", str(directory), *args], capture_output=True, text=True, check=False, timeout=timeout
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
