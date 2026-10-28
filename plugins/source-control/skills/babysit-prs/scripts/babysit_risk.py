#!/usr/bin/env python3
"""Diff risk scorer for the unattended merge path.

`score(RiskInput) -> RiskResult` is a pure function: no I/O, no GitHub calls.
The caller reads the PR, the base-SHA config and the review-lane evidence, and
hands them in; this module only judges them. No work class is read. A LOW
score merges unattended, and so does a MED one whose every reason is a size,
reported review-finding or cost-finding reason (`holds`); every other reason
holds.
So every doubtful
input rates a holding reason: missing or unrecognized data is a miss, never a
pass, and it never raises: input it cannot read at all rates HIGH as
`high-path:**`. Inputs are plain built-in
types (str, int, bool, None, list, tuple) built from parsed JSON; subclasses
that override their own behavior are out of scope. A count outside
0..10**9 is malformed. Each reason code appears once.

The HIGH path floor and the lane table are fixed here, never read from
configuration. The floor is narrow (owner decision Q-FLOOR (B)): the code
main runs to mint and scope lane tokens and judge triggers, code owners and
submodules, and it holds whatever the floor switch says. Its
`enforcement` entries (`REVIEW_FLOOR`) rate HIGH as `review-path:<glob>`
instead, which a clean security review bound to the head clears
(`security_review_clean`, owner decision Q26 option B). No other path rates
HIGH for being trusted alone, and the two review lanes, which are the gate,
judge it, except the cost and trusted-actor holds below. The configured
`merge.diff-check.denied-paths` are joined to the floor. Every glob matches
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
Q25, Q33 and Q693). A real new charge holds through `cost-review-required`
and a trusted-actor widening through `trust-gate:trusted-actors`.

Cost is not a stop; only a real new charge is (docs/conventions/loop-lane/
README.md, "When work stops for the owner"). A change that could start one
(billed infrastructure or billed runner minutes) rates HIGH as
`cost-review-required` in every lane, floor or not and whatever `floor_exempt`
says: any `COST_PATHS` file (Pulumi, Terraform, Bicep) or file
under a `RiskInput.pulumi_dirs` directory, and every file when `pulumi_dirs` is
None (the base tree was not listed); a file renamed or copied into a workflow
or `pr-pipeline.yaml` path from outside one; a workflow or pipeline file with
no patch; and a `.github/workflows/` file whose patch, unless
`RiskInput.public` is True, adds a `runs-on:`, `windows`, `macos` or `cron`
line (a schedule runs billed minutes), a raised timeout (below) or an artifact
`retention-days` above every one it removes, or above
`DEFAULT_ARTIFACT_RETENTION_DAYS` when it removes none (storage past the free
quota); or that gains a runner value (head text against base text, and added
inline `runs-on:` lines) that is not `_FREE_RUNNER` on a public repository,
or any on another, counting the matrix values and input defaults and options
a `runs-on` expression names. Only `RiskInput.cost_decision`, an owner
decision the caller verified, clears it.

A raised timeout is a `timeout-minutes` or `leg-timeout-minutes`: on a
workflow whose head text (`contents`) names a model leg or could not be
read, one the patch adds above every one it removes once equal values cancel
or an added expression; and on one that names a model leg or a local `uses:
./` workflow or action, head text against base text at each key path (list
indices dropped), one raised, set to an expression, added above
`DEFAULT_TIMEOUT_MINUTES`, or removed from a job or step the head keeps.

A workflow patch that gains a `_SECRET_REF` (or a bare `secrets` inside a
`${{ }}` expression, outside a string) rates HIGH as `secret-exposure-review`, and one that
gains a `_MODEL_ACTION` or a `_MODEL_PACKAGE` run, in a workflow or a
composite action's `action.yml`, rates HIGH as `agent-surface-review`, each
counted against the lines it removes, an expression split across lines read
whole, so a move or repin is not new. They widen what a credential or an
agent can reach, so both are a person's (`PERSON_CODES`) and no cost
decision clears them.

Spend that draws only on a subscription or prepaid credit is the MED
`cost-finding`, reported and never held: a workflow patch that adds a
`_COST_WORKFLOW_LINE` (a `_MODEL_SETTING`, or on a public repository a `cron`
key in any spelling) or a new local `uses: ./` call; on a public repository,
a raised timeout or `retention-days`; a composite action patch that adds a
`_MODEL_SETTING`, a `.github/scripts/` patch that adds a `_MODEL_FLAG`, and
either file with no patch;
and a `pr-pipeline.yaml` change with any added or removed line off
`_SAFE_PIPELINE_LINE`, unless it only edits trailing comments.

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
from collections.abc import Callable, Iterable
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
    # The listing reached the files API's cap, so no read ever completes it
    # and its paths can never all be judged.
    files_capped: bool = False


@dataclass(frozen=True)
class Reason:
    code: str
    severity: Risk
    detail: str


@dataclass(frozen=True)
class RiskResult:
    score: Risk  # max(reason.severity), LOW when no reason
    reasons: tuple[Reason, ...]  # sorted by severity desc, then code


# What a lane pull request must not change unattended (owner decisions
# Q-FLOOR (B), Q-ENFORCE (A) and Q26 option B), each glob with its class:
# - `trust`: what mints and scopes lane tokens and judges triggers
#   (request-lane-token, check-trusted-trigger, check-kill-switch, whose
#   writeOutputs both of those write their verdicts through), code owners
#   and submodules.
# - `gate`: the merge gate's own code and the config the token broker loads:
#   resolve-config (which the broker runs from main in its signer process,
#   effect-grants.json included), the rate guard, every pr-merge script and
#   the workflow that wires them, babysit_merge*, babysit_risk.py and
#   babysit_review_evidence.py (which compute the review's clear condition),
#   the ci-status workflow and
#   the pipeline config.
# - `enforcement`: the rest of the modules the floored scripts import and
#   the Python that decides the holds (test_merge_holds_sync.py derives both
#   closures and requires them here).
# A `trust` or `gate` path holds for a person (HIGH_FLOOR). An `enforcement`
# path holds until the security lane's review binds to the head with no
# open finding (REVIEW_FLOOR, `review-path:`), so no person is needed.
# merge-holds.mjs HOLD_PATH_CLASSES is the same list (test_merge_holds_sync.py).
FLOOR_CLASSES: tuple[tuple[str, str], ...] = (
    (".github/actions/check-trusted-trigger/**", "trust"),
    ("**/CODEOWNERS", "trust"),
    ("**/.gitmodules", "trust"),
    (".github/actions/resolve-config/**", "gate"),
    (".github/actions/check-kill-switch/**", "trust"),
    (".github/actions/request-lane-token/**", "trust"),
    (".github/actions/log-api-budget/rate-guard.mjs", "gate"),
    (".github/actions/log-api-budget/rate-limits.json", "gate"),
    (".github/scripts/pr-merge/merge-holds.mjs", "gate"),
    (".github/scripts/pr-merge/enable-auto-merge.mjs", "gate"),
    (".github/scripts/pr-merge/superseded.mjs", "gate"),
    (".github/scripts/pr-merge/clear-escalations.mjs", "gate"),
    (".github/scripts/pr-merge/carry-run-cache.mjs", "gate"),
    (".github/scripts/pr-merge/gate-check.mjs", "gate"),
    (".github/scripts/pr-merge/head-ref-map.mjs", "gate"),
    (".github/scripts/pr-merge/lane-records.mjs", "gate"),
    (".github/scripts/pr-merge/last-report.mjs", "gate"),
    (".github/scripts/pr-merge/rate-stop.bash", "gate"),
    (".github/scripts/pr-merge/refire-refused.mjs", "gate"),
    (".github/scripts/pr-merge/rotation.mjs", "gate"),
    (".github/scripts/pr-merge/sweep-summary.mjs", "gate"),
    (".github/scripts/pr-merge/who.mjs", "gate"),
    (".github/scripts/pr-merge/post-unarmed-status.mjs", "gate"),
    (".github/scripts/pr-merge/verify-answers.mjs", "gate"),
    (".github/scripts/pr-merge/listing-carry.mjs", "gate"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_risk.py", "gate"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_check_inputs.py", "enforcement"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_checks.py", "enforcement"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_classify.py", "enforcement"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_dependabot.py", "enforcement"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_feedback.py", "enforcement"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_gh.py", "enforcement"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_merge.py", "gate"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_merge_policy.py", "gate"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_postmerge.py", "enforcement"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_repo_config.py", "enforcement"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_review_evidence.py", "gate"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_review_trigger.py", "enforcement"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_run_cache.py", "enforcement"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_state.py", "enforcement"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_util.py", "enforcement"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_verify_evidence.py", "enforcement"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_whole_review.py", "enforcement"),
    (".github/workflows/pr-require-checks.yml", "enforcement"),
    (".github/workflows/pr-merge.yml", "enforcement"),
    ("docs/conventions/pr-pipeline.yaml", "gate"),
    (".github/scripts/pr-unblock/address-feedback.mjs", "enforcement"),
    (".github/scripts/pr-unblock/gate-source.mjs", "enforcement"),
    (".github/scripts/pr-unblock/thread-scope.mjs", "enforcement"),
    (".github/scripts/pr-unblock/retry-fetch.mjs", "enforcement"),
    (".github/scripts/work-resolve-issue/report-outcome.mjs", "enforcement"),
    (".github/scripts/work-resolve-issue/limits.mjs", "enforcement"),
    (".github/scripts/work-resolve-issue/retry-fetch.mjs", "enforcement"),
    (".github/scripts/pr-unblock/fix-ci-context.mjs", "enforcement"),
    (".github/scripts/maintenance-reconcile-lost-runs/infra-failure.mjs", "enforcement"),
    (".github/scripts/work-resolve-issue/stop-routes.json", "enforcement"),
    (".github/scripts/work-resolve-issue/stop-routes.mjs", "enforcement"),
)  # fmt: skip
PERSON_CLASSES = frozenset({"trust", "gate"})
HIGH_FLOOR: tuple[str, ...] = tuple(g for g, c in FLOOR_CLASSES if c in PERSON_CLASSES)
REVIEW_FLOOR: tuple[str, ...] = tuple(g for g, c in FLOOR_CLASSES if c == "enforcement")
# Every floor glob, whichever clears it.
FLOOR: tuple[str, ...] = tuple(g for g, _ in FLOOR_CLASSES)
REVIEW_PATH_PREFIX = "review-path:"
# An enforcement path whose security review can never bind at this head: the
# pull request also changes a lane source (babysit_review_evidence
# `lane-source-changed`), so no lane can clear it and a person does.
UNBINDABLE_PATH_PREFIX = "review-path-unbindable:"
_UNBINDABLE_REASON = "lane-source-changed"

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
    for pattern in dict.fromkeys((*HIGH_FLOOR, *configured)):
        hits = [path for path in paths if glob_match(pattern, path)]
        if hits:
            reasons.append(Reason(f"high-path:{pattern}", Risk.HIGH, ", ".join(hits)))
    if not security_review_clean(inp.lanes):
        unbindable = _security_review_unbindable(inp.lanes)
        for pattern in REVIEW_FLOOR:
            hits = [path for path in paths if glob_match(pattern, path)]
            if hits and unbindable:
                detail = f"{', '.join(hits)}; it also changes a lane source, so no security review binds to this head"
                reasons.append(
                    Reason(f"{UNBINDABLE_PATH_PREFIX}{pattern}", Risk.HIGH, detail)
                )
            elif hits:
                detail = f"{', '.join(hits)}; a clean claude-security-review bound to this head clears it"
                reasons.append(
                    Reason(f"{REVIEW_PATH_PREFIX}{pattern}", Risk.HIGH, detail)
                )
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
# Spend on a subscription or prepaid credit: reported, never held.
COST_FINDING_CODE = "cost-finding"
# A workflow that gains a secrets reference, or a new model leg, widens what
# a credential or an agent can reach: a person's hold, which no cost decision
# clears.
SECRET_EXPOSURE_CODE = "secret-exposure-review"
AGENT_SURFACE_CODE = "agent-surface-review"
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
# Model or turn settings: the CLI flags, and in YAML an `ANTHROPIC_*MODEL`
# variable or a `model:` or `max-turns:` input.
_MODEL_FLAG = re.compile(r"--model\b|--max-turns\b", re.IGNORECASE)
_MODEL_SETTING = re.compile(
    _MODEL_FLAG.pattern
    + r"|\bANTHROPIC_\w*MODEL\b|(?:^|[\s{,'\"])(?:model|max[-_]turns)['\"]?\s*:",
    re.IGNORECASE,
)
# Added workflow lines that spend model usage: a schedule in any YAML or JSON
# spelling and a model or turn setting.
_COST_WORKFLOW_LINE = re.compile(
    r"\bcron\s*:|[\"']cron[\"']\s*:|" + _MODEL_SETTING.pattern, re.IGNORECASE
)
# Standard hosted runners are free only on public repositories, so on any
# other a runs-on line, a Windows or macOS label (a matrix value) or a
# schedule (recurring runs) charges.
_COST_PRIVATE_LINE = re.compile(
    r"\bruns-on\s*:|\bmacos\b|\bwindows\b|\bcron\s*:|[\"']cron[\"']\s*:",
    re.IGNORECASE,
)
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


_ENTRY = re.compile(r"""(['"]?)([^\s'":#{}\[\],]+)\1\s*:(?:\s+(.*))?$""")
_FLOW_PAIR = re.compile(r"""(['"]?)([^\s'":#{}\[\],]+)\1\s*:\s*([^,{}]*)""")
_BLOCK_SCALAR = re.compile(r"[|>][0-9+-]*")


def _yaml_entries(text: str) -> list[tuple[tuple[str, ...], str]]:
    """(key path, value) for each mapping entry and list scalar in YAML text,
    read from indentation: a list item's segment is its index (`[0]`), a
    block entry's value is empty, a block scalar's lines are skipped, and a
    one-line flow mapping adds its pairs. Enough to place a timeout or a
    runner label, not a YAML parser."""
    entries: list[tuple[tuple[str, ...], str]] = []
    stack: list[tuple[int, str]] = []
    items: Counter[tuple[str, ...]] = Counter()
    scalar_at = -1  # the indent of the key whose block scalar is open
    for line in text.split("\n"):
        content = line.split(" #", 1)[0].rstrip()
        stripped = content.lstrip()
        indent = len(content) - len(stripped)
        if not stripped or stripped.startswith("#"):
            continue
        if scalar_at >= 0 and indent > scalar_at:
            continue
        scalar_at = -1
        dash = stripped == "-" or stripped.startswith("- ")
        # A list may sit at its key's own indent; a sibling item closes the
        # one before it.
        while stack and (
            stack[-1][0] > indent
            or (
                stack[-1][0] == indent
                and (not dash or stack[-1][1].startswith("["))
            )
        ):
            stack.pop()
        while stripped == "-" or stripped.startswith("- "):
            parent = tuple(s for _, s in stack)
            stack.append((indent, f"[{items[parent]}]"))
            items[parent] += 1
            rest = stripped[1:].lstrip()
            indent += len(stripped) - len(rest)
            stripped = rest
        if not stripped:
            continue
        path = tuple(s for _, s in stack)
        m = _ENTRY.match(stripped)
        if not m and stripped.startswith("{"):
            entries += [(path + (k,), _scalar(v)) for _, k, v in _FLOW_PAIR.findall(stripped)]
            continue
        if not m:
            entries.append((path, _scalar(stripped)))
            continue
        key, value = m[2], _scalar(m[3] or "")
        entries.append((path + (key,), value))
        if not value or _BLOCK_SCALAR.fullmatch(value):
            stack.append((indent, key))
            if value:
                scalar_at = indent
        elif value.startswith("{"):
            entries += [
                (path + (key, k), _scalar(v)) for _, k, v in _FLOW_PAIR.findall(value)
            ]
    return entries


# A runs-on value that is one matrix key or input, as is or through fromJSON.
_RUNNER_REF = re.compile(
    r"\$\{\{\s*(?:fromJSON\(\s*)?(matrix|inputs)\.([\w-]+)\s*\)?\s*\}\}",
    re.IGNORECASE,
)


def _referenced_runners(text: str) -> list[str]:
    """The labels a `runs-on` value of `${{ matrix.<key> }}` or
    `${{ inputs.<name> }}` can take from the text itself: each scalar value
    of that matrix key (include entries too), and that input's default and
    options."""
    refs = {
        (m[1].casefold(), m[2].casefold())
        for value in _runner_values(text)
        if (m := _RUNNER_REF.fullmatch(value))
    }
    values: list[str] = []
    if not refs:
        return values
    for path, value in _yaml_entries(text):
        names = [p.casefold() for p in path]
        if not value or not names or "{" in value:
            continue
        item = names[-1].startswith("[")
        for kind, name in refs:
            if kind not in names[:-1]:
                continue
            if kind == "matrix" and names[-1] == name:
                values += _labels(value)
            elif kind == "matrix" and item and names[-2:-1] == [name]:
                values.append(value)
            elif kind == "inputs" and names[-2:] == [name, "default"]:
                values += _labels(value)
            elif kind == "inputs" and item and names[-3:-1] == [name, "options"]:
                values.append(value)
    return values


def _free(value: str) -> bool:
    labels = _labels(value)
    if "self-hosted" in (label.casefold() for label in labels):
        return True
    return bool(labels) and all(_FREE_RUNNER.fullmatch(label) for label in labels)


def _new_runners(raw: Any, added: list[str], public: bool) -> list[str]:
    """Runner values the change adds that are not free: from the head text
    against the base text when both were read, with the matrix values and
    input defaults a runs-on expression names, and from added inline runs-on
    lines. Unread text and an added block holds."""
    contents = getattr(raw, "contents", None)
    pair = contents if isinstance(contents, tuple) and len(contents) == 2 else None
    base, head = pair if pair else (None, None)
    gained: Counter[str] = Counter()
    if isinstance(head, str):
        before = base if isinstance(base, str) else ""
        gained.update(_runner_values(head) + _referenced_runners(head))
        gained.subtract(_runner_values(before) + _referenced_runners(before))
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
# Any secrets reference: `secrets.NAME`, `secrets.*`, `secrets['NAME']`, the
# whole `secrets` context as an argument, and `secrets: inherit`.
_SECRET_REF = re.compile(
    r"\bsecrets\s*(?:\.\s*(?:[A-Za-z0-9_]+|\*)|\[[^\]]*\])|\bsecrets\b(?=\s*\))"
    r"|\bsecrets\s*:\s*inherit\b",
    re.IGNORECASE,
)
# Inside a `${{ }}` expression, the bare `secrets` context anywhere outside a
# string literal (`${{ secrets }}`, `contains(secrets, 'X')`) is a reference
# too; `has-secrets` or `steps.secrets-check` is another name.
_EXPRESSION = re.compile(r"\$\{\{(.*?)\}\}")
_STRING_LITERAL = re.compile(r"'(?:[^']|'')*'")
_BARE_SECRETS = re.compile(r"(?<![\w.-])secrets(?![\w-])(?!\s*[.\[])", re.IGNORECASE)
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
# A call to a local reusable workflow or composite action, which may start a
# model leg of its own.
_LOCAL_USES = re.compile(r"\buses\s*:\s*['\"]?(\./[^\s'\"#]+)", re.IGNORECASE)
# Files outside `.github/workflows/` that set a model leg's model or turns:
# a composite action's metadata, which can also start a leg, and the scripts
# workflows run.
_ACTIONS = (".github/actions/**/action.yml", ".github/actions/**/action.yaml")
_SCRIPTS = ".github/scripts/**"
# A timeout key at a line's start (a list item's too) or in a flow mapping,
# its value a number or an expression.
_TIMEOUT = re.compile(
    r"(?:^\s*(?:-\s+)?|[{,]\s*)['\"]?(?:leg-)?timeout-minutes['\"]?\s*:\s*"
    r"((?:\$\{\{.*?\}\}|[^,{}\[\]#])*)",
    re.IGNORECASE,
)
_TIMEOUT_KEYS = frozenset({"timeout-minutes", "leg-timeout-minutes"})
_NUMBER = re.compile(r"[0-9]+")
# GitHub cancels a job after 360 minutes unless timeout-minutes says otherwise:
# https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax
DEFAULT_TIMEOUT_MINUTES = 360
_RETENTION = re.compile(r"^\s*-?\s*retention-days\s*:\s*['\"]?([0-9]+)")
# GitHub keeps artifacts and logs 90 days unless retention-days says otherwise:
# https://docs.github.com/en/organizations/managing-organization-settings/configuring-the-retention-period-for-github-actions-artifacts-and-logs-in-your-organization
DEFAULT_ARTIFACT_RETENTION_DAYS = 90


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


# The most lines one open `${{` expression joins.
_MAX_JOINED = 8


def _logical_lines(lines: list[str]) -> list[str]:
    """`lines` with each line that leaves a `${{` expression open joined to
    the next, up to `_MAX_JOINED` lines, so a reference split across a folded
    scalar reads whole."""
    joined: list[str] = []
    held = ""
    depth = count = 0
    for line in lines:
        held = f"{held} {line}" if held else line
        depth += line.count("${{") - line.count("}}")
        count += 1
        if depth <= 0 or count >= _MAX_JOINED:
            joined.append(held)
            held = ""
            depth = count = 0
    if held:
        joined.append(held)
    return joined


def _secret_refs(line: str) -> list[str]:
    found = _SECRET_REF.findall(line)
    for expression in _EXPRESSION.findall(line):
        found += _BARE_SECRETS.findall(_STRING_LITERAL.sub("''", expression))
    return found


def _net_added(
    find: Callable[[str], list[str]], added: list[str], removed: list[str]
) -> list[str]:
    """Each match `added` gains over `removed`, so a moved or repinned line
    is not new."""
    gained = Counter(
        re.sub(r"\s+", "", m).casefold()
        for line in _logical_lines(added)
        for m in find(line)
    )
    gained.subtract(
        re.sub(r"\s+", "", m).casefold()
        for line in _logical_lines(removed)
        for m in find(line)
    )
    return sorted(m for m, n in gained.items() if n > 0)


def _new_model_legs(added: list[str], removed: list[str]) -> list[str]:
    return [
        f"new model leg {n}" for n in _net_added(_MODEL_ACTION.findall, added, removed)
    ] + [
        f"new model package run {n}"
        for n in _net_added(_MODEL_PACKAGE.findall, added, removed)
    ]


def _timeout_values(lines: list[str]) -> list[str]:
    return [v for line in lines for m in _TIMEOUT.findall(line) if (v := _scalar(m))]


def _raises(new: list[str], old: list[str], where: str = "") -> list[str]:
    """The values in `new` that raise a timeout over `old` once equal values
    cancel: an expression, or a number above every number left in `old`."""
    gained = Counter(new) - Counter(old)
    lost = Counter(old) - Counter(new)
    top = max((int(v) for v in lost if _NUMBER.fullmatch(v)), default=None)
    at = f" at {where}" if where else ""
    return [
        f"timeout{at} raised to {v}"
        if _NUMBER.fullmatch(v)
        else f"timeout{at} set to {v}"
        for v in sorted(gained)
        if not _NUMBER.fullmatch(v) or top is None or int(v) > top
    ]


def _unindexed(path: tuple[str, ...]) -> tuple[str, ...]:
    return tuple("[]" if s.startswith("[") else s for s in path)


def _is_timeout(path: tuple[str, ...], value: str) -> bool:
    return bool(path and value and path[-1].casefold() in _TIMEOUT_KEYS)


def _timeouts(
    entries: list[tuple[tuple[str, ...], str]],
) -> dict[tuple[str, ...], list[str]]:
    """Each timeout value by key path, list indices dropped so a step added
    before another does not move its timeout."""
    found: dict[tuple[str, ...], list[str]] = {}
    for path, value in entries:
        if _is_timeout(path, value):
            found.setdefault(_unindexed(path), []).append(value)
    return found


def _path_timeouts(base: str, head: str) -> list[str]:
    """Timeouts the head text raises over the base text at the same key path.
    Where the base had none, a job ran to GitHub's default; one removed from
    a job or step the head still has lets GitHub's default, or the action's
    own, apply."""
    base_entries, head_entries = _yaml_entries(base), _yaml_entries(head)
    old, new = _timeouts(base_entries), _timeouts(head_entries)
    keys = {p for p, _ in head_entries}
    parents = {p[:i] for p in keys for i in range(len(p))}
    # A timeout key the head drops from a job or step it keeps, by index.
    dropped = Counter(
        _unindexed(p)
        for p, v in base_entries
        if _is_timeout(p, v) and p not in keys and p[:-1] in parents
    )
    found = []
    for path in sorted(set(old) | set(new)):
        before, after = old.get(path, []), new.get(path, [])
        job_limit = path[-1].casefold() == "timeout-minutes"
        default = str(DEFAULT_TIMEOUT_MINUTES) if job_limit else "its default"
        if not before and job_limit:
            before = [default]
        missing = min(dropped[path], len(before) - len(after))
        if missing > 0:
            after = after + [default] * missing
        found += _raises(after, before, ".".join(path[:-1]))
    return found


def _raised_timeouts(
    f: _File, raw: Any, added: list[str], removed: list[str]
) -> list[str]:
    """Timeouts raised on a workflow that starts a model leg, or whose head
    text could not be read: a value the patch adds above every one it
    removes once equal values cancel, so one job's value moved does not hide
    another's raise, and an added expression. On a workflow that starts a
    model leg or calls a local workflow or action that may, the head text
    against the base text too: each timeout raised, set to an expression or
    removed at its own key path."""
    contents = getattr(raw, "contents", None)
    pair = contents if isinstance(contents, tuple) and len(contents) == 2 else None
    base, head = pair if pair else (None, None)
    if not isinstance(head, str):
        return _raises(_timeout_values(added), _timeout_values(removed))
    found: list[str] = []
    if _MODEL_ACTION_NAME.search(head):
        found += _raises(_timeout_values(added), _timeout_values(removed))
    elif not _LOCAL_USES.search(head):
        return found
    return found + _path_timeouts(base if isinstance(base, str) else "", head)


def _model_surface(f: _File, raw: Any) -> tuple[list[str], list[str]]:
    """(model spend, new model legs) outside `.github/workflows/`: an added
    model setting or a new model leg in a composite action's metadata, and
    an added model flag in a `.github/scripts/` file."""
    action = any(glob_match(g, p) for g in _ACTIONS for p in f.paths)
    script = any(glob_match(_SCRIPTS, p) for p in f.paths)
    if not (action or script):
        return [], []
    lines = _patch_lines(getattr(raw, "patch", None))
    if lines is None:
        return ["no patch to read"], []
    added, removed = lines
    setting = _MODEL_SETTING if action else _MODEL_FLAG
    spend = [s.strip() for s in added if setting.search(s)]
    return spend, (_new_model_legs(added, removed) if action else [])


def _raised_retention(added: list[str], removed: list[str]) -> list[str]:
    """Artifact `retention-days` values the patch adds above every one it
    removes, or above GitHub's default when it removes none: more storage
    held against the free quota."""
    new = [int(m[1]) for line in added if (m := _RETENTION.match(line))]
    old = [int(m[1]) for line in removed if (m := _RETENTION.match(line))]
    top = max(old, default=DEFAULT_ARTIFACT_RETENTION_DAYS)
    return [f"retention raised to {n}" for n in new if n > top]


def _cost_reasons(
    inp: RiskInput, files: list[_File], raw_files: list[Any]
) -> list[Reason]:
    """`cost-review-required` (HIGH) for a change that could start a real
    charge, unless `inp.cost_decision` names the owner decision that clears
    it; it holds in every lane, whatever the floor switch says. Spend that
    draws only on a subscription or prepaid credit is `cost-finding` (MED),
    reported and never held (cost is not a stop, only a real new charge is).
    A net-new secrets reference (`secret-exposure-review`) or model leg
    (`agent-surface-review`) is a security change, HIGH and a person's, which
    the cost decision does not clear."""
    charges, spends, secrets, agents = [], [], [], []
    for f, raw in zip(files, raw_files):
        if any(glob_match(g, p) for g in COST_PATHS for p in f.paths):
            charges.append(f"{f.path}: infrastructure as code")
            continue
        if inp.pulumi_dirs is None:
            charges.append(
                f"{f.path}: the base tree was not listed for Pulumi projects"
            )
            continue
        if any(
            p == d or not d or p.casefold().startswith(d.casefold() + "/")
            for d in inp.pulumi_dirs or ()
            for p in f.paths
        ):
            charges.append(f"{f.path}: in a Pulumi project")
            continue
        workflow = any(is_workflow_path(p) for p in f.paths)
        pipeline = any(glob_match(_PIPELINE_CONFIG, p) for p in f.paths)
        if not (workflow or pipeline):
            model_spend, model_legs = _model_surface(f, raw)
            if model_spend:
                spends.append(f"{f.path}: {'; '.join(model_spend)}")
            if model_legs:
                agents.append(f"{f.path}: {'; '.join(model_legs)}")
            continue
        new, old = f.paths[0], f.paths[-1]
        if new != old and not (
            is_workflow_path(old) or glob_match(_PIPELINE_CONFIG, old)
        ):
            charges.append(f"{f.path}: renamed or copied from {old}")
            continue
        lines = _patch_lines(getattr(raw, "patch", None))
        if lines is None:
            charges.append(f"{f.path}: no patch to read")
            continue
        added, removed = lines
        public = inp.public is True
        charge: list[str] = []
        spend: list[str] = []
        if workflow:
            for s in added:
                if not public and _COST_PRIVATE_LINE.search(s):
                    charge.append(s.strip())
                elif _COST_WORKFLOW_LINE.search(s):
                    spend.append(s.strip())
            secret = _net_added(_secret_refs, added, removed)
            if secret:
                secrets.append(f"{f.path}: new secrets reference {', '.join(secret)}")
            agent = _new_model_legs(added, removed)
            if agent:
                agents.append(f"{f.path}: {'; '.join(agent)}")
            spend += [
                f"new local call {n}, which may start a model leg"
                for n in _net_added(_LOCAL_USES.findall, added, removed)
            ]
            # Hosted minutes and artifact storage are free only on a public
            # repository.
            (spend if public else charge).extend(
                _raised_timeouts(f, raw, added, removed)
                + _raised_retention(added, removed)
            )
            charge += [f"runner {v}" for v in _new_runners(raw, added, public)]
        else:
            spend = _unsafe_pipeline_lines(getattr(raw, "patch", ""))
        if charge:
            charges.append(f"{f.path}: {'; '.join(charge)}")
        if spend:
            spends.append(f"{f.path}: {'; '.join(spend)}")
    reasons = []
    if charges and not inp.cost_decision:
        detail = "; ".join(charges) + (
            "; cite the owner's `**Decision recorded.**` comment on the closing "
            "issue or this pull request in the body to clear it"
        )
        reasons.append(Reason(COST_CODE, Risk.HIGH, detail))
    if spends:
        detail = "; ".join(spends) + "; subscription or prepaid spend, reported only"
        reasons.append(Reason(COST_FINDING_CODE, Risk.MED, detail))
    if secrets:
        reasons.append(Reason(SECRET_EXPOSURE_CODE, Risk.HIGH, "; ".join(secrets)))
    if agents:
        reasons.append(Reason(AGENT_SURFACE_CODE, Risk.HIGH, "; ".join(agents)))
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
    if inp.files_capped is True:
        detail = "the listing is past the files API's cap, so it never reads whole"
        reasons.append(Reason(FILES_CAPPED_CODE, Risk.HIGH, detail))
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


def _security_review_unbindable(raw_lanes: Any) -> bool:
    """Whether the security lane's evidence is unbound for good at this head:
    its one entry says `lane-source-changed`. Any other unbind (no run yet, a
    read that failed) a later review or read can clear."""
    lanes = _sequence(raw_lanes) or ()
    entries = [lane for lane in lanes if getattr(lane, "lane", None) == _HOLDING_LANE]
    return (
        len(entries) == 1
        and getattr(entries[0], "unbound_reason", None) == _UNBINDABLE_REASON
    )


def security_review_clean(raw_lanes: Any) -> bool:
    """Whether the security lane's review clears a `REVIEW_FLOOR` path: its
    one evidence entry is bound to the head, with no unbound reason, and
    counts no open finding at all, CRITICAL or below (the evidence does not
    tell IMPORTANT from SUGGESTION, so any open finding holds). Anything
    else, a missing or doubled entry included, holds."""
    lanes = _sequence(raw_lanes) or ()
    entries = [lane for lane in lanes if getattr(lane, "lane", None) == _HOLDING_LANE]
    if len(entries) != 1:
        return False
    lane = entries[0]
    total = getattr(lane, "open_findings", None)
    count = blocking(lane)
    return (
        getattr(lane, "bound", None) is True
        and getattr(lane, "unbound_reason", None) is None
        and _is_count(total)
        and total == 0
        and _is_count(count)
        and count == 0
    )


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
            # A blocking finding the lane did report holds whether or not its
            # evidence binds to the head.
            if name == _HOLDING_LANE and _is_count(count) and count > 0:
                detail = f"{count} open, evidence unbound"
                reasons.append(Reason(finding_code, finding_severity, detail))
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


# MED reasons an unattended merge passes: the diff's size and the review and
# cost findings that are reported only.
MERGEABLE_MED = frozenset(
    {
        "lines-over",
        "files-over",
        LANES["claude-review"][0],
        REPORTED_SECURITY_CODE,
        COST_FINDING_CODE,
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


# The holding reasons only a person clears (when a person is needed:
# https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/loop-lane/README.md#when-work-stops-for-the-owner,
# with real-charge and trust holds kept, and for a hold no lane can clear): a
# CRITICAL security finding, a trusted-actor widening, a real-charge hold, a
# new secrets reference or model leg, every high path
# (the floor, a configured denied path, or an aliasing path, symlink,
# submodule or mode change) and a listing past the files API's cap. The lanes
# clear every other holding reason, such as review evidence not yet bound to
# the head or a listing a read did not finish, by judging again. The one list
# both the merge gate and enable-auto-merge.mjs read.
FILES_CAPPED_CODE = "files-capped"
PERSON_CODES = frozenset(
    {
        LANES[_HOLDING_LANE][0],
        COST_CODE,
        SECRET_EXPOSURE_CODE,
        AGENT_SURFACE_CODE,
        FILES_CAPPED_CODE,
    }
)
PERSON_PREFIXES = (TRUST_GATE_PREFIX, "high-path:", UNBINDABLE_PATH_PREFIX)


def person_reasons(reasons: Iterable[Reason]) -> list[Reason]:
    """The reasons in `reasons` only a person clears (`PERSON_CODES`)."""
    return [
        r
        for r in reasons
        if r.code in PERSON_CODES or r.code.startswith(PERSON_PREFIXES)
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
