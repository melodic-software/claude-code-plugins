#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Inventory the `.work` memory tiers: what is stale, what is in flight.

Stdlib only; Python 3.10+. Every subcommand is read-only.

Usage:
    tidy_work.py report [--days N] [--memory-dir <root>] [--json]
                        [--link-state <file> | --offline]

`report` lists the first-level items of the current repo's memory root and of
`$HOME/.work`, each with its path, age, size, kind and whether it is in flight.
Kinds come from the layout in `reference/topic-docs.md`:

    handoff        `handoffs/<TS>-handoff-<topic>.md`
    running-retro  `running-retros/<TS>-running-retro-<topic>.md`
    slice          `<slug>/` holding an `INDEX.md`
    checklist      `<slug>/` holding a `workflow-checklist.md` and no `INDEX.md`
    scratch        an entry of a regenerable concern dir (reviews, exports, ...)
    unknown        everything else; always reported, always kept

An item is in flight, and so kept, when any of these holds:
    - its frontmatter names an issue or PR (keys issue, issues, pr, prs,
      pull_request, pull_requests) that is open or whose state is unknown
    - it changed within `--days` days (default 14)
    - a later handoff mentions it by name
    - its `workflow-checklist.md` has an unticked stage that is not marked SKIP

Issue and PR state comes from `gh api` unless `--link-state` supplies a JSON
object mapping `#N` or `owner/repo#N` to a state, or `--offline` treats every
link as unknown (in flight). A link missing from the table is unknown.

Exit codes:
    report  0 printed
            2 usage, or `--link-state` unreadable or not a JSON object
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

_SCRIPTS_DIR = Path(__file__).resolve().parent
if str(_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS_DIR))

import save_point  # noqa: E402  (save_point.py beside this script)
from io_streams import utf8_streams  # noqa: E402

DEFAULT_DAYS = 14
SELF_IGNORE = ".gitignore"
CHECKLIST = "workflow-checklist.md"
SLICE_INDEX = "INDEX.md"
RETRO_NAME_RE = re.compile(r"^\d{8}T\d{6}Z-running-retro-[^/\\]+\.md$")
# Concern dirs the contract calls regenerable reports; each entry is scratch.
SCRATCH_DIRS = (
    "reviews",
    "exports",
    "overengineering",
    "enforceability",
    "docs-hygiene",
)
LINK_KEYS = ("issue", "issues", "pr", "prs", "pull_request", "pull_requests")
LINK_RE = re.compile(
    r"(?:github\.com/([\w.-]+/[\w.-]+)/(?:issues|pull)/|([\w.-]+/[\w.-]+)?#)?(\d+)"
)
UNTICKED_RE = re.compile(r"^\s*[-*]\s+\[ \]\s")
STAGES_HEADING = "## Stages"


@dataclass
class Item:
    path: Path
    root: str
    kind: str
    mtime: float
    size: int
    links: list[str] = field(default_factory=list)
    reasons: list[str] = field(default_factory=list)

    @property
    def in_flight(self) -> bool:
        return bool(self.reasons)

    @property
    def keep(self) -> bool:
        return self.kind == "unknown" or self.in_flight


def _tree_stats(path: Path) -> tuple[float, int]:
    """Newest mtime and total bytes under path; symlinks are counted, never followed."""
    st = path.lstat()
    newest, size = st.st_mtime, st.st_size
    if path.is_dir() and not path.is_symlink():
        for base, dirs, files in os.walk(path, followlinks=False):
            for name in (*dirs, *files):
                try:
                    entry = os.lstat(os.path.join(base, name))
                except OSError:
                    continue
                newest = max(newest, entry.st_mtime)
                size += entry.st_size
    return newest, size


def _links_of(path: Path) -> list[str]:
    if path.suffix != ".md":
        return []
    try:
        doc = save_point.parse_doc(path)
    except (OSError, UnicodeDecodeError):
        return []
    refs: list[str] = []
    for key in LINK_KEYS:
        for url_repo, repo, number in LINK_RE.findall(doc.frontmatter.get(key, "")):
            ref = f"{url_repo or repo}#{number}" if url_repo or repo else f"#{number}"
            if ref not in refs:
                refs.append(ref)
    return refs


def _classify(path: Path, parent_kind: str | None) -> tuple[str, Path | None]:
    """(kind, file whose frontmatter carries the links)."""
    if path.is_symlink():
        return "unknown", None
    if parent_kind == "handoff":
        ok = save_point.HANDOFF_NAME_RE.match(path.name) and path.is_file()
        return ("handoff", path) if ok else ("unknown", None)
    if parent_kind == "running-retro":
        ok = RETRO_NAME_RE.match(path.name) and path.is_file()
        return ("running-retro", path) if ok else ("unknown", None)
    if parent_kind == "scratch":
        return "scratch", None
    if path.is_dir():
        if (path / SLICE_INDEX).is_file():
            return "slice", path / SLICE_INDEX
        if (path / CHECKLIST).is_file():
            return "checklist", None
    return "unknown", None


def _unfinished_stage(slice_dir: Path) -> bool:
    checklist = slice_dir / CHECKLIST
    try:
        lines = checklist.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError):
        return False
    if STAGES_HEADING in lines:
        start = lines.index(STAGES_HEADING) + 1
        end = next(
            (i for i in range(start, len(lines)) if lines[i].startswith("## ")),
            len(lines),
        )
        lines = lines[start:end]
    return any(UNTICKED_RE.match(line) and "skip" not in line.lower() for line in lines)


def inventory(root: Path, label: str) -> list[Item]:
    items: list[Item] = []
    try:
        entries = sorted(root.iterdir())
    except OSError:
        return items

    def add(path: Path, kind: str, link_file: Path | None) -> None:
        try:
            mtime, size = _tree_stats(path)
        except OSError:
            return
        items.append(
            Item(
                path,
                label,
                kind,
                mtime,
                size,
                _links_of(link_file) if link_file else [],
            )
        )

    for entry in entries:
        if entry.name == SELF_IGNORE:
            continue
        if entry.name in ("handoffs", "running-retros", *SCRATCH_DIRS) and (
            entry.is_dir() and not entry.is_symlink()
        ):
            parent_kind = {
                "handoffs": "handoff",
                "running-retros": "running-retro",
            }.get(entry.name, "scratch")
            for child in sorted(entry.iterdir()):
                kind, link_file = _classify(child, parent_kind)
                add(child, kind, link_file)
            continue
        kind, link_file = _classify(entry, None)
        add(entry, kind, link_file)
    return items


def _gh_state(ref: str) -> str:
    repo, _, number = ref.rpartition("#")
    api_path = f"repos/{repo or '{owner}/{repo}'}/issues/{number}"
    try:
        result = subprocess.run(
            ["gh", "api", api_path, "--jq", ".state"],
            capture_output=True,
            text=True,
            check=False,
            timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired):
        return "unknown"
    return result.stdout.strip() or "unknown" if result.returncode == 0 else "unknown"


class LinkStates:
    def __init__(self, table: dict[str, str] | None, offline: bool) -> None:
        self._table = table
        self._offline = offline
        self._cache: dict[str, str] = {}

    def state(self, ref: str) -> str:
        if self._offline:
            return "unknown"
        if self._table is not None:
            return str(self._table.get(ref, "unknown")).lower()
        if ref not in self._cache:
            self._cache[ref] = _gh_state(ref).lower()
        return self._cache[ref]


def _mentions(text: str, name: str, is_dir: bool) -> bool:
    if not is_dir:
        return name in text
    return re.search(rf"(?<![\w.-]){re.escape(name)}/", text) is not None


def mark_in_flight(
    items: list[Item], days: float, states: LinkStates, now: float
) -> None:
    handoffs: list[tuple[float, str]] = []
    for item in items:
        if item.kind == "handoff":
            try:
                handoffs.append((item.mtime, item.path.read_text(encoding="utf-8")))
            except (OSError, UnicodeDecodeError):
                continue
    for item in items:
        for ref in item.links:
            if (state := states.state(ref)) not in ("closed", "merged"):
                item.reasons.append(f"link {ref} is {state}")
        if now - item.mtime < days * 86400:
            item.reasons.append(f"modified within {days:g} days")
        is_dir = item.path.is_dir()
        if any(
            mtime > item.mtime and _mentions(text, item.path.name, is_dir)
            for mtime, text in handoffs
        ):
            item.reasons.append("named by a later handoff")
        if item.kind in ("slice", "checklist") and _unfinished_stage(item.path):
            item.reasons.append("checklist has an unfinished stage")


def resolve_roots(memory_dir: str | None) -> tuple[list[tuple[str, Path]], list[str]]:
    notes: list[str] = []
    memory: Path | None
    if memory_dir:
        memory = Path(memory_dir).expanduser().resolve()
    else:
        default = save_point._default_memory_dir()
        top = save_point._git_toplevel(Path.cwd())
        memory = (
            None
            if default is None
            else (default if default.is_absolute() or top is None else top / default)
        )
        if memory is None:
            notes.append("no memory root: no git work tree and no plugin data dir")
    home = os.environ.get("HOME") or os.environ.get("USERPROFILE") or str(Path.home())
    roots: list[tuple[str, Path]] = []
    if memory is not None:
        roots.append(("memory", memory.resolve()))
    home_work = (Path(home) / ".work").resolve()
    if all(home_work != path for _, path in roots):
        roots.append(("home", home_work))
    return roots, notes


def _age_days(mtime: float, now: float) -> float:
    return round(max(now - mtime, 0) / 86400, 1)


def _to_dict(item: Item, now: float) -> dict[str, object]:
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
    }


def _verdict(item: Item) -> str:
    if item.reasons:
        return "keep: " + "; ".join(item.reasons)
    return "keep: unknown kind" if item.kind == "unknown" else "stale"


def _table(items: list[Item], now: float) -> str:
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


def cmd_report(args: argparse.Namespace) -> int:
    table: dict[str, str] | None = None
    if args.link_state:
        try:
            table = json.loads(Path(args.link_state).read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:
            print(f"error: --link-state unreadable: {exc}", file=sys.stderr)
            return 2
        if not isinstance(table, dict):
            print("error: --link-state must be a JSON object", file=sys.stderr)
            return 2
    roots, notes = resolve_roots(args.memory_dir)
    states = LinkStates(table, args.offline)
    now = datetime.now(timezone.utc).timestamp()
    items: list[Item] = []
    for label, root in roots:
        items.extend(inventory(root, label))
    mark_in_flight(items, args.days, states, now)
    rows = [_to_dict(item, now) for item in items]
    if args.json:
        payload = {
            "days": args.days,
            "roots": [
                {"label": label, "path": root.as_posix()} for label, root in roots
            ],
            "notes": notes,
            "items": rows,
        }
        print(json.dumps(payload, indent=2))
        return 0
    for note in notes:
        print(f"note: {note}", file=sys.stderr)
    for label, root in roots:
        print(f"{label}: {root.as_posix()}")
    print(_table(items, now))
    stale = sum(1 for item in items if not item.keep)
    print(
        f"{len(items)} items, {stale} stale and known-kind, {len(items) - stale} kept"
    )
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    sub = parser.add_subparsers(dest="command", required=True)
    report = sub.add_parser("report", help="inventory the memory roots (read-only)")
    report.add_argument("--days", type=float, default=DEFAULT_DAYS)
    report.add_argument("--memory-dir", help="memory root; default is save_point.py's")
    report.add_argument(
        "--json", action="store_true", help="print JSON instead of a table"
    )
    link = report.add_mutually_exclusive_group()
    link.add_argument(
        "--link-state", help="JSON file mapping #N or owner/repo#N to a state"
    )
    link.add_argument(
        "--offline", action="store_true", help="treat every link as unknown"
    )
    report.set_defaults(func=cmd_report)
    return parser


def main(argv: list[str] | None = None) -> int:
    utf8_streams()
    args = build_parser().parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    sys.exit(main())
