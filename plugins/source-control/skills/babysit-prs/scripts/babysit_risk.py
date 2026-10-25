#!/usr/bin/env python3
"""Diff risk scorer for the unattended merge path.

`score(RiskInput) -> RiskResult` is a pure function: no I/O, no GitHub calls.
The caller reads the PR, the base-SHA config and the review-lane evidence, and
hands them in; this module only judges them. No work class is read. A LOW
score merges unattended, and so does a MED one whose every reason is a size or
reported review-finding reason (`holds`); every other reason holds.
So every doubtful
input rates a holding reason: missing or unrecognized data is a miss, never a
pass, and it never raises: input it cannot read at all rates HIGH as
`high-path:**`. Inputs are plain built-in
types (str, int, bool, None, list, tuple) built from parsed JSON; subclasses
that override their own behavior are out of scope. A count outside
0..10**9 is malformed. Each reason code appears once.

The HIGH path floor and the lane table are fixed here, never read from
configuration. The floor is empty (owner direction 2026-10-24): no path rates
HIGH for being trusted alone, and the two review lanes, which are the gate,
judge it, except the cost and trusted-actor holds below. The configured
`merge.diff-check.denied-paths` rate HIGH. Every glob matches
case-insensitively, because a lane host on a case-insensitive filesystem
treats `Codeowners` as `CODEOWNERS`.
With the floor switch on (`high_floor`), a
plugins/<plugin>/.claude-plugin/plugin.json or the top-level
.claude-plugin/marketplace.json is compared base against head instead, and a
change that installs or runs something new rates HIGH as
`manifest-review-required`: in plugin.json a differing `_EXECUTABLE_KEYS` value
or `experimental.monitors`, in marketplace.json a plugin entry added, removed
or renamed, a changed entry `source`, or a changed marketplace `name`. A
manifest removed, renamed or copied, or whose side cannot be read or parsed,
or repeats a key, holds; an added plugin.json is compared with `{}`.

A change that adds or widens an entry in the trusted-actor list
(`TRUSTED_ACTORS_PATH`) rates HIGH as `trust-gate:trusted-actors` in every
lane, whatever the floor switch and `floor_exempt` say, and waits for the
owner. Base and head text are compared: only removing entries passes; an
added or changed entry, any other key changed, a side that cannot be read or
parsed or repeats a key, and an added, removed, renamed or copied file hold.

A review finding holds only as a CRITICAL security finding
(`security-finding`): the security lane's `blocking_findings`. Every other open
finding, a code-review finding or an IMPORTANT or SUGGESTION security one, is
reported as a MED `findings:<lane>` reason that does not hold (owner decisions
Q25, Q33 and Q693). A cost increase holds through `cost-review-required` and a
trusted-actor widening through `trust-gate:trusted-actors`.

A change that could add or raise a charge rates HIGH as `cost-review-required`
in every lane, floor or not and whatever `floor_exempt` says (owner rule,
2026-10-22): any `COST_PATHS` file (Pulumi, Terraform, Bicep) or file under a
`RiskInput.pulumi_dirs` directory, and every file when `pulumi_dirs` is None
(the base tree was not listed); a file renamed or copied into a workflow or
`pr-pipeline.yaml` path from outside one; a `.github/workflows/` file whose
patch adds a `_COST_WORKFLOW_LINE` (a `cron` key in any spelling, `--model`,
`--max-turns`), or, unless `RiskInput.public` is True, a `runs-on:`, `windows`
or `macos` line; that gains a `_SECRET_REF`, a `_MODEL_ACTION` or a
`_MODEL_PACKAGE` run, counted against the lines it removes so a move or repin
is not new; that adds a `timeout-minutes` or `leg-timeout-minutes` above every
one it removes, when its head text (`contents`) names a model leg or could not
be read; or that gains a runner value (head text against base text, and added
inline `runs-on:` lines) that is not `_FREE_RUNNER` on a public repository, or
any on another; and a `pr-pipeline.yaml` change with any added or removed line
off `_SAFE_PIPELINE_LINE`, unless it only edits trailing comments. A workflow
or pipeline file with no patch holds. Only `RiskInput.cost_decision`, an owner
decision the caller verified, clears it.

Paths are normalized before matching (`\\` to `/`, empty and `.` segments
dropped). A path is safe only when every `/`-separated segment is non-empty,
uses only `[A-Za-z0-9._-]` and does not end in `.` (Windows strips it); every
tracked path in this repository passes. Any other path rates HIGH as
`high-path:**`, because it could alias any path: `..`, `:` (an NTFS stream),
`~1` (an 8.3 short name), whitespace, control or non-ASCII characters. So does
a rename or copy with no previous path, a modification, change, rename or copy with no
previous mode, and a file whose git mode is missing,
unknown, a symlink or submodule, or changes type. A configured glob outside the
same set (plus `*` and whole `**` segments), read exactly as written, makes the
configured HIGH set unreadable, and then only the floor is matched.
Malformed values have no code of their own in the contract, so each maps to the
nearest existing code: per-file data and the listing to `files-incomplete`, an
unreadable line limit to `lines-over`, and an unreadable configured HIGH set or
file mode to `high-path:**`.
"""

from __future__ import annotations

import enum
import json
import re
from collections import Counter
from dataclasses import dataclass
from typing import Any


class Risk(enum.IntEnum):
    """Ordered, so the score is the max() of the reasons' severities."""

    LOW = 0
    MED = 1
    HIGH = 2


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
    # The base-side mode. Required for a modified, changed, renamed or copied file. The
    # caller passes None for an absent side; "000000" (git's absent mode) is
    # read as absent and accepted only for an added file.
    previous_mode: str | None = None
    # The files API's unified patch text, when it sent one (None otherwise).
    patch: str | None = None
    # A manifest's or workflow's (base, head) text, None for an absent side,
    # read by the caller; contents_error says why it could not.
    contents: tuple[str | None, str | None] | None = None
    contents_error: str | None = None


@dataclass(frozen=True)
class LaneEvidence:
    lane: str  # "claude-review" | "claude-security-review"
    bound: bool  # the evidence binding held on the pinned SHA
    unbound_reason: str | None
    open_findings: int | None  # None when not bound
    # Every open finding is one a clean whole review of the head closes: none
    # was reported at the head, no whole review of it is recorded, and no
    # lane thread is unresolved.
    whole_review_clears: bool = False
    # The security lane's open findings that hold the merge (CRITICAL, read
    # by babysit_review_evidence.py); None when every one does. A
    # claude-review finding never holds, whatever this says.
    blocking_findings: int | None = None


@dataclass(frozen=True)
class RiskInput:
    files: tuple[ChangedFile, ...]
    files_complete: bool  # the listing was read to its end
    max_changed_lines: int | None  # merge.diff-check.max-changed-lines at the base SHA
    high_paths: tuple[str, ...]  # configured denied paths, joined to HIGH_FLOOR
    lanes: tuple[LaneEvidence, ...]
    # The switches the pr-merge lane may turn off (merge.diff-check); the
    # defaults keep every check. An unset line cap is MED unless optional.
    high_floor: bool = True
    max_changed_files: int | None = 8  # None: no cap
    lines_optional: bool = False
    # The repository is public, where standard hosted runners are free; any
    # other value reads every runs-on and macOS line as a charge.
    public: bool | None = None
    # The owner decision the caller verified for a `cost-review-required`
    # change (its comment URL); None keeps the hold.
    cost_decision: str | None = None
    # Directories holding a Pulumi.yaml at the base ("" for the root): any
    # change under one is infrastructure as code.
    pulumi_dirs: tuple[str, ...] | None = ()
    # Paths only a trusted author's own commits touched: the path floor and
    # the manifest review leave them out (owner decision 2026-10-22).
    floor_exempt: frozenset[str] = frozenset()


@dataclass(frozen=True)
class Reason:
    code: str
    severity: Risk
    detail: str


@dataclass(frozen=True)
class RiskResult:
    score: Risk  # max(reason.severity), LOW when no reason
    reasons: tuple[Reason, ...]  # sorted by severity desc, then code


# No path holds for being trusted alone (owner direction 2026-10-24): the
# review lanes judge it, and the trust gate holds a trusted-actor widening.
HIGH_FLOOR: tuple[str, ...] = ()

# plugin.json keys whose values Claude Code runs or reads as run config.
_EXECUTABLE_KEYS = ("hooks", "mcpServers", "lspServers", "monitors")

# Lane -> (code, severity) for an open finding on that lane. Only the
# security lane's blocking findings hold (`LaneEvidence.blocking_findings`);
# claude-review's code is reported and never holds (`MERGEABLE_MED`). Both
# lanes are required: a lane absent from the input is unbound.
LANES: dict[str, tuple[str, Risk]] = {
    "claude-review": ("findings:claude-review", Risk.MED),
    "claude-security-review": ("security-finding", Risk.HIGH),
}
_HOLDING_LANE = "claude-security-review"
# The security lane's open findings below the holding tier: reported only.
REPORTED_SECURITY_CODE = "findings:claude-security-review"

TRUST_GATE_PREFIX = "trust-gate:"
TRUST_GATE_CODE = f"{TRUST_GATE_PREFIX}trusted-actors"
TRUSTED_ACTORS_PATH = ".github/standards/trusted-actors/trusted-actors.json"

# GitHub's documented pull request file statuses.
STATUSES = frozenset(
    {"added", "removed", "modified", "renamed", "copied", "changed", "unchanged"}
)

UNSAFE_PATH_CODE = "high-path:**"

# Every tracked path segment uses only these characters. Anything else (a `:`,
# a `~`, whitespace, a control or non-ASCII character) could alias a floor path
# on some filesystem, so it is unsafe rather than enumerated.
_SAFE_SEGMENT = re.compile(r"[A-Za-z0-9._-]+")
_SAFE_GLOB_SEGMENT = re.compile(r"[A-Za-z0-9._*-]+")

_ABSENT_MODE = "000000"
_TWO_SIDED = frozenset(
    {"modified", "changed", "renamed", "copied"}
)  # need a previous mode
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
    """Return (normalized path, safe). Unsafe means it could hide a floor path."""
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
    only as a whole segment. A bare `**` names every path, which is no denied
    path at all, so it is unreadable too."""
    if pattern.endswith("/"):
        pattern = pattern[:-1]
    return pattern != "**" and all(
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
    """A changed file after validation: normalized paths plus its problems."""

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
    unsafe.extend(_mode_problems(changed, raw_path, status))
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


def _mode_problems(changed: Any, raw_path: Any, status: str | None) -> list[str]:
    """Only a regular file that stays regular may rate below HIGH."""
    mode = getattr(changed, "mode", None)
    previous = getattr(changed, "previous_mode", None)
    kind = _MODE_TYPES.get(mode) if isinstance(mode, str) else None
    found = []
    if kind != "regular":
        found.append(f"{_show(raw_path)} mode {_show(mode)} ({kind or 'unknown'})")
    if previous == _ABSENT_MODE:
        if status != "added":
            found.append(f"{_show(raw_path)} {status} with an absent previous mode")
    elif previous is None:
        if status in _TWO_SIDED:
            found.append(f"{_show(raw_path)} {status} with no previous mode")
    else:
        before = _MODE_TYPES.get(previous) if isinstance(previous, str) else None
        if before is None:
            found.append(f"{_show(raw_path)} malformed previous mode {_show(previous)}")
        elif before != kind:
            found.append(
                f"{_show(raw_path)} mode {_show(previous)} -> {_show(mode)}"
                " changes type"
            )
    return found


def _readable_globs(value: Any, unsafe: list[str]) -> tuple[str, ...]:
    globs = _sequence(value)
    if globs is None or not all(isinstance(p, str) and _safe_glob(p) for p in globs):
        unsafe.append(f"configured HIGH set unreadable: {_show(value)}")
        return ()  # match only the floor
    return globs


_MANIFEST_CODE = "manifest-review-required"


def is_manifest_path(path: str) -> bool:
    """plugins/<plugin>/.claude-plugin/plugin.json or the top-level
    .claude-plugin/marketplace.json, matched case-sensitively."""
    parts = path.split("/")
    return parts == [".claude-plugin", "marketplace.json"] or (
        len(parts) == 4
        and parts[0] == "plugins"
        and parts[2:] == [".claude-plugin", "plugin.json"]
    )


def _no_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    keys = [k for k, _ in pairs]
    if len(set(keys)) != len(keys):
        raise ValueError("duplicate key")
    return dict(pairs)


def _manifest(text: Any) -> dict[str, Any] | None:
    """The parsed object, None when unreadable, malformed or a key repeats."""
    if not isinstance(text, str):
        return None
    try:
        data = json.loads(text, object_pairs_hook=_no_duplicates)
    except (ValueError, RecursionError):
        return None
    return data if isinstance(data, dict) else None


def _canonical(data: Any, key: str) -> str | None:
    """A key's value as sorted JSON, so `false` and `0` differ; None when
    absent or `data` is no object."""
    if not isinstance(data, dict) or key not in data:
        return None
    return json.dumps(data[key], sort_keys=True)


def _plugin_changes(base: dict[str, Any], head: dict[str, Any]) -> list[str]:
    """The executable keys whose value differs."""
    found = [k for k in _EXECUTABLE_KEYS if _canonical(base, k) != _canonical(head, k)]
    before, after = base.get("experimental"), head.get("experimental")
    if _canonical(before, "monitors") != _canonical(after, "monitors"):
        found.append("experimental.monitors")
    return found


def _entries(data: dict[str, Any]) -> dict[str, Any] | None:
    """`plugins` by name, None unless a list of uniquely named objects."""
    plugins = data.get("plugins", [])
    if not isinstance(plugins, list):
        return None
    named = {
        e["name"]: e
        for e in plugins
        if isinstance(e, dict) and isinstance(e.get("name"), str)
    }
    return named if len(named) == len(plugins) else None


def _marketplace_changes(base: dict[str, Any], head: dict[str, Any]) -> list[str]:
    """A plugin added, removed or renamed (a rename reads as both), a changed
    entry `source`, and a changed marketplace `name`."""
    found = ["name"] if _canonical(base, "name") != _canonical(head, "name") else []
    old, new = _entries(base), _entries(head)
    if old is None or new is None:
        return [*found, "plugins is not a list of uniquely named entries"]
    for name in sorted(set(old) | set(new)):
        if name not in new:
            found.append(f"plugins[{name}] removed")
        elif name not in old:
            found.append(f"plugins[{name}] added")
        elif _canonical(old[name], "source") != _canonical(new[name], "source"):
            found.append(f"plugins[{name}].source")
    return found


def _manifest_changes(f: _File, raw: Any) -> list[str]:
    """What in a manifest change needs review (`_MANIFEST_CODE`)."""
    contents = getattr(raw, "contents", None)
    if f.status not in ("modified", "added") or f.paths != (f.path,):
        return [f"{f.status} manifest"]
    if getattr(raw, "contents_error", None) is not None or not (
        isinstance(contents, tuple) and len(contents) == 2
    ):
        return ["contents unreadable"]
    before = "{}" if f.status == "added" else contents[0]
    base, head = _manifest(before), _manifest(contents[1])
    if base is None or head is None:
        return ["unreadable, malformed or a repeated key"]
    if f.path.endswith("marketplace.json"):
        return _marketplace_changes(base, head)
    return _plugin_changes(base, head)


def _high_path_reasons(
    inp: RiskInput, files: list[_File], raw_files: list[Any]
) -> list[Reason]:
    unsafe = [raw for f in files for raw in f.unsafe]
    configured = _readable_globs(inp.high_paths, unsafe)
    on = inp.high_floor is not False
    reasons = []
    if unsafe:
        reasons.append(Reason(UNSAFE_PATH_CODE, Risk.HIGH, "; ".join(unsafe)))
    paths = [
        path for f in files for path in f.paths if path and path not in inp.floor_exempt
    ]
    for pattern in dict.fromkeys((*(HIGH_FLOOR if on else ()), *configured)):
        hits = [path for path in paths if glob_match(pattern, path)]
        if hits:
            reasons.append(Reason(f"high-path:{pattern}", Risk.HIGH, ", ".join(hits)))
    review = [
        f"{f.path}: {', '.join(changes)}"
        for f, raw in zip(files, raw_files)
        if on
        and is_manifest_path(f.path)
        and f.path not in inp.floor_exempt
        and (changes := _manifest_changes(f, raw))
    ]
    if review:
        reasons.append(Reason(_MANIFEST_CODE, Risk.HIGH, "; ".join(review)))
    return reasons


def is_trusted_actors_path(path: str) -> bool:
    return glob_match(TRUSTED_ACTORS_PATH, path)


def _actors_widened(f: _File, raw: Any) -> str | None:
    """Why a trusted-actor list change widens trust, None when it only
    removes entries."""
    if f.status != "modified" or len(f.paths) != 1:
        return f"{f.status} trusted-actor list"
    contents = getattr(raw, "contents", None)
    if getattr(raw, "contents_error", None) is not None or not (
        isinstance(contents, tuple) and len(contents) == 2
    ):
        return "contents unreadable"
    base, head = _manifest(contents[0]), _manifest(contents[1])
    if base is None or head is None:
        return "unreadable, malformed or a repeated key"
    old, new = base.get("actors"), head.get("actors")
    if not isinstance(old, list) or not isinstance(new, list):
        return "actors is not a list"
    if {k: v for k, v in base.items() if k != "actors"} != {
        k: v for k, v in head.items() if k != "actors"
    }:
        return "a key other than actors changed"
    gained = Counter(json.dumps(e, sort_keys=True) for e in new)
    gained.subtract(json.dumps(e, sort_keys=True) for e in old)
    added = sorted(e for e, n in gained.items() if n > 0)
    return f"entries added or changed: {', '.join(added)}" if added else None


def _trust_gate_reasons(files: list[_File], raw_files: list[Any]) -> list[Reason]:
    found = []
    for f, raw in zip(files, raw_files):
        if any(is_trusted_actors_path(p) for p in f.paths if p):
            why = _actors_widened(f, raw)
            if why:
                found.append(f"{f.path}: {why}")
    if not found:
        return []
    detail = "; ".join(found) + "; the owner merges it"
    return [Reason(TRUST_GATE_CODE, Risk.HIGH, detail)]


COST_CODE = "cost-review-required"
# Infrastructure as code: any change can add or resize a billed resource.
COST_PATHS: tuple[str, ...] = (
    "**/Pulumi.yaml",
    "**/Pulumi.*.yaml",
    "**/*.tf",
    "**/*.tfvars",
    "**/*.bicep",
    "**/*.bicepparam",
)
_WORKFLOWS = (".github/workflows/*.yml", ".github/workflows/*.yaml")
_PIPELINE_CONFIG = "**/pr-pipeline.yaml"
# Added workflow lines that can charge in any repository: a schedule in any
# YAML or JSON spelling (a scheduled lane spends model credits) and a model or
# turn flag.
_COST_WORKFLOW_LINE = re.compile(
    r"\bcron\s*:|[\"']cron[\"']\s*:|--model\b|--max-turns\b", re.IGNORECASE
)
# Standard hosted runners are free only on public repositories, so on any
# other a runs-on line or a Windows or macOS label (a matrix value) charges.
_COST_PRIVATE_LINE = re.compile(r"\bruns-on\s*:|\bmacos\b|\bwindows\b", re.IGNORECASE)
# Runner labels free on a public repository: GitHub's standard hosted labels
# and the self-hosted managed labels (`.github/standards/runner-policy`). A
# list holding `self-hosted` targets a self-hosted runner, which is free.
_FREE_RUNNER = re.compile(
    r"(?:ubuntu|windows|macos)-(?:latest|[0-9]+(?:\.[0-9]+)?)(?:-arm)?|windows-11-arm"
    r"|(?:melodic|kyle)-(?:[a-z0-9]+-)*ubuntu-24\.04-x64(?:-[a-z0-9-]+)?",
    re.IGNORECASE,
)
_RUNS_ON = re.compile(r"^(\s*)-?\s*runs-on\s*:\s*(.*)$")


def _scalar(value: str) -> str:
    return value.split(" #", 1)[0].strip().strip("'\"")


def _labels(value: str) -> list[str]:
    value = _scalar(value)
    if value.startswith("[") and value.endswith("]"):
        return [_scalar(v) for v in value[1:-1].split(",") if v.strip()]
    return [value] if value else []


def _runner_values(text: str) -> list[str]:
    """Each runs-on value in workflow text: an inline label or list, and a
    block's list items and `group:`/`labels:` entries (as `group:<name>`)."""
    values: list[str] = []
    lines = text.split("\n")
    for i, line in enumerate(lines):
        m = _RUNS_ON.match(line)
        if not m:
            continue
        if _scalar(m[2]):
            values.append(_scalar(m[2]))
            continue
        indent = len(m[1])
        for inner in lines[i + 1 :]:
            if inner.strip() and len(inner) - len(inner.lstrip()) <= indent:
                break
            item = inner.strip()
            if item.startswith("- "):
                values.append(_scalar(item[2:]))
            elif item.startswith("group:"):
                values.append("group:" + _scalar(item[6:]))
            elif item.startswith("labels:"):
                values.append(_scalar(item[7:]))
    return values


def _free(value: str) -> bool:
    labels = _labels(value)
    if "self-hosted" in (label.casefold() for label in labels):
        return True
    return bool(labels) and all(_FREE_RUNNER.fullmatch(label) for label in labels)


def _new_runners(raw: Any, added: list[str], public: bool) -> list[str]:
    """Runner values the change adds that are not free: from the head text
    against the base text when both were read, and from added inline runs-on
    lines. Unread text and an added block holds."""
    contents = getattr(raw, "contents", None)
    pair = contents if isinstance(contents, tuple) and len(contents) == 2 else None
    base, head = pair if pair else (None, None)
    gained: Counter[str] = Counter()
    if isinstance(head, str):
        gained.update(_runner_values(head))
        gained.subtract(_runner_values(base if isinstance(base, str) else ""))
    found = [v for v, n in gained.items() if n > 0]
    for line in added:
        m = _RUNS_ON.match(line)
        if m and _scalar(m[2]):
            found.append(_scalar(m[2]))
        elif m and not isinstance(head, str):
            found.append("runs-on block in unread text")
    return sorted({v for v in found if not (public and _free(v))})


# The pr-pipeline.yaml lines a change may touch without moving spend: blank and
# comment lines and a `description:` or `title:` value. Any other added or
# removed line holds, unless the change only edits trailing comments (the same
# lines with the comments stripped).
_SAFE_PIPELINE_LINE = re.compile(
    r"\s*(?:#.*)?|\s*(?:description|title)\s*:(?:\s.*)?", re.IGNORECASE
)
# Any secrets reference: `secrets.NAME`, `secrets['NAME']`, the whole
# `secrets` context, and `secrets: inherit`.
_SECRET_REF = re.compile(
    r"\bsecrets\s*(?:\.\s*[A-Za-z0-9_]+|\[[^\]]*\])|\bsecrets\b(?=\s*\))"
    r"|\bsecrets\s*:\s*inherit\b",
    re.IGNORECASE,
)
# A model leg: a claude-code-* action or image, run-claude-cli, or the
# Claude Code npm package on a run line.
_MODEL_ACTION_NAME = re.compile(
    r"run-claude-cli|claude-code[\w-]*|@anthropic-ai/claude-code", re.IGNORECASE
)
_MODEL_ACTION = re.compile(
    r"\buses\s*:\s*['\"]?([^@\s'\"]*(?:run-claude-cli|claude-code[\w-]*)[^@\s'\"]*)",
    re.IGNORECASE,
)
_MODEL_PACKAGE = re.compile(r"@anthropic-ai/claude-code\b", re.IGNORECASE)
_TIMEOUT = re.compile(r"^\s*(?:leg-)?timeout-minutes\s*:\s*['\"]?([0-9]+)")


def is_workflow_path(path: str) -> bool:
    return any(glob_match(g, path) for g in _WORKFLOWS)


def _patch_lines(patch: Any) -> tuple[list[str], list[str]] | None:
    """(added, removed) line texts of a unified patch, None when unreadable."""
    if not isinstance(patch, str):
        return None
    added, removed = [], []
    for line in patch.split("\n"):
        if line.startswith("+") and not line.startswith("+++"):
            added.append(line[1:])
        elif line.startswith("-") and not line.startswith("---"):
            removed.append(line[1:])
    return added, removed


def _unsafe_pipeline_lines(patch: str) -> list[str]:
    """The changed pr-pipeline.yaml lines off `_SAFE_PIPELINE_LINE`. A run of
    removed lines and the added lines that follow it pass together only when
    they are the same lines, in order, once trailing comments are stripped, so
    a value moved between two places in the file still holds."""

    def unsafe(lines: list[str]) -> list[str]:
        return [
            line.split(" #", 1)[0].rstrip()
            for line in lines
            if not _SAFE_PIPELINE_LINE.fullmatch(line)
        ]

    found: list[str] = []
    removed: list[str] = []
    added: list[str] = []

    def close() -> None:
        lost, gained = unsafe(removed), unsafe(added)
        if lost != gained:
            found.extend(line.strip() for line in lost + gained)
        removed.clear()
        added.clear()

    for line in patch.split("\n"):
        if line.startswith("-") and not line.startswith("---"):
            if added:
                close()
            removed.append(line[1:])
        elif line.startswith("+") and not line.startswith("+++"):
            added.append(line[1:])
        else:
            close()
    close()
    return found


def _net_added(
    pattern: re.Pattern[str], added: list[str], removed: list[str]
) -> list[str]:
    """Each match `added` gains over `removed`, so a moved or repinned line
    is not new."""
    gained = Counter(
        re.sub(r"\s+", "", m).casefold()
        for line in added
        for m in pattern.findall(line)
    )
    gained.subtract(
        re.sub(r"\s+", "", m).casefold()
        for line in removed
        for m in pattern.findall(line)
    )
    return sorted(m for m, n in gained.items() if n > 0)


def _raised_timeouts(
    f: _File, raw: Any, added: list[str], removed: list[str]
) -> list[str]:
    """Timeouts on a workflow that starts a model leg (or whose head text could
    not be read) that the patch adds above every value it removes."""
    new = [int(m[1]) for line in added if (m := _TIMEOUT.match(line))]
    if not new:
        return []
    contents = getattr(raw, "contents", None)
    head = contents[1] if isinstance(contents, tuple) and len(contents) == 2 else None
    if isinstance(head, str) and not _MODEL_ACTION_NAME.search(head):
        return []
    old = [int(m[1]) for line in removed if (m := _TIMEOUT.match(line))]
    return [f"timeout raised to {n}" for n in new if not old or n > max(old)]


def _cost_reasons(
    inp: RiskInput, files: list[_File], raw_files: list[Any]
) -> list[Reason]:
    """`cost-review-required` for a change that could add or raise a charge,
    unless `inp.cost_decision` names the owner decision that clears it. It
    holds in every lane, whatever the floor switch says."""
    hits = []
    for f, raw in zip(files, raw_files):
        if any(glob_match(g, p) for g in COST_PATHS for p in f.paths):
            hits.append(f"{f.path}: infrastructure as code")
            continue
        if inp.pulumi_dirs is None:
            hits.append(f"{f.path}: the base tree was not listed for Pulumi projects")
            continue
        if any(
            p == d or not d or p.casefold().startswith(d.casefold() + "/")
            for d in inp.pulumi_dirs or ()
            for p in f.paths
        ):
            hits.append(f"{f.path}: in a Pulumi project")
            continue
        workflow = any(is_workflow_path(p) for p in f.paths)
        pipeline = any(glob_match(_PIPELINE_CONFIG, p) for p in f.paths)
        if not (workflow or pipeline):
            continue
        new, old = f.paths[0], f.paths[-1]
        if new != old and not (
            is_workflow_path(old) or glob_match(_PIPELINE_CONFIG, old)
        ):
            hits.append(f"{f.path}: renamed or copied from {old}")
            continue
        lines = _patch_lines(getattr(raw, "patch", None))
        if lines is None:
            hits.append(f"{f.path}: no patch to read")
            continue
        added, removed = lines
        if workflow:
            patterns = [_COST_WORKFLOW_LINE] + (
                [] if inp.public is True else [_COST_PRIVATE_LINE]
            )
            found = [s.strip() for s in added if any(p.search(s) for p in patterns)]
            found += [
                f"new secrets reference {n}"
                for n in _net_added(_SECRET_REF, added, removed)
            ]
            found += [
                f"new model leg {n}" for n in _net_added(_MODEL_ACTION, added, removed)
            ]
            found += [
                f"new model package run {n}"
                for n in _net_added(_MODEL_PACKAGE, added, removed)
            ]
            found += _raised_timeouts(f, raw, added, removed)
            found += [
                f"runner {v}" for v in _new_runners(raw, added, inp.public is True)
            ]
        else:
            found = _unsafe_pipeline_lines(getattr(raw, "patch", ""))
        if found:
            hits.append(f"{f.path}: {'; '.join(found)}")
    if not hits or inp.cost_decision:
        return []
    detail = "; ".join(hits) + (
        "; cite the owner's `**Decision recorded.**` comment on the closing issue or "
        "this pull request in the body to clear it"
    )
    return [Reason(COST_CODE, Risk.HIGH, detail)]


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
    if limit is None and inp.lines_optional is True:
        pass
    elif not _is_count(limit):
        reasons.append(
            Reason("lines-over", Risk.MED, f"limit unreadable: {_show(limit)}")
        )
    elif lines > limit:
        reasons.append(Reason("lines-over", Risk.MED, f"{lines} > {limit}"))
    cap = inp.max_changed_files
    if cap is not None and not _is_count(cap):
        reasons.append(
            Reason("files-over", Risk.MED, f"limit unreadable: {_show(cap)}")
        )
    elif cap is not None and len(files) > cap:
        reasons.append(Reason("files-over", Risk.MED, f"{len(files)} > {cap}"))
    for path in dict.fromkeys(f.path for f in files if f.has_patch is False):
        reasons.append(
            Reason(f"no-patch:{path}", Risk.MED, "no patch: line counts unknown")
        )
    return reasons


def blocking(lane: Any) -> Any:
    """The lane's open findings that hold the merge: `blocking_findings`, or
    every open finding when that is None."""
    count = getattr(lane, "blocking_findings", None)
    return getattr(lane, "open_findings", None) if count is None else count


def _lane_reasons(raw_lanes: Any) -> list[Reason]:
    lanes = _sequence(raw_lanes) or ()
    reasons = []
    names = [getattr(lane, "lane", None) for lane in lanes]
    unknown = [
        _show(name) for name in names if not (isinstance(name, str) and name in LANES)
    ]
    if unknown:
        reasons.append(Reason("evidence-unbound:unknown", Risk.MED, ", ".join(unknown)))
    for name, (finding_code, finding_severity) in LANES.items():
        entries = [lane for lane in lanes if getattr(lane, "lane", None) == name]
        if len(entries) != 1:
            detail = "missing" if not entries else "more than one evidence entry"
            reasons.append(Reason(f"evidence-unbound:{name}", Risk.MED, detail))
            continue
        lane = entries[0]
        count = blocking(lane)
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
            continue
        total = getattr(lane, "open_findings", None)
        if name != _HOLDING_LANE:
            seen = total if _is_count(total) else count
            if seen > 0:
                reasons.append(
                    Reason(finding_code, Risk.MED, f"{seen} open, reported only")
                )
            continue
        if count > 0:
            reasons.append(Reason(finding_code, finding_severity, f"{count} open"))
        if _is_count(total) and total > count:
            detail = f"{total - count} open below CRITICAL, reported only"
            reasons.append(Reason(REPORTED_SECURITY_CODE, Risk.MED, detail))
    return reasons


def _score(inp: RiskInput) -> RiskResult:
    raw_files = _sequence(inp.files)
    files = None if raw_files is None else [_check_file(f) for f in raw_files]
    # Each producer emits a code at most once, and the only code two of them
    # could share (high-path:**) is refused as a configured glob.
    reasons = [
        *_size_reasons(inp, files),
        *_lane_reasons(inp.lanes),
        *_high_path_reasons(inp, files or [], list(raw_files or ())),
        *_cost_reasons(inp, files or [], list(raw_files or ())),
        *_trust_gate_reasons(files or [], list(raw_files or ())),
    ]
    reasons.sort(key=lambda reason: (-reason.severity, reason.code))
    worst = max((reason.severity for reason in reasons), default=Risk.LOW)
    return RiskResult(Risk(worst), tuple(reasons))


# MED reasons an unattended merge passes: the diff's size and the review
# findings that are reported only.
MERGEABLE_MED = frozenset(
    {
        "lines-over",
        "files-over",
        LANES["claude-review"][0],
        REPORTED_SECURITY_CODE,
    }
)
_MERGEABLE_MED_PREFIX = "no-patch:"


def holding(result: RiskResult) -> list[Reason]:
    """The reasons that refuse an unattended merge: every HIGH one, and each
    MED one outside `MERGEABLE_MED`, such as unbound review evidence or an
    unread file listing."""
    return [
        r
        for r in result.reasons
        if r.severity is not Risk.MED
        or not (r.code in MERGEABLE_MED or r.code.startswith(_MERGEABLE_MED_PREFIX))
    ]


def holds(result: RiskResult) -> bool:
    """Whether the score refuses an unattended merge (`holding`)."""
    return bool(holding(result))


def score(inp: RiskInput) -> RiskResult:
    """Never raises: input the scorer cannot read at all is HIGH, any path."""
    try:
        return _score(inp)
    except Exception as exc:  # noqa: BLE001 - fail closed, never raise
        detail = f"scorer could not read its input: {type(exc).__name__}"
        return RiskResult(Risk.HIGH, (Reason(UNSAFE_PATH_CODE, Risk.HIGH, detail),))
