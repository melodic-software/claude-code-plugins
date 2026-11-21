"""The files-written scan behind the away report's Files written block.

`scan_files` walks the watched folders for files modified during the absence, skipping dot
entries, the run's own roots and every git repository or worktree, within the time budget the caller passes.
Stdlib only; Python 3.10+.
"""

from __future__ import annotations

import contextlib
import os
import time
from typing import NamedTuple


class FileScan(NamedTuple):
    files: list[str]
    complete: bool


def _pruned(dirpath: str, name: str, prune: set[str]) -> bool:
    path = os.path.join(dirpath, name)
    return name.startswith(".") or path in prune or os.path.lexists(os.path.join(path, ".git"))


def scan_files(watched: list[str], since: float, prune: set[str], budget: float) -> FileScan:
    """Files modified since `since` under the watched folders, skipping dot entries, the run's roots
    and every git repository or worktree; stops once `budget` seconds have passed."""
    deadline = time.monotonic() + budget
    found = []
    for folder in watched:
        top = os.path.realpath(folder)
        if not os.path.isdir(top):
            continue
        for dirpath, dirnames, filenames in os.walk(top):
            if time.monotonic() > deadline:
                return FileScan(found, False)
            dirnames[:] = sorted(d for d in dirnames if not _pruned(dirpath, d, prune))
            for name in sorted(filenames):
                if name.startswith("."):
                    continue
                path = os.path.join(dirpath, name)
                with contextlib.suppress(OSError):
                    if os.lstat(path).st_mtime >= since and os.path.isfile(path):
                        found.append(path)
    return FileScan(found, True)
