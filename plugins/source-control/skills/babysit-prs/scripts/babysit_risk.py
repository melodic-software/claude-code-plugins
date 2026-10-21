#!/usr/bin/env python3
"""Diff risk scorer for the unattended merge path.

`score(RiskInput) -> RiskResult` is a pure function: no I/O, no GitHub calls.
The caller reads the PR, its linked issue's class, the base-SHA config and the
review-lane evidence, and hands them in; this module only judges them. Only a
LOW score may merge unattended, so every doubtful input rates MED or HIGH:
missing or unrecognized data is a miss, never a pass, and it never raises: input
it cannot read at all rates HIGH as `high-path:**`. Inputs are plain built-in
types (str, int, bool, None, list, tuple) built from parsed JSON; subclasses
that override their own behavior are out of scope. A count outside
0..10**9 is malformed. Each reason code appears once.

The HIGH path floor and the lane table are fixed here on purpose. A weaker value
could only come from a file a pull request can edit, and this module's own path
is in the floor, so a pull request cannot change the rule it is judged by. The
configured `merge.diff-check.denied-paths` and `floor-paths` are joined to the
floor, never in place of it. So are the paths each plugin's base-side
`DECLARATION_FILES` declare as run (`RiskInput.declarations`); a declaration it
cannot read rates HIGH as `high-path:**`. With the floor, a SKILL.md, agents/**/*.md or
commands/**/*.md file whose head text gains or changes a capability frontmatter
key, adds a `!` command, or changes a line inside a ```! block, compared with
its base text, or whose text could not be read, rates HIGH as
`high-capability`.
A safe file whose every path is a test (a `*.test.mjs`, `*.test.sh`,
`*.test.js` or `test_*.py` name, matched case-sensitively; a `tests` or
`fixtures` directory alone is not one), under no declared path and named by no other changed file
(every other file readable), is left out of the floor's script-directory
entries, `floor-paths` globs whose last segment other than `**` is `scripts`
(unless spelled like another fixed entry), and the script scopes; every other entry and every denied path still holds it.
`floor_extensions` gates FLOOR_ADDITIONS, `floor-paths`, the script scopes and
the capability check in every lane. Every glob matches case-insensitively,
because a lane host on a case-insensitive filesystem treats `Claude.md` as
`CLAUDE.md`.
Two changes take no `high-capability` hold: a modified
plugins/<plugin>/skills/<skill>/SKILL.md whose head text is its base text with
the one line `disable-model-invocation: true` added as a new frontmatter key,
unless an agent definition at the base (`RiskInput.agents`, unknown when None)
or changed in the diff could preload the skill (its `skills` entry names the
skill's directory or `name`, or it cannot be read); and eval data. Eval data is
a safe file whose every path is under plugins/<plugin>/evals/ (segments matched
case-sensitively), not a `*.sh`, `*.py`, `*.mjs`, `*.js`, `*.ps1` or `*.cjs`
file, of no mode 100755, and under no declared path; it also takes no hold from
the floor entries in `_EVALS_FLOOR` that no denied path repeats. Every other
floor entry (a `.claude-plugin/` manifest, `**/CLAUDE.md`, `**/.claude/**` and
the rest) still holds it.
While the floor applies, a changed path in a directory from
plugins/<plugin>/evals/ down to its own whose case.yaml, at the base
(`RiskInput.eval_cases`) or on either side of the diff, could name a
`context.scaffold_script` rates HIGH as `eval-scaffold-review-required`: a
scaffold runs as the operator outside the sandbox under `--scaffold`. A case
file is scaffold-free only when the strict frontmatter reader follows it and
every `context` line is `history_file`, `add_dirs` or a list item; an unread
case file (`eval_cases` None, or a None text) holds. Any `_EVAL_RUNNABLE` or
mode 100755 file under plugins/<plugin>/evals/ also rates HIGH as
`eval-scaffold-review-required`, floor or not: a scaffold may source it.
A plugins/<plugin>/.claude-plugin/plugin.json or the top-level
.claude-plugin/marketplace.json takes no `**/.claude-plugin/**` floor hold
unless a denied path repeats that pattern. Its base and head JSON are compared
against allow-lists instead, and any other difference rates HIGH as
`manifest-review-required`, so an unlisted key fails closed. In plugin.json
only `_PLUGIN_CLEAR` keys may differ, and `version` may not be removed; a
`userConfig` entry may change only its `title` or `description`, and an added
or removed one holds. In
marketplace.json only `plugins` and `metadata.description`/`version` may
differ; a plugin entry, matched by name, may change only `_ENTRY_CLEAR` keys,
and an added, removed or renamed entry holds. A manifest whose side cannot be
read or parsed, or repeats a key, holds; an added plugin.json is compared with
`{}`, so it holds. Values are compared as sorted JSON, so `false` and `0`
differ, and a listed key clears only with the type `_CLEAR_TYPES` names (a
string otherwise).

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
unknown rung to `class-above-rung` (read as off), an unreadable line limit to
`lines-over`, an unreadable configured HIGH set or file mode to `high-path:**`,
and a blast radius other than LOW above C2 to `blast-radius-missing`.
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
    # The base-side mode. Required for a modified, changed, renamed or copied file. The
    # caller passes None for an absent side; "000000" (git's absent mode) is
    # read as absent and accepted only for an added file.
    previous_mode: str | None = None
    # The files API's unified patch text, when it sent one (None otherwise).
    patch: str | None = None
    # A capability file's (base, head) text, None for an absent side, read by
    # the caller while the floor applies; contents_error says why it could not.
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


@dataclass(frozen=True)
class RiskInput:
    work_class: str | None  # class of the one linked issue (C1..C5)
    rung: Rung  # effective rung
    files: tuple[ChangedFile, ...]
    files_complete: bool  # the listing was read to its end
    max_changed_lines: int | None  # merge.diff-check.max-changed-lines at the base SHA
    high_paths: tuple[str, ...]  # configured denied paths, joined to HIGH_FLOOR
    lanes: tuple[LaneEvidence, ...]
    blast_radius: str | None  # consulted only above C2
    # The switches the pr-merge lane may turn off (merge.diff-check); the
    # defaults keep every check. An unset line cap is MED unless optional.
    high_floor: bool = True
    # merge.diff-check.high-path-floor in every lane: false leaves out
    # FLOOR_ADDITIONS, floor_paths, floor_script_scopes and the capability
    # check, so the floor is main's HIGH_FLOOR alone where high_floor holds.
    floor_extensions: bool = True
    # merge.diff-check.floor-paths: globs joined to HIGH_FLOOR while it applies.
    floor_paths: tuple[str, ...] = ()
    # merge.diff-check.floor-script-scopes: globs inside which, as at the top
    # level, a script file (`_SCRIPT_SUFFIXES`, or git mode 100755) scores
    # HIGH with the floor.
    floor_script_scopes: tuple[str, ...] = ()
    c2_contradictions: bool = True
    max_changed_files: int | None = 8  # None: no cap
    lines_optional: bool = False
    # Each DECLARATION_FILES file at the base SHA as (path, text), None when
    # unreadable; None when the base tree could not be listed. What they
    # declare runs joins HIGH_FLOOR while it applies.
    declarations: tuple[tuple[str, str | None], ...] | None = ()
    # Each AGENT_FILES file at the base SHA as (path, text), None when
    # unreadable; None when not read, so no skill change may skip its hold.
    agents: tuple[tuple[str, str | None], ...] | None = None
    # Each case.yaml at the base SHA in a directory `eval_case_dirs` names for
    # a changed path, as (path, text), None when unreadable; None when not
    # read, so every changed path under plugins/<plugin>/evals/ holds.
    eval_cases: tuple[tuple[str, str | None], ...] | None = None


@dataclass(frozen=True)
class Reason:
    code: str
    severity: Risk
    detail: str


@dataclass(frozen=True)
class RiskResult:
    score: Risk  # max(reason.severity), LOW when no reason
    reasons: tuple[Reason, ...]  # sorted by severity desc, then code


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
    "plugins/*/lib/**",  # synced copies of lib/ that hooks run
    "plugins/*/bin/**",  # on the Bash tool's PATH while the plugin is enabled
    # Scripts skills run through `!` lines, and agents and workflows by path.
    "plugins/*/scripts/**",
    "plugins/*/skills/*/scripts/**",
    "plugins/**/scripts/**",  # any deeper scripts/ directory
    "plugins/*/git-hooks/**",  # installed as git hooks in consumer repos
    # Run by a skill, not under a scripts/ directory.
    "plugins/harness-ops/skills/observability/otel/net-probe.sh",
    "plugins/knowledge/skills/video-digest/extraction/preflight.mjs",
    # Hook-run scripts outside hooks/.
    "plugins/disk-hygiene/skills/clean/scripts/destructive_guard.py",
    "plugins/disk-hygiene/skills/clean/scripts/engine_context.py",
    "plugins/disk-hygiene/skills/clean/scripts/guard_launch_monitor.py",
    "**/package.json",
    "**/package-lock.json",
    ".node-version",
    ".python-version",
    ".gitleaks.toml",
    ".gitleaksignore",
    ".gitattributes",
    "**/.gitmodules",
    "**/CLAUDE.local.md",
    "**/.mcp.json",
    "**/.lsp.json",
    "**/AGENTS.override.md",
)
# Floor entries `merge.diff-check.high-path-floor` gates in every lane.
FLOOR_ADDITIONS: tuple[str, ...] = (
    "plugins/*/monitors/**",  # commands Claude Code runs in the background
    "plugins/*/workflows/**",
)

# Plugin files that declare what Claude Code runs. The caller reads each at the
# base SHA, so a pull request cannot drop the declaration that floors its code.
DECLARATION_FILES: tuple[str, ...] = (
    "plugins/*/.claude-plugin/plugin.json",
    "plugins/*/.mcp.json",
    "plugins/*/.lsp.json",
    "plugins/*/hooks/hooks.json",
    "plugins/*/monitors/monitors.json",
)
# plugin.json keys whose values Claude Code runs or reads as run config; its
# other `./` paths (types, skills) are not executable. A string value of one is
# a pointer to a config file, which is read and declares too.
_EXECUTABLE_KEYS = ("hooks", "mcpServers", "lspServers", "monitors")
_PLUGIN_ROOT_REF = re.compile(
    r"\$(?:\{CLAUDE_PLUGIN_ROOT\}|CLAUDE_PLUGIN_ROOT\b)([^\s\"'`;|&<>(){}$]*)"
)
# Any spelling of the variable; one _PLUGIN_ROOT_REF does not consume (a
# default, a trim, PowerShell's or cmd's form) is unsafe.
_PLUGIN_ROOT_NAME = re.compile("CLAUDE_PLUGIN_ROOT", re.IGNORECASE)
_RELATIVE = ("./", "../", ".\\", "..\\")

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


def _strings(value: Any) -> list[str]:
    if isinstance(value, str):
        return [value]
    if not isinstance(value, (dict, list)):
        return []
    items = value.values() if isinstance(value, dict) else value
    return [s for item in items for s in _strings(item)]


def _resolve(root: str, rest: str) -> list[str] | None:
    """The segments of a path under the plugin root, None when it leaves it."""
    parts: list[str] = []
    for segment in rest.replace("\\", "/").split("/"):
        if segment == "..":
            if not parts:
                return None
            parts.pop()
        elif segment not in ("", "."):
            parts.append(segment)
    return parts


def _under_root(root: str, rest: str) -> str | None:
    """A declared path as the directory holding it (code beside an entry point
    runs with it), or the path itself at the plugin root; None when it leaves
    the plugin."""
    parts = _resolve(root, rest)
    if parts is None:
        return None
    return "/".join([root, *(parts[:-1] if len(parts) > 1 else parts)])


_DECLARATION_NAMES = {g.removeprefix("plugins/*/") for g in DECLARATION_FILES}
_PLUGIN_JSON = ".claude-plugin/plugin.json"
# A monitors file holds the monitors array; the other declarations an object.
_MONITORS = "monitors/monitors.json"


def _located(path: Any) -> tuple[str, str, str] | None:
    """(normalized path, plugin root, casefolded path under the root) for a
    safe path inside a plugin directory."""
    normalized, safe = normalize_path(path)
    parts = normalized.split("/")
    if not safe or len(parts) < 3 or parts[0] != "plugins":
        return None
    return normalized, "/".join(parts[:2]), "/".join(parts[2:]).casefold()


def _load(text: Any, *, array: bool = False) -> dict[str, Any] | list[Any] | None:
    if not isinstance(text, str):
        return None
    try:
        data = json.loads(text)
    except (ValueError, RecursionError):
        return None
    return (
        data if isinstance(data, dict) or (array and isinstance(data, list)) else None
    )


def _executable_values(data: dict[str, Any]) -> list[tuple[Any, bool]]:
    """Each executable key's value, and whether it is a monitors value."""
    experimental = data.get("experimental")
    monitors = experimental.get("monitors") if isinstance(experimental, dict) else None
    keyed = [(data.get(key), key == "monitors") for key in _EXECUTABLE_KEYS]
    return [*keyed, (monitors, True)]


def _pointers(path: Any, text: Any) -> list[tuple[str, bool]]:
    """`declaration_pointers`, each with whether a monitors key names it."""
    located, data = _located(path), _load(text)
    if located is None or located[2] != _PLUGIN_JSON or not isinstance(data, dict):
        return []
    root = located[1]
    found = []
    for value, monitors in _executable_values(data):
        pointers = [value] if isinstance(value, str) else _sequence(value) or ()
        for pointer in pointers:
            parts = _resolve(root, pointer) if isinstance(pointer, str) else None
            if parts:
                found.append(("/".join([root, *parts]), monitors))
    return found


def declaration_pointers(path: Any, text: Any) -> tuple[str, ...]:
    """The config files a plugin.json's executable keys point at (a string or
    a list of strings), as repository paths for the caller to read at the base
    SHA; () for any other file, unreadable text, or a pointer leaving the
    plugin, which the scorer rates."""
    return tuple(dict.fromkeys(pointer for pointer, _ in _pointers(path, text)))


def _declared_paths(value: Any, unsafe: list[str]) -> tuple[str, ...]:
    """The paths base-side declarations run: every `${CLAUDE_PLUGIN_ROOT}`
    reference and every `./` or `../` path, resolved against the plugin root,
    in plugin.json under an executable key only, and in the files its pointers
    name. A declaration it cannot read, a pointer not read, a reference it
    cannot resolve, or a path outside its plugin is unsafe."""
    entries = _sequence(value)
    if entries is None:
        unsafe.append(f"declarations unreadable: {_show(value)}")
        return ()
    pairs = []
    for entry in entries:
        pair = _sequence(entry)
        pairs.append(pair if pair is not None and len(pair) == 2 else (entry, None))
    named = [
        (p.casefold(), monitors)
        for path, text in pairs
        for p, monitors in _pointers(path, text)
    ]
    pointers = {p for p, _ in named}
    monitor_files = {p for p, monitors in named if monitors}
    read = {located[0].casefold() for path, _ in pairs if (located := _located(path))}
    unsafe.extend(f"pointer not read: {_show(p)}" for p in sorted(pointers - read))
    found = []
    for path, text in pairs:
        located = _located(path)
        if located is None or not (
            located[2] in _DECLARATION_NAMES or located[0].casefold() in pointers
        ):
            unsafe.append(f"declaration file not recognized: {_show(path)}")
            continue
        _, root, name = located
        array = name == _MONITORS or located[0].casefold() in monitor_files
        data = _load(text, array=array)
        if data is None or (name == _PLUGIN_JSON and not isinstance(data, dict)):
            unsafe.append(f"declaration unreadable: {_show(path)}")
            continue
        scope = (
            [value for value, _ in _executable_values(data)]
            if isinstance(data, dict) and name == _PLUGIN_JSON
            else data
        )
        for string in _strings(scope):
            refs = [m.group(1) for m in _PLUGIN_ROOT_REF.finditer(string)]
            if len(_PLUGIN_ROOT_NAME.findall(string)) > len(refs):
                unsafe.append(f"{_show(path)} names the plugin root as {_show(string)}")
            if string.startswith(_RELATIVE):
                refs.append(string)
            for ref in refs:
                declared = _under_root(root, ref)
                if declared is None or not normalize_path(declared)[1]:
                    unsafe.append(f"{_show(path)} declares {_show(ref)}")
                else:
                    found.append(declared)
    return tuple(dict.fromkeys(found))


_SCRIPT_SUFFIXES = (".ps1", ".cjs")
_EXECUTABLE_MODE = "100755"

# The floor's script-directory entries, which a test-only file does not hold.
_SCRIPT_FLOOR = frozenset(
    {"plugins/*/scripts/**", "plugins/*/skills/*/scripts/**", "plugins/**/scripts/**"}
)
_TEST_NAMES = ("*.test.mjs", "*.test.sh", "*.test.js", "test_*.py")


def _ends_in_scripts(glob: str) -> bool:
    """Whether the last segment of a glob other than `**` is `scripts`."""
    segments = [s for s in glob.split("/") if s not in ("", "**")]
    return bool(segments) and segments[-1] == "scripts"


def _test_path(path: str) -> bool:
    """A test file name, matched case-sensitively. A tests or fixtures
    directory alone is no test: an unchanged shipped file the scorer cannot
    read may source, glob or copy what it holds."""
    name = path.rsplit("/", 1)[-1]
    return any(_segment_match(g, name) for g in _TEST_NAMES)


def _named(f: _File, files: list[_File], raw_files: list[Any]) -> bool:
    """Whether another changed file's patch or text names one of this file's
    names, or one of them cannot be read (fail closed)."""
    names = {path.rsplit("/", 1)[-1].casefold() for path in f.paths}
    for other, raw in zip(files, raw_files):
        if other is f:
            continue
        patch = getattr(raw, "patch", None)
        contents = getattr(raw, "contents", None)
        texts = [patch] if isinstance(patch, str) else []
        if isinstance(contents, tuple):
            texts += [c for c in contents if isinstance(c, str)]
        if not texts:
            return True
        if any(name in text.casefold() for text in texts for name in names):
            return True
    return False


def _test_only(
    f: _File,
    files: list[_File],
    raw_files: list[Any],
    declared: tuple[str, ...],
) -> bool:
    """Every path of a safe file is a test (`_test_path`), under no declared
    path, and no other changed file names it."""
    if f.unsafe or not f.paths:
        return False
    for path in f.paths:
        if not _test_path(path) or any(glob_match(d, path) for d in declared):
            return False
    return not _named(f, files, raw_files)


def _script_reasons(
    files: list[_File], raw_files: list[Any], scopes, tests: set[str]
) -> list[Reason]:
    hits = []
    for f, raw in zip(files, raw_files):
        modes = (getattr(raw, "mode", None), getattr(raw, "previous_mode", None))
        for path in f.paths:
            # The top level is always in scope (owner decision Q646).
            top = "/" not in path
            if not path or not (top or any(glob_match(g, path) for g in scopes)):
                continue
            if not top and path in tests:
                continue
            if path.casefold().endswith(_SCRIPT_SUFFIXES) or _EXECUTABLE_MODE in modes:
                hits.append(path)
    if not hits:
        return []
    return [Reason("high-script", Risk.HIGH, ", ".join(dict.fromkeys(hits)))]


# Files whose frontmatter grants capability, and the keys that grant it.
AGENT_FILES = "**/agents/**/*.md"
_CAPABILITY_FILES = ("**/SKILL.md", AGENT_FILES, "**/commands/**/*.md")
_CAPABILITY_KEYS = frozenset(
    {
        "hooks",
        "allowed-tools",
        "tools",
        "disallowed-tools",
        "disallowedtools",
        "permissionmode",
        "mcpservers",
        "disable-model-invocation",
        "context",
        "agent",
        "shell",
        "skills",
        "memory",
    }
)
_HUNK = re.compile(r"@@ -[0-9]+(?:,[0-9]+)? \+([0-9]+)(?:,[0-9]+)? @@")
_FRONT_KEY = re.compile(r"([A-Za-z][A-Za-z0-9_-]*)[ \t]*:(?:[ \t]|$)")
# A `|` or `>` block scalar header: its indented lines are text.
_BLOCK_SCALAR = re.compile(r"[|>][0-9+-]*(?:[ \t]+#.*)?$")
# Anchors, aliases, tags and merge keys let one entry change another's value.
# YAML reads them only where a node starts: at line start, after `key: ` or
# `[`, `{`, `,` in a flow collection, and after any run of `- `, `? ` or `: `
# block indicators there. So `Bash(git *)` and `x:*` stay text.
_INDIRECT = re.compile(
    r"(?:^|[\[{,]|:(?=[ \t]))(?:[ \t]*[-?:][ \t]+)*[ \t]*[&*!][^\s,\]}]|^[ \t]*<<[ \t]*:"
)
# Unanchored, so a ```! after a quote marker, a list marker or text counts.
_FENCED_BANG = re.compile(r"(?:`{3,}|~{3,})[ \t]*!")
# A closing fence starts its line, so a quoted fence inside a block never
# ends it early: the block can only read longer.
_CLOSING_FENCE = re.compile(r"[ \t]*(?:`{3,}|~{3,})")


def is_capability_path(path: str) -> bool:
    """Whether Claude Code reads this file's frontmatter as capability."""
    return any(glob_match(g, path) for g in _CAPABILITY_FILES)


def _front_block(text: str) -> tuple[str | None, bool]:
    """The frontmatter text between the opening and closing `---` lines, and
    whether its shape is one this reader follows: no BOM, no CR, the opening
    and closing lines exactly `---`. No frontmatter is ("", True); a file whose
    start only looks like frontmatter is (the whole text, False)."""
    first, _, rest = text.partition("\n")
    if first != "---":
        if text.lstrip("\ufeff \t\r\n").startswith("---"):
            return text, False
        return "", True
    lines = rest.split("\n")
    end = next(
        (i for i, line in enumerate(lines) if line.rstrip() in ("---", "...")), None
    )
    if end is None or lines[end] != "---":
        return rest, False
    block = "\n".join(lines[:end])
    return block, "\r" not in block


def _front_entries(block: str) -> dict[str, str] | None:
    """Top-level frontmatter entries, each key (casefolded) to its lines, read
    strictly: None for any shape a line-by-line read cannot follow."""
    entries: dict[str, list[str]] = {}
    key, scalar = None, False
    for line in block.split("\n"):
        if not line.strip() or line.startswith("#"):
            if key is not None:
                entries[key].append(line)
            continue
        if _INDIRECT.search(line):
            return None
        named = _FRONT_KEY.match(line)
        if named:
            key = named.group(1).casefold()
            if key in entries:
                return None
            entries[key] = [line]
            value = line[named.end() :].strip()
            scalar = bool(value) and not _BLOCK_SCALAR.match(value)
        elif key is not None and (
            line[0] in " \t" or line == "-" or line.startswith("- ")
        ):
            # An indented key under a plain scalar may be read as its own entry.
            if scalar and _FRONT_KEY.match(line.strip()):
                return None
            entries[key].append(line)
        else:
            return None
    return {k: "\n".join(v).rstrip() for k, v in entries.items()}


def _inline_lines(text: str) -> list[str]:
    return [line for line in text.split("\n") if "!`" in line]


def _bang_lines(text: str) -> set[int]:
    """The 1-based lines of `text` inside a ```! block, opener and closer
    included; the block runs to the next line starting with a fence, or to the
    end."""
    inside, found = False, set()
    for number, line in enumerate(text.split("\n"), 1):
        opener = None if inside else _FENCED_BANG.search(line)
        if opener:
            inside = True
            found.add(number)
        elif inside:
            found.add(number)
            inside = not _CLOSING_FENCE.match(line)
    return found


def _changed_lines(patch: str) -> set[int]:
    """Head-side line numbers a unified patch adds, and the head lines on
    either side of each line it removes."""
    changed: set[int] = set()
    line_no = None
    for line in patch.split("\n"):
        hunk = _HUNK.match(line)
        if hunk:
            line_no = int(hunk.group(1))
        elif line_no is not None and line and line[0] in " +-":
            if line[0] == "-":
                changed.update((line_no - 1, line_no))
                continue
            if line[0] == "+":
                changed.add(line_no)
            line_no += 1
    return changed


def _content_triggers(before: str, after: str, raw: Any) -> list[str]:
    """What the head text gains over the base text: frontmatter capability
    keys, `!` commands, and changes inside a ```! block (fail closed)."""
    triggers = []
    base_block, base_ok = _front_block(before)
    head_block, head_ok = _front_block(after)
    if base_block != head_block or base_ok != head_ok:
        base = _front_entries(base_block or "") if base_ok else None
        head = _front_entries(head_block or "") if head_ok else None
        if base is None or head is None:
            triggers.append("frontmatter the reader cannot follow")
        else:
            triggers += [
                f"frontmatter {k}"
                for k in sorted(_CAPABILITY_KEYS)
                if base.get(k) != head.get(k)
            ]
    # Every line holding a `!` command, compared as a multiset, so a rewritten
    # or swapped command counts as well as an added one.
    if Counter(_inline_lines(after)) - Counter(_inline_lines(before)):
        triggers.append("adds or changes a !` command")
    if len(_FENCED_BANG.findall(after)) > len(_FENCED_BANG.findall(before)):
        triggers.append("adds a ```! block")
    block = _bang_lines(after)
    if block and before != after:
        patch = getattr(raw, "patch", None)
        changed = _changed_lines(patch) if isinstance(patch, str) else set()
        if not changed:
            triggers.append(
                "changes a file with a ```! block and no patch to place them"
            )
        elif changed & block:
            triggers.append("changes a line inside a ```! block")
    return triggers


def _capability_reasons(
    files: list[_File], raw_files: list[Any], agents: Any, evals: set[str]
) -> list[Reason]:
    """A capability file the head gains capability in, compared by content:
    `ChangedFile.contents` holds the base and head text, read by the caller."""
    hits = []
    for f, raw in zip(files, raw_files):
        capable = [is_capability_path(p) if p else False for p in f.paths]
        if f.status == "removed" or not capable[0] or f.path in evals:
            continue
        contents = getattr(raw, "contents", None)
        error = getattr(raw, "contents_error", None)
        if error is not None or not (
            isinstance(contents, tuple)
            and len(contents) == 2
            and all(c is None or isinstance(c, str) for c in contents)
        ):
            triggers = [f"contents unreadable: {_show(error)}"]
        else:
            before, after = (c or "" for c in contents)
            triggers = _content_triggers(before, after, raw)
            if (
                f.status == "modified"
                and f.paths == (f.path,)
                and is_skill_path(f.path)
                and contents[0] is not None
                and _adds_only_dmi(before, after)
                and not _preloaded(f.path, after, agents, files, raw_files)
            ):
                triggers = []
        # Unchanged frontmatter reads the same on both sides of a rename or copy.
        if f.status == "copied" or (f.status == "renamed" and not all(capable)):
            triggers.append(f"{f.status} into a capability path")
        if triggers:
            hits.append(f"{f.path}: {', '.join(dict.fromkeys(triggers))}")
    return [Reason("high-capability", Risk.HIGH, "; ".join(hits))] if hits else []


_DMI_LINE = "disable-model-invocation: true"
_DMI_KEY = "disable-model-invocation"


def is_skill_path(path: str) -> bool:
    """plugins/<plugin>/skills/<skill>/SKILL.md, matched case-sensitively."""
    parts = path.split("/")
    return (
        len(parts) == 5
        and parts[0] == "plugins"
        and parts[2] == "skills"
        and parts[4] == "SKILL.md"
    )


def _adds_only_dmi(before: str, after: str) -> bool:
    """The head text is the base text with one line, `_DMI_LINE`, added as a
    new top-level frontmatter key and every other entry unchanged."""
    old, new = before.split("\n"), after.split("\n")
    if len(new) != len(old) + 1:
        return False
    at = next((i for i, (a, b) in enumerate(zip(old, new)) if a != b), len(old))
    if new[at] != _DMI_LINE or new[:at] + new[at + 1 :] != old:
        return False
    (base_block, base_ok), (head_block, head_ok) = map(_front_block, (before, after))
    if not (base_ok and head_ok and new[0] == "---"):
        return False
    if not 1 <= at <= len((head_block or "").split("\n")):
        return False
    base, head = _front_entries(base_block or ""), _front_entries(head_block or "")
    # A base that already has the key reads as a duplicate (None) at the head.
    return base is not None and head == {**base, _DMI_KEY: _DMI_LINE}


def _tokens(text: str) -> set[str]:
    return set(re.findall(r"[a-z0-9_.-]+", text.casefold()))


def _preloaded(
    path: str, after: str, agents: Any, files: list[_File], raw_files: list[Any]
) -> bool:
    """Whether an agent definition at the base (`RiskInput.agents`) or changed
    in this diff could preload the skill at `path`: its `skills` entry names
    the skill's directory or `name`, or it cannot be read (fail closed)."""
    entries = _sequence(agents)
    if entries is None:
        return True
    texts = []
    for entry in entries:
        pair = _sequence(entry)
        texts.append(pair[1] if pair is not None and len(pair) == 2 else None)
    for f, raw in zip(files, raw_files):
        if f.status != "removed" and any(glob_match(AGENT_FILES, p) for p in f.paths):
            contents = getattr(raw, "contents", None)
            ok = isinstance(contents, tuple) and len(contents) == 2
            texts.append(contents[1] if ok else None)
    head = _front_entries(_front_block(after)[0] or "") or {}
    names = {path.split("/")[3].casefold()}
    names |= _tokens(head.get("name", "").partition(":")[2])
    for text in texts:
        if not isinstance(text, str):
            return True
        block, ok = _front_block(text)
        found = _front_entries(block or "") if ok else None
        if found is None or names & _tokens(found.get("skills", "").partition(":")[2]):
            return True
    return False


# The floor entries eval data does not take: they hold it by location only.
_EVALS_FLOOR = frozenset(
    {
        "plugins/review/**",
        "plugins/guardrails/**",
        "plugins/work-items/**",
        "plugins/**/scripts/**",
    }
)
_EVAL_SCRIPTS = (".sh", ".py", ".mjs", ".js", ".ps1", *_SCRIPT_SUFFIXES)


def _eval_data(f: _File, raw: Any, declared: tuple[str, ...]) -> bool:
    """A safe file whose every path is under plugins/<plugin>/evals/, matched
    case-sensitively, is no script by name or mode, and is under no declared
    path."""
    modes = (getattr(raw, "mode", None), getattr(raw, "previous_mode", None))
    if f.unsafe or not f.paths or _EXECUTABLE_MODE in modes:
        return False
    for path in f.paths:
        parts = path.split("/")
        if len(parts) < 4 or parts[0] != "plugins" or parts[2] != "evals":
            return False
        if path.casefold().endswith(_EVAL_SCRIPTS):
            return False
        if any(glob_match(d, path) for d in declared):
            return False
    return True


_MANIFEST_FLOOR = "**/.claude-plugin/**"
_MANIFEST_CODE = "manifest-review-required"
_MISSING = object()
# The plugin.json keys that may differ without review; `userConfig` is
# checked entry by entry.
_PLUGIN_CLEAR = frozenset(
    {
        "version",
        "description",
        "keywords",
        "author",
        "homepage",
        "repository",
        "license",
        "userConfig",
    }
)
# The userConfig entry attributes that may differ without review.
_USER_CONFIG_CLEAR = frozenset({"title", "description"})
# The marketplace entry keys that may differ without review.
_ENTRY_CLEAR = frozenset(
    {
        "version",
        "description",
        "keywords",
        "author",
        "homepage",
        "repository",
        "license",
        "category",
        "tags",
    }
)
_METADATA_CLEAR = frozenset({"description", "version"})


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


def _object(data: dict[str, Any], key: str) -> Any:
    """A key's value: {} when absent, None when present and not an object."""
    value = data.get(key, {})
    return value if isinstance(value, dict) else None


def _canonical(data: dict[str, Any], key: str) -> str | None:
    """A key's value as sorted JSON, so `false` and `0` differ; None when
    absent."""
    return json.dumps(data[key], sort_keys=True) if key in data else None


def _differing(before: dict[str, Any], after: dict[str, Any]) -> list[str]:
    """The keys added, removed or changed between two objects, sorted."""
    return sorted(
        k
        for k in set(before) | set(after)
        if _canonical(before, k) != _canonical(after, k)
    )


def _is_str(value: Any) -> bool:
    return isinstance(value, str)


def _string_list(value: Any) -> bool:
    return isinstance(value, list) and all(isinstance(v, str) for v in value)


def _author(value: Any) -> bool:
    return isinstance(value, str) or (
        isinstance(value, dict) and all(isinstance(v, str) for v in value.values())
    )


# The type a listed key's head value must have to clear; a string otherwise.
_CLEAR_TYPES = {
    "keywords": _string_list,
    "tags": _string_list,
    "author": _author,
    "userConfig": lambda value: isinstance(value, dict),
}


def _unlisted(
    prefix: str, before: dict[str, Any], after: dict[str, Any], clear: frozenset
) -> list[str]:
    """Each differing key outside `clear` or whose head value has the wrong
    type, and a removed `version`."""
    found = []
    for k in _differing(before, after):
        if k not in clear:
            found.append(f"{prefix}{k}")
        elif k in after and not _CLEAR_TYPES.get(k, _is_str)(after[k]):
            found.append(f"{prefix}{k} has the wrong type")
    if "version" in before and "version" not in after:
        found.append(f"{prefix}version removed")
    return found


def _user_config_changes(base: dict[str, Any], head: dict[str, Any]) -> list[str]:
    before, after = _object(base, "userConfig"), _object(head, "userConfig")
    if before is None or after is None:
        return ["userConfig is not an object"]
    found = []
    for key in _differing(before, after):
        old, new = before.get(key, _MISSING), after.get(key, _MISSING)
        if new is _MISSING:
            found.append(f"userConfig.{key} removed")
        elif old is _MISSING:
            found.append(f"userConfig.{key} added")
        elif not (isinstance(old, dict) and isinstance(new, dict)):
            found.append(f"userConfig.{key} is not an object")
        else:
            found += _unlisted(f"userConfig.{key}.", old, new, _USER_CONFIG_CLEAR)
    return found


def _plugin_changes(base: dict[str, Any], head: dict[str, Any]) -> list[str]:
    return _unlisted("", base, head, _PLUGIN_CLEAR) + _user_config_changes(base, head)


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
    found = [k for k in _differing(base, head) if k not in ("plugins", "metadata")]
    before, after = _object(base, "metadata"), _object(head, "metadata")
    if before is None or after is None:
        found.append("metadata is not an object")
    else:
        found += _unlisted("metadata.", before, after, _METADATA_CLEAR)
    old, new = _entries(base), _entries(head)
    if old is None or new is None:
        return [*found, "plugins is not a list of uniquely named entries"]
    for name in sorted(set(old) | set(new)):
        if name not in new:
            found.append(f"plugins[{name}] removed")
        elif name not in old:
            found.append(f"plugins[{name}] added")
        else:
            found += _unlisted(f"plugins[{name}].", old[name], new[name], _ENTRY_CLEAR)
    return found


def _manifest_changes(f: _File, raw: Any) -> list[str]:
    """What in a manifest change needs review (`_MANIFEST_CODE`): every key
    outside the allow-lists that differs, so an unlisted key fails closed."""
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


_EVAL_SCAFFOLD_CODE = "eval-scaffold-review-required"
_EVALS = "plugins/*/evals/**"
_EVAL_RUNNABLE = (".sh", ".bash", ".py", ".mjs", ".js", ".cjs", ".ps1")
_CASE_FILE = "case.yaml"
# The `context` keys that run nothing; `scaffold_script` runs a script.
_SAFE_CONTEXT = frozenset({"history_file", "add_dirs"})
_CONTEXT_KEY = re.compile(r"[ \t]+([A-Za-z_][A-Za-z0-9_-]*)[ \t]*:(?:[ \t]|$)")
_CONTEXT_ITEM = re.compile(r"[ \t]+-(?:[ \t]|$)")


def eval_case_dirs(path: str) -> list[str]:
    """Every directory from plugins/<plugin>/evals down to the file's own
    that could hold the file's eval case, matched case-sensitively."""
    parts = path.split("/")
    if len(parts) < 4 or parts[0] != "plugins" or parts[2] != "evals":
        return []
    return ["/".join(parts[:end]) for end in range(3, len(parts))]


def _scaffolds(text: Any) -> bool:
    """Whether a case.yaml could name a `context.scaffold_script`: true unless
    the strict reader follows it and every `context` line is a plain key in
    `_SAFE_CONTEXT` or a list item."""
    if not isinstance(text, str):
        return True
    entries = _front_entries(text)
    if entries is None:
        return True
    block = entries.get("context")
    if block is None:
        return False
    head, *lines = block.split("\n")
    if head.rstrip() != "context:":
        return True
    for line in lines:
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        key = _CONTEXT_KEY.match(line)
        if key and key.group(1) in _SAFE_CONTEXT:
            continue
        if not key and _CONTEXT_ITEM.match(line):
            continue
        return True
    return False


def _eval_runnable(f: _File, raw: Any) -> bool:
    """A script by name or mode with any path under plugins/<plugin>/evals/."""
    modes = (getattr(raw, "mode", None), getattr(raw, "previous_mode", None))
    return any(
        glob_match(_EVALS, p)
        and (p.casefold().endswith(_EVAL_RUNNABLE) or _EXECUTABLE_MODE in modes)
        for p in f.paths
        if p
    )


def _scaffold_hits(
    inp: RiskInput, files: list[_File], raw_files: list[Any], runnable: set[str]
) -> list[str]:
    """Each changed path in an eval case directory whose case.yaml, at the base
    (`RiskInput.eval_cases`) or on either side of this diff, could name a
    scaffold script, or could not be read (fail closed)."""
    base = _sequence(inp.eval_cases)
    texts: dict[str, list[Any]] = {}
    for entry in base or ():
        pair = _sequence(entry)
        if pair is None or len(pair) != 2 or not isinstance(pair[0], str):
            return [f"{f.path} (case files unreadable)" for f in files]
        texts.setdefault(pair[0], []).append(pair[1])
    for f, raw in zip(files, raw_files):
        if f.status == "removed" or f.path.rsplit("/", 1)[-1] != _CASE_FILE:
            continue
        contents = getattr(raw, "contents", None)
        ok = getattr(raw, "contents_error", None) is None and (
            isinstance(contents, tuple) and len(contents) == 2
        )
        # An added file has no base side; a missing side reads as unreadable.
        if not ok:
            contents = (None,)
        elif f.status == "added":
            contents = contents[1:]
        texts.setdefault(f.path, []).extend(contents)
    hits = []
    for f in files:
        if f.path in runnable:
            continue
        dirs = {d for p in f.paths if p for d in eval_case_dirs(p)}
        if not dirs:
            continue
        if base is None:
            hits.append(f"{f.path} (case files not read)")
        elif any(
            _scaffolds(t) for d in dirs for t in texts.get(f"{d}/{_CASE_FILE}", ())
        ):
            hits.append(f.path)
    return hits


def _high_path_reasons(
    inp: RiskInput, files: list[_File], raw_files: list[Any]
) -> list[Reason]:
    unsafe = [raw for f in files for raw in f.unsafe]
    configured = _readable_globs(inp.high_paths, unsafe)
    on = inp.high_floor is not False
    extended = on and inp.floor_extensions is not False
    floor_globs = _readable_globs(inp.floor_paths, unsafe) if extended else ()
    added = (*FLOOR_ADDITIONS, *floor_globs) if extended else ()
    declared = _declared_paths(inp.declarations, unsafe) if on else ()
    floor = (*HIGH_FLOOR, *added, *declared) if on else ()
    scopes = _readable_globs(inp.floor_script_scopes, unsafe) if extended else ()
    reasons = []
    if unsafe:
        reasons.append(Reason(UNSAFE_PATH_CODE, Risk.HIGH, "; ".join(unsafe)))
    paths = [path for f in files for path in f.paths if path]
    evals = {
        p
        for f, raw in zip(files, raw_files)
        if on and _eval_data(f, raw, declared)
        for p in f.paths
    }
    eval_exempt = _EVALS_FLOOR.difference(configured)
    manifests = {
        f.path
        for f in files
        if on and _MANIFEST_FLOOR not in configured and is_manifest_path(f.path)
    }
    tests = {
        p for f in files if _test_only(f, files, raw_files, declared) for p in f.paths
    }
    # The floor's script entries and floor-paths globs ending in a scripts
    # directory exempt tests; a denied path never does, and neither does a
    # floor-paths glob spelled like another fixed entry, which keeps holding.
    fixed = {*HIGH_FLOOR, *FLOOR_ADDITIONS}
    scripted = {g for g in floor_globs if _ends_in_scripts(g) and g not in fixed}
    exempt = _SCRIPT_FLOOR.union(scripted).difference(configured) if on else ()
    for pattern in dict.fromkeys((*floor, *configured)):
        hits = [
            path
            for path in paths
            if glob_match(pattern, path)
            and not (pattern in eval_exempt and path in evals)
            and not (pattern == _MANIFEST_FLOOR and path in manifests)
            and not (pattern in exempt and path in tests)
        ]
        if hits:
            reasons.append(Reason(f"high-path:{pattern}", Risk.HIGH, ", ".join(hits)))
    review = [
        f"{f.path}: {', '.join(changes)}"
        for f, raw in zip(files, raw_files)
        if f.path in manifests and (changes := _manifest_changes(f, raw))
    ]
    if review:
        reasons.append(Reason(_MANIFEST_CODE, Risk.HIGH, "; ".join(review)))
    # A script anywhere under evals/ can run outside the sandbox, sourced by a
    # scaffold under `--scaffold`, so it holds whatever the floor says.
    runnable = [f.path for f, raw in zip(files, raw_files) if _eval_runnable(f, raw)]
    scaffolded = runnable + (
        _scaffold_hits(inp, files, raw_files, set(runnable)) if on else []
    )
    if scaffolded:
        reasons.append(Reason(_EVAL_SCAFFOLD_CODE, Risk.HIGH, ", ".join(scaffolded)))
    if extended:
        reasons.extend(_capability_reasons(files, raw_files, inp.agents, evals))
        reasons.extend(_script_reasons(files, raw_files, scopes, tests))
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
        contradictions = (
            _c2_contradictions(files) if inp.c2_contradictions is not False else []
        )
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


def _score(inp: RiskInput) -> RiskResult:
    raw_files = _sequence(inp.files)
    files = None if raw_files is None else [_check_file(f) for f in raw_files]
    # Each producer emits a code at most once, and the only code two of them
    # could share (high-path:**) is refused as a configured glob.
    reasons = [
        *_class_reasons(inp, files or []),
        *_size_reasons(inp, files),
        *_lane_reasons(inp.lanes),
        *_high_path_reasons(inp, files or [], list(raw_files or ())),
    ]
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
