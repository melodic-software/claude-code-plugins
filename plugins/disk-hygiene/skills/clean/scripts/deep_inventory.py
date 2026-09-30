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
import functools
import os
import re
import stat
import sys
import tempfile
from collections.abc import Iterable
from pathlib import Path
from typing import Any

_LIB_DIR = Path(__file__).resolve().parents[3] / "lib"
if str(_LIB_DIR) not in sys.path:
    sys.path.insert(0, str(_LIB_DIR))

from plugin_cache_versions import (  # noqa: E402  (path set above; plugin-bundled module)
    INSTALLED_PLUGINS,
    ORPHAN_SWEEP_DAYS,
    load_registry,
    orphan_marker,
    resolve,
)

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
# Group 1 is the numeric part, group 2 the "-" of a prerelease or the "+" of build metadata.
VERSION_RE = re.compile(r"^v?(\d+(?:\.\d+)*)(?:([-+])[\w.+-]+)?$")
_TOKEN = r"[\w.@/+-]+"
_NAMED_TOOL = re.compile(
    rf"(?:managed|owned) by (?:the )?({_TOKEN}(?: {_TOKEN}){{0,2}})"
)
_CATEGORY_PHRASE = re.compile(
    rf"(?:(?:tool|os|system|app|vendor)[- ]?(?:managed|owned)|{_NAMED_TOOL.pattern})"
)


def _iso(epoch: float) -> str:
    return dt.datetime.fromtimestamp(epoch, dt.timezone.utc).isoformat(
        timespec="seconds"
    )


@functools.lru_cache(maxsize=None)
def _owner(uid: int) -> str:
    if pwd is not None:
        try:
            return pwd.getpwuid(uid).pw_name
        except KeyError:
            pass
    return str(uid)


def _tree_size(path: Path, mounts: frozenset[str] = frozenset()) -> int:
    """Bytes under ``path``, links not followed and mount points in ``mounts`` not entered."""
    total, stack = 0, [path]
    while stack:
        current = stack.pop()
        try:
            with os.scandir(current) as entries:
                for entry in entries:
                    if entry.is_dir(follow_symlinks=False):
                        if entry.path not in mounts:
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


def running_paths(proc_root: Path = Path("/proc")) -> set[str] | None:
    """Resolved executable, working-directory and open-descriptor targets of every process under ``proc_root``.

    A deleted target reads ``<path> (deleted)``; the suffix is dropped so the
    superseded directory it came from still matches. Descriptors that are not
    paths (``socket:[1]``, ``pipe:[1]``) never match an entry. A process another
    user owns is unreadable here and contributes nothing. None means the process
    table could not be read (no ``/proc``, as on macOS and Windows), which is not
    the same as an empty set: nothing was checked.
    """
    found: set[str] = set()
    try:
        pids = [p for p in proc_root.iterdir() if p.name.isdigit()]
    except OSError:
        return None
    for pid in pids:
        links = [pid / "exe", pid / "cwd"]
        try:
            links += [Path(e.path) for e in os.scandir(pid / "fd")]
        except OSError:
            pass
        for link in links:
            try:
                found.add(os.readlink(link).removesuffix(" (deleted)"))
            except OSError:
                pass
    return found


def _in_use(entry: Path, running: Iterable[str]) -> str | None:
    prefix = str(entry)
    return next(
        (r for r in running if r == prefix or r.startswith(prefix + os.sep)), None
    )


def _link_targets(directories: Iterable[Path]) -> dict[str, str]:
    """Resolved target -> link path for every symlink directly inside ``directories``."""
    found: dict[str, str] = {}
    for directory in directories:
        try:
            with os.scandir(directory) as entries:
                for entry in entries:
                    if entry.is_symlink():
                        found.setdefault(os.path.realpath(entry.path), entry.path)
        except OSError:
            pass
    return found


def superseded_versions(
    parents: Iterable[Path],
    running: Iterable[str] | None = (),
    launcher_dirs: Iterable[Path] = (),
) -> list[dict[str, Any]]:
    """Sibling entries under each parent whose names parse as versions.

    Keeps the newest (a release outranks its own prerelease), any version a
    running process executes, and any version a symlink points at, read from the
    parent, its parent and ``launcher_dirs``. The rest are candidates, or UNKNOWN
    when ``running`` is None (process table not read). A version chosen through a
    file rather than a symlink (an nvm alias, ``.tool-versions``) is not seen. A
    parent with fewer than two version entries yields no rows.
    """
    rows: list[dict[str, Any]] = []
    running = None if running is None else set(running)
    launcher_dirs = tuple(launcher_dirs)
    for parent in parents:
        versions: list[tuple[tuple[tuple[int, ...], int], str, Path]] = []
        try:
            with os.scandir(parent) as entries:
                for entry in entries:
                    match = VERSION_RE.match(entry.name)
                    if match and not entry.is_symlink():
                        numbers = tuple(int(n) for n in match.group(1).split("."))
                        key = (numbers, 0 if match.group(2) == "-" else 1)
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
        links = _link_targets((parent, parent.parent, *launcher_dirs))
        for _, name, path in versions:
            used = _in_use(path, running or ())
            target = _in_use(Path(os.path.realpath(path)), links)
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
            elif target:
                disposition, reason, evidence = (
                    "KEEP",
                    f"the symlink {links[target]} points at it",
                    {"symlink": links[target]},
                )
            elif running is None:
                disposition, reason, evidence = (
                    "UNKNOWN",
                    f"superseded by {newest}; the process table was not read, "
                    "so whether a process executes it is not known",
                    None,
                )
            else:
                disposition, reason, evidence = (
                    "CANDIDATE",
                    f"superseded by {newest}; no running process executes it and "
                    "no symlink beside it or in a launcher directory points at it",
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


def _read_guarded(root: Path, relpath: str, limit: int = 2_000_000) -> str:
    """Read a bounded amount of text from a regular file under ``root``.

    A cached plugin controls the paths below the cache, so a link is never
    followed out of ``root``. The registry itself may be a link.
    """
    path = root / relpath
    if relpath != INSTALLED_PLUGINS and (path.is_symlink() or not path.is_file()):
        raise OSError(f"{relpath} is not a regular file")
    with path.open(encoding="utf-8", errors="replace") as fh:
        return fh.read(limit)


def _orphan_reason(registry: str, marker: dict[str, Any] | None, sweeping: bool) -> str:
    base = f"no installPath in {registry} references this version"
    if not sweeping:
        return (
            f"{base}, and {registry} records no install, so Claude Code's "
            "removal of orphaned versions does not run"
        )
    if marker is None:
        return f"{base}, and it has no readable .orphaned_at marker"
    age = marker["marker_age_days"]
    if marker["past_sweep_window"]:
        return (
            f"{base}; its .orphaned_at marker is {age} days old, past the "
            f"{ORPHAN_SWEEP_DAYS}-day window after which Claude Code removes an "
            "orphaned version, so it has not been swept"
        )
    return (
        f"{base}; its .orphaned_at marker is {age} days old, inside the "
        f"{ORPHAN_SWEEP_DAYS}-day window, so Claude Code removes it itself"
    )


def plugin_cache_versions(claude_dir: Path, now: float) -> list[dict[str, Any]]:
    """Rows for ``plugins/cache/<marketplace>/<plugin>/<version>`` under ``claude_dir``.

    A version some ``installPath`` in ``plugins/installed_plugins.json`` names is
    KEEP with that registry as evidence; one no path names is a candidate, whose
    reason and evidence carry its ``.orphaned_at`` marker age and whether that is
    past the sweep window. When the registry cannot vouch for this cache
    (unreadable, no ``plugins`` object, or no path in it under this cache) every
    row is UNKNOWN: a missing registry is not evidence that a version is
    unreferenced.
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
    registry = claude_dir / INSTALLED_PLUGINS

    def read(rel: str) -> str:
        return _read_guarded(claude_dir, rel)

    known = load_registry(read, claude_dir, registry.name)
    doubt = known.doubt
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
        elif resolve(path) in known.referenced:
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
            marker = orphan_marker(read, path.relative_to(claude_dir).as_posix(), now)
            rows.append(
                make_row(
                    path,
                    disposition="CANDIDATE",
                    reason=_orphan_reason(registry.name, marker, known.installs),
                    evidence=marker,
                    **common,
                )
            )
    return rows


def tmp_entries(
    tmp_dir: Path,
    now: float,
    running: Iterable[str] | None = (),
    min_age_days: float = TMP_MIN_AGE_DAYS,
    producers: tuple[tuple[str, str, str | None], ...] = TMP_PRODUCERS,
) -> list[dict[str, Any]]:
    """One row per top-level entry of ``tmp_dir``, attributed by producer name prefix.

    An unattributed entry is UNKNOWN. An attributed one stays when its producer
    rule names a reason, when a running process uses it, or when it changed
    inside ``min_age_days``; otherwise it is a candidate, or UNKNOWN when
    ``running`` is None (process table not read).
    """
    rows: list[dict[str, Any]] = []
    running = None if running is None else set(running)
    try:
        entries = sorted(tmp_dir.iterdir())
    except OSError:
        return rows
    for path in entries:
        match = next((p for p in producers if path.name.startswith(p[0])), None)
        try:
            age = (now - os.lstat(path).st_mtime) / DAY
            used = _in_use(path, running or ())
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
            elif running is None:
                verdict = (
                    "UNKNOWN",
                    f"{producer} leftover unchanged for {age:.0f} days; the process table "
                    "was not read, so whether a process uses it is not known",
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


# Claude Code keeps the first 200 characters of an encoded project directory name
# and appends `-<hash>`, after which the source path cannot be recovered from the
# name. Basis: the path-sanitizing function in the Claude Code 2.1.285 binary
# (non-alphanumerics become `-`, names over 200 characters are cut and hashed),
# verified 2026-09-30; recheck when a Claude Code changelog entry mentions
# project directory naming or a release changes the encoding.
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


def tmp_root() -> Path:
    """The directory the ``tmp-producer`` category covers.

    ``/tmp`` on POSIX, not ``$TMPDIR``, which may name a subdirectory of it and
    would then attribute that subdirectory's children instead of ``/tmp``'s own
    entries. Elsewhere the OS temp directory.
    """
    return Path("/tmp" if os.name == "posix" else tempfile.gettempdir()).resolve()


def category_rows(
    target: Path,
    *,
    home: Path,
    tmp_dir: Path,
    now: float,
    running: set[str] | None,
) -> dict[str, dict[str, Any]]:
    """Rows of each category whose root lies inside ``target``, keyed by name."""
    rows: list[dict[str, Any]] = []
    claude_dir = home / ".claude"
    if _within(claude_dir, target):
        rows += plugin_cache_versions(claude_dir, now)
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
    running: Iterable[str] | None = (),
    skip: frozenset[str] = frozenset(),
    mounts: frozenset[str] = frozenset(),
) -> Iterable[dict[str, Any]]:
    """Yield one row per entry of ``target``, the target itself last.

    ``deep`` lists every level, each directory after its contents with the
    sum of their sizes; otherwise only the immediate children, each directory
    sized by its own walk. A category row replaces the unclassified row at its
    path. A directory that cannot be read, or that is a mount point (another
    device, or a path in ``mounts``, which also catches a bind mount on the
    same device), is one UNKNOWN row and is not entered. Paths in ``skip`` (the
    report being written) are left out. ``running`` is the process table; None
    means it was not read, so rows that rest on it are UNKNOWN.
    """
    running = None if running is None else set(running)
    launcher_dirs = (home / ".local" / "bin", home / "bin")
    overrides = category_rows(
        target, home=home, tmp_dir=tmp_dir, now=now, running=running
    )

    def children(directory: Path) -> list[tuple[Path, os.stat_result | None, str]]:
        with os.scandir(directory) as it:
            entries = sorted(it, key=lambda e: e.name, reverse=True)
        if _dotted_versions(e.name for e in entries):
            for row in superseded_versions([directory], running, launcher_dirs):
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
        if _descends(st) and (
            str(path) in mounts or (st.st_dev and st.st_dev != root_st.st_dev)
        ):
            yield not_entered(path, st, "another filesystem is mounted here")
            continue
        if deep and _descends(st):
            try:
                stack.append((path, st, children(path), [0]))
            except OSError as exc:
                yield not_entered(path, st, f"unreadable ({type(exc).__name__}: {exc})")
            continue
        size = _tree_size(path, mounts) if _descends(st) else st.st_size
        total[0] += size
        yield row(path, st, size)


def _category_only(reason: str) -> bool:
    parts = [
        p for p in re.split(r"\s*(?:[;,.]|\band\b)\s*", reason.strip().lower()) if p
    ]
    return not parts or all(_CATEGORY_PHRASE.fullmatch(p) for p in parts)


def _shows_reference(reason: str, evidence: object) -> bool:
    """True when the reason names a tool ("managed by <tool>") that evidence shows references the entry."""
    if not isinstance(evidence, dict):
        return False
    tool = str(evidence.get("tool") or "").strip().lower()
    return bool(
        tool
        and str(evidence.get("references") or "").strip()
        and any(
            tool in m.group(1).split() for m in _NAMED_TOOL.finditer(reason.lower())
        )
    )


def validate_report(rows: Iterable[dict[str, Any]]) -> list[str]:
    """Failures of a report; an empty list means it passes.

    Every row needs the schema columns except the optional ``evidence`` and a
    valid disposition. A KEEP row fails when its reason is empty, which names no
    tool, so no evidence can stand in for it. It also fails when its reason is
    only a category phrase ("tool-managed", "OS-owned", "managed by <tool>"),
    unless the phrase names a tool ("managed by <tool>") and the row's evidence
    shows that tool still references the entry.
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
        if not reason.strip():
            failures.append(f"{label}: KEEP reason is empty")
        elif _category_only(reason) and not _shows_reference(
            reason, row.get("evidence")
        ):
            failures.append(
                f"{label}: KEEP reason {reason!r} is only a category phrase "
                "and no evidence shows the named tool still references the entry"
            )
    return failures
