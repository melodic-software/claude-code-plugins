#!/usr/bin/env python3
"""Diff risk scorer for the unattended merge path.

`score(RiskInput) -> RiskResult` is a pure function: no I/O, no GitHub calls.
The caller reads the PR, its linked issue's class, the base-SHA config and the
review-lane evidence, and hands them in; this module only judges them. Only a
LOW score may merge unattended, so every doubtful input rates MED or HIGH:
missing or unrecognised data is a miss, never a pass, and it never raises: input
it cannot read at all rates HIGH as `high-path:**`. Inputs are plain built-in
types (str, int, bool, None, list, tuple) built from parsed JSON; subclasses
that override their own behaviour are out of scope. A count outside
0..10**9 is malformed. Each reason code appears once.

The HIGH path floor and the lane table are fixed here on purpose. A weaker value
could only come from a file a pull request can edit, and this module's own path
is in the floor, so a pull request cannot change the rule it is judged by. The
configured `merge.diff-check.denied-paths` is joined to the floor, never in
place of it. Every glob matches case-insensitively, because a lane host on a
case-insensitive filesystem treats `Claude.md` as `CLAUDE.md`.

Paths are normalised before matching (`\\` to `/`, empty and `.` segments
dropped). A path is safe only when every `/`-separated segment is non-empty,
uses only `[A-Za-z0-9._-]` and does not end in `.` (Windows strips it); every
tracked path in this repository passes. Any other path rates HIGH as
`high-path:**`, because it could alias any path: `..`, `:` (an NTFS stream),
`~1` (an 8.3 short name), whitespace, control or non-ASCII characters. So does
a rename or copy with no previous path, and a file whose git mode is missing,
unknown, a symlink or submodule, or changes type. A configured glob outside the
same set (plus `*` and whole `**` segments), read exactly as written, makes the
configured HIGH set unreadable, and then only the floor is matched.
Malformed values have no code of their own in the contract, so each maps to the
nearest existing code: per-file data and the listing to `files-incomplete`, an
unknown rung to `class-above-rung` (read as off), an unreadable line limit to
`lines-over`, an unreadable configured HIGH set or file mode to `high-path:**`,
and a blast radius other than LOW above C2 to `blast-radius-missing`.
"""

from __future__ import annotations

import enum
import re
from dataclasses import dataclass
from typing import Any


class Risk(enum.IntEnum):
    """Ordered, so the score is the max() of the reasons' severities."""

    LOW = 0
    MED = 1
    HIGH = 2


class Rung(enum.IntEnum):
    """Order matches the `merge.rung` enum in pr-pipeline.schema.json. Each value
    is the highest _CLASS_RANK the rung admits; OFF admits none."""

    OFF = 0
    C2 = 2
    C3 = 3


@dataclass(frozen=True)
class ChangedFile:
    path: str
    previous_path: str | None  # set on a rename; both paths are tested
    status: str  # one of STATUSES
    additions: int
    deletions: int
    has_patch: bool  # False for binary, submodule, or over-size files
    # Git file mode ("100644", "100755", "120000", "160000") on the side that
    # exists (the base side for a removed file). The pull-request files API
    # omits it, so the caller fills it from the git trees API or
    # `git diff --raw`.
    mode: str
    previous_mode: str | None = None  # the base-side mode on a rename or change


@dataclass(frozen=True)
class LaneEvidence:
    lane: str  # "claude-review" | "claude-security-review"
    bound: bool  # the evidence binding held on the pinned SHA
    unbound_reason: str | None
    open_findings: int | None  # None when not bound


@dataclass(frozen=True)
class RiskInput:
    work_class: str | None  # class of the one linked issue (C1..C5)
    rung: Rung  # effective rung
    files: tuple[ChangedFile, ...]
    files_complete: bool  # the listing was read to its end
    max_changed_lines: int  # merge.diff-check.max-changed-lines at the base SHA
    high_paths: tuple[str, ...]  # configured denied paths, joined to HIGH_FLOOR
    lanes: tuple[LaneEvidence, ...]
    blast_radius: str | None  # consulted only above C2


@dataclass(frozen=True)
class Reason:
    code: str
    severity: Risk
    detail: str


@dataclass(frozen=True)
class RiskResult:
    score: Risk  # max(reason.severity), LOW when no reason
    reasons: tuple[Reason, ...]  # sorted by severity desc, then code


MAX_FILES = 8

HIGH_FLOOR: tuple[str, ...] = (
    ".github/**",
    "docs/conventions/**",
    "**/AGENTS.md",
    "**/CLAUDE.md",
    "**/.claude/**",
    "scripts/**",
    "REVIEW.md",
    "plugins/source-control/skills/babysit-prs/**",
    "plugins/review/**",
    "plugins/autonomy/reference/guardrails/**",
    "**/.claude-plugin/**",
    "lib/**",
    "plugins/source-control/lib/**",
    "plugins/source-control/skills/babysit-loop/**",
    ".work-item-tracker.json",
    "plugins/guardrails/**",
    "plugins/work-items/**",
    "plugins/*/hooks/**",
    "prompts/**",
    "package.json",
    "package-lock.json",
    "**/package-lock.json",
    ".node-version",
    ".python-version",
    ".gitleaks.toml",
    ".gitleaksignore",
    ".gitattributes",
    "**/.gitmodules",
    "**/CLAUDE.local.md",
    "**/.mcp.json",
    "**/AGENTS.override.md",
)

# Lane -> (code, severity) for an open finding on that lane. Both lanes are
# required: a lane absent from the input is unbound.
LANES: dict[str, tuple[str, Risk]] = {
    "claude-review": ("findings:claude-review", Risk.MED),
    "claude-security-review": ("security-finding", Risk.HIGH),
}

# GitHub's documented pull request file statuses.
STATUSES = frozenset(
    {"added", "removed", "modified", "renamed", "copied", "changed", "unchanged"}
)
_STRUCTURAL = frozenset({"removed", "renamed", "copied", "changed"})

UNSAFE_PATH_CODE = "high-path:**"

# Every tracked path segment uses only these characters. Anything else (a `:`,
# a `~`, whitespace, a control or non-ASCII character) could alias a floor path
# on some filesystem, so it is unsafe rather than enumerated.
_SAFE_SEGMENT = re.compile(r"[A-Za-z0-9._-]+")
_SAFE_GLOB_SEGMENT = re.compile(r"[A-Za-z0-9._*-]+")
# The plan's blast-radius scale is LOW / MEDIUM / HIGH / CRITICAL; only LOW
# can leave a class above C2 at LOW.
_LOW_BLAST = "low"

_CLASS_RANK = {"C1": 1, "C2": 2, "C3": 3, "C4": 4, "C5": 5}
_C1_RANK = _CLASS_RANK["C1"]
_C2_RANK = _CLASS_RANK["C2"]

# Git file modes by type. Only regular files may stay below HIGH.
_MODE_TYPES = {
    "100644": "regular",
    "100755": "regular",
    "120000": "symlink",
    "160000": "submodule",
}


MAX_COUNT = 10**9


def _is_count(value: Any) -> bool:
    return (
        isinstance(value, int)
        and not isinstance(value, bool)
        and 0 <= value <= MAX_COUNT
    )


def _show(value: Any) -> str:
    """repr() for a detail string; a value repr() rejects (an int past Python's
    digit limit, say) is named by type, never formatted."""
    if isinstance(value, int) and not isinstance(value, bool):
        if not -MAX_COUNT <= value <= MAX_COUNT:
            return "<int out of range>"
    try:
        return repr(value)
    except Exception:
        return f"<unprintable {type(value).__name__}>"


def _sequence(value: Any) -> tuple[Any, ...] | None:
    return tuple(value) if isinstance(value, (tuple, list)) else None


def normalize_path(path: Any) -> tuple[str, bool]:
    """Return (normalised path, safe). Unsafe means it could hide a floor path."""
    if not isinstance(path, str):
        return "", False
    safe = all(
        _SAFE_SEGMENT.fullmatch(segment) and not segment.endswith(".")
        for segment in path.split("/")
    )
    segments = [s for s in path.replace("\\", "/").split("/") if s not in ("", ".")]
    return "/".join(segments), safe


def _safe_glob(pattern: str) -> bool:
    """A configured glob must name a path in the same character set, exactly as
    written: no `./` or `/` prefix, no `\\`, no segment ending in `.`, and `**`
    only as a whole segment."""
    if pattern.endswith("/"):
        pattern = pattern[:-1]
    return all(
        _SAFE_GLOB_SEGMENT.fullmatch(segment)
        and not segment.endswith(".")
        and ("**" not in segment or segment == "**")
        for segment in pattern.split("/")
    )


def _segment_match(pattern: str, name: str) -> bool:
    """`*` within one segment. Greedy with one backtrack point, so the cost is
    at most len(pattern) * len(name) however many stars there are."""
    p = n = 0
    star, mark = -1, 0
    while n < len(name):
        if p < len(pattern) and pattern[p] == "*":
            star, mark, p = p, n, p + 1
        elif p < len(pattern) and pattern[p] == name[n]:
            p, n = p + 1, n + 1
        elif star >= 0:
            mark += 1
            p, n = star + 1, mark
        else:
            return False
    return all(char == "*" for char in pattern[p:])


def glob_match(pattern: str, path: str) -> bool:
    """Match a path glob: `**` spans any number of segments, `*` stays within
    one. A pattern also covers everything under it, so `plugins/foo` and
    `plugins/foo/` both match `plugins/foo/x.md`, and `X/**` matches `X` itself.
    Matching is case-folded, by an iterative table over (glob segment, path
    segment), so its cost is O(glob segments x path segments) for any glob."""
    folded = pattern.casefold()
    if folded.endswith("/"):
        folded += "**"
    globs: list[str] = []
    for segment in folded.split("/"):
        if segment != "**":
            segment = re.sub(r"\*+", "*", segment)
        if not (segment == "**" and globs and globs[-1] == "**"):
            globs.append(segment)
    names = path.casefold().split("/")
    # below[j]: globs[i + 1:] match a prefix of names[j:]. With no glob left,
    # the rest of the path sits under what matched.
    below = [True] * (len(names) + 1)
    for glob in reversed(globs):
        row = [False] * (len(names) + 1)
        if glob == "**":
            row[len(names)] = below[len(names)]
            for j in range(len(names) - 1, -1, -1):
                row[j] = below[j] or row[j + 1]
        else:
            for j in range(len(names)):
                row[j] = below[j + 1] and _segment_match(glob, names[j])
        below = row
    return below[0]


@dataclass(frozen=True)
class _File:
    """A changed file after validation: normalised paths plus its problems."""

    path: str
    paths: tuple[str, ...]
    unsafe: tuple[str, ...]
    status: Any
    lines: int
    has_patch: bool | None  # None when malformed: reported once, as a problem
    problems: tuple[str, ...]


def _check_file(changed: Any) -> _File:
    raw_path = getattr(changed, "path", None)
    previous = getattr(changed, "previous_path", None)
    raws = [raw_path] if previous is None else [raw_path, previous]
    paths, unsafe = [], []
    for raw in raws:
        normalized, safe = normalize_path(raw)
        paths.append(normalized)
        if not safe:
            unsafe.append(_show(raw))
    raw_status = getattr(changed, "status", None)
    # A non-string status (possibly unhashable) is unknown, never a raise.
    status = raw_status if isinstance(raw_status, str) else None
    if status in ("renamed", "copied") and previous is None:
        unsafe.append(f"{_show(raw_path)} {status} with no previous path")
    unsafe.extend(_mode_problems(changed, raw_path))
    problems = []
    if status not in STATUSES:
        problems.append(f"status {_show(raw_status)}")
    lines = 0
    for field in ("additions", "deletions"):
        value = getattr(changed, field, None)
        if _is_count(value):
            lines += value
        else:
            problems.append(f"{field} {_show(value)}")
    has_patch = getattr(changed, "has_patch", None)
    if not isinstance(has_patch, bool):
        problems.append(f"has_patch {_show(has_patch)}")
        has_patch = None
    if not isinstance(raw_path, str):
        problems.append(f"path {_show(raw_path)}")
    return _File(
        path=paths[0],
        paths=tuple(paths),
        unsafe=tuple(unsafe),
        status=status,
        lines=lines,
        has_patch=has_patch,
        problems=tuple(problems),
    )


def _mode_problems(changed: Any, raw_path: Any) -> list[str]:
    """Only a regular file that stays regular may rate below HIGH."""
    mode = getattr(changed, "mode", None)
    previous = getattr(changed, "previous_mode", None)
    kind = _MODE_TYPES.get(mode) if isinstance(mode, str) else None
    found = []
    if kind != "regular":
        found.append(f"{_show(raw_path)} mode {_show(mode)} ({kind or 'unknown'})")
    if previous is not None:
        before = _MODE_TYPES.get(previous) if isinstance(previous, str) else None
        if before != kind:
            found.append(
                f"{_show(raw_path)} mode {_show(previous)} -> {_show(mode)}"
                " changes type"
            )
    return found


def _high_path_reasons(inp: RiskInput, files: list[_File]) -> list[Reason]:
    unsafe = [raw for f in files for raw in f.unsafe]
    configured = _sequence(inp.high_paths)
    if configured is None or not all(
        isinstance(p, str) and _safe_glob(p) for p in configured
    ):
        unsafe.append(f"configured HIGH set unreadable: {_show(inp.high_paths)}")
        configured = ()  # match only the floor
    reasons = []
    if unsafe:
        reasons.append(Reason(UNSAFE_PATH_CODE, Risk.HIGH, "; ".join(unsafe)))
    paths = [path for f in files for path in f.paths if path]
    for pattern in dict.fromkeys((*HIGH_FLOOR, *configured)):
        hits = [path for path in paths if glob_match(pattern, path)]
        if hits:
            reasons.append(Reason(f"high-path:{pattern}", Risk.HIGH, ", ".join(hits)))
    return reasons


def _c2_contradictions(files: list[_File]) -> list[str]:
    """The diff contradicts C2 ("deterministic and trivially reversible")."""
    found = []
    structural = [
        f.path
        for f in files
        if f.status in _STRUCTURAL or (len(f.paths) > 1 and f.paths[1] != f.paths[0])
    ]
    if structural:
        found.append(f"removed, renamed, copied or changed: {', '.join(structural)}")
    paths = [path for f in files for path in f.paths]
    schemas = [path for path in paths if path.casefold().endswith(".schema.json")]
    if schemas:
        found.append(f"schema changed: {', '.join(schemas)}")
    # Only `plugins` is folded: plugins/Foo and plugins/foo are two plugins.
    plugins = {
        parts[1]
        for parts in (path.split("/") for path in paths)
        if len(parts) >= 3 and parts[0].casefold() == "plugins"
    }
    if len(plugins) > 1:
        found.append(f"more than one plugin: {', '.join(sorted(plugins))}")
    return found


def _class_reasons(inp: RiskInput, files: list[_File]) -> list[Reason]:
    rank = _CLASS_RANK.get(inp.work_class) if isinstance(inp.work_class, str) else None
    if rank is None:
        return [
            Reason("class-missing", Risk.MED, f"work class {_show(inp.work_class)}")
        ]
    reasons = []
    rung = inp.rung
    known = isinstance(rung, int) and not isinstance(rung, bool) and rung in set(Rung)
    if not known or rung == Rung.OFF or rank > rung:
        shown = Rung(rung).name if known else f"{_show(rung)} (unknown)"
        detail = f"{inp.work_class} above rung {shown}"
        reasons.append(Reason("class-above-rung", Risk.MED, detail))
    if rank <= _C2_RANK:
        contradictions = _c2_contradictions(files)
        if rank == _C1_RANK:
            contradictions.insert(0, "C1 work produces no pull request")
        if contradictions:
            reasons.append(
                Reason("class-contradicted", Risk.MED, "; ".join(contradictions))
            )
    blast = inp.blast_radius
    if rank > _C2_RANK and not (
        isinstance(blast, str) and blast.casefold() == _LOW_BLAST
    ):
        rated = isinstance(blast, str) and blast.strip()
        detail = f"rated {_show(blast)}, not LOW" if rated else "has no rating"
        reasons.append(
            Reason("blast-radius-missing", Risk.MED, f"{inp.work_class} {detail}")
        )
    return reasons


def _size_reasons(inp: RiskInput, files: list[_File] | None) -> list[Reason]:
    reasons = []
    incomplete = []
    if files is None:
        incomplete.append(f"file listing unreadable: {_show(inp.files)}")
        files = []
    elif not files:
        incomplete.append("file listing is empty")
    if inp.files_complete is not True:
        incomplete.append(f"listing not read to its end ({_show(inp.files_complete)})")
    incomplete.extend(f"{f.path or '?'}: {p}" for f in files for p in f.problems)
    if incomplete:
        reasons.append(Reason("files-incomplete", Risk.MED, "; ".join(incomplete)))
    lines = sum(f.lines for f in files)
    limit = inp.max_changed_lines
    if not _is_count(limit):
        reasons.append(
            Reason("lines-over", Risk.MED, f"limit unreadable: {_show(limit)}")
        )
    elif lines > limit:
        reasons.append(Reason("lines-over", Risk.MED, f"{lines} > {limit}"))
    if len(files) > MAX_FILES:
        reasons.append(Reason("files-over", Risk.MED, f"{len(files)} > {MAX_FILES}"))
    for path in dict.fromkeys(f.path for f in files if f.has_patch is False):
        reasons.append(
            Reason(f"no-patch:{path}", Risk.MED, "no patch: line counts unknown")
        )
    return reasons


def _lane_reasons(raw_lanes: Any) -> list[Reason]:
    lanes = _sequence(raw_lanes) or ()
    reasons = []
    for name, (finding_code, finding_severity) in LANES.items():
        entries = [lane for lane in lanes if getattr(lane, "lane", None) == name]
        if len(entries) != 1:
            detail = "missing" if not entries else "more than one evidence entry"
            reasons.append(Reason(f"evidence-unbound:{name}", Risk.MED, detail))
            continue
        lane = entries[0]
        count = getattr(lane, "open_findings", None)
        unbound_reason = getattr(lane, "unbound_reason", None)
        bound = getattr(lane, "bound", None) is True
        if not bound or unbound_reason is not None or not _is_count(count):
            parts = [] if bound else ["not bound"]
            if isinstance(unbound_reason, str) and unbound_reason:
                parts.append(unbound_reason)
            elif unbound_reason is not None:
                parts.append(f"unbound_reason {_show(unbound_reason)}")
            if bound and not _is_count(count):
                parts.append(f"open_findings {_show(count)}")
            reasons.append(
                Reason(f"evidence-unbound:{name}", Risk.MED, ": ".join(parts))
            )
        elif count > 0:
            reasons.append(Reason(finding_code, finding_severity, f"{count} open"))
    return reasons


def _merge_by_code(reasons: list[Reason]) -> list[Reason]:
    """One reason per code: the first, at the highest severity seen, with each
    distinct later detail appended."""
    merged: dict[str, Reason] = {}
    for reason in reasons:
        seen = merged.setdefault(reason.code, reason)
        if seen is reason:
            continue
        detail = seen.detail
        if reason.detail not in detail.split("; "):
            detail = f"{detail}; {reason.detail}"
        severity = max(seen.severity, reason.severity)
        merged[reason.code] = Reason(reason.code, Risk(severity), detail)
    return list(merged.values())


def _score(inp: RiskInput) -> RiskResult:
    raw_files = _sequence(inp.files)
    files = None if raw_files is None else [_check_file(f) for f in raw_files]
    reasons = _merge_by_code(
        [
            *_class_reasons(inp, files or []),
            *_size_reasons(inp, files),
            *_lane_reasons(inp.lanes),
            *_high_path_reasons(inp, files or []),
        ]
    )
    reasons.sort(key=lambda reason: (-reason.severity, reason.code))
    worst = max((reason.severity for reason in reasons), default=Risk.LOW)
    return RiskResult(Risk(worst), tuple(reasons))


def score(inp: RiskInput) -> RiskResult:
    """Never raises: input the scorer cannot read at all is HIGH, any path."""
    try:
        return _score(inp)
    except Exception as exc:  # noqa: BLE001 - fail closed, never raise
        detail = f"scorer could not read its input: {type(exc).__name__}"
        return RiskResult(Risk.HIGH, (Reason(UNSAFE_PATH_CODE, Risk.HIGH, detail),))
