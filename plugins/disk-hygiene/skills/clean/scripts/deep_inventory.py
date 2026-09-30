#!/usr/bin/env python3
"""Deep-inventory categories and KEEP-reason validator for ``/disk-hygiene:clean``.

Read-only. Every function takes its paths, clock and process table as arguments
and only reads; nothing here deletes, moves or writes. A candidate row is a
finding, not a deletion plan: removal stays behind the engine's own gates.

Row schema (one dict per inventoried entry, shared by every producer of a
machine listing):

    name         absolute path of the entry
    ext          file suffix, "" for a directory
    size         bytes; a directory is the sum of the files beneath it, links not followed
    mtime        modification time, ISO-8601 UTC
    owner        owning user name, or the numeric uid when it has no name
    producer     the tool that made the entry ("unknown" when no rule attributes it)
    category     the named category that produced the row
    disposition  KEEP | CANDIDATE | UNKNOWN
    reason       who produced it, what uses it, why it stays or may go
    evidence     optional dict of proof. {"tool": ..., "references": ...} shows the named
                 tool still references the entry, which is what lets a KEEP rest on a
                 category phrase such as "managed by <tool>"

``validate_report`` fails a report whose KEEP row has an empty reason, or one
that is only a category phrase without such evidence.
"""

from __future__ import annotations

import datetime as dt
import json
import os
import re
import stat
from collections.abc import Iterable
from pathlib import Path
from typing import Any

try:
    import pwd
except ImportError:  # Windows
    pwd = None

ROW_COLUMNS = (
    "name",
    "ext",
    "size",
    "mtime",
    "owner",
    "producer",
    "category",
    "disposition",
    "reason",
    "evidence",
)
DISPOSITIONS = ("KEEP", "CANDIDATE", "UNKNOWN")
DAY = 86400.0
# A directory's mtime moves only when its direct children change, so an entry
# untouched for this long may still be in use; the running-process check and
# the reader's judgment cover that gap.
TMP_MIN_AGE_DAYS = 7.0
# (name prefix, producer, reason the entry must stay or None when age decides).
TMP_PRODUCERS = (
    ("pytest-of-", "pytest", None),
    ("claude-", "claude-code", None),
    ("npm-", "npm", None),
    ("uv-", "uv", None),
    ("playwright", "playwright", None),
    ("codex-", "codex", None),
    ("cursor-", "cursor-agent", None),
    (
        "systemd-private-",
        "systemd",
        "private /tmp of a service unit; removing it breaks the running unit until it restarts",
    ),
    (
        ".X11-unix",
        "xorg",
        "socket directory of the running X server; clients cannot connect without it",
    ),
    ("ssh-", "ssh-agent", "socket directory of a running ssh-agent"),
)
# Substring of a dangling link's path -> producer.
LINK_PRODUCERS = (
    ("/mise/", "mise"),
    ("/.claude/", "claude-code"),
    ("/.npm/", "npm"),
    ("/uv/", "uv"),
)
VERSION_RE = re.compile(r"^v?(\d+(?:\.\d+)*)(?:[-+][\w.+-]+)?$")
_TOKEN = r"[\w.@/+-]+"
_CATEGORY_PHRASE = re.compile(
    rf"(?:(?:tool|os|system|app|vendor)[- ]?(?:managed|owned)"
    rf"|(?:managed|owned) by (?:the )?{_TOKEN}(?: {_TOKEN}){{0,2}})"
)
_MANAGED_BY = re.compile(r"managed by ")


def _iso(epoch: float) -> str:
    return dt.datetime.fromtimestamp(epoch, dt.timezone.utc).isoformat(
        timespec="seconds"
    )


def _owner(uid: int) -> str:
    if pwd is not None:
        try:
            return pwd.getpwuid(uid).pw_name
        except KeyError:
            pass
    return str(uid)


def _tree_size(path: Path) -> int:
    total, stack = 0, [path]
    while stack:
        current = stack.pop()
        try:
            with os.scandir(current) as entries:
                for entry in entries:
                    if entry.is_dir(follow_symlinks=False):
                        stack.append(Path(entry.path))
                    else:
                        try:
                            total += entry.stat(follow_symlinks=False).st_size
                        except OSError:
                            pass
        except OSError:
            pass
    return total


def make_row(
    path: Path,
    *,
    producer: str,
    category: str,
    disposition: str,
    reason: str,
    evidence: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """One schema row for ``path``, measured with lstat so a link is never followed."""
    st = os.lstat(path)
    return _stat_row(
        path,
        st,
        _tree_size(path) if stat.S_ISDIR(st.st_mode) else st.st_size,
        producer=producer,
        category=category,
        disposition=disposition,
        reason=reason,
        evidence=evidence,
    )


def _stat_row(
    path: Path,
    st: os.stat_result,
    size: int,
    *,
    producer: str,
    category: str,
    disposition: str,
    reason: str,
    evidence: dict[str, Any] | None = None,
) -> dict[str, Any]:
    row: dict[str, Any] = {
        "name": str(path),
        "ext": "" if stat.S_ISDIR(st.st_mode) else path.suffix,
        "size": size,
        "mtime": _iso(st.st_mtime),
        "owner": _owner(st.st_uid),
        "producer": producer,
        "category": category,
        "disposition": disposition,
        "reason": reason,
    }
    if evidence is not None:
        row["evidence"] = evidence
    return row


def _child_dirs(parent: Path) -> list[Path]:
    try:
        with os.scandir(parent) as entries:
            return sorted(
                Path(e.path) for e in entries if e.is_dir(follow_symlinks=False)
            )
    except OSError:
        return []


def running_paths(proc_root: Path = Path("/proc")) -> set[str]:
    """Resolved executable and working-directory targets of every process under ``proc_root``.

    A deleted executable reads ``<path> (deleted)``; the suffix is dropped so the
    superseded directory it came from still matches.
    """
    found: set[str] = set()
    try:
        pids = [p for p in proc_root.iterdir() if p.name.isdigit()]
    except OSError:
        return found
    for pid in pids:
        for link in ("exe", "cwd"):
            try:
                found.add(os.readlink(pid / link).removesuffix(" (deleted)"))
            except OSError:
                pass
    return found


def _in_use(entry: Path, running: Iterable[str]) -> str | None:
    prefix = str(entry)
    return next(
        (r for r in running if r == prefix or r.startswith(prefix + os.sep)), None
    )


def superseded_versions(
    parents: Iterable[Path], running: Iterable[str] = ()
) -> list[dict[str, Any]]:
    """Sibling entries under each parent whose names parse as versions.

    Keeps the newest and any version a running process executes; the rest are
    candidates. A parent with fewer than two version entries yields no rows.
    """
    rows: list[dict[str, Any]] = []
    running = set(running)
    for parent in parents:
        versions: list[tuple[tuple[int, ...], str, Path]] = []
        try:
            with os.scandir(parent) as entries:
                for entry in entries:
                    match = VERSION_RE.match(entry.name)
                    if match and not entry.is_symlink():
                        key = tuple(int(n) for n in match.group(1).split("."))
                        versions.append((key, entry.name, Path(entry.path)))
        except OSError:
            continue
        if len(versions) < 2:
            continue
        versions.sort()
        newest = versions[-1][1]
        holder = (
            parent.parent.name
            if parent.name in {"versions", "releases", "bin"}
            else parent.name
        )
        for _, name, path in versions:
            used = _in_use(path, running)
            if name == newest:
                disposition, reason, evidence = (
                    "KEEP",
                    f"newest of {len(versions)} versions beside it in {parent}",
                    None,
                )
            elif used:
                disposition, reason, evidence = (
                    "KEEP",
                    f"a running process executes {used}",
                    {"running": used},
                )
            else:
                disposition, reason, evidence = (
                    "CANDIDATE",
                    f"superseded by {newest}; no running process executes it",
                    None,
                )
            rows.append(
                make_row(
                    path,
                    producer=holder,
                    category="superseded-version",
                    disposition=disposition,
                    reason=reason,
                    evidence=evidence,
                )
            )
    return rows


def _install_paths(data: object) -> list[str]:
    if isinstance(data, dict):
        own = data.get("installPath")
        found = [own] if isinstance(own, str) else []
        return found + [p for v in data.values() for p in _install_paths(v)]
    if isinstance(data, list):
        return [p for v in data for p in _install_paths(v)]
    return []


def _resolve(path: str | Path) -> Path | None:
    try:
        return Path(path).expanduser().resolve()
    except (OSError, RuntimeError):
        return None


def plugin_cache_versions(claude_dir: Path) -> list[dict[str, Any]]:
    """Rows for ``plugins/cache/<marketplace>/<plugin>/<version>`` under ``claude_dir``.

    A version some ``installPath`` in ``plugins/installed_plugins.json`` names is
    KEEP with that registry as evidence; one no path names is a candidate. When
    the registry cannot vouch for this cache (unreadable, no ``plugins`` object,
    or no path in it under this cache) every row is UNKNOWN: a missing registry
    is not evidence that a version is unreferenced.
    """
    cache = claude_dir / "plugins" / "cache"
    paths = [
        version
        for marketplace in _child_dirs(cache)
        for plugin in _child_dirs(marketplace)
        for version in _child_dirs(plugin)
    ]
    if not paths:
        return []
    registry = claude_dir / "plugins" / "installed_plugins.json"
    referenced: set[Path] = set()
    doubt = ""
    try:
        data = json.loads(registry.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        data, doubt = None, f"{registry.name} unreadable ({type(exc).__name__})"
    if not doubt and not (
        isinstance(data, dict) and isinstance(data.get("plugins"), dict)
    ):
        doubt = f"{registry.name} has no `plugins` object"
    if not doubt:
        referenced = {p for p in map(_resolve, _install_paths(data)) if p is not None}
        cache_resolved = _resolve(cache)
        if data["plugins"] and not any(cache_resolved in p.parents for p in referenced):
            doubt = f"no installPath in {registry.name} lies under {cache}"
    rows = []
    for path in paths:
        producer = path.parent.name
        common = {"producer": producer, "category": "plugin-cache-version"}
        if doubt:
            rows.append(
                make_row(
                    path,
                    disposition="UNKNOWN",
                    reason=f"{doubt}; the registry cannot show whether this version is installed",
                    **common,
                )
            )
        elif _resolve(path) in referenced:
            rows.append(
                make_row(
                    path,
                    disposition="KEEP",
                    reason=f"an installPath in {registry.name} points at this installed version",
                    evidence={"tool": "claude-code", "references": str(registry)},
                    **common,
                )
            )
        else:
            rows.append(
                make_row(
                    path,
                    disposition="CANDIDATE",
                    reason=f"no installPath in {registry.name} references this version",
                    **common,
                )
            )
    return rows


def tmp_entries(
    tmp_dir: Path,
    now: float,
    running: Iterable[str] = (),
    min_age_days: float = TMP_MIN_AGE_DAYS,
    producers: tuple[tuple[str, str, str | None], ...] = TMP_PRODUCERS,
) -> list[dict[str, Any]]:
    """One row per top-level entry of ``tmp_dir``, attributed by producer name prefix.

    An unattributed entry is UNKNOWN. An attributed one stays when its producer
    rule names a reason, when a running process uses it, or when it changed
    inside ``min_age_days``; otherwise it is a candidate.
    """
    rows: list[dict[str, Any]] = []
    running = set(running)
    try:
        entries = sorted(tmp_dir.iterdir())
    except OSError:
        return rows
    for path in entries:
        match = next((p for p in producers if path.name.startswith(p[0])), None)
        try:
            age = (now - os.lstat(path).st_mtime) / DAY
            used = _in_use(path, running)
        except OSError:
            continue
        common = {"category": "tmp-producer"}
        if match is None:
            row = make_row(
                path,
                producer="unknown",
                disposition="UNKNOWN",
                reason="no producer prefix rule matches this name",
                **common,
            )
        else:
            _, producer, keep_reason = match
            if keep_reason:
                verdict = ("KEEP", keep_reason)
            elif used:
                verdict = ("KEEP", f"a running process uses {used}")
            elif age < min_age_days:
                verdict = (
                    "KEEP",
                    f"changed {age:.1f} days ago, inside the {min_age_days:g}-day window "
                    f"in which a live {producer} run may still use it",
                )
            else:
                verdict = (
                    "CANDIDATE",
                    f"{producer} leftover unchanged for {age:.0f} days; no running process uses it",
                )
            row = make_row(
                path,
                producer=producer,
                disposition=verdict[0],
                reason=verdict[1],
                **common,
            )
        rows.append(row)
    return rows


def _encode_project(path: str) -> str:
    return re.sub(r"[^A-Za-z0-9]", "-", path)


def decode_project(encoded: str, fs_root: Path = Path("/")) -> str | None:
    """The existing path under ``fs_root`` whose encoding is ``encoded``, or None.

    The encoding replaces every non-alphanumeric character with ``-``, so a name
    has no unique decoding; the directory tree settles which reading exists.
    """

    def walk(base: Path, rest: str) -> Path | None:
        try:
            names = os.listdir(base)
        except OSError:
            return None
        for name in names:
            code = _encode_project(name)
            if rest == code:
                return base / name
            if rest.startswith(code + "-") and (base / name).is_dir():
                found = walk(base / name, rest[len(code) + 1 :])
                if found:
                    return found
        return None

    found = walk(fs_root, encoded[1:])
    return None if found is None else "/" + found.relative_to(fs_root).as_posix()


# Claude Code caps an encoded directory name near this length and appends a hash,
# after which the source path cannot be recovered from the name.
PROJECT_NAME_CAP = 200


def project_transcripts(
    projects_dir: Path, fs_root: Path = Path("/")
) -> list[dict[str, Any]]:
    """Rows for ``~/.claude/projects/<encoded>``; a source path that is gone makes a candidate."""
    rows = []
    for path in _child_dirs(projects_dir):
        name = path.name
        common = {"producer": "claude-code", "category": "transcript-dir"}
        if not name.startswith("-") or len(name) > PROJECT_NAME_CAP:
            rows.append(
                make_row(
                    path,
                    disposition="UNKNOWN",
                    reason="the name is not a decodable POSIX path encoding",
                    **common,
                )
            )
            continue
        source = decode_project(name, fs_root)
        if source is None:
            rows.append(
                make_row(
                    path,
                    disposition="CANDIDATE",
                    reason="transcripts of a project whose source path no longer exists",
                    **common,
                )
            )
        else:
            rows.append(
                make_row(
                    path,
                    disposition="KEEP",
                    reason=f"transcripts of {source}, which still exists",
                    evidence={"tool": "claude-code", "references": source},
                    **common,
                )
            )
    return rows


def dangling_symlinks(
    roots: Iterable[Path], max_depth: int = 8
) -> list[dict[str, Any]]:
    """Symlinks under ``roots`` (to ``max_depth`` levels) whose target does not exist."""
    rows: list[dict[str, Any]] = []
    for root in roots:
        base_depth = len(root.parts)
        for current, dirs, files in os.walk(root, followlinks=False):
            if len(Path(current).parts) - base_depth >= max_depth:
                dirs[:] = []
            for name in dirs + files:
                path = Path(current) / name
                if path.is_symlink() and not path.exists():
                    rows.append(dangling_row(path))
    return rows


def dangling_row(path: Path) -> dict[str, Any]:
    """The candidate row for one symlink whose target does not exist."""
    producer = next(
        (p for hint, p in LINK_PRODUCERS if hint in path.as_posix()), "unknown"
    )
    return make_row(
        path,
        producer=producer,
        category="dangling-symlink",
        disposition="CANDIDATE",
        reason=f"points to {os.readlink(path)}, which does not exist",
    )


FILE_ATTRIBUTE_REPARSE_POINT = 0x0400
UNCLASSIFIED = {
    "producer": "unknown",
    "category": "unclassified",
    "disposition": "UNKNOWN",
    "reason": "no category rule attributes this entry",
}


def _descends(st: os.stat_result) -> bool:
    """A real directory: not a symlink, junction or other reparse point."""
    return stat.S_ISDIR(st.st_mode) and not (
        getattr(st, "st_file_attributes", 0) & FILE_ATTRIBUTE_REPARSE_POINT
    )


def _within(path: Path, root: Path) -> bool:
    return path == root or root in path.parents


def _dotted_versions(names: Iterable[str]) -> bool:
    """Two or more dotted version names, so a year-named folder pair never qualifies."""
    dotted = (VERSION_RE.match(name) for name in names)
    return sum(1 for m in dotted if m and "." in m.group(1)) >= 2


def category_rows(
    target: Path, *, home: Path, tmp_dir: Path, now: float, running: set[str]
) -> dict[str, dict[str, Any]]:
    """Rows of each category whose root lies inside ``target``, keyed by name."""
    rows: list[dict[str, Any]] = []
    claude_dir = home / ".claude"
    if _within(claude_dir, target):
        rows += plugin_cache_versions(claude_dir)
        rows += project_transcripts(claude_dir / "projects")
    if _within(tmp_dir, target):
        rows += tmp_entries(tmp_dir, now, running)
    return {row["name"]: row for row in rows}


def inventory_rows(
    target: Path,
    *,
    deep: bool,
    home: Path,
    tmp_dir: Path,
    now: float,
    running: Iterable[str] = (),
    skip: frozenset[str] = frozenset(),
) -> Iterable[dict[str, Any]]:
    """Yield one row per entry of ``target``, the target itself last.

    ``deep`` lists every level, each directory after its contents with the
    sum of their sizes; otherwise only the immediate children, each directory
    sized by its own walk. A category row replaces the unclassified row at its
    path. A directory that cannot be read, or that is another filesystem's
    mount point, is one UNKNOWN row and is not entered. Paths in ``skip`` (the
    report being written) are left out.
    """
    running = set(running)
    overrides = category_rows(
        target, home=home, tmp_dir=tmp_dir, now=now, running=running
    )

    def children(directory: Path) -> list[tuple[Path, os.stat_result | None, str]]:
        with os.scandir(directory) as it:
            entries = sorted(it, key=lambda e: e.name, reverse=True)
        if _dotted_versions(e.name for e in entries):
            for row in superseded_versions([directory], running):
                overrides.setdefault(row["name"], row)
        found: list[tuple[Path, os.stat_result | None, str]] = []
        for entry in entries:
            if entry.path in skip:
                continue
            try:
                found.append((Path(entry.path), entry.stat(follow_symlinks=False), ""))
            except OSError as exc:
                found.append((Path(entry.path), None, f"{type(exc).__name__}: {exc}"))
        return found

    def row(path: Path, st: os.stat_result, size: int) -> dict[str, Any]:
        found = overrides.get(str(path))
        if found is not None:
            return found
        if stat.S_ISLNK(st.st_mode) and not path.exists():
            return dangling_row(path)
        return _stat_row(path, st, size, **UNCLASSIFIED)

    def not_entered(path: Path, st: os.stat_result, why: str) -> dict[str, Any]:
        return _stat_row(
            path,
            st,
            0,
            producer="unknown",
            category="not-walked",
            disposition="UNKNOWN",
            reason=f"{why}; its contents and size are not counted",
        )

    root_st = os.lstat(target)
    try:
        stack = [(target, root_st, children(target), [0])]
    except OSError as exc:
        yield not_entered(target, root_st, f"unreadable ({type(exc).__name__}: {exc})")
        return
    while stack:
        directory, dir_st, pending, total = stack[-1]
        if not pending:
            stack.pop()
            if stack:
                stack[-1][3][0] += total[0]
            yield row(directory, dir_st, total[0])
            continue
        path, st, error = pending.pop()
        if st is None:
            yield {
                "name": str(path),
                "ext": path.suffix,
                "size": 0,
                "mtime": None,
                "owner": None,
                **UNCLASSIFIED,
                "category": "not-walked",
                "reason": f"cannot be read ({error})",
            }
            continue
        # Windows DirEntry stats carry st_dev 0, so only a real device id compares.
        if _descends(st) and st.st_dev and st.st_dev != root_st.st_dev:
            yield not_entered(path, st, "another filesystem is mounted here")
            continue
        if deep and _descends(st):
            try:
                stack.append((path, st, children(path), [0]))
            except OSError as exc:
                yield not_entered(path, st, f"unreadable ({type(exc).__name__}: {exc})")
            continue
        size = _tree_size(path) if _descends(st) else st.st_size
        total[0] += size
        yield row(path, st, size)


def _category_only(reason: str) -> bool:
    parts = [
        p for p in re.split(r"\s*(?:[;,.]|\band\b)\s*", reason.strip().lower()) if p
    ]
    return not parts or all(_CATEGORY_PHRASE.fullmatch(p) for p in parts)


def _shows_reference(reason: str, evidence: object) -> bool:
    if not (
        isinstance(evidence, dict)
        and str(evidence.get("tool") or "").strip()
        and str(evidence.get("references") or "").strip()
    ):
        return False
    return not _MANAGED_BY.search(reason.lower()) or (
        str(evidence["tool"]).strip().lower() in reason.lower()
    )


def validate_report(rows: Iterable[dict[str, Any]]) -> list[str]:
    """Failures of a report; an empty list means it passes.

    Every row needs the schema columns except the optional ``evidence`` and a
    valid disposition. A KEEP row fails when its reason is empty or only a
    category phrase ("tool-managed", "OS-owned", "managed by <tool>") unless its
    evidence shows the named tool still references the entry.
    """
    failures = []
    for index, row in enumerate(rows):
        label = str(row.get("name") or f"row {index}")
        missing = [c for c in ROW_COLUMNS if c != "evidence" and c not in row]
        if missing:
            failures.append(f"{label}: missing columns {', '.join(missing)}")
            continue
        if row["disposition"] not in DISPOSITIONS:
            failures.append(
                f"{label}: disposition {row['disposition']!r} is not one of {DISPOSITIONS}"
            )
            continue
        if row["disposition"] != "KEEP":
            continue
        reason = str(row["reason"] or "")
        if _category_only(reason) and not _shows_reference(reason, row.get("evidence")):
            failures.append(
                f"{label}: KEEP reason {reason!r} is "
                f"{'empty' if not reason.strip() else 'only a category phrase'} "
                "and no evidence shows the named tool still references the entry"
            )
    return failures
