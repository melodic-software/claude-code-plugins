#!/usr/bin/env python3
"""Deep-inventory categories, adapters, KEEP-reason validator, and standalone CLI.

Read-only. Every function takes its paths, clock, and liveness/classifier ports
as arguments and only reads; nothing here deletes, moves, or modifies target
files. A candidate row is a finding, not a deletion plan: removal stays behind
the engine's own gates.

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

import argparse
import datetime as dt
import functools
import json
import os
import re
import stat
import sys
import tempfile
from collections.abc import Iterable, Sequence
from pathlib import Path
from typing import Any

_SCRIPTS_DIR = Path(__file__).resolve().parent
if str(_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS_DIR))

_LIB_DIR = Path(__file__).resolve().parents[3] / "lib"
if str(_LIB_DIR) not in sys.path:
    sys.path.insert(0, str(_LIB_DIR))

from claude_projects import (  # noqa: E402, F401  (re-exported for callers/tests)
    PROJECT_NAME_CAP,
    ProjectSlugResolver,
    TranscriptReaderCwdAdapter,
)
from inventory_classifiers import (  # noqa: E402, F401  (sibling classifier module)
    DAY,
    TMP_MIN_AGE_DAYS,
    VERSION_RE,
    ClaudeHarnessClassifier,
    Classification,
    DanglingSymlinkClassifier,
    DictClassifierAdapter,
    EntryClassifierPort,
    InMemoryLivenessAdapter,
    ProcLivenessAdapter,
    SupersededVersionClassifier,
    TmpProducerClassifier,
    UnavailableLivenessAdapter,
    VersionLivenessPort,
    VersionUse,
    WalkContext,
    _in_use,
    _liveness_from_running,
    _overlaps,
    _within,
    default_classifiers,
    running_paths,
)
from plugin_cache_versions import (  # noqa: E402, F401  (re-exported for callers/tests)
    INSTALLED_PLUGINS,
    ORPHAN_SWEEP_DAYS,
    FsGuardedTextReader,
    inspect_plugin_cache,
    load_registry,
    orphan_marker,
    resolve,
    resolve_claude_dir,
)

try:
    import pwd
except ImportError:
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
LINK_PRODUCERS = (
    ("/mise/", "mise"),
    ("/.claude/", "claude-code"),
    ("/.npm/", "npm"),
    ("/uv/", "uv"),
)
_TOKEN = r"[\w.@/+-]+"
_NAMED_TOOL = re.compile(
    rf"(?:managed|owned) by (?:the )?({_TOKEN}(?: {_TOKEN}){{0,2}})"
)
_CATEGORY_PHRASE = re.compile(
    rf"(?:(?:tool|os|system|app|vendor)[- ]?(?:managed|owned)|{_NAMED_TOOL.pattern})"
)
FILE_ATTRIBUTE_REPARSE_POINT = 0x0400
UNCLASSIFIED = {
    "producer": "unknown",
    "category": "unclassified",
    "disposition": "UNKNOWN",
    "reason": "no category rule attributes this entry",
}
_UNSET: Any = object()


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


def _descends(st: os.stat_result) -> bool:
    return stat.S_ISDIR(st.st_mode) and not (
        getattr(st, "st_file_attributes", 0) & FILE_ATTRIBUTE_REPARSE_POINT
    )


def _tree_size(
    path: Path,
    mounts: frozenset[str] = frozenset(),
    root_dev: int | None = None,
) -> int:
    if root_dev is None:
        try:
            root_dev = os.lstat(path).st_dev
        except OSError:
            return 0
    total, stack = 0, [path]
    while stack:
        current = stack.pop()
        try:
            with os.scandir(current) as entries:
                for entry in entries:
                    try:
                        st = entry.stat(follow_symlinks=False)
                    except OSError:
                        continue
                    if _descends(st):
                        if entry.path in mounts or (
                            root_dev and st.st_dev and st.st_dev != root_dev
                        ):
                            continue
                        stack.append(Path(entry.path))
                    else:
                        total += st.st_size
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
    mounts: frozenset[str] = frozenset(),
) -> dict[str, Any]:
    """One schema row for ``path``, measured with lstat so a link is never followed."""
    st = os.lstat(path)
    return _stat_row(
        path,
        st,
        _tree_size(path, mounts=mounts, root_dev=st.st_dev)
        if _descends(st)
        else st.st_size,
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


def _row_from_classification(path: Path, cls: Classification) -> dict[str, Any]:
    return make_row(
        path,
        producer=cls.producer,
        category=cls.category,
        disposition=cls.disposition,
        reason=cls.reason,
        evidence=cls.evidence,
    )


def superseded_versions(
    parents: Iterable[Path],
    running: Iterable[str] | None = (),
    launcher_dirs: Iterable[Path] = (),
    *,
    liveness: VersionLivenessPort | None = None,
) -> list[dict[str, Any]]:
    """Sibling entries under each parent whose names parse as versions."""
    live = _liveness_from_running(running, liveness)
    classifier = SupersededVersionClassifier(launcher_dirs=tuple(launcher_dirs))
    ctx = WalkContext(
        target=Path("/"),
        home=Path.home(),
        tmp_dir=tmp_root(),
        claude_dir=None,
        now=0.0,
        liveness=live,
    )
    classifier.prepare(ctx)
    rows: list[dict[str, Any]] = []
    for parent in parents:
        classified = classifier.classify_parent(parent, require_dotted=False)
        for path_str, cls in classified.items():
            rows.append(_row_from_classification(Path(path_str), cls))
    return rows


def plugin_cache_versions(claude_dir: Path, now: float) -> list[dict[str, Any]]:
    """Rows for ``plugins/cache/<marketplace>/<plugin>/<version>`` under ``claude_dir``.

    Excludes depth-1 ``plugins/cache/temp_git_*`` staging clones from plugin
    version rows via ``ClaudeHarnessClassifier``.
    """
    classifier = ClaudeHarnessClassifier()
    ctx = WalkContext(
        target=claude_dir / "plugins" / "cache",
        home=Path.home(),
        tmp_dir=tmp_root(),
        claude_dir=claude_dir,
        now=now,
        liveness=UnavailableLivenessAdapter(),
    )
    classified = classifier.classify_plugin_cache(claude_dir, ctx)
    return [
        _row_from_classification(Path(path_str), cls)
        for path_str, cls in classified.items()
        if cls.category == "plugin-cache-version"
    ]


def tmp_entries(
    tmp_dir: Path,
    now: float,
    running: Iterable[str] | None = (),
    min_age_days: float = TMP_MIN_AGE_DAYS,
    producers: tuple[tuple[str, str, str | None], ...] = TMP_PRODUCERS,
) -> list[dict[str, Any]]:
    """One row per top-level entry of ``tmp_dir``, attributed by producer name prefix."""
    live = _liveness_from_running(running)
    classifier = TmpProducerClassifier(min_age_days=min_age_days, producers=producers)
    ctx = WalkContext(
        target=tmp_dir,
        home=Path.home(),
        tmp_dir=tmp_dir,
        claude_dir=None,
        now=now,
        liveness=live,
    )
    classifier.prepare(ctx)
    rows: list[dict[str, Any]] = []
    try:
        entries = sorted(tmp_dir.resolve().iterdir())
    except OSError:
        return rows
    for path in entries:
        cls = classifier._by_path.get(str(path))
        if cls is not None:
            rows.append(_row_from_classification(path, cls))
    return rows


def decode_project(encoded: str, fs_root: Path = Path("/")) -> str | None:
    """The existing path under ``fs_root`` whose encoding is ``encoded``, or None."""
    return ProjectSlugResolver(fs_root=fs_root).decode_slug(encoded)


def project_transcripts(
    projects_dir: Path, fs_root: Path = Path("/")
) -> list[dict[str, Any]]:
    """Rows for ``~/.claude/projects/<encoded>`` via ``ClaudeHarnessClassifier``."""
    classifier = ClaudeHarnessClassifier()
    ctx = WalkContext(
        target=projects_dir,
        home=Path.home(),
        tmp_dir=tmp_root(),
        claude_dir=None,
        now=0.0,
        liveness=UnavailableLivenessAdapter(),
        fs_root=fs_root,
    )
    classified = classifier.classify_projects(projects_dir, ctx)
    return [
        _row_from_classification(Path(path_str), cls)
        for path_str, cls in classified.items()
    ]


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
    claude_dir: Path | None | Any = _UNSET,
) -> dict[str, dict[str, Any]]:
    """Rows of each category overlapping ``target``, keyed by path string."""
    rows: list[dict[str, Any]] = []
    resolved_claude = (
        resolve_claude_dir(home=home) if claude_dir is _UNSET else claude_dir
    )
    if resolved_claude is not None:
        if _overlaps(resolved_claude / "plugins" / "cache", target):
            rows += plugin_cache_versions(resolved_claude, now)
        if _overlaps(resolved_claude / "projects", target):
            rows += project_transcripts(resolved_claude / "projects")
    if _overlaps(tmp_dir, target):
        rows += tmp_entries(tmp_dir, now, running)
    return {row["name"]: row for row in rows}


def _default_classifiers() -> tuple[EntryClassifierPort, ...]:
    return default_classifiers(
        tmp_producers=TMP_PRODUCERS,
        link_producers=LINK_PRODUCERS,
    )


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
    claude_dir: Path | None | Any = _UNSET,
    liveness: VersionLivenessPort | None = None,
    classifiers: Sequence[EntryClassifierPort] | None = None,
    fs_root: Path = Path("/"),
) -> Iterable[dict[str, Any]]:
    """Yield one row per entry of ``target``, the target itself last.

    Single-pass mount-safe and ``st_dev``-safe sizing: classifiers return
    ``Classification`` metadata only and never pre-walk sizes. A directory that
    cannot be read, or that is a mount point (another device, or a path in
    ``mounts``, which also catches a bind mount on the same device), is one
    UNKNOWN row and is not entered. Paths in ``skip`` (the report being written)
    are left out.
    """
    live = _liveness_from_running(running, liveness)
    resolved_claude: Path | None
    if claude_dir is _UNSET:
        resolved_claude = resolve_claude_dir(home=home)
    elif claude_dir is None:
        resolved_claude = None
    else:
        resolved_claude = Path(claude_dir).expanduser()

    ctx = WalkContext(
        target=target,
        home=home,
        tmp_dir=tmp_dir,
        claude_dir=resolved_claude,
        now=now,
        liveness=live,
        fs_root=fs_root,
    )

    active_classifiers: list[EntryClassifierPort] = (
        list(classifiers) if classifiers is not None else list(_default_classifiers())
    )
    for clf in active_classifiers:
        clf.prepare(ctx)

    dir_classifications: dict[str, Classification] = {}

    def children(directory: Path) -> list[tuple[Path, os.stat_result | None, str]]:
        with os.scandir(directory) as it:
            entries = sorted(it, key=lambda e: e.name, reverse=True)
        for clf in active_classifiers:
            for key, cls in clf.classify_directory(directory, entries).items():
                dir_classifications.setdefault(key, cls)
        found: list[tuple[Path, os.stat_result | None, str]] = []
        for entry in entries:
            if entry.path in skip:
                continue
            try:
                found.append((Path(entry.path), entry.stat(follow_symlinks=False), ""))
            except OSError as exc:
                found.append((Path(entry.path), None, f"{type(exc).__name__}: {exc}"))
        return found

    def classify(path: Path, st: os.stat_result) -> Classification | None:
        for clf in active_classifiers:
            hit = clf.classify_entry(path, st)
            if hit is not None:
                return hit
        return dir_classifications.get(str(path))

    def row(path: Path, st: os.stat_result, size: int) -> dict[str, Any]:
        cls = classify(path, st)
        if cls is not None:
            return _stat_row(
                path,
                st,
                size,
                producer=cls.producer,
                category=cls.category,
                disposition=cls.disposition,
                reason=cls.reason,
                evidence=cls.evidence,
            )
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

    target = Path(target).resolve()
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
        size = (
            _tree_size(path, mounts=mounts, root_dev=root_st.st_dev)
            if _descends(st)
            else st.st_size
        )
        total[0] += size
        yield row(path, st, size)


def _category_only(reason: str) -> bool:
    parts = [
        p for p in re.split(r"\s*(?:[;,.]|\band\b)\s*", reason.strip().lower()) if p
    ]
    return not parts or all(_CATEGORY_PHRASE.fullmatch(p) for p in parts)


def _shows_reference(reason: str, evidence: object) -> bool:
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
    """Failures of a report; an empty list means it passes."""
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


def _linux_mount_points(mountinfo: Path = Path("/proc/self/mountinfo")) -> frozenset[str]:
    """Read Linux mount points for standalone CLI runs; empty set when unavailable."""
    try:
        text = mountinfo.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return frozenset()
    found: set[str] = set()
    for line in text.splitlines():
        parts = line.split()
        if len(parts) < 5:
            continue
        point = re.sub(
            r"\\([0-7]{3})", lambda m: chr(int(m.group(1), 8)), parts[4]
        )
        found.add(point)
    return frozenset(found)


def main(argv: Sequence[str] | None = None) -> int:
    """Standalone read-only JSONL inventory CLI (zero ``--data-root``, zero writes by default)."""
    parser = argparse.ArgumentParser(
        prog="deep_inventory.py",
        description="Read-only deep disk inventory streaming validated JSONL rows.",
    )
    parser.add_argument("target", help="Directory to inventory.")
    depth = parser.add_mutually_exclusive_group()
    depth.add_argument(
        "--deep",
        action="store_true",
        help="Walk every nested directory (default when TARGET is $HOME).",
    )
    depth.add_argument(
        "--shallow",
        action="store_true",
        help="Emit only immediate children (and TARGET itself).",
    )
    parser.add_argument(
        "--out",
        default=None,
        help="Write JSONL rows to PATH instead of stdout.",
    )
    parser.add_argument(
        "--claude-dir",
        default=None,
        help="Claude config directory (default: $CLAUDE_CONFIG_DIR or ~/.claude).",
    )
    parser.add_argument(
        "--no-claude",
        action="store_true",
        help="Disable Claude harness classifiers.",
    )
    parser.add_argument(
        "--no-validate",
        action="store_true",
        help="Skip KEEP-reason validation.",
    )
    args = parser.parse_args(list(argv) if argv is not None else None)

    target_input = Path(args.target).expanduser()
    if not target_input.is_dir():
        print(f"error: target is not an existing directory: {args.target}", file=sys.stderr)
        return 2
    target = target_input.resolve()
    home = Path.home().resolve()
    if args.deep:
        deep = True
    elif args.shallow:
        deep = False
    else:
        deep = target == home

    claude_dir: Path | None
    if args.no_claude:
        claude_dir = None
    elif args.claude_dir:
        claude_dir = Path(args.claude_dir).expanduser()
    else:
        claude_dir = resolve_claude_dir(home=home)

    out_path = Path(args.out).expanduser().resolve() if args.out else None
    skip = frozenset({str(out_path)}) if out_path is not None else frozenset()
    mounts = _linux_mount_points()
    liveness = ProcLivenessAdapter()
    now = dt.datetime.now(dt.timezone.utc).timestamp()

    failures: list[str] = []
    stream_rows = inventory_rows(
        target,
        deep=deep,
        home=home,
        tmp_dir=tmp_root(),
        now=now,
        liveness=liveness,
        skip=skip,
        mounts=mounts,
        claude_dir=claude_dir,
    )

    if out_path is not None:
        try:
            with out_path.open("w", encoding="utf-8") as fh:
                for item in stream_rows:
                    fh.write(json.dumps(item, sort_keys=True) + "\n")
                    if not args.no_validate:
                        failures.extend(validate_report([item]))
        except OSError as exc:
            print(f"error: cannot write --out {out_path}: {exc}", file=sys.stderr)
            return 2
    else:
        try:
            for item in stream_rows:
                sys.stdout.write(json.dumps(item, sort_keys=True) + "\n")
                if not args.no_validate:
                    failures.extend(validate_report([item]))
        except BrokenPipeError:
            return 0

    if failures:
        for msg in failures:
            print(f"validation error: {msg}", file=sys.stderr)
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
