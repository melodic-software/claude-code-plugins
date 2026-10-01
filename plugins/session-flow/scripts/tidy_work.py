#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Inventory the `.work` memory tiers: what is stale, what is in flight.

Stdlib only; Python 3.10+. `report` is read-only; `normalize` and `clean`
are dry runs that print exact absolute paths until `--apply` is given.

Usage:
    tidy_work.py report [--days N] [--memory-dir <root>] [--json]
                        [--link-state <file> | --offline]
    tidy_work.py normalize [--memory-dir <root>] [--apply]
    tidy_work.py clean [--days N] [--memory-dir <root>] [--apply]
                       [--link-state <file> | --offline]

`report` lists the first-level items of the current repo's memory root and of
`$HOME/.work`, each with its path, age, size, kind and whether it is in flight.
A relative `--memory-dir` resolves against the repository top level. Kinds come
from the memory-root layout:

    handoff        a `<TS>-handoff-<topic>.md` file, with its `.slots.json`
                   sidecar as part of the same item. `handoffs/` is its place;
                   one in the root or in `running-retros/` is a misplaced handoff
    running-retro  a `<TS>-running-retro-<topic>.md` file, in `running-retros/`
                   or misplaced the same way
    slice          `<slug>/` holding an `INDEX.md`
    checklist      `<slug>/` holding a `workflow-checklist.md` and no `INDEX.md`
    scratch        any other entry whose name carries exactly one issue or PR
                   number: one all-digit token of 3 to 7 digits, optionally
                   prefixed `pr`, `issue` or `gh` (`lint-5371.log`, `pr4120.md`,
                   `scratch-4586-d2cc1ea4d`). A year-like token (1900 to 2099)
                   needs the prefix (`backup-2026.tar` is not attributed,
                   `pr2026.md` is). A name with no such token, with several
                   all-digit tokens (a version, a date), or starting with a
                   writer's `<TS>Z-` timestamp is not attributed: it is unknown
    concern        an entry of another skill's concern dir (reviews, exports,
                   ...): state that skill reads back; always reported, always kept
    unknown        everything else; always reported, always kept

An item is in flight, and so kept, when any of these holds:
    - a slice's `INDEX.md` status, or a child slice's, is anything but `done`
      (missing and unrecognized values count as not done)
    - a `workflow-checklist.md` in it has an unticked stage not marked SKIP
    - it changed within `--days` days (default 14)
    - a later handoff that is itself kept mentions it by name
    - a `.git` file or directory sits under it (a clone or worktree can hold
      commits that exist nowhere else)
    - a handoff, running-retro, or scratch item names an issue or PR (a
      github.com URL, `owner/repo#N`, or `#N` in a handoff or running-retro's
      text, `#N` in a scratch item's name) that is not closed, not merged, or
      whose state is unknown

A bare `#N` means the repository holding the memory root; in `$HOME/.work`, or
any root outside a work tree, it has no repository and counts as unknown.

An item that names no issue or PR is kept however old it is: `clean` removes an
item only when it names at least one issue or PR and every one is closed or
merged. A handoff or running retro is attributed by the references in its text,
a scratch item by its name. A slice or checklist has no attribution source, so
`report` marks it and `clean` never removes it.
Issue and PR state comes from `gh api` (one listing of the open ones per
repository, then one lookup per link that is not open, which also separates a
closed link from a number that is no issue or PR: that one is unknown) unless
`--link-state` supplies a JSON object mapping `#N` or `owner/repo#N` to a
state, or `--offline` treats every link as unknown (in flight). A link missing
from the table is unknown. A closed PR that was not merged is `closed-unmerged`
and keeps its item. A link is looked up only when nothing cheaper already keeps
the item, except a scratch item's. Each state looked up is shown in brackets on
the report row and on the `clean` dry-run path, so the confirmation covers the
issue or PR each path was matched to.

`normalize` moves a handoff (with its sidecar) or running-retro file that sits
in the wrong place (the root, or the other one's directory) into `handoffs/` or
`running-retros/`. It never deletes, never touches an unknown item, and refuses
to overwrite.

`clean` removes only items of a known kind that are not in flight and whose
issues and PRs are all closed or merged, and only inside a resolved root. It refuses an item holding a symlink that resolves
outside the root. The root's `.gitignore` self-ignore file is never touched.

`normalize` and `clean` never modify content git tracks: they refuse the whole
memory root unless its `.gitignore` holds a line `*` (`$HOME/.work` excepted),
and refuse any item with a tracked path under it. Every command rejects a
memory root that is the repository root, and an existing one outside the
repository whose `.gitignore` lacks a line `*`: `memory_dir` comes from a
repo-controlled file and `report` is pre-approved, so neither may walk an
arbitrary directory.

Exit codes:
    all     2 usage, `--link-state` unreadable or not a JSON object, or a
            memory root that is rejected as above
    report  0 printed
    others  0 dry run, or every planned action applied
            1 an action was refused or failed
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
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
SLOTS_RE = re.compile(r"^(\d{8}T\d{6}Z-handoff-[^/\\]+)\.slots\.json$")
# Concern dirs other skills write and read back; their entries are never removed.
CONCERN_DIRS = (
    "reviews",
    "exports",
    "overengineering",
    "enforceability",
    "docs-hygiene",
    "lanes",
)
REF_RE = re.compile(
    r"github\.com/(?P<url_repo>[\w.-]+/[\w.-]+)/(?:issues|pull)/(?P<url_num>\d+)"
    r"|(?P<repo>[\w.-]+/[\w.-]+)#(?P<num>\d+)\b"
    r"|(?<![\w&#/])#(?P<bare>[1-9]\d*)\b"
)
NAME_TOKEN_RE = re.compile(r"(pr|issue|gh)?(\d+)", re.IGNORECASE)
YEAR_RE = re.compile(r"(?:19|20)\d\d")
TIMESTAMP_RE = re.compile(r"^\d{8}T\d{6}Z-")
UNTICKED_RE = re.compile(r"^\s*[-*]\s+\[ \]\s")
STAGES_HEADING = "## Stages"
FINISHED = ("closed", "merged")
GH_STATES = ("open", *FINISHED, "closed-unmerged")


@dataclass
class Item:
    path: Path
    root: str
    kind: str
    mtime: float
    size: int
    links: list[str] = field(default_factory=list)
    extras: list[Path] = field(default_factory=list)
    reasons: list[str] = field(default_factory=list)
    # link -> state, recorded when the link is looked up
    states: dict[str, str] = field(default_factory=dict)

    @property
    def paths(self) -> list[Path]:
        return [self.path, *self.extras]

    @property
    def in_flight(self) -> bool:
        return bool(self.reasons)

    @property
    def keep(self) -> bool:
        return self.kind in ("unknown", "concern") or self.in_flight or not self.links


def _plain_file(path: Path) -> bool:
    return path.is_file() and not path.is_symlink()


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


def _refs_of(path: Path) -> list[str]:
    """Issue and PR references in the text: `owner/repo#N`, or `#N` when bare."""
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return []
    refs: list[str] = []
    for match in REF_RE.finditer(text):
        repo = match["url_repo"] or match["repo"]
        number = match["url_num"] or match["num"] or match["bare"]
        ref = f"{repo}#{number}" if repo else f"#{number}"
        if ref not in refs:
            refs.append(ref)
    return refs


def _name_refs(name: str) -> list[str]:
    """`#N` when the name holds exactly one all-digit token of 3 to 7 digits
    (optionally prefixed pr, issue or gh), and a year-like one has the prefix; any
    other name is not attributed, and neither is a timestamped one (the writers'
    handoff, retro and export names)."""
    if TIMESTAMP_RE.match(name):
        return []
    tokens = [
        match.groups()
        for token in re.split(r"[-_.\s]+", name)
        if (match := NAME_TOKEN_RE.fullmatch(token))
    ]
    if len(tokens) == 1:
        prefix, number = tokens[0]
        if re.fullmatch(r"[1-9]\d{2,6}", number) and (
            prefix or not YEAR_RE.fullmatch(number)
        ):
            return [f"#{number}"]
    return []


def _classify(path: Path, parent_kind: str | None) -> tuple[str, Path | None]:
    """(kind, file whose text names the issues and PRs it is about)."""
    if path.is_symlink():
        return "unknown", None
    if parent_kind == "concern":
        return "concern", None
    if path.is_file():
        if save_point.HANDOFF_NAME_RE.match(path.name):
            return "handoff", path
        if RETRO_NAME_RE.match(path.name):
            return "running-retro", path
    if parent_kind:
        return "unknown", None
    if path.is_dir():
        if (path / SLICE_INDEX).is_file():
            return "slice", None
        if (path / CHECKLIST).is_file():
            return "checklist", None
    return ("scratch" if _name_refs(path.name) else "unknown"), None


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


def _slice_status(index: Path) -> str:
    try:
        return save_point.parse_doc(index).frontmatter.get("status", "")
    except (OSError, UnicodeDecodeError):
        return ""


def _holds_git(path: Path) -> bool:
    """True when a `.git` file or directory sits under path: a clone or worktree
    can hold commits that exist nowhere else, and the tracked-path guard cannot
    see into it."""
    if not path.is_dir() or path.is_symlink():
        return False
    return any(
        ".git" in (*dirs, *files) for _, dirs, files in os.walk(path, followlinks=False)
    )


def _open_work(directory: Path) -> list[str]:
    """Why a slice or checklist directory is not finished: every INDEX.md under
    it (child slices included) whose status is not `done`, and every checklist
    with an unfinished stage. `clean` removes the whole tree, so all of it counts."""
    reasons: list[str] = []
    for base, dirs, files in os.walk(directory, followlinks=False):
        dirs.sort()
        here = Path(base)
        rel = here.relative_to(directory)
        if (
            SLICE_INDEX in files
            and (status := _slice_status(here / SLICE_INDEX)) != "done"
        ):
            reasons.append(
                f"{(rel / SLICE_INDEX).as_posix()} status is {status or 'missing'}"
            )
        if CHECKLIST in files and _unfinished_stage(here):
            reasons.append(f"{(rel / CHECKLIST).as_posix()} has an unfinished stage")
    return reasons


def inventory(root: Path, label: str) -> list[Item]:
    items: list[Item] = []
    try:
        entries = sorted(root.iterdir())
    except OSError:
        return items

    def add(path: Path, kind: str, link_file: Path | None) -> None:
        extras: list[Path] = []
        if kind == "handoff" and _plain_file(
            sidecar := path.with_suffix(".slots.json")
        ):
            extras.append(sidecar)
        try:
            stats = [_tree_stats(p) for p in (path, *extras)]
        except OSError:
            return
        links = _refs_of(link_file) if link_file else []
        if kind == "scratch":
            links = _name_refs(path.name)
        items.append(
            Item(
                path,
                label,
                kind,
                max(mtime for mtime, _ in stats),
                sum(size for _, size in stats),
                links,
                extras,
            )
        )

    def visit(path: Path, parent_kind: str | None) -> None:
        # a handoff's sidecar is part of the handoff, wherever the pair sits
        if (slots := SLOTS_RE.match(path.name)) and _plain_file(
            path.with_name(f"{slots[1]}.md")
        ):
            return
        kind, link_file = _classify(path, parent_kind)
        add(path, kind, link_file)

    for entry in entries:
        if entry.name == SELF_IGNORE:
            continue
        if entry.name in ("handoffs", "running-retros", *CONCERN_DIRS) and (
            entry.is_dir() and not entry.is_symlink()
        ):
            parent_kind = {
                "handoffs": "handoff",
                "running-retros": "running-retro",
            }.get(entry.name, "concern")
            for child in sorted(entry.iterdir()):
                visit(child, parent_kind)
            continue
        visit(entry, None)
    return items


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


_GH_STATE_JQ = (
    'if .state == "open" then "open" elif .pull_request.merged_at then "merged" '
    'elif .pull_request then "closed-unmerged" else .state end'
)


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
        top = None if repo else save_point._git_toplevel(root)
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


def _mentions(text: str, name: str, is_dir: bool) -> bool:
    if not is_dir:
        return name in text
    return re.search(rf"(?<![\w.-]){re.escape(name)}/", text) is not None


def mark_in_flight(
    items: list[Item],
    days: float,
    states: LinkStates,
    now: float,
    roots: dict[str, Path],
) -> None:
    kept_handoffs: list[tuple[float, str]] = []  # (mtime, text) of handoffs kept

    def judge(item: Item) -> None:
        if item.kind in ("slice", "checklist"):
            item.reasons.extend(_open_work(item.path))
        if now - item.mtime < days * 86400:
            item.reasons.append(f"modified within {days:g} days")
        is_dir = item.path.is_dir()
        if any(
            mtime > item.mtime and _mentions(text, item.path.name, is_dir)
            for mtime, text in kept_handoffs
        ):
            item.reasons.append("named by a later handoff")
        if not item.reasons and _holds_git(item.path):
            item.reasons.append("holds a git repository or worktree")
        if item.reasons and item.kind != "scratch":
            return
        for ref in item.links:
            state = item.states[ref] = states.state(ref, roots[item.root])
            if state not in FINISHED:
                item.reasons.append(f"link {ref} is {state}")

    # Newest first, so a handoff is judged after every later one: a stale
    # handoff does not keep what it names.
    for item in sorted(
        (i for i in items if i.kind == "handoff"), key=lambda i: i.mtime, reverse=True
    ):
        judge(item)
        if item.keep:
            try:
                kept_handoffs.append(
                    (item.mtime, item.path.read_text(encoding="utf-8"))
                )
            except (OSError, UnicodeDecodeError):
                pass
    for item in items:
        if item.kind != "handoff":
            judge(item)


def resolve_roots(memory_dir: str | None) -> tuple[list[tuple[str, Path]], list[str]]:
    """The roots to inventory. Raises ValueError for a memory root that is the
    repository root (every top-level `INDEX.md` directory there would be a slice),
    and for an existing one outside the repository without the self-ignore guard
    (`memory_dir` comes from a repo-controlled file, so `/etc` must not be walked)."""
    notes: list[str] = []
    top = save_point._git_toplevel(Path.cwd())
    declared = (
        Path(memory_dir).expanduser()
        if memory_dir
        else save_point._default_memory_dir()
    )
    memory = (
        None
        if declared is None
        else (declared if declared.is_absolute() or top is None else top / declared)
    )
    if memory is None:
        notes.append("no memory root: no git work tree and no plugin data dir")
    else:
        memory = memory.resolve()
        if save_point._git_toplevel(memory) == memory:
            raise ValueError(
                f"memory root {memory.as_posix()} is the repository root; "
                "it must be a dedicated directory below it"
            )
        if (
            (top is None or not memory.is_relative_to(top.resolve()))
            and memory.is_dir()
            and not _self_ignored(memory)
        ):
            raise ValueError(
                f"memory root {memory.as_posix()} is outside the repository and "
                f"lacks the self-ignore guard: {(memory / SELF_IGNORE).as_posix()} "
                "must contain a line '*'"
            )
    home = os.environ.get("HOME") or os.environ.get("USERPROFILE") or str(Path.home())
    roots: list[tuple[str, Path]] = []
    if memory is not None:
        roots.append(("memory", memory))
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
        "links": item.states,
    }


def _attribution(item: Item) -> str:
    """The issues or PRs the item was matched to, with the states looked up."""
    if not item.states:
        return ""
    return (
        " [" + ", ".join(f"{ref} {state}" for ref, state in item.states.items()) + "]"
    )


def _verdict(item: Item) -> str:
    if item.kind == "concern":
        verdict = "keep: concern state read back by its skill"
    elif item.kind == "unknown":
        verdict = "keep: unknown kind"
    elif item.reasons:
        verdict = "keep: " + "; ".join(item.reasons)
    else:
        verdict = "stale" if item.links else "keep: names no issue or PR"
    return verdict + _attribution(item)


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


def _roots(
    args: argparse.Namespace,
) -> tuple[list[tuple[str, Path]], list[str]] | None:
    try:
        return resolve_roots(args.memory_dir)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return None


def _survey(
    args: argparse.Namespace,
) -> tuple[list[tuple[str, Path]], list[str], list[Item], float] | None:
    try:
        table = _load_link_table(args.link_state)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return None
    resolved = _roots(args)
    if resolved is None:
        return None
    roots, notes = resolved
    states = LinkStates(table, args.offline)
    now = datetime.now(timezone.utc).timestamp()
    items: list[Item] = []
    for label, root in roots:
        items.extend(inventory(root, label))
    mark_in_flight(items, args.days, states, now, dict(roots))
    return roots, notes, items, now


def cmd_report(args: argparse.Namespace) -> int:
    survey = _survey(args)
    if survey is None:
        return 2
    roots, notes, items, now = survey
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
    print(f"{len(items)} items, {stale} removable, {len(items) - stale} kept")
    return 0


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
    tracked: list[str] | None = (
        None  # root-relative tracked paths; None outside a work tree
    )

    def blocks(self, path: Path) -> str | None:
        if self.refusal:
            return self.refusal
        if self.tracked is not None:
            rel = path.relative_to(self.root).as_posix()
            if any(t == rel or t.startswith(f"{rel}/") for t in self.tracked):
                return f"git tracks content at {rel}"
        return None


def _self_ignored(root: Path) -> bool:
    try:
        lines = (root / SELF_IGNORE).read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError):
        return False
    return any(line.strip() == "*" for line in lines)


def _guard(label: str, root: Path) -> Guard:
    guard = Guard(root)
    if not root.is_dir():
        return guard
    if label != "home" and not _self_ignored(root):
        guard.refusal = (
            f"memory root lacks the self-ignore guard: {(root / SELF_IGNORE).as_posix()} "
            "must contain a line '*'"
        )
    elif save_point._git_toplevel(root) is not None:
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


def plan_moves(root: Path) -> list[tuple[Path, Path]]:
    """(source, target) for each handoff (with its sidecar) or running-retro file
    outside its directory."""
    layout = (
        ("handoffs", save_point.HANDOFF_NAME_RE),
        ("running-retros", RETRO_NAME_RE),
    )
    sources: list[Path] = []
    try:
        for entry in sorted(root.iterdir()):
            if entry.name in ("handoffs", "running-retros"):
                if entry.is_dir() and not entry.is_symlink():
                    sources.extend(sorted(entry.iterdir()))
            else:
                sources.append(entry)
    except OSError:
        return []
    moves: list[tuple[Path, Path]] = []
    for src in sources:
        if src.is_symlink() or not src.is_file():
            continue
        for dirname, name_re in layout:
            if name_re.match(src.name) and src.parent != root / dirname:
                moves.append((src, root / dirname / src.name))
                if _plain_file(sidecar := src.with_suffix(".slots.json")):
                    moves.append((sidecar, root / dirname / sidecar.name))
    return moves


def _refusal(dst: Path) -> str | None:
    if dst.parent.is_symlink() or (dst.parent.exists() and not dst.parent.is_dir()):
        return f"{dst.parent.as_posix()} is not a plain directory"
    if os.path.lexists(dst):
        return f"target exists: {dst.as_posix()}"
    return None


def cmd_normalize(args: argparse.Namespace) -> int:
    resolved = _roots(args)
    if resolved is None:
        return 2
    roots, notes = resolved
    for note in notes:
        print(f"note: {note}", file=sys.stderr)
    failed = total = 0
    for label, root in roots:
        moves = plan_moves(root)
        guard = _guard(label, root) if moves else Guard(root)
        for src, dst in moves:
            total += 1
            if refusal := guard.blocks(src) or _refusal(dst):
                failed += 1
                print(f"refused: {src.as_posix()} ({refusal})")
                continue
            if args.apply:
                try:
                    dst.parent.mkdir(exist_ok=True)
                    os.rename(src, dst)
                except OSError as exc:
                    failed += 1
                    print(f"failed: {src.as_posix()} ({exc})")
                    continue
            verb = "moved" if args.apply else "would move"
            print(f"{verb}: {src.as_posix()} -> {dst.as_posix()}")
    print(f"{total} misplaced, {failed} refused" + ("" if args.apply else ", dry run"))
    return 1 if failed and args.apply else 0


def _blocked(item: Item, root: Path, guard: Guard) -> str | None:
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


def cmd_clean(args: argparse.Namespace) -> int:
    survey = _survey(args)
    if survey is None:
        return 2
    roots, notes, items, _ = survey
    for note in notes:
        print(f"note: {note}", file=sys.stderr)
    root_of = dict(roots)
    stale = [item for item in items if not item.keep]
    guards = {
        label: _guard(label, root)
        for label, root in roots
        if any(item.root == label for item in stale)
    }
    failed = removed = 0
    for item in stale:
        if refusal := _blocked(item, root_of[item.root], guards[item.root]):
            failed += 1
            print(f"refused: {item.path.as_posix()} ({refusal})")
        elif not args.apply:
            for path in item.paths:
                print(f"would remove: {path.as_posix()}{_attribution(item)}")
        else:
            try:
                for path in item.paths:
                    _remove(path)
                    print(f"removed: {path.as_posix()}{_attribution(item)}")
            except OSError as exc:
                failed += 1
                print(f"failed: {item.path.as_posix()} ({exc})")
                continue
            removed += 1
    kept = len(items) - len(stale)
    count = f"{removed} removed" if args.apply else f"{len(stale) - failed} to remove"
    print(f"{count}, {failed} refused or failed, {kept} kept")
    return 1 if failed and args.apply else 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    sub = parser.add_subparsers(dest="command", required=True)
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--memory-dir", help="memory root; default is save_point.py's")
    inflight = argparse.ArgumentParser(add_help=False)
    inflight.add_argument("--days", type=float, default=DEFAULT_DAYS)
    link = inflight.add_mutually_exclusive_group()
    link.add_argument(
        "--link-state", help="JSON file mapping #N or owner/repo#N to a state"
    )
    link.add_argument(
        "--offline", action="store_true", help="treat every link as unknown"
    )
    report = sub.add_parser(
        "report", parents=[common, inflight], help="inventory the roots (read-only)"
    )
    report.add_argument(
        "--json", action="store_true", help="print JSON instead of a table"
    )
    report.set_defaults(func=cmd_report)
    normalize = sub.add_parser(
        "normalize", parents=[common], help="move misplaced handoffs and retros"
    )
    normalize.set_defaults(func=cmd_normalize)
    clean = sub.add_parser(
        "clean",
        parents=[common, inflight],
        help="remove stale items whose issues and PRs are closed",
    )
    clean.set_defaults(func=cmd_clean)
    for cmd in (normalize, clean):
        cmd.add_argument(
            "--apply", action="store_true", help="mutate; the default is a dry run"
        )
    return parser


def main(argv: list[str] | None = None) -> int:
    utf8_streams()
    args = build_parser().parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    sys.exit(main())
