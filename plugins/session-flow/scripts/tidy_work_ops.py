#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Formatting, GitHub link lookup, and filesystem guards for tidy_work.py."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import plugin_paths

SELF_IGNORE = plugin_paths.SELF_IGNORE
FINISHED = ("closed", "merged")
GH_STATES = ("open", *FINISHED, "closed-unmerged")

_GH_STATE_JQ = (
    'if .state == "open" then "open" elif .pull_request.merged_at then "merged" '
    'elif .pull_request then "closed-unmerged" else .state end'
)


def _human_size(size: int) -> str:
    value = float(size)
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if value < 1024 or unit == "TiB":
            return f"{int(value)} {unit}" if unit == "B" else f"{value:.1f} {unit}"
        value /= 1024
    return f"{size} B"


def _age_days(mtime: float, now: float) -> float:
    return round(max(now - mtime, 0) / 86400, 1)


def _to_dict(item: Any, now: float) -> dict[str, object]:
    return {
        "path": item.path.as_posix(),
        "root": item.root,
        "kind": item.kind,
        "age_days": _age_days(item.mtime, now),
        "mtime": datetime.fromtimestamp(item.mtime, timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        ),
        "size_bytes": item.size,
        "in_flight": item.in_flight,
        "reasons": item.reasons,
        "keep": item.keep,
        "links": item.states,
    }


def _attribution(item: Any) -> str:
    if not item.states:
        return ""
    return (
        " [" + ", ".join(f"{ref} {state}" for ref, state in item.states.items()) + "]"
    )


def _verdict(item: Any) -> str:
    if item.kind == "concern":
        verdict = "keep: concern state read back by its skill"
    elif item.kind == "git-clone":
        verdict = (
            f"keep: git clone or worktree ({_human_size(item.size)}); "
            "inspect or remove via git/worktree tooling"
        )
    elif item.kind == "recovery-archive":
        verdict = (
            f"keep: recovery archive ({_human_size(item.size)}); "
            "verify backup before removing manually"
        )
    elif item.kind == "unknown":
        verdict = "keep: unknown kind"
    elif item.reasons:
        verdict = "keep: " + "; ".join(item.reasons)
    elif item.kind == "orphan-marker":
        verdict = "stale: its handoff is gone"
    else:
        verdict = "stale" if item.links else "keep: names no issue or PR"
    return verdict + _attribution(item)


def _table(items: list[Any], now: float) -> str:
    header = ("KIND", "AGE(d)", "SIZE", "VERDICT", "PATH")
    body = [
        (
            i.kind,
            str(_age_days(i.mtime, now)),
            str(i.size),
            _verdict(i),
            i.path.as_posix(),
        )
        for i in items
    ]
    widths = [max(len(row[col]) for row in (header, *body)) for col in range(4)]
    fmt = "  ".join(f"{{:<{w}}}" for w in widths) + "  {}"
    return "\n".join(fmt.format(*row) for row in (header, *body))


def _load_link_table(path: str | None) -> dict[str, str] | None:
    if not path:
        return None
    try:
        table = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise ValueError(f"--link-state unreadable: {exc}") from exc
    if not isinstance(table, dict):
        raise ValueError("--link-state must be a JSON object")
    return table


def _gh_api(path: str, jq: str, cwd: Path | None, *flags: str) -> str | None:
    """Output of `gh api` for a repos/{owner}/{repo}/issues path (`{owner}/{repo}`
    comes from cwd), or None when gh fails."""
    try:
        result = subprocess.run(
            ["gh", "api", path, *flags, "--jq", jq],
            capture_output=True,
            text=True,
            check=False,
            timeout=120,
            cwd=cwd,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    return result.stdout if result.returncode == 0 else None


class LinkStates:
    def __init__(self, table: dict[str, str] | None, offline: bool) -> None:
        self._table = table
        self._offline = offline
        self._open: dict[tuple[str, Path | None], set[str] | None] = {}
        self._one: dict[tuple[str, Path | None, str], str] = {}

    def state(self, ref: str, root: Path) -> str:
        if self._offline:
            return "unknown"
        if self._table is not None:
            return str(self._table.get(ref, "unknown")).lower()
        repo, _, number = ref.rpartition("#")
        top = None if repo else plugin_paths.git_toplevel(root)
        if not repo and top is None:
            return "unknown"
        base = f"repos/{repo or '{owner}/{repo}'}/issues"
        if (repo, top) not in self._open:
            listing = _gh_api(
                f"{base}?state=open&per_page=100", ".[].number", top, "--paginate"
            )
            self._open[repo, top] = None if listing is None else set(listing.split())
        numbers = self._open[repo, top]
        if numbers is None:
            return "unknown"
        if number in numbers:
            return "open"
        if (repo, top, number) not in self._one:
            found = _gh_api(f"{base}/{number}", _GH_STATE_JQ, top)
            state = (found or "").strip()
            self._one[repo, top, number] = state if state in GH_STATES else "unknown"
        return self._one[repo, top, number]


def _escapes(path: Path, root: Path) -> bool:
    """True when path, or a symlink inside it, resolves outside root."""
    try:
        if not path.resolve().is_relative_to(root):
            return True
        if path.is_dir() and not path.is_symlink():
            for base, dirs, files in os.walk(path, followlinks=False):
                for name in (*dirs, *files):
                    entry = Path(base, name)
                    if entry.is_symlink() and not entry.resolve().is_relative_to(root):
                        return True
    except (OSError, RuntimeError):
        return True
    return False


@dataclass
class Guard:
    """Whether a root may be modified: git-tracked content never is."""

    root: Path
    refusal: str | None = None
    tracked: list[str] | None = None

    def blocks(self, path: Path) -> str | None:
        if self.refusal:
            return self.refusal
        if self.tracked is not None:
            rel = path.relative_to(self.root).as_posix()
            if any(t == rel or t.startswith(f"{rel}/") for t in self.tracked):
                return f"git tracks content at {rel}"
        return None


def _guard(label: str, root: Path) -> Guard:
    guard = Guard(root)
    if not root.is_dir():
        return guard
    if label != "home" and not plugin_paths.is_self_ignored(root):
        guard.refusal = (
            f"memory root lacks the self-ignore guard: {(root / SELF_IGNORE).as_posix()} "
            "must contain a line '*'"
        )
    elif plugin_paths.git_toplevel(root) is not None:
        try:
            result = subprocess.run(
                ["git", "-C", str(root), "ls-files", "-z"],
                capture_output=True,
                text=True,
                check=False,
            )
        except OSError:
            result = None
        if result is None or result.returncode != 0:
            guard.refusal = "cannot list the files git tracks"
        else:
            guard.tracked = [name for name in result.stdout.split("\0") if name]
    return guard


def _refusal(dst: Path) -> str | None:
    if dst.parent.is_symlink() or (dst.parent.exists() and not dst.parent.is_dir()):
        return f"{dst.parent.as_posix()} is not a plain directory"
    if os.path.lexists(dst):
        return f"target exists: {dst.as_posix()}"
    return None


def _blocked(item: Any, root: Path, guard: Guard) -> str | None:
    for path in item.paths:
        if _escapes(path, root):
            return "outside the root"
        if reason := guard.blocks(path):
            return reason
    return None


def _remove(path: Path) -> None:
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
    else:
        path.unlink()
