#!/usr/bin/env python3
"""Diff risk scorer for the unattended merge path.

`score(RiskInput) -> RiskResult` is a pure function: no I/O, no GitHub calls.
The caller reads the PR, its linked issue's class, the base-SHA config and the
review-lane evidence, and hands them in; this module only judges them. Only a
LOW score may merge unattended, so every doubtful input rates MED or HIGH:
missing data is a miss, never a pass.

The HIGH path floor and the lane table are fixed here on purpose. A weaker value
could only come from a file a pull request can edit, and this module's own path
is in the floor, so a pull request cannot change the rule it is judged by. The
configured `merge.diff-check.denied-paths` is joined to the floor, never in
place of it. Every glob matches case-insensitively, because a lane host on a
case-insensitive filesystem treats `Claude.md` as `CLAUDE.md`.
"""

from __future__ import annotations

import enum
import re
from dataclasses import dataclass


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
    status: str  # added | modified | removed | renamed | copied | changed
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

_CLASS_RANK = {"C1": 1, "C2": 2, "C3": 3, "C4": 4, "C5": 5}


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
    within one. A trailing `/` means everything under that directory. Matching
    is on the case-folded path."""
    folded = pattern.casefold()
    if folded.endswith("/"):
        folded += "**"
    segments = folded.split("/")
    parts = []
    for index, segment in enumerate(segments):
        last = index == len(segments) - 1
        if segment == "**":
            parts.append(".*" if last else "(?:[^/]+/)*")
        else:
            parts.append(_segment_regex(segment) + ("" if last else "/"))
    return re.compile("".join(parts))


def _paths(files: tuple[ChangedFile, ...]) -> list[str]:
    out = []
    for changed in files:
        out.append(changed.path)
        if changed.previous_path:
            out.append(changed.previous_path)
    return out


def _high_path_reasons(inp: RiskInput) -> list[Reason]:
    paths = _paths(inp.files)
    reasons = []
    for pattern in dict.fromkeys((*HIGH_FLOOR, *inp.high_paths)):
        regex = glob_regex(pattern)
        hits = [path for path in paths if regex.fullmatch(path.casefold())]
        if hits:
            reasons.append(Reason(f"high-path:{pattern}", Risk.HIGH, ", ".join(hits)))
    return reasons


def _c2_contradictions(files: tuple[ChangedFile, ...]) -> list[str]:
    """The diff contradicts C2 ("deterministic and trivially reversible")."""
    found = []
    if any(
        f.status in ("removed", "renamed")
        or (f.previous_path and f.previous_path != f.path)
        for f in files
    ):
        found.append("removed or renamed file")
    paths = [path.casefold() for path in _paths(files)]
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


def _class_reasons(inp: RiskInput) -> list[Reason]:
    rank = _CLASS_RANK.get(inp.work_class or "")
    if rank is None:
        return [Reason("class-missing", Risk.MED, f"work class {inp.work_class!r}")]
    reasons = []
    rung = int(inp.rung)
    if rung == Rung.OFF or rank > rung:
        reasons.append(
            Reason("class-above-rung", Risk.MED, f"{inp.work_class} above rung {rung}")
        )
    if rank <= Rung.C2:
        contradictions = _c2_contradictions(inp.files)
        if contradictions:
            reasons.append(
                Reason("class-contradicted", Risk.MED, "; ".join(contradictions))
            )
    if rank > Rung.C2 and not (inp.blast_radius or "").strip():
        reasons.append(
            Reason("blast-radius-missing", Risk.MED, f"{inp.work_class} has no rating")
        )
    return reasons


def _size_reasons(inp: RiskInput) -> list[Reason]:
    reasons = []
    lines = sum(f.additions + f.deletions for f in inp.files)
    if lines > inp.max_changed_lines:
        reasons.append(
            Reason("lines-over", Risk.MED, f"{lines} > {inp.max_changed_lines}")
        )
    if len(inp.files) > MAX_FILES:
        reasons.append(
            Reason("files-over", Risk.MED, f"{len(inp.files)} > {MAX_FILES}")
        )
    if not inp.files_complete:
        reasons.append(
            Reason("files-incomplete", Risk.MED, "file listing not read to its end")
        )
    for path in dict.fromkeys(f.path for f in inp.files if not f.has_patch):
        reasons.append(
            Reason(f"no-patch:{path}", Risk.MED, "no patch: line counts unknown")
        )
    return reasons


def _lane_reasons(lanes: tuple[LaneEvidence, ...]) -> list[Reason]:
    reasons = []
    for name, (finding_code, finding_severity) in LANES.items():
        entries = [lane for lane in lanes if lane.lane == name]
        if len(entries) != 1:
            detail = "missing" if not entries else "more than one evidence entry"
            reasons.append(Reason(f"evidence-unbound:{name}", Risk.MED, detail))
            continue
        lane = entries[0]
        if not lane.bound or lane.open_findings is None or lane.open_findings < 0:
            detail = lane.unbound_reason or "no bound finding count"
            reasons.append(Reason(f"evidence-unbound:{name}", Risk.MED, detail))
        elif lane.open_findings > 0:
            reasons.append(
                Reason(finding_code, finding_severity, f"{lane.open_findings} open")
            )
    return reasons


def score(inp: RiskInput) -> RiskResult:
    reasons = [
        *_class_reasons(inp),
        *_size_reasons(inp),
        *_lane_reasons(inp.lanes),
        *_high_path_reasons(inp),
    ]
    reasons.sort(key=lambda reason: (-reason.severity, reason.code))
    worst = max((reason.severity for reason in reasons), default=Risk.LOW)
    return RiskResult(Risk(worst), tuple(reasons))
