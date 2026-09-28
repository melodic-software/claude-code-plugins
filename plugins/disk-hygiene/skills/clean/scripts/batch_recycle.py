"""Manual-lane batch recycle.

The hook asks on this subcommand. After that approval, this process re-checks
each path's existence and type and only then recycles. It never permanently
deletes: a path the bin cannot take is skipped.
"""

from __future__ import annotations

import os
import stat
import subprocess
from pathlib import Path, PurePosixPath
from typing import Any, Callable

MAX_PATHS = 32
MAX_DESCENDANTS = 64

# Bundled next to this module. It sends one literal path to the Recycle Bin.
_RECYCLE_SCRIPT = Path(__file__).with_name("recycle-one.ps1")


def permanent_delete_used() -> bool:
    """The batch lane has no permanent-delete fallback."""
    return False


def descendant_count(path: str, entries: dict[str, dict[str, Any]]) -> int:
    prefix = f"{path}/"
    return sum(1 for name in entries if name.startswith(prefix))


def live_kind(path: Path) -> str | None:
    """Kind observed now, or None when the path is gone."""
    try:
        info = path.lstat()
    except FileNotFoundError:
        return None
    except OSError:
        return "unverified"
    mode = info.st_mode
    if stat.S_ISLNK(mode):
        return "link"
    if stat.S_ISDIR(mode):
        return "directory"
    if stat.S_ISREG(mode):
        return "file"
    return "other"


def recycle_or_refuse(path: Path) -> str:
    """Recycle ``path`` or refuse. Never falls through to a permanent delete."""
    if permanent_delete_used():
        raise RuntimeError("batch recycle must not permanently delete")
    if os.name != "nt":
        return "recycle-unsupported"
    if not _RECYCLE_SCRIPT.is_file():
        return "recycle-script-missing"
    completed = subprocess.run(
        [
            "powershell.exe",
            "-NoProfile",
            "-NonInteractive",
            "-File",
            str(_RECYCLE_SCRIPT),
            "-LiteralPath",
            str(path),
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode == 0:
        return "recycled"
    return "recycle-refused"


def batch_recycle(
    snapshot: dict[str, Any],
    paths: list[str],
    tier: str,
    *,
    handoff_verify: Callable[..., dict[str, Any]],
    validate_paths: Callable[[dict[str, Any]], list[str]],
    schema_version: int,
) -> dict[str, Any]:
    """Re-verify, re-stat, then recycle. One process, one tier."""
    approved = validate_paths({"version": schema_version, "paths": paths})
    entries = {
        entry["path"]: entry
        for entry in snapshot.get("entries") or []
        if isinstance(entry, dict) and isinstance(entry.get("path"), str)
    }
    verified = handoff_verify(snapshot, approved, None)
    by_verdict = {item["path"]: item for item in verified["verdicts"]}
    target = Path(snapshot["target"])
    results: list[dict[str, Any]] = []
    recycled = 0
    skipped = 0
    for relative in approved:
        verdict = by_verdict.get(relative, {"verdict": "contested", "reasons": []})
        entry = entries[relative]
        if descendant_count(relative, entries) > MAX_DESCENDANTS:
            skipped += 1
            results.append(
                {
                    "path": relative,
                    "action": "skipped",
                    "reason": "descendant-cap",
                }
            )
            continue
        if verdict["verdict"] != "clear":
            skipped += 1
            results.append(
                {
                    "path": relative,
                    "action": "skipped",
                    "reason": verdict["verdict"],
                    "reasons": verdict.get("reasons") or [],
                }
            )
            continue
        # The approval already happened (this process is running). Re-stat
        # immediately before the recycle, in this same process.
        current = target.joinpath(*PurePosixPath(relative).parts)
        kind = live_kind(current)
        expected = entry.get("kind")
        if kind is None:
            skipped += 1
            results.append(
                {"path": relative, "action": "skipped", "reason": "gone"}
            )
            continue
        if kind != expected:
            skipped += 1
            results.append(
                {
                    "path": relative,
                    "action": "skipped",
                    "reason": "type-changed",
                    "expected": expected,
                    "observed": kind,
                }
            )
            continue
        outcome = recycle_or_refuse(current)
        if outcome == "recycled":
            recycled += 1
            results.append({"path": relative, "action": "recycled"})
        else:
            skipped += 1
            results.append(
                {"path": relative, "action": "skipped", "reason": outcome}
            )
    return {
        "status": "batch-recycle-complete",
        "tier": tier,
        "count": len(approved),
        "paths": approved,
        "recycled": recycled,
        "skipped": skipped,
        "results": results,
        "permanent_delete": False,
    }
