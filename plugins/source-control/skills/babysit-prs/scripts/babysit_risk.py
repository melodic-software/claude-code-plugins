#!/usr/bin/env python3
"""Diff risk scorer for the unattended merge path.

`score(RiskInput) -> RiskResult` is a pure function: no I/O, no GitHub calls.
The caller reads the PR, its linked issue's class, the base-SHA config and the
review-lane evidence, and hands them in; this module only judges them. Only a
LOW score may merge unattended, so every doubtful input rates MED or HIGH:
missing or unrecognised data is a miss, never a pass, and it never raises.

The HIGH path floor and the lane table are fixed here on purpose. A weaker value
could only come from a file a pull request can edit, and this module's own path
is in the floor, so a pull request cannot change the rule it is judged by. The
configured `merge.diff-check.denied-paths` is joined to the floor, never in
place of it. Every glob matches case-insensitively, because a lane host on a
case-insensitive filesystem treats `Claude.md` as `CLAUDE.md`.

Paths are normalised before matching (`\\` to `/`, empty and `.` segments
dropped, `..` resolved). A path that could still hide a floor path after that
(empty, absolute, escaping the root, or with a segment ending in `.` or a space,
which Windows strips) rates HIGH as `high-path:**`: it could be any path.
Malformed values have no code of their own in the contract, so each maps to the
nearest existing code: per-file data and the listing to `files-incomplete`, an
unknown rung to `class-above-rung` (read as off), an unreadable line limit to
`lines-over`, an unreadable configured HIGH set to `high-path:**`.
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
    """Order matches the `merge.rung` enum in pr-pipeline.schema.json."""

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

_CLASS_RANK = {"C1": 1, "C2": 2, "C3": 3, "C4": 4, "C5": 5}


def _is_count(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value >= 0


def _sequence(value: Any) -> tuple[Any, ...] | None:
    return tuple(value) if isinstance(value, (tuple, list)) else None


def normalize_path(path: Any) -> tuple[str, bool]:
    """Return (normalised path, safe). Unsafe means it could hide a floor path."""
    if not isinstance(path, str):
        return "", False
    raw = path.replace("\\", "/")
    safe = not raw.startswith("/")
    segments: list[str] = []
    for segment in raw.split("/"):
        if segment in ("", "."):
            continue
        if segment == "..":
            if segments:
                segments.pop()
            else:
                safe = False
            continue
        if segment.endswith((".", " ")):
            safe = False
        segments.append(segment)
    return "/".join(segments), safe and bool(segments)


def _normalize_glob(pattern: str) -> str:
    pattern = pattern.replace("\\", "/")
    while pattern.startswith(("./", "/")):
        pattern = pattern[2:] if pattern.startswith("./") else pattern[1:]
    return pattern


def _segment_regex(segment: str) -> str:
    out = []
    for char in segment:
        if char == "*":
            out.append("[^/]*")
        elif char == "?":
            out.append("[^/]")
        else:
            out.append(re.escape(char))
    return "".join(out)


def glob_regex(pattern: str) -> re.Pattern[str]:
    """Compile a path glob: `**` spans any number of segments, `*` and `?` stay
    within one. A pattern also covers everything under it, so `plugins/foo` and
    `plugins/foo/` both match `plugins/foo/x.md`. Matching is on the case-folded
    path."""
    folded = _normalize_glob(pattern).casefold()
    if folded.endswith("/"):
        folded += "**"
    segments = folded.split("/")
    parts = []
    for index, segment in enumerate(segments):
        last = index == len(segments) - 1
        if segment == "**":
            parts.append(".*" if last else "(?:[^/]+/)*")
        else:
            parts.append(_segment_regex(segment) + ("(?:/.*)?" if last else "/"))
    return re.compile("".join(parts))


@dataclass(frozen=True)
class _File:
    """A changed file after validation: normalised paths plus its problems."""

    path: str
    paths: tuple[str, ...]
    unsafe: tuple[str, ...]
    status: Any
    lines: int
    has_patch: bool
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
            unsafe.append(repr(raw))
    problems = []
    status = getattr(changed, "status", None)
    if status not in STATUSES:
        problems.append(f"status {status!r}")
    lines = 0
    for field in ("additions", "deletions"):
        value = getattr(changed, field, None)
        if _is_count(value):
            lines += value
        else:
            problems.append(f"{field} {value!r}")
    has_patch = getattr(changed, "has_patch", None)
    if not isinstance(has_patch, bool):
        problems.append(f"has_patch {has_patch!r}")
    if not isinstance(raw_path, str):
        problems.append(f"path {raw_path!r}")
    return _File(
        path=paths[0],
        paths=tuple(paths),
        unsafe=tuple(unsafe),
        status=status,
        lines=lines,
        has_patch=has_patch is True,
        problems=tuple(problems),
    )


def _high_path_reasons(inp: RiskInput, files: list[_File]) -> list[Reason]:
    unsafe = [raw for f in files for raw in f.unsafe]
    configured = _sequence(inp.high_paths)
    if configured is None or not all(isinstance(p, str) for p in configured):
        unsafe.append(f"configured HIGH set unreadable: {inp.high_paths!r}")
        configured = tuple(p for p in configured or () if isinstance(p, str))
    reasons = []
    if unsafe:
        reasons.append(Reason(UNSAFE_PATH_CODE, Risk.HIGH, "; ".join(unsafe)))
    paths = [path for f in files for path in f.paths if path]
    for pattern in dict.fromkeys((*HIGH_FLOOR, *configured)):
        regex = glob_regex(pattern)
        hits = [path for path in paths if regex.fullmatch(path.casefold())]
        if hits:
            reasons.append(Reason(f"high-path:{pattern}", Risk.HIGH, ", ".join(hits)))
    return reasons


def _c2_contradictions(files: list[_File]) -> list[str]:
    """The diff contradicts C2 ("deterministic and trivially reversible")."""
    found = []
    if any(
        f.status in _STRUCTURAL or (len(f.paths) > 1 and f.paths[1] != f.paths[0])
        for f in files
    ):
        found.append("removed, renamed, copied or changed file")
    paths = [path.casefold() for f in files for path in f.paths]
    if any(path.endswith(".schema.json") for path in paths):
        found.append("*.schema.json changed")
    plugins = {
        parts[1]
        for parts in (path.split("/") for path in paths)
        if len(parts) >= 3 and parts[0] == "plugins"
    }
    if len(plugins) > 1:
        found.append(f"more than one plugin: {', '.join(sorted(plugins))}")
    return found


def _class_reasons(inp: RiskInput, files: list[_File]) -> list[Reason]:
    rank = _CLASS_RANK.get(inp.work_class) if isinstance(inp.work_class, str) else None
    if rank is None:
        return [Reason("class-missing", Risk.MED, f"work class {inp.work_class!r}")]
    reasons = []
    rung = inp.rung
    known = isinstance(rung, int) and not isinstance(rung, bool) and rung in set(Rung)
    if not known or rung == Rung.OFF or rank > rung:
        detail = f"{inp.work_class} above rung {rung!r}" + (
            "" if known else " (unknown)"
        )
        reasons.append(Reason("class-above-rung", Risk.MED, detail))
    if rank <= Rung.C2:
        contradictions = _c2_contradictions(files)
        if contradictions:
            reasons.append(
                Reason("class-contradicted", Risk.MED, "; ".join(contradictions))
            )
    blast = inp.blast_radius
    if rank > Rung.C2 and not (isinstance(blast, str) and blast.strip()):
        reasons.append(
            Reason("blast-radius-missing", Risk.MED, f"{inp.work_class} has no rating")
        )
    return reasons


def _size_reasons(inp: RiskInput, files: list[_File] | None) -> list[Reason]:
    reasons = []
    incomplete = []
    if files is None:
        incomplete.append(f"file listing unreadable: {inp.files!r}")
        files = []
    elif not files:
        incomplete.append("file listing is empty")
    if inp.files_complete is not True:
        incomplete.append(f"listing not read to its end ({inp.files_complete!r})")
    incomplete.extend(f"{f.path or '?'}: {p}" for f in files for p in f.problems)
    if incomplete:
        reasons.append(Reason("files-incomplete", Risk.MED, "; ".join(incomplete)))
    lines = sum(f.lines for f in files)
    limit = inp.max_changed_lines
    if not _is_count(limit):
        reasons.append(Reason("lines-over", Risk.MED, f"limit unreadable: {limit!r}"))
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
        if getattr(lane, "bound", None) is not True or not _is_count(count):
            detail = getattr(lane, "unbound_reason", None) or "no bound finding count"
            reasons.append(Reason(f"evidence-unbound:{name}", Risk.MED, str(detail)))
        elif count > 0:
            reasons.append(Reason(finding_code, finding_severity, f"{count} open"))
    return reasons


def score(inp: RiskInput) -> RiskResult:
    raw_files = _sequence(inp.files)
    files = None if raw_files is None else [_check_file(f) for f in raw_files]
    reasons = [
        *_class_reasons(inp, files or []),
        *_size_reasons(inp, files),
        *_lane_reasons(inp.lanes),
        *_high_path_reasons(inp, files or []),
    ]
    reasons.sort(key=lambda reason: (-reason.severity, reason.code))
    worst = max((reason.severity for reason in reasons), default=Risk.LOW)
    return RiskResult(Risk(worst), tuple(reasons))
