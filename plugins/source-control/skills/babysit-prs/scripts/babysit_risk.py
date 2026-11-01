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

The lane table is fixed here. The HIGH path floor is `FLOOR_CLASSES`, the paths
every consumer shares, plus the repository's `merge.diff-check.floor-paths`
rows (`floor_for`, `RiskInput.floor_rows`), which can add to it and never drop
or loosen a built-in row. The floor is narrow (owner decision Q-FLOOR (B)): the
code main runs to mint and scope lane tokens and judge triggers, code owners
and submodules, and it holds whatever the floor switch says. Its
`enforcement` entries (`Floor.review`) rate HIGH as `review-path:<glob>`
instead, which a clean security review bound to the head clears
(`security_review_clean`, owner decision Q26 option B), and so do the
`gate` entries in `RiskInput.author_reviewed` (owner direction 2026-10-27).
No other path rates
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

Cost is not a stop; only a real new charge is (docs/contracts/loop-lane/
README.md, "When work stops for the owner"). A change that could start one
(billed infrastructure or billed runner minutes) rates HIGH as
`cost-review-required` in every lane, floor or not and whatever `floor_exempt`
says: any `COST_PATHS` file (Pulumi, Terraform, Bicep, ARM templates) or file
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

Off a public repository, a raised timeout is a `timeout-minutes` or
`leg-timeout-minutes`: on a workflow whose head text (`contents`) names a model leg or could not be
read, one the patch adds above every one it removes once equal values cancel
or an added expression; and on one that names a model leg or a local `uses:
./` workflow or action, head text against base text at each key path (list
indices dropped), one raised, set to an expression, added above the highest
number already at its path (a `timeout-minutes` path with none above
`DEFAULT_TIMEOUT_MINUTES`; a `leg-timeout-minutes` set where none was is a
cap, not a raise), or removed from a job or step the head keeps.

A workflow patch that gains a `_SECRET_REF` (or a bare `secrets` inside a
`${{ }}` expression or an `if:` value, outside a string) rates HIGH as `secret-exposure-review`, and one that
gains a `_MODEL_ACTION` or a `_MODEL_PACKAGE` run, in a workflow or a
composite action's `action.yml`, rates HIGH as `agent-surface-review`, each
counted against the lines it removes, an expression split across lines read
whole, so a move or repin is not new; so does a composite action file with
no patch, unless it is deleted, re-moded, or renamed from another composite
action, with no line added. The secrets
reference is also read from the head text against the base text, so a
workflow with no patch is not skipped. A workflow whose token gains a write
scope rates HIGH as `permission-widening-review`: its base and head text are
parsed and each job's write scopes compared (a job left with no
`permissions:` of its own or at the top level runs on the repository default
and counts as a gain; an added file compares against none; unread text, a
repeated key or an alias holds), with net-added `write` lines as a raw-text
backstop. Where PyYAML is not installed the text alone decides: a `write`
grant the head adds, a `permissions:` key it drops, or an added file with
jobs and no `permissions:` key. One that gains a `PRIVILEGED_TRIGGERS` trigger (`pull_request_target`, `workflow_run`, or one
on text an outsider writes: issues, comments, reviews, discussions, `repository_dispatch`)
rates HIGH as `privileged-trigger-review`, read the same two ways. They widen
what a credential, an agent or a write token can reach, so all four are a
person's (`PERSON_CODES`) and no cost decision clears them.

Cost means only what can bill. Model usage under a subscription or prepaid
credit does not, so a model or turn flag reports nothing; nor do hosted
minutes or artifact storage on a public repository, so a schedule, a raised
timeout or a raised `retention-days` there reports nothing. A
`pr-pipeline.yaml` change with any added or removed line off
`_SAFE_PIPELINE_LINE`, unless it only edits trailing comments, is the MED
`cost-finding`, reported and never held.

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
import math
import re
from collections import Counter
from collections.abc import Callable, Iterable, Mapping
from dataclasses import dataclass
from functools import lru_cache
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
    # Git blob ids, read with the modes: `blob` on the side `mode` names,
    # `previous_blob` on the base side of a two-sided change. With no patch,
    # they show a file carries no content a review did not read
    # (`_unread_content`); None holds it for a person.
    blob: str | None = None
    previous_blob: str | None = None


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


# (glob, class, whether a `gate` row may take the author lift).
FloorRows = tuple[tuple[str, str, bool], ...]


@dataclass(frozen=True)
class RiskInput:
    files: tuple[ChangedFile, ...]
    files_complete: bool  # the listing was read to its end
    max_changed_lines: int | None  # merge.diff-check.max-changed-lines at the base SHA
    high_paths: tuple[str, ...]  # configured denied paths, joined to Floor.high
    lanes: tuple[LaneEvidence, ...]
    # The switches the pr-merge lane may turn off (merge.diff-check); the
    # defaults keep every check. An unset line cap is MED unless optional.
    high_floor: bool = True
    # `merge.diff-check.path-holds`: False moves every path hold (the
    # `high-path:` floor and configured globs, `review-path:`) to
    # `RiskResult.skipped`; anything else keeps them (owner decision Q15).
    path_holds: bool = True
    max_changed_files: int | None = 8  # None: no cap
    lines_optional: bool = False
    # The repository is public, where standard hosted runners are free; any
    # other value reads every runs-on and macOS line as a charge.
    public: bool | None = None
    # The owner decision the caller verified for a `cost-review-required`
    # change (its comment URL); None keeps the hold.
    cost_decision: str | None = None
    # Directories holding a Pulumi project file (Pulumi.yaml, .yml or .json)
    # at the base ("" for the root): any change under one is infrastructure
    # as code.
    pulumi_dirs: tuple[str, ...] | None = ()
    # Paths only a trusted author's own commits touched: the path floor and
    # the manifest review leave them out (owner decision 2026-10-22).
    floor_exempt: frozenset[str] = frozenset()
    # `gate` paths a trusted person's own commits alone touched, on a head
    # pr-verify passed, on that person's own pull request
    # (babysit_merge_policy.author_reviewed_paths): they rate `review-path:`
    # as an enforcement path does (owner direction 2026-10-27). Anything but
    # a frozenset of strings lifts nothing.
    author_reviewed: frozenset[str] = frozenset()
    # The listing reached the files API's cap, so no read ever completes it
    # and its paths can never all be judged.
    files_capped: bool = False
    # The pull request's base commit, `bind()`'s `base_sha`: with it a
    # read-only workflow's head text (`ChangedFile.contents`) shows the
    # main-run review does not bind it. None holds as if it did.
    base_sha: str | None = None
    # `merge.diff-check.floor-paths`, joined to the built-in floor (`floor_for`).
    floor_rows: FloorRows = ()


@dataclass(frozen=True)
class Reason:
    code: str
    severity: Risk
    detail: str


@dataclass(frozen=True)
class RiskResult:
    score: Risk  # max(reason.severity), LOW when no reason
    reasons: tuple[Reason, ...]  # sorted by severity desc, then code
    # The path holds `RiskInput.path_holds` False left out of `reasons`.
    skipped: tuple[Reason, ...] = ()


# What a lane pull request must not change unattended (owner decisions
# Q-FLOOR (B), Q-ENFORCE (A) and Q26 option B), each glob with its class:
# - `trust`: what mints and scopes lane tokens and judges triggers
#   (request-lane-token, resolve-config, which the token broker runs from
#   main in its signer process with effect-grants.json, lane-rules.json and
#   activity-rules.json, the pipeline config, whose activity `effect:`
#   values and lane slots the broker reads, check-trusted-trigger,
#   check-kill-switch, whose writeOutputs both of those write their verdicts
#   through), code owners, submodules, and the code that computes the
#   author lift and the hold tables: babysit_merge*, babysit_risk.py and
#   babysit_review_evidence.py (which compute the review's clear
#   condition), merge-holds.mjs and scripts/sync-hold-floor.py, which writes
#   this table's copies, and the pr-merge scripts that apply and enforce the
#   holds: enable-auto-merge.mjs, superseded.mjs, clear-escalations.mjs,
#   gate-check.mjs and head-ref-map.mjs.
# This repository's rows of each class sit in `merge.diff-check.floor-paths`.
# - `gate`: the rest of the merge gate's own code: the rate guard and the
#   other pr-merge scripts; the main-run review's scripts, whose verdict
#   writer sets the counts; every workflow `gated_workflow` names (owner
#   decision Q11 (A), 2026-10-28): the review workflows, ci-status
#   (pr-require-checks.yml, which posts the required status and runs the
#   hold step), each that holds a credential beyond its job's GITHUB_TOKEN,
#   a job token dying with its job while an App key or PAT outlives the run,
#   and each whose token has `actions: write`, which dispatches those
#   credentialed workflows. The generator derives
#   those rows from the workflow files (`GATE_WORKFLOWS` in `floor-paths`), so a
#   workflow that gains a secret joins the gate. A workflow outside it that
#   gains a write scope, a privileged trigger or a secret holds by its patch
#   instead (`_workflow_privilege_gains`, `secret-exposure-review`). And
#   what changes what agents may do unattended or what later reviews judge
#   against: Claude Code settings (hooks, permission allows) and the hook
#   scripts under `.claude/hooks/`, `.mcp.json`,
#   `CLAUDE.md`, `AGENTS.md`, `REVIEW.md` and the synced standards. Those
#   review-surface rows (`_NO_AUTHOR_LIFT`, and a `floor-paths` row with
#   `author-lift: false`) never take the author lift.
# - `enforcement`: the rest of the modules the floored scripts import and
#   the Python that decides the holds (test_merge_holds_sync.py derives both
#   closures and requires them here), and the scripts that act on a
#   pr-unblock stop's route (report-escalation.sh, adjudicate-feedback.mjs,
#   publish-feedback.mjs, apply-patch.mjs) with every module they import and
#   the routing table they read, so a held reason cannot be dropped unreviewed.
# A `trust` or `gate` path holds for a person (`Floor.high`). An `enforcement`
# path holds until the security lane's review binds to the head with no
# open finding (`Floor.review`, `review-path:`), so no person is needed. So
# does a `gate` path on a trusted person's own pull request that only their
# own commits touched, on a head pr-verify passed (`Floor.author_review`,
# `RiskInput.author_reviewed`); a lanes App pull request's never does, nor
# does a `trust` path: agents commit as the trusted owner, so what scopes a
# lane token, and what could widen the lift or drop a floor row for the next
# pull request, always waits for a person.
# Only the paths every consumer shares sit here. scripts/sync-hold-floor.py
# joins this table to the repository's `floor-paths` rows, writes the result
# into merge-holds.mjs HOLD_PATH_CLASSES, the review callers' hold-paths and
# ci-status's hold_patterns, and test_merge_holds_sync.py runs its --check.
FLOOR_CLASSES: tuple[tuple[str, str], ...] = (
    ("**/CODEOWNERS", "trust"),
    # The pipeline config every consumer's merge gate reads
    # (`babysit_merge_policy.CONFIG_PATH`), so the row that holds it never sits
    # inside it.
    ("docs/conventions/pr-pipeline.yaml", "trust"),
    ("**/.gitmodules", "trust"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_risk.py", "trust"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_check_inputs.py", "enforcement"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_checks.py", "enforcement"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_classify.py", "enforcement"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_dependabot.py", "enforcement"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_feedback.py", "enforcement"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_gh.py", "enforcement"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_merge.py", "trust"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_merge_policy.py", "trust"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_postmerge.py", "enforcement"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_repo_config.py", "enforcement"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_review_evidence.py", "trust"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_review_trigger.py", "enforcement"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_run_cache.py", "enforcement"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_state.py", "enforcement"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_tracker_binding.py", "enforcement"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_util.py", "enforcement"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_verify_evidence.py", "enforcement"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_whole_review.py", "enforcement"),
    ("**/.claude/**", "gate"),
    ("**/.claude-lane/**", "gate"),
    ("**/.mcp.json", "gate"),
    ("**/CLAUDE.md", "gate"),
    ("**/CLAUDE.local.md", "gate"),
    ("**/AGENTS.md", "gate"),
    ("REVIEW.md", "gate"),
)  # fmt: skip
PERSON_CLASSES = frozenset({"trust", "gate"})

# A secret the job token is not: any `secrets` reference but GITHUB_TOKEN
# itself. The union of the reference forms (`secrets.X`, `secrets.*`,
# `secrets['X']`, `toJSON(secrets)`, `secrets: inherit`) and any `secrets`
# context in a `${{ }}` expression, whose span may hold a lone `}` (a string
# or a `format` placeholder); a word inside a string or a name is neither.
_NOT_JOB_TOKEN = r"(?!\s*\.\s*github_token\b)(?!\s*\[\s*['\"]github_token['\"]\s*\])"
_EXPRESSION_SECRET = r"\$\{\{(?:[^}]|\}(?!\}))*?(?<![\w.'\"-])secrets(?![\w-])"
_NON_JOB_SECRET = re.compile(
    r"\bsecrets\s*(?:\.\s*(?!github_token\b)(?:[A-Za-z0-9_]+|\*)"
    r"|\[(?!\s*['\"]github_token['\"]\s*\])[^\]]*\])"
    r"|\bsecrets\b(?=\s*\))|\bsecrets['\"]?\s*:\s*['\"]?inherit\b"
    rf"|{_EXPRESSION_SECRET}{_NOT_JOB_TOKEN}",
    re.IGNORECASE,
)
# A lane token minted in the run, or an OIDC token a cloud trusts:
# `id-token: write`, its key or value quoted or not, or `write-all`, which
# sets "access for all of the available permissions" (https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions#permissions),
# id-token among them.
_MINTED_CREDENTIAL = re.compile(
    r"\buses\s*:\s*['\"]?[^\s'\"]*request-lane-token|\bid-token['\"]?\s*:\s*['\"]?write\b"
    r"|\bwrite-all\b",
    re.IGNORECASE,
)
# `actions: write`, any key or value quoting, block or flow form: the token
# can dispatch the gated credentialed workflows. `write-all` is matched above.
_DISPATCH_SCOPE = re.compile(
    r"(?<![\w-])['\"]?actions['\"]?\s*:\s*['\"]?write\b", re.IGNORECASE
)
# The review workflows, and ci-status, which posts the required status and
# holds the floor's hold step, named by file so no permission trim drops it.
_NAMED_GATE_WORKFLOW = re.compile(r"pr-review-[a-z0-9-]+|pr-require-checks")


def gated_workflow(stem: str, text: str) -> bool:
    """Whether a top-level workflow is a `gate` floor path (owner decision Q11
    (A)): a review workflow (`pr-review-*`), ci-status (`pr-require-checks`),
    or one whose comment-stripped text reaches a credential beyond its job's
    GITHUB_TOKEN (a secret other than GITHUB_TOKEN, a lane token, an OIDC
    token) or grants `actions: write`, which dispatches those."""
    if _NAMED_GATE_WORKFLOW.fullmatch(stem):
        return True
    code = "\n".join(_code_lines(text.split("\n")))
    return bool(
        _NON_JOB_SECRET.search(code)
        or _MINTED_CREDENTIAL.search(code)
        or _DISPATCH_SCOPE.search(code)
    )


AUTHOR_REVIEW_CLASSES = frozenset({"gate"})
FLOOR_ROW_CLASSES = frozenset({"trust", "gate", "enforcement"})
# The review's own surface, which owner decision Q11 (A) keeps with a person:
# a review cannot judge the workflows holding its or other credentials, the
# scripts that set its counts, or the files that set what agents may do and
# what reviews judge against, so these `gate` rows never take the author lift.
# A repository's own such rows carry `author-lift: false` in `floor-paths`.
_NO_AUTHOR_LIFT = frozenset(
    {
        "**/.claude/**",
        "**/.claude-lane/**",
        "**/.mcp.json",
        "**/CLAUDE.md",
        "**/CLAUDE.local.md",
        "**/AGENTS.md",
        "REVIEW.md",
    }
)


class FloorRowError(ValueError):
    """A `merge.diff-check.floor-paths` entry the floor cannot use."""


def floor_rows(records: Mapping[str, str]) -> FloorRows:
    """The rows in the flattened `floor-paths` records, keyed `<index>.<field>`.
    Each row is a mapping of `glob`, `class` and, on a `gate` row, `author-lift`.
    Raises `FloorRowError` on anything else, the plain-string form the key once
    took included: `author-lift` defaults to true, so a misspelled field read
    as absent would grant the lift."""
    rows: dict[int, dict[str, str]] = {}
    for key, value in records.items():
        index, dot, field = key.partition(".")
        if not dot or not index.isdecimal():
            raise FloorRowError(f"floor-paths entry {key!r} is not a mapping row")
        rows.setdefault(int(index), {})[field] = value
    if sorted(rows) != list(range(len(rows))):
        raise FloorRowError("floor-paths has an empty row")
    parsed = []
    for index in range(len(rows)):
        row = rows[index]
        unknown = set(row) - {"glob", "class", "author-lift"}
        if unknown:
            raise FloorRowError(f"floor-paths row {index}: unknown {sorted(unknown)}")
        glob, kind = row.get("glob"), row.get("class")
        if not glob:
            raise FloorRowError(f"floor-paths row {index}: no glob")
        if kind not in FLOOR_ROW_CLASSES:
            raise FloorRowError(f"floor-paths row {index}: class {kind!r}")
        lift = row.get("author-lift")
        if lift is not None and kind not in AUTHOR_REVIEW_CLASSES:
            raise FloorRowError(f"floor-paths row {index}: author-lift on a {kind} row")
        if lift not in (None, "true", "false"):
            raise FloorRowError(f"floor-paths row {index}: author-lift {lift!r}")
        parsed.append((glob, kind, lift != "false"))
    return tuple(parsed)


@dataclass(frozen=True)
class Floor:
    """The effective floor: each glob with its class, and who clears what."""

    classes: tuple[tuple[str, str], ...]
    high: tuple[str, ...]
    review: tuple[str, ...]
    author_review: tuple[str, ...]
    all: tuple[str, ...]


@lru_cache(maxsize=32)
def floor_for(rows: FloorRows = ()) -> Floor:
    """`FLOOR_CLASSES` joined to the repository's rows. The strictest row of a
    glob wins, so a row can add to the floor and never loosen it: a glob any
    row calls `trust` or refuses the lift never takes it."""
    joined = (*((g, c, True) for g, c in FLOOR_CLASSES), *rows)
    classes = tuple(dict.fromkeys((g, c) for g, c, _ in joined))
    no_lift = {
        *_NO_AUTHOR_LIFT,
        *(g for g, c, lift in joined if c == "trust" or not lift),
    }
    return Floor(
        classes=classes,
        high=tuple(dict.fromkeys(g for g, c in classes if c in PERSON_CLASSES)),
        review=tuple(dict.fromkeys(g for g, c in classes if c == "enforcement")),
        author_review=tuple(
            dict.fromkeys(
                g
                for g, c in classes
                if c in AUTHOR_REVIEW_CLASSES
                and g not in no_lift
                and not g.startswith(".github/workflows/")
            )
        ),
        all=tuple(dict.fromkeys(g for g, _ in classes)),
    )


REVIEW_PATH_PREFIX = "review-path:"

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
    floor = floor_for(inp.floor_rows)
    reviewed = _author_reviewed(inp.author_reviewed, paths, configured, floor)
    for pattern in dict.fromkeys((*floor.high, *configured)):
        hits = [
            path
            for path in paths
            if glob_match(pattern, path)
            and not (path in reviewed and pattern in floor.author_review)
        ]
        if hits:
            reasons.append(Reason(f"high-path:{pattern}", Risk.HIGH, ", ".join(hits)))
    if not security_review_clean(inp.lanes):
        # A pull request that also changes a lane source binds the security
        # review only from main (babysit_review_evidence `_main_bound`), so
        # a clean main-run review clears these too.
        for pattern in (*floor.review, *floor.author_review):
            candidates = paths if pattern in floor.review else reviewed
            hits = [path for path in candidates if glob_match(pattern, path)]
            if hits:
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


def _author_reviewed(
    raw: Any, paths: list[str], configured: Iterable[str], floor: Floor
) -> list[str]:
    """The changed `paths` in `raw` (`RiskInput.author_reviewed`) that a
    `gate` glob matches and no other floor or configured glob does: only
    those leave `high-path:` for `review-path:`. Anything but a frozenset of
    strings names none."""
    if not (isinstance(raw, frozenset) and all(isinstance(p, str) for p in raw)):
        return []
    held = [*(g for g in floor.high if g not in floor.author_review), *configured]
    return [
        path
        for path in dict.fromkeys(paths)
        if path in raw
        and any(glob_match(g, path) for g in floor.author_review)
        and not any(glob_match(g, path) for g in held)
    ]


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
# Pulumi reads a project or stack file in JSON or either YAML extension;
# Terraform's JSON forms and the ARM template names Azure's quickstart
# samples use count with the native ones.
COST_PATHS: tuple[str, ...] = (
    "**/Pulumi.yaml",
    "**/Pulumi.yml",
    "**/Pulumi.json",
    "**/Pulumi.*.yaml",
    "**/Pulumi.*.yml",
    "**/Pulumi.*.json",
    "**/*.tf",
    "**/*.tf.json",
    "**/*.tfvars",
    "**/*.tfvars.json",
    "**/*.bicep",
    "**/*.bicepparam",
    "**/azuredeploy.json",
    "**/azuredeploy.*.json",
    "**/*.azuredeploy.json",
    "**/*.azuredeploy.*.json",
)
_WORKFLOWS = (".github/workflows/*.yml", ".github/workflows/*.yaml")
_PIPELINE_CONFIG = "**/pr-pipeline.yaml"
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
    """Each runs-on value in workflow text: an inline label or list (a list
    wrapped onto continuation lines too), and a block's list items and
    `group:`/`labels:` entries (as `group:<name>`)."""
    values: list[str] = []
    lines = text.split("\n")
    for i, line in enumerate(lines):
        m = _RUNS_ON.match(line)
        if not m:
            continue
        if _scalar(m[2]):
            value, _ = _join_flow(m[2].split(" #", 1)[0], lines, i + 1)
            values.append(_scalar(value))
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
# A line whose value (a list item's too) starts a flow list or mapping.
_FLOW_START = re.compile(r"""(?:-\s+)*(?:(['"]?)[^\s'":#{}\[\],]+\1\s*:\s+)?[\[{]""")


def _join_flow(content: str, lines: list[str], i: int) -> tuple[str, int]:
    """`content`, a line that starts a flow list or mapping, with the lines
    from `lines[i]` on joined to it while that collection stays open, so a
    list wrapped onto continuation lines reads whole; and the index after the
    lines it took."""
    if not _FLOW_START.match(content.lstrip()):
        return content, i
    depth = sum(map(content.count, "[{")) - sum(map(content.count, "]}"))
    while depth > 0 and i < len(lines):
        more = lines[i].split(" #", 1)[0].strip()
        depth += sum(map(more.count, "[{")) - sum(map(more.count, "]}"))
        content += " " + more
        i += 1
    return content, i


def _yaml_entries(text: str) -> list[tuple[tuple[str, ...], str]]:
    """(key path, value) for each mapping entry and list scalar in YAML text,
    read from indentation: a list item's segment is its index (`[0]`), a
    block entry's value is empty, a block scalar's lines are skipped, a flow
    list or mapping wrapped onto continuation lines reads as one line, and a
    flow mapping adds its pairs. Enough to place a timeout or a runner label,
    not a YAML parser."""
    entries: list[tuple[tuple[str, ...], str]] = []
    stack: list[tuple[int, str]] = []
    items: Counter[tuple[str, ...]] = Counter()
    scalar_at = -1  # the indent of the key whose block scalar is open
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        content = lines[i].split(" #", 1)[0].rstrip()
        i += 1
        stripped = content.lstrip()
        indent = len(content) - len(stripped)
        if not stripped or stripped.startswith("#"):
            continue
        if scalar_at >= 0 and indent > scalar_at:
            continue
        scalar_at = -1
        content, i = _join_flow(content, lines, i)
        stripped = content.lstrip()
        dash = stripped == "-" or stripped.startswith("- ")
        # A list may sit at its key's own indent; a sibling item closes the
        # one before it.
        while stack and (
            stack[-1][0] > indent
            or (stack[-1][0] == indent and (not dash or stack[-1][1].startswith("[")))
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
            entries += [
                (path + (k,), _scalar(v)) for _, k, v in _FLOW_PAIR.findall(stripped)
            ]
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
            elif kind == "inputs" and names[-2:] in (
                [name, "default"],
                [name, "options"],
            ):
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
# whole `secrets` context as an argument, and `secrets: inherit`, its key or
# value quoted or not.
_SECRET_REF = re.compile(
    r"\bsecrets\s*(?:\.\s*(?:[A-Za-z0-9_]+|\*)|\[[^\]]*\])|\bsecrets\b(?=\s*\))"
    r"|\bsecrets['\"]?\s*:\s*['\"]?inherit\b"
    rf"|{_EXPRESSION_SECRET}(?:[^}}]|\}}(?!\}}))*\}}\}}",
    re.IGNORECASE,
)
# Inside a `${{ }}` expression, the bare `secrets` context anywhere outside a
# string literal (`${{ secrets }}`, `contains(secrets, 'X')`) is a reference
# too; `has-secrets` or `steps.secrets-check` is another name.
_STRING_LITERAL = re.compile(r"'(?:[^']|'')*'")
_BARE_SECRETS = re.compile(r"(?<![\w.-])secrets(?![\w-])(?!\s*[.\[])", re.IGNORECASE)
# An `if:` value is an expression without `${{ }}`, so its bare `secrets`
# counts too; a block scalar's lines are joined to it first.
_IF_VALUE = re.compile(
    r"(?:^\s*(?:-\s+)?|[{,]\s*)['\"]?if['\"]?\s*:\s*(.*)", re.IGNORECASE
)
_IF_BLOCK = re.compile(
    r"(\s*(?:-\s+)?['\"]?if['\"]?\s*:)\s*[|>][-+0-9]*\s*(?:#.*)?", re.IGNORECASE
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
# A call to a local reusable workflow or composite action, which may start a
# model leg of its own.
_LOCAL_USES = re.compile(r"\buses\s*:\s*['\"]?(\./[^\s'\"#]+)", re.IGNORECASE)
# A composite action's metadata, which can start a model leg outside
# `.github/workflows/`.
_ACTIONS = (".github/actions/**/action.yml", ".github/actions/**/action.yaml")
# A timeout key at a line's start (a list item's too) or in a flow mapping,
# its value a number or an expression.
_TIMEOUT_VALUE = re.compile(
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


def _expressions(
    text: str, inside: bool = False, quoted: bool = False
) -> tuple[list[str], bool, bool]:
    """(bodies, inside, quoted): the body of each `${{ }}` expression in
    `text`, read as GitHub reads one, so a `}}` inside a single-quoted
    literal does not close it, and whether an expression and a literal in it
    are still open at the end. An open expression's body runs to the end;
    `inside` and `quoted` carry that state in from a line before. Every `${{`
    starts a fresh body with no literal open, even inside another one, so a
    quote opened in a YAML comment cannot carry over a real expression; the
    body it cuts short is kept, its literal still open."""
    bodies: list[str] = []
    start = i = 0
    while i < len(text):
        if not inside or text.startswith("${{", i):
            j = text.find("${{", i)
            if j < 0:
                break
            if inside:
                bodies.append(text[start:j])
            inside, quoted = True, False
            start = i = j + 3
        elif quoted:
            # A doubled `''` closes and reopens: the same literal.
            quoted = text[i] != "'"
            i += 1
        elif text[i] == "'":
            quoted = True
            i += 1
        elif text.startswith("}}", i):
            bodies.append(text[start:i])
            inside = False
            i += 2
        else:
            i += 1
    if inside:
        bodies.append(text[start:])
    return bodies, inside, quoted


def _logical_lines(lines: list[str]) -> list[str]:
    """`lines` with each line that leaves a `${{` expression open joined to
    the next until it closes, so a reference split across a folded scalar
    reads whole however many lines pad it. One still open at the end joins
    every line after it."""
    joined: list[str] = []
    held: list[str] = []
    inside = quoted = False
    for line in lines:
        held.append(line)
        _, inside, quoted = _expressions(line, inside, quoted)
        if not inside:
            joined.append(" ".join(held))
            held = []
    if held:
        joined.append(" ".join(held))
    return joined


def _secret_refs(line: str) -> list[str]:
    """Each `${{` body's bare `secrets`, and a body whose literal is still
    open where its read ends (the line ends, or a `${{` cuts it short), which
    this read cannot follow, so it holds under its own text: only the same
    body removed elsewhere offsets it. An `if:` value with no `${{` is read
    as one body, its YAML quotes removed and a trailing comment cut."""
    found = _SECRET_REF.findall(line)
    for body in _expressions(line)[0]:
        blanked = _STRING_LITERAL.sub("''", body)
        if "'" in blanked.replace("''", ""):
            found.append(f"unclosed literal in ${{{{{body}")
        found += _BARE_SECRETS.findall(blanked)
    for value in _IF_VALUE.findall(line):
        if "${{" in value:
            continue
        value = value.strip()
        if m := re.match(r'"((?:[^"\\]|\\.)*)"', value):
            value = m[1]
        elif m := re.match(r"'((?:[^']|'')*)'", value):
            value = m[1].replace("''", "'")
        blanked = _STRING_LITERAL.sub("''", value).split(" #", 1)[0]
        found += _BARE_SECRETS.findall(blanked)
    return found


def _if_blocks(lines: list[str]) -> list[str]:
    """`lines` with each `if:` block scalar joined to its more-indented lines,
    so `_secret_refs` reads its value whole."""
    joined: list[str] = []
    indent: int | None = None
    for line in lines:
        if indent is not None and (
            not line.strip() or len(line) - len(line.lstrip()) > indent
        ):
            joined[-1] += " " + line.strip()
            continue
        indent = None
        if m := _IF_BLOCK.fullmatch(line):
            indent = len(line) - len(line.lstrip())
            line = m[1] + " "
        joined.append(line)
    return joined


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
    return [
        v for line in lines for m in _TIMEOUT_VALUE.findall(line) if (v := _scalar(m))
    ]


def _raises(
    new: list[str], old: list[str], where: str = "", ceiling: float | None = None
) -> list[str]:
    """The values in `new` that raise a timeout over `old` once equal values
    cancel: an expression, or a number above every number left in `old`, or
    above `ceiling` when none is left."""
    gained = Counter(new) - Counter(old)
    lost = Counter(old) - Counter(new)
    top = max((int(v) for v in lost if _NUMBER.fullmatch(v)), default=ceiling)
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


_ITEM_KEYS = frozenset({"id", "name", "uses", "run"})


def _items(
    entries: list[tuple[tuple[str, ...], str]],
) -> dict[tuple[str, ...], tuple[tuple[tuple[str, str], ...], set[tuple[str, ...]]]]:
    """Each innermost list item by its indexed path: its identity (its own
    `id`, `name`, `uses` with its ref dropped, and `run` values) and the
    timeout keys below it, by unindexed path."""
    ids: dict[tuple[str, ...], dict[str, str]] = {}
    keys: dict[tuple[str, ...], set[tuple[str, ...]]] = {}
    for path, value in entries:
        at = [i for i, s in enumerate(path) if s.startswith("[")]
        if not at:
            continue
        item = path[: at[-1] + 1]
        ids.setdefault(item, {})
        key = path[-1]
        if len(path) == len(item) + 1 and key in _ITEM_KEYS:
            ids[item][key] = value.split("@", 1)[0] if key == "uses" else value
        if _is_timeout(path, value):
            keys.setdefault(item, set()).add(_unindexed(path[len(item) :]))
    return {p: (tuple(sorted(d.items())), keys.get(p, set())) for p, d in ids.items()}


def _item_drops(base: list, head: list) -> Counter[tuple[str, ...]]:
    """Timeout keys the head drops from list items it keeps, by unindexed
    path. Items match by identity count, not index, and one counts as deleted
    only as far as its list shrinks and its identity is gone, taken first
    from items without the key: a step renamed, edited or moved while it
    loses its timeout still counts, and a step shifting into a deleted one's
    index does not."""
    lists: dict[tuple[str, ...], tuple[list, list]] = {}
    for side, entries in ((0, base), (1, head)):
        for item, found in _items(entries).items():
            lists.setdefault(_unindexed(item[:-1]), ([], []))[side].append(found)
    drops: Counter[tuple[str, ...]] = Counter()
    for where, (olds, news) in lists.items():
        deleted = max(0, len(olds) - len(news))
        surplus = Counter(i for i, _ in olds) - Counter(i for i, _ in news)
        for key in set().union(*(k for _, k in olds)):
            spare = sum(
                min(n, sum(i == ident and key not in k for i, k in olds))
                for ident, n in surplus.items()
            )
            lost = (
                sum(key in k for _, k in olds)
                - sum(key in k for _, k in news)
                - max(0, deleted - spare)
            )
            if lost > 0:
                drops[where + ("[]",) + key] += lost
    return drops


def _path_timeouts(base: str, head: str) -> list[str]:
    """Timeouts the head text raises over the base text at the same key path:
    with none lost there, a number above the highest the base had. Where the
    base had no `timeout-minutes`, a job ran to GitHub's default; where it had
    no `leg-timeout-minutes`, a number set is a cap; one removed from
    a job or step the head still has lets GitHub's default, or the action's
    own, apply."""
    base_entries, head_entries = _yaml_entries(base), _yaml_entries(head)
    old, new = _timeouts(base_entries), _timeouts(head_entries)
    keys = {p for p, _ in head_entries}
    parents = {p[:i] for p in keys for i in range(len(p))}
    # A timeout key the head drops from a job it keeps, or from a list item
    # it keeps.
    dropped = _item_drops(base_entries, head_entries) + Counter(
        p
        for p, v in base_entries
        if _is_timeout(p, v)
        and p not in keys
        and p[:-1] in parents
        and not any(s.startswith("[") for s in p)
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
        # With none lost, a number counts above the highest already there; a
        # key with no default set where none was is a cap, not a raise.
        numbers = [int(v) for v in before if _NUMBER.fullmatch(v)]
        ceiling = max(numbers) if numbers else None if before else math.inf
        found += _raises(after, before, ".".join(path[:-1]), ceiling)
    return found


def _billed_timeouts(raw: Any, added: list[str], removed: list[str]) -> list[str]:
    """Timeouts raised, off a public repository, on a workflow that starts a
    model leg, or whose head text could not be read: a value the patch adds
    above every one it removes once equal values cancel, so one job's value
    moved does not hide another's raise, and an added expression. On a
    workflow that starts a model leg or calls a local workflow or action that
    may, the head text against the base text too: each timeout raised, set to
    an expression or removed at its own key path."""
    contents = getattr(raw, "contents", None)
    pair = contents if isinstance(contents, tuple) and len(contents) == 2 else None
    base, head = pair if pair else (None, None)
    if not isinstance(head, str):
        return _raises(_timeout_values(added), _timeout_values(removed))
    found: list[str] = []
    if _MODEL_ACTION_NAME.search(head):
        # With base text to compare, the path pass below judges each number at
        # its key path, so the line pass keeps only added expressions.
        values = _timeout_values(added)
        if isinstance(base, str) and base:
            values = [v for v in values if not _NUMBER.fullmatch(v)]
        found += _raises(values, _timeout_values(removed))
    elif not _LOCAL_USES.search(head):
        return found
    return found + _path_timeouts(base if isinstance(base, str) else "", head)


def _composite_model_legs(f: _File, raw: Any) -> list[str]:
    """New model legs in a composite action's metadata, outside
    `.github/workflows/`; with no patch to read, one may hide there, unless
    the file is deleted, re-moded with no line added, or renamed from another
    composite action with no line added."""
    action = [any(glob_match(g, p) for g in _ACTIONS) for p in f.paths]
    if not any(action):
        return []
    lines = _patch_lines(getattr(raw, "patch", None))
    if lines is not None:
        return _new_model_legs(*lines)
    additions = getattr(raw, "additions", None)
    unchanged = type(additions) is int and additions == 0
    if f.status == "removed" or (
        f.status in ("renamed", "modified") and unchanged and all(action)
    ):
        return []
    return ["no patch to read"]


def _raised_retention(added: list[str], removed: list[str]) -> list[str]:
    """Artifact `retention-days` values the patch adds above every one it
    removes, or above GitHub's default when it removes none: more storage
    held against the free quota."""
    new = [int(m[1]) for line in added if (m := _RETENTION.match(line))]
    old = [int(m[1]) for line in removed if (m := _RETENTION.match(line))]
    top = max(old, default=DEFAULT_ARTIFACT_RETENTION_DAYS)
    return [f"retention raised to {n}" for n in new if n > top]


PERMISSION_WIDENING_CODE = "permission-widening-review"
PRIVILEGED_TRIGGER_CODE = "privileged-trigger-review"
# Triggers that run the default branch's copy with a write token on another
# event's behalf, or on text anyone who can comment or open an issue writes.
PRIVILEGED_TRIGGERS = frozenset(
    {
        "pull_request_target",
        "workflow_run",
        "issue_comment",
        "issues",
        "pull_request_review",
        "pull_request_review_comment",
        "discussion",
        "discussion_comment",
        "repository_dispatch",
    }
)
# A job with no `permissions:` of its own or at the top level runs on the
# repository default, which this module cannot see, so it may write.
_DEFAULT_TOKEN = "repository-default"
# Raw-text backstops on comment-stripped lines, so a parser difference
# between PyYAML and GitHub's cannot hide a gain: a write grant, and a
# privileged trigger in a trigger's shape (a key, a list item, or a name on
# an `on:` line), never a `github.event.workflow_run` expression.
_WRITE_TEXT = re.compile(
    r"\b(?:id-token|[a-z-]+)\s*:\s*['\"]?write\b|\bwrite-all\b", re.IGNORECASE
)
_TRIGGER_NAMES = "|".join(sorted(PRIVILEGED_TRIGGERS, key=len, reverse=True))
# A key form never takes `issues`, which is also a permissions scope.
_TRIGGER_KEY = re.compile(
    r"^\s*['\"]?("
    + "|".join(sorted(PRIVILEGED_TRIGGERS - {"issues"}, key=len, reverse=True))
    + r")['\"]?\s*(?::|,|$)"
)
_TRIGGER_ITEM = re.compile(r"^\s*-\s*['\"]?(" + _TRIGGER_NAMES + r")['\"]?\s*$")
_ON_LINE = re.compile(r"^\s*['\"]?on['\"]?\s*:(.*)$")
_TRIGGER_NAME = re.compile(r"(?<![.\w-])(" + _TRIGGER_NAMES + r")(?![.\w-])")


def _trigger_tokens(line: str) -> list[str]:
    key = _TRIGGER_KEY.match(line) or _TRIGGER_ITEM.match(line)
    if key:
        return [key[1]]
    on = _ON_LINE.match(line)
    return _TRIGGER_NAME.findall(on[1]) if on else []


_ON_BLOCK = re.compile(r"^(\s*)['\"]?on['\"]?\s*:\s*$")
_BLOCK_KEY = re.compile(r"^(\s*)['\"]?([\w-]+)['\"]?\s*:")


def _on_block_keys(lines: list[str]) -> list[str]:
    """The keys directly under a block `on:`, so a mapping-form trigger is
    read even when its name (`issues`) is also a permissions scope."""
    keys: list[str] = []
    on: int | None = None
    child: int | None = None
    for line in lines:
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip())
        if on is not None and indent <= on:
            on = child = None
        if on is None:
            block = _ON_BLOCK.match(line)
            if block:
                on = len(block[1])
            continue
        child = indent if child is None else child
        key = _BLOCK_KEY.match(line)
        if key and indent == child:
            keys.append(key[2])
    return keys


# A line whose value opens a block scalar: `key: |`, `- >-`, `key: &a |`.
_BLOCK_SCALAR_START = re.compile(r"(?:^|[:-])\s+(?:[&!]\S*\s+)*[|>][0-9+-]*\s*$")
# An anchor or tag a value may carry before its scalar.
_NODE_PROPERTIES = re.compile(r"(?:(?<=\s)[&!]\S*\s*)+$")


def _uncommented(line: str, quote: str) -> tuple[str, str]:
    """`line` up to a YAML comment, a `#` after whitespace outside quotes,
    and the quote of a quoted scalar still open at its end; `quote` carries
    one in from the line before. A quote opens a scalar only where one can
    start: the line's start, after `: `, `- ` or `? `, after the `:` of a
    quoted or bracketed key (a flow mapping's `{"K":"v"}`), or after `[`,
    `{` or `,`. A quote inside a plain scalar is text to YAML, but the line
    is read as if it opened one, to the line's end at most, so a ` #` after
    it never hides the rest."""
    carry = bool(quote)
    i = 0
    while i < len(line):
        c = line[i]
        if quote == '"' and c == "\\":
            i += 1
        elif c == quote:
            # A doubled `''` is a quote inside the single-quoted scalar.
            if quote == "'" and line.startswith("''", i):
                i += 1
            else:
                quote = ""
        elif quote:
            pass
        elif c == "#" and i and line[i - 1] in " \t":
            return line[: i - 1], ""
        elif c in "'\"":
            head = _NODE_PROPERTIES.sub("", line[:i])
            before = head.rstrip()
            carry = (
                not before
                or before[-1] in "[{,"
                or (before[-1] in ":-?" and len(before) < len(head))
                or (
                    before[-1] == ":"
                    and before[:-1].rstrip()[-1:] in ("'", '"', "]", "}")
                )
            )
            quote = c
        i += 1
    return line, quote if carry else ""


def _scalar_parent(line: str) -> int:
    """The indent a block scalar opened on `line` must exceed: its key's
    column, or a bare list item's dash."""
    rest = line.lstrip()
    dash = len(line) - len(rest)
    while rest == "-" or rest.startswith("- "):
        dash = len(line) - len(rest)
        rest = rest[1:].lstrip()
    return dash if rest[:1] in ("|", ">", "&", "!") else len(line) - len(rest)


def _code_lines(lines: list[str]) -> list[str]:
    """Lines with YAML comments dropped: a whole-line comment, or the text
    from a ` #` outside a quoted scalar. A block scalar's body, and a quoted
    scalar's lines after its first, are text, kept whole."""
    code: list[str] = []
    scalar_at: int | None = None
    quote = ""
    for line in lines:
        stripped = line.lstrip()
        if scalar_at is not None and (
            not stripped or len(line) - len(stripped) > scalar_at
        ):
            code.append(line)
            continue
        scalar_at = None
        if not quote and stripped.startswith("#"):
            continue
        cut, quote = _uncommented(line, quote)
        code.append(cut)
        if not quote and _BLOCK_SCALAR_START.search(cut):
            scalar_at = _scalar_parent(cut)
    return code


def _yaml() -> Any:
    """PyYAML, or None where it is not installed."""
    try:
        import yaml
    except ImportError:
        return None
    return yaml


_PERMISSIONS_KEY = re.compile(r"^\s*['\"]?permissions['\"]?\s*:")


def _text_privileges(text: str | None) -> tuple[Counter[str], int, set[str]]:
    """Without PyYAML: (write grants, `permissions:` keys, triggers) read
    from the comment-stripped lines of workflow text."""
    lines = _code_lines(text.split("\n")) if isinstance(text, str) else []
    grants = Counter(
        re.sub(r"\s+", "", m).casefold()
        for line in lines
        for m in _WRITE_TEXT.findall(line)
    )
    keys = sum(1 for line in lines if _PERMISSIONS_KEY.match(line))
    triggers = {t for line in lines for t in _trigger_tokens(line)}
    triggers |= set(_on_block_keys(lines)) & PRIVILEGED_TRIGGERS
    return grants, keys, triggers


def _text_gains(base: str | None, head: str) -> tuple[list[str], list[str]]:
    """`_workflow_privilege_gains` without PyYAML: a write grant the head
    text adds, a `permissions:` key it drops (a job may fall back to the
    repository default), or a file with jobs and no `permissions:` key at
    all that the base did not already have; and the privileged triggers it
    adds."""
    b_grants, b_keys, b_triggers = _text_privileges(base)
    h_grants, h_keys, h_triggers = _text_privileges(head)
    gained = h_grants.copy()
    gained.subtract(b_grants)
    widened = [f"grants {g}" for g, n in sorted(gained.items()) if n > 0]
    if h_keys < b_keys:
        widened.append("a permissions block removed")
    elif (
        h_keys == 0
        and (base is None or b_keys > 0)
        and re.search(r"^jobs\s*:", head, re.MULTILINE)
    ):
        widened.append(f"jobs on the {_DEFAULT_TOKEN} token")
    return widened, sorted((h_triggers - b_triggers) & PRIVILEGED_TRIGGERS)


def _workflow_privileges(text: str | None) -> tuple[set[str], set[str]] | None:
    """(job:scope write grants, triggers) of workflow text, None when it
    does not read as one mapping with a `jobs` mapping and a readable `on`.
    An absent side (None) and an empty document are the empty workflow. A
    repeated key, an anchor or an alias is unreadable, since GitHub's parser
    could read it otherwise."""
    if text is None:
        return set(), set()
    yaml = _yaml()
    if yaml is None:
        return None

    class _Strict(yaml.SafeLoader):
        pass

    def mapping(loader: Any, node: Any) -> dict[Any, Any]:
        seen: dict[Any, Any] = {}
        for key_node, value_node in node.value:
            key = loader.construct_object(key_node, deep=True)
            if str(key).casefold() in (str(k).casefold() for k in seen):
                raise ValueError("repeated key")
            seen[key] = loader.construct_object(value_node, deep=True)
        return seen

    _Strict.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, mapping)
    try:
        for event in yaml.parse(text, Loader=_Strict):
            if isinstance(event, yaml.AliasEvent) or getattr(event, "anchor", None):
                return None
        data = yaml.load(text, Loader=_Strict)  # noqa: S506 - SafeLoader subclass
    except Exception:  # noqa: BLE001 - unreadable holds
        return None
    if data is None:
        # An empty document runs nothing.
        return set(), set()
    if not isinstance(data, dict) or not isinstance(data.get("jobs"), dict):
        return None
    # PyYAML reads a plain `on` key as the YAML 1.1 bool; GitHub reads "on".
    on = data.get("on", data.get(True))
    if on is None:
        triggers: set[str] = set()
    elif isinstance(on, str):
        triggers = {on}
    elif isinstance(on, list):
        triggers = {str(t) for t in on}
    elif isinstance(on, dict):
        triggers = {str(t) for t in on}
    else:
        return None

    def writes(perm: Any) -> set[str] | None:
        if perm is None:
            return None
        if perm == "read-all" or perm == {}:
            return set()
        if perm == "write-all":
            return {"*"}
        if not isinstance(perm, dict):
            return {"?"}
        return {
            str(scope).casefold()
            for scope, level in perm.items()
            if level not in ("read", "none")
        }

    top = writes(data.get("permissions"))
    grants: set[str] = set()
    for name, job in data["jobs"].items():
        own = writes(job.get("permissions")) if isinstance(job, dict) else {"?"}
        scopes = own if own is not None else top
        for scope in scopes if scopes is not None else {_DEFAULT_TOKEN}:
            grants.add(f"{name}:{scope}")
    return grants, {t.casefold() for t in triggers}


def _workflow_privilege_gains(
    f: _File, raw: Any, patch: Any
) -> tuple[list[str], list[str]]:
    """(permission widenings, privileged triggers gained) of one changed
    workflow: its base text against its head text (an added file against
    none), and its patch's net-added lines as a backstop. Unreadable text
    holds as a widening."""
    contents = getattr(raw, "contents", None)
    if getattr(raw, "contents_error", None) is not None or not (
        isinstance(contents, tuple) and len(contents) == 2
    ):
        return ["contents unreadable"], []
    if not isinstance(contents[1], str) or not (
        contents[0] is None or isinstance(contents[0], str)
    ):
        return ["contents unreadable"], []
    if _yaml() is None:
        widened, triggers = _text_gains(contents[0], contents[1])
    else:
        base = _workflow_privileges(contents[0])
        head = _workflow_privileges(contents[1])
        if base is None or head is None:
            return ["unreadable, malformed, a repeated key or an alias"], []
        widened = sorted(head[0] - base[0])
        triggers = sorted((head[1] - base[1]) & PRIVILEGED_TRIGGERS)
    lines = _patch_lines(patch)
    if lines is not None:
        added, removed = (_code_lines(side) for side in lines)
        widened += [
            f"added line {m}" for m in _net_added(_WRITE_TEXT.findall, added, removed)
        ]
        gained = Counter(t for line in added for t in _trigger_tokens(line))
        gained.subtract(t for line in removed for t in _trigger_tokens(line))
        triggers += sorted(t for t, n in gained.items() if n > 0 and t not in triggers)
    return widened, triggers


def _text_secret_gains(raw: Any) -> list[str]:
    """Secrets references a workflow's head text gains over its base text
    (comment-stripped), so a change with no patch, or one a cost branch
    skips, is still read. Unread text gains nothing here: the patch check
    and `_workflow_privilege_gains` hold it."""
    contents = getattr(raw, "contents", None)
    if not (isinstance(contents, tuple) and len(contents) == 2):
        return []
    base, head = contents
    if not isinstance(head, str):
        return []
    before = _code_lines(base.split("\n")) if isinstance(base, str) else []
    return _net_added(
        _secret_refs, _if_blocks(_code_lines(head.split("\n"))), _if_blocks(before)
    )


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
    widenings: list[str] = []
    privileged: list[str] = []
    secret_files: set[str] = set()
    for f, raw in zip(files, raw_files):
        # Before any branch below can skip the file: no cost decision clears
        # a widening.
        if f.status != "removed" and any(is_workflow_path(p) for p in f.paths):
            widened, triggers = _workflow_privilege_gains(
                f, raw, getattr(raw, "patch", None)
            )
            if widened:
                widenings.append(f"{f.path}: {'; '.join(widened)}")
            if triggers:
                privileged.append(f"{f.path}: adds {', '.join(triggers)}")
            gained = _text_secret_gains(raw)
            if gained:
                secrets.append(f"{f.path}: new secrets reference {', '.join(gained)}")
                secret_files.add(f.path)
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
            model_legs = _composite_model_legs(f, raw)
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
            secret = _net_added(_secret_refs, _if_blocks(added), _if_blocks(removed))
            if secret and f.path not in secret_files:
                secrets.append(f"{f.path}: new secrets reference {', '.join(secret)}")
            agent = _new_model_legs(added, removed)
            if agent:
                agents.append(f"{f.path}: {'; '.join(agent)}")
            # Hosted minutes and artifact storage are free only on a public
            # repository.
            if not public:
                charge += _billed_timeouts(raw, added, removed)
                charge += _raised_retention(added, removed)
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
    if widenings:
        reasons.append(
            Reason(PERMISSION_WIDENING_CODE, Risk.HIGH, "; ".join(widenings))
        )
    if privileged:
        reasons.append(
            Reason(PRIVILEGED_TRIGGER_CODE, Risk.HIGH, "; ".join(privileged))
        )
    return reasons


# The longest diff line, in bytes, the main-run review reads whole. Read may
# cut a long line short, so a pull request that review binds
# (`needs_main_review`, as `bind()` decides) with a longer line in its patch
# holds for a person (`long-line-review:`), pr-review-main.yml writes
# no verdict for it, and the binder counts no verdict past it
# (babysit_review_evidence `_main_review_counted`). Bytes are at least
# characters, so the cap is never looser than a character count.
LONG_LINE_BYTES = 1800
LONG_LINE_PREFIX = "long-line-review:"


def _long_line_reasons(
    inp: RiskInput, files: list[_File], raw_files: list[Any]
) -> list[Reason]:
    """`long-line-review:<path>` (HIGH, a person's) per changed file of a pull
    request only the main-run review binds (`needs_main_review` over the
    changed paths, the head text `with_contents` read and `inp.base_sha`),
    whose patch holds a line, added, removed or context, longer than
    `LONG_LINE_BYTES`. The pull_request lanes that bind any other read the
    whole diff."""
    from babysit_review_evidence import needs_main_review

    heads = {
        getattr(raw, "path", None): getattr(raw, "contents", None)
        for raw in raw_files
        if getattr(raw, "contents_error", None) is None
    }

    def head_file(path: str, _base: str) -> str | None:
        contents = heads.get(path)
        if isinstance(contents, tuple) and len(contents) == 2:
            return contents[1] if isinstance(contents[1], str) else None
        return None

    paths = [p for f in files for p in f.paths] if inp.files_complete is True else None
    if not needs_main_review(paths, head_file, inp.base_sha, floor_for(inp.floor_rows)):
        return []
    reasons = []
    for f, raw in zip(files, raw_files):
        patch = getattr(raw, "patch", None)
        if not isinstance(patch, str):
            continue
        long = [
            line
            for line in patch.split("\n")
            if len(line[1:].encode("utf-8")) > LONG_LINE_BYTES
        ]
        if long:
            detail = (
                f"{len(long)} diff line(s) over {LONG_LINE_BYTES} bytes, more than the"
                " main-run review reads whole; a person reads them"
            )
            reasons.append(Reason(f"{LONG_LINE_PREFIX}{f.path}", Risk.HIGH, detail))
    return reasons


_UNREAD_DETAIL = (
    "no patch, so no review read it (git calls a file with a NUL byte"
    " binary, and an over-size patch is not sent); a person reads it"
)
_BLOB_ID = re.compile(r"[0-9a-f]{40}")
EMPTY_BLOB = "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391"


def _unread_content(changed: Any) -> str | None:
    """Why a file the files API sent no patch for holds for a person, or None
    when its blob ids show it carries no content a review did not read: an
    empty file added or removed, or a rename or mode change that keeps its
    blob, unless the mode gains execute. A copy, a missing or malformed blob
    id and any other change hold."""
    status = getattr(changed, "status", None)
    blob = getattr(changed, "blob", None)
    if not (isinstance(blob, str) and _BLOB_ID.fullmatch(blob)):
        return _UNREAD_DETAIL
    if status in ("added", "removed"):
        return None if blob == EMPTY_BLOB else _UNREAD_DETAIL
    if status not in ("renamed", "modified", "changed"):
        return _UNREAD_DETAIL
    if getattr(changed, "previous_blob", None) != blob:
        return _UNREAD_DETAIL
    mode = getattr(changed, "mode", None)
    if mode == getattr(changed, "previous_mode", None) or mode == "100644":
        return None
    return "no patch, and its mode gains execute; a person reads it"


def _size_reasons(
    inp: RiskInput, files: list[_File] | None, raw_files: list[Any]
) -> list[Reason]:
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
    # A path listed twice holds when either entry does.
    unread: dict[str, str | None] = {}
    for f, raw in zip(files, raw_files):
        if f.has_patch is False:
            media = f.path.casefold().endswith(MEDIA_SUFFIXES)
            unread[f.path] = unread.get(f.path) or (
                None if media else _unread_content(raw)
            )
    for path, detail in unread.items():
        if detail is None:
            reasons.append(
                Reason(f"no-patch:{path}", Risk.MED, "no patch: line counts unknown")
            )
        else:
            reasons.append(
                Reason(f"{UNREVIEWED_PATCH_PREFIX}{path}", Risk.HIGH, detail)
            )
    return reasons


def blocking(lane: Any) -> Any:
    """The lane's open findings that hold the merge: `blocking_findings`, or
    every open finding when that is None."""
    count = getattr(lane, "blocking_findings", None)
    return getattr(lane, "open_findings", None) if count is None else count


def security_review_clean(raw_lanes: Any) -> bool:
    """Whether the security lane's review clears a `Floor.review` path: its
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
    paths = _high_path_reasons(inp, files or [], list(raw_files or ()))
    skipped = (
        [] if inp.path_holds is not False else [r for r in paths if is_path_hold(r)]
    )
    reasons = [
        *_size_reasons(inp, files, list(raw_files or ())),
        *_lane_reasons(inp.lanes),
        *(r for r in paths if r not in skipped),
        *_cost_reasons(inp, files or [], list(raw_files or ())),
        *_trust_gate_reasons(files or [], list(raw_files or ())),
        *_long_line_reasons(inp, files or [], list(raw_files or ())),
    ]
    reasons.sort(key=lambda reason: (-reason.severity, reason.code))
    worst = max((reason.severity for reason in reasons), default=Risk.LOW)
    return RiskResult(Risk(worst), tuple(reasons), tuple(skipped))


def is_path_hold(reason: Reason) -> bool:
    """Whether `reason` holds for a changed path alone (`high-path:<glob>`,
    `review-path:<glob>`), which `merge.diff-check.path-holds` turns off. An
    unsafe or aliasing path (`high-path:**`) and the manifest review read
    more than the path, and stay."""
    return reason.code != UNSAFE_PATH_CODE and reason.code.startswith(
        ("high-path:", REVIEW_PATH_PREFIX)
    )


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
# A file with no patch passes unread as an image, font or PDF, which nothing
# runs, or when it carries no unread content (`_unread_content`). Any other
# file (a script whose NUL byte makes git call it binary, an over-size patch)
# no review read, so a person does.
MEDIA_SUFFIXES = (
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".bmp",
    ".woff", ".woff2", ".ttf", ".otf", ".pdf",
)  # fmt: skip
UNREVIEWED_PATCH_PREFIX = "unreviewed-patch:"


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
# https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/loop-lane/README.md#when-work-stops-for-the-owner,
# with real-charge and trust holds kept, and for a hold no lane can clear): a
# CRITICAL security finding, a trusted-actor widening, a real-charge hold, a
# new secrets reference or model leg and a listing past the files API's cap.
# A high path (the floor, a configured denied path, or an aliasing path,
# symlink, submodule or mode change) still holds, but is not a person's: the
# owner set no path restrictions (#11020). The lanes clear every other
# holding reason, such as review evidence not yet bound to the head or a
# listing a read did not finish, by judging again. The one list both the
# merge gate and enable-auto-merge.mjs read.
FILES_CAPPED_CODE = "files-capped"
PERSON_CODES = frozenset(
    {
        LANES[_HOLDING_LANE][0],
        COST_CODE,
        SECRET_EXPOSURE_CODE,
        AGENT_SURFACE_CODE,
        PERMISSION_WIDENING_CODE,
        PRIVILEGED_TRIGGER_CODE,
        FILES_CAPPED_CODE,
    }
)
PERSON_PREFIXES = (
    TRUST_GATE_PREFIX,
    UNREVIEWED_PATCH_PREFIX,
    LONG_LINE_PREFIX,
)


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
