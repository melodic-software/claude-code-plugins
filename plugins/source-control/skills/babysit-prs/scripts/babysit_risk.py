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
line (a schedule runs billed minutes), a `timeout-minutes` or
`leg-timeout-minutes` above every one it removes when its head text
(`contents`) names a model leg or could not be read, or an artifact
`retention-days` above every one it removes, or above
`DEFAULT_ARTIFACT_RETENTION_DAYS` when it removes none (storage past the free
quota); or that gains a runner value (head text against base text, and added
inline `runs-on:` lines) that is not `_FREE_RUNNER` on a public repository,
or any on another. Only `RiskInput.cost_decision`, an owner decision the
caller verified, clears it.

A workflow patch that gains a `_SECRET_REF` rates HIGH as
`secret-exposure-review`, and one that gains a `_MODEL_ACTION` or a
`_MODEL_PACKAGE` run rates HIGH as `agent-surface-review`, each counted
against the lines it removes so a move or repin is not new; the secrets
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
import re
from collections import Counter
from collections.abc import Iterable
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
    # Bound by a main-run review of the head (babysit_review_evidence
    # `_main_lane`), the only binding that lane-arms a `gate` path
    # (`lane_armed`).
    main_run: bool = False


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
    # Unresolved review threads on the pull request, read only when a
    # lane-armable `gate` path could clear (`lane_arm_pending`); None (unread)
    # keeps every `gate` path with a person.
    open_threads: int | None = None


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
# - `gate`: the rest of the merge gate's own code: the rate guard and the
#   other pr-merge scripts; the main-run review's scripts, whose verdict
#   writer sets the counts; every workflow `gated_workflow` names (owner
#   decision Q11 (A), 2026-10-28): the review workflows, ci-status
#   (pr-require-checks.yml, which posts the required status and runs the
#   hold step), each that holds a credential beyond its job's GITHUB_TOKEN,
#   a job token dying with its job while an App key or PAT outlives the run,
#   and each whose token has `actions: write`, which dispatches those
#   credentialed workflows. The generator derives
#   those rows from the workflow files (`GATE_WORKFLOWS` below), so a
#   workflow that gains a secret joins the gate. A workflow outside it that
#   gains a write scope, a privileged trigger or a secret holds by its patch
#   instead (`_workflow_privilege_gains`, `secret-exposure-review`). And
#   what changes what agents may do unattended or what later reviews judge
#   against: Claude Code settings (hooks, permission allows) and the hook
#   scripts under `.claude/hooks/`, `.mcp.json`,
#   `CLAUDE.md`, `AGENTS.md`, `REVIEW.md` and the synced standards. Those
#   review-surface rows (`_NO_AUTHOR_LIFT`) never take the author lift.
# - `enforcement`: the rest of the modules the floored scripts import and
#   the Python that decides the holds (test_merge_holds_sync.py derives both
#   closures and requires them here), and the scripts that act on a
#   pr-unblock stop's route (report-escalation.sh, adjudicate-feedback.mjs,
#   publish-feedback.mjs, apply-patch.mjs) with every module they import and
#   the routing table they read, so a held reason cannot be dropped unreviewed.
# A `trust` or `gate` path holds for a person (HIGH_FLOOR). An `enforcement`
# path holds until the security lane's review binds to the head with no
# open finding (REVIEW_FLOOR, `review-path:`), so no person is needed. So
# does a `gate` path on a trusted person's own pull request that only their
# own commits touched, on a head pr-verify passed (AUTHOR_REVIEW_FLOOR,
# `RiskInput.author_reviewed`); a lanes App pull request's never does, nor
# does a `trust` path: agents commit as the trusted owner, so what scopes a
# lane token, and what could widen the lift or drop a floor row for the next
# pull request, always waits for a person.
# The one table: scripts/sync-hold-floor.py writes it into merge-holds.mjs
# HOLD_PATH_CLASSES, the review callers' hold-paths and ci-status's
# hold_patterns, and test_merge_holds_sync.py runs its --check.
FLOOR_CLASSES: tuple[tuple[str, str], ...] = (
    (".github/actions/check-trusted-trigger/**", "trust"),
    ("**/CODEOWNERS", "trust"),
    ("**/.gitmodules", "trust"),
    (".github/actions/resolve-config/**", "trust"),
    (".github/actions/check-kill-switch/**", "trust"),
    (".github/actions/request-lane-token/**", "trust"),
    (".github/actions/log-api-budget/rate-guard.mjs", "gate"),
    (".github/actions/log-api-budget/rate-limits.json", "gate"),
    (".github/scripts/pr-merge/merge-holds.mjs", "trust"),
    (".github/scripts/pr-merge/enable-auto-merge.mjs", "trust"),
    (".github/scripts/pr-merge/superseded.mjs", "trust"),
    (".github/scripts/pr-merge/clear-escalations.mjs", "trust"),
    (".github/scripts/pr-merge/carry-run-cache.mjs", "gate"),
    (".github/scripts/pr-merge/gate-check.mjs", "trust"),
    (".github/scripts/pr-merge/head-ref-map.mjs", "trust"),
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
    (".github/actions/report-check-run/posting-run.mjs", "gate"),
    ("scripts/sync-hold-floor.py", "trust"),
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
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_util.py", "enforcement"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_verify_evidence.py", "enforcement"),
    ("plugins/source-control/skills/babysit-prs/scripts/babysit_whole_review.py", "enforcement"),
    ("docs/conventions/pr-pipeline.yaml", "trust"),
    (".github/scripts/pr-unblock/address-feedback.mjs", "enforcement"),
    (".github/scripts/pr-unblock/escalation-routes.mjs", "enforcement"),
    (".github/scripts/pr-unblock/escalation-routes.json", "enforcement"),
    (".github/scripts/pr-unblock/gate-source.mjs", "enforcement"),
    (".github/scripts/pr-unblock/thread-scope.mjs", "enforcement"),
    (".github/scripts/pr-unblock/retry-fetch.mjs", "enforcement"),
    (".github/scripts/work-resolve-issue/report-outcome.mjs", "enforcement"),
    (".github/scripts/work-resolve-issue/limits.mjs", "enforcement"),
    (".github/scripts/work-resolve-issue/retry-fetch.mjs", "enforcement"),
    (".github/scripts/pr-unblock/report-escalation.sh", "enforcement"),
    (".github/scripts/pr-unblock/adjudicate-feedback.mjs", "enforcement"),
    (".github/scripts/pr-unblock/publish-feedback.mjs", "enforcement"),
    (".github/scripts/pr-unblock/request-budget.mjs", "enforcement"),
    (".github/scripts/pr-unblock/dependency-classify.mjs", "enforcement"),
    (".github/scripts/apply-patch/apply-patch.mjs", "enforcement"),
    (".github/scripts/apply-patch/predicates.mjs", "enforcement"),
    (".github/scripts/apply-patch/protected-paths.mjs", "enforcement"),
    (".github/scripts/apply-patch/retry-fetch.mjs", "enforcement"),
    (".github/scripts/pr-unblock/fix-ci-context.mjs", "enforcement"),
    (".github/scripts/pr-unblock/feedback-dispatch.mjs", "enforcement"),
    (".github/scripts/pr-unblock/verify-notes.mjs", "enforcement"),
    (".github/scripts/pr-unblock/limit-stop.mjs", "enforcement"),
    (".github/scripts/pr-unblock/dispatch-record.mjs", "enforcement"),
    (".github/scripts/maintenance-reconcile-lost-runs/infra-failure.mjs", "enforcement"),
    (".github/scripts/work-resolve-issue/stop-routes.json", "enforcement"),
    (".github/scripts/work-resolve-issue/stop-routes.mjs", "enforcement"),
    (".github/scripts/pr-review-main/**", "gate"),
    # Agent settings and instruction files, whatever their name or depth:
    # settings, hooks and the scripts settings registers, skills, agents,
    # commands, rules, output styles and memory (owner decision Q11: agent
    # settings and instruction files stay gated).
    ("**/.claude/**", "gate"),
    ("**/.claude-lane/**", "gate"),
    # The security review applies both as its criteria.
    ("docs/conventions/instruction-exception-register/**", "gate"),
    ("docs/conventions/untrusted-content/**", "gate"),
    ("**/.mcp.json", "gate"),
    ("**/CLAUDE.md", "gate"),
    ("**/CLAUDE.local.md", "gate"),
    ("**/AGENTS.md", "gate"),
    ("REVIEW.md", "gate"),
    ("docs/standards/**", "gate"),
    # BEGIN hold-floor GATE_WORKFLOWS: generated by scripts/sync-hold-floor.py
    (".github/workflows/dependabot-fragments.yml", "gate"),
    (".github/workflows/eval-browser-dispatch.yml", "gate"),
    (".github/workflows/intake-reenter.yml", "gate"),
    (".github/workflows/intake-triage.yml", "gate"),
    (".github/workflows/maintenance-audit-lane-runs.yml", "gate"),
    (".github/workflows/maintenance-reconcile-lost-runs.yml", "gate"),
    (".github/workflows/post-merge-demotion-alert.yml", "gate"),
    (".github/workflows/post-merge-test-mutation.yml", "gate"),
    (".github/workflows/pr-feedback-dispatch.yml", "gate"),
    (".github/workflows/pr-merge.yml", "gate"),
    (".github/workflows/pr-refine.yml", "gate"),
    (".github/workflows/pr-require-checks.yml", "gate"),
    (".github/workflows/pr-review-hosted.yml", "gate"),
    (".github/workflows/pr-review-main.yml", "gate"),
    (".github/workflows/pr-review-security-hosted.yml", "gate"),
    (".github/workflows/pr-run-activity-read.yml", "gate"),
    (".github/workflows/pr-run-activity-write.yml", "gate"),
    (".github/workflows/pr-unblock-dispatch.yml", "gate"),
    (".github/workflows/pr-unblock.yml", "gate"),
    (".github/workflows/pr-verify.yml", "gate"),
    (".github/workflows/release-publish-plugins.yml", "gate"),
    (".github/workflows/work-resolve-issue.yml", "gate"),
    (".github/workflows/work-unblock.yml", "gate"),
    # END hold-floor GATE_WORKFLOWS
)  # fmt: skip
PERSON_CLASSES = frozenset({"trust", "gate"})

# Owner decision Q7 (#10743): with `merge.lane-arm-gate` on, a `gate` path not
# in `merge.person-held` (docs/conventions/pr-pipeline.yaml, the
# merge-enforcement set) waits for no person once both review lanes are bound
# to a main-run review of the head with no open finding and no review thread
# is open (`lane_armed`). A `trust` path never does. Copied here by
# scripts/sync-hold-floor.py, whose --check fails on a stale copy.
# BEGIN hold-floor LANE_ARM: generated by scripts/sync-hold-floor.py
LANE_ARM_GATE = True
PERSON_HELD: tuple[str, ...] = (
    ".github/scripts/pr-merge/merge-holds.mjs",
    ".github/scripts/pr-merge/enable-auto-merge.mjs",
    ".github/scripts/pr-merge/superseded.mjs",
    ".github/scripts/pr-merge/clear-escalations.mjs",
    ".github/scripts/pr-merge/gate-check.mjs",
    ".github/scripts/pr-merge/head-ref-map.mjs",
    ".github/workflows/pr-merge.yml",
    ".github/workflows/pr-require-checks.yml",
    ".github/workflows/pr-review-hosted.yml",
    ".github/workflows/pr-review-security-hosted.yml",
    ".github/workflows/pr-review-main.yml",
    ".github/scripts/pr-review-main/**",
    ".github/workflows/pr-verify.yml",
)
# END hold-floor LANE_ARM
# The `gate` globs that lane-arm: none with the switch off.
LANE_ARMED_FLOOR: tuple[str, ...] = (
    tuple(g for g, c in FLOOR_CLASSES if c == "gate" and g not in PERSON_HELD)
    if LANE_ARM_GATE is True
    else ()
)

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
    r"|\bsecrets\b(?=\s*\))|\bsecrets\s*:\s*inherit\b"
    rf"|{_EXPRESSION_SECRET}{_NOT_JOB_TOKEN}",
    re.IGNORECASE,
)
# A lane token minted in the run, or an OIDC token a cloud trusts:
# `id-token: write`, or `write-all`, which sets "access for all of the
# available permissions" (https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions#permissions),
# id-token among them.
_MINTED_CREDENTIAL = re.compile(
    r"\buses\s*:\s*['\"]?[^\s'\"]*request-lane-token|\bid-token\s*:\s*['\"]?write\b"
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
    code = "\n".join(
        line.split(" #", 1)[0]
        for line in text.split("\n")
        if not line.lstrip().startswith("#")
    )
    return bool(
        _NON_JOB_SECRET.search(code)
        or _MINTED_CREDENTIAL.search(code)
        or _DISPATCH_SCOPE.search(code)
    )


HIGH_FLOOR: tuple[str, ...] = tuple(g for g, c in FLOOR_CLASSES if c in PERSON_CLASSES)
REVIEW_FLOOR: tuple[str, ...] = tuple(g for g, c in FLOOR_CLASSES if c == "enforcement")
AUTHOR_REVIEW_CLASSES = frozenset({"gate"})
# The review's own surface, which owner decision Q11 (A) keeps with a person:
# a review cannot judge the workflows holding its or other credentials, the
# scripts that set its counts, or the files that set what agents may do and
# what reviews judge against, so these `gate` rows never take the author lift.
_NO_AUTHOR_LIFT = frozenset(
    {
        ".github/scripts/pr-review-main/**",
        "**/.claude/**",
        "**/.claude-lane/**",
        "docs/conventions/instruction-exception-register/**",
        "docs/conventions/untrusted-content/**",
        "**/.mcp.json",
        "**/CLAUDE.md",
        "**/CLAUDE.local.md",
        "**/AGENTS.md",
        "REVIEW.md",
        "docs/standards/**",
    }
)
AUTHOR_REVIEW_FLOOR: tuple[str, ...] = tuple(
    g
    for g, c in FLOOR_CLASSES
    if c in AUTHOR_REVIEW_CLASSES
    and g not in _NO_AUTHOR_LIFT
    and not g.startswith(".github/workflows/")
)
# Every floor glob, whichever clears it.
FLOOR: tuple[str, ...] = tuple(g for g, _ in FLOOR_CLASSES)
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
    reviewed = _author_reviewed(inp.author_reviewed, paths, configured)
    # A configured glob is never lane-armed, even when it repeats a floor row.
    armed = lane_armed(inp)
    for pattern in dict.fromkeys((*HIGH_FLOOR, *configured)):
        if armed and pattern in LANE_ARMED_FLOOR and pattern not in configured:
            continue
        hits = [
            path
            for path in paths
            if glob_match(pattern, path)
            and not (path in reviewed and pattern in AUTHOR_REVIEW_FLOOR)
        ]
        if hits:
            reasons.append(Reason(f"high-path:{pattern}", Risk.HIGH, ", ".join(hits)))
    if not security_review_clean(inp.lanes):
        # A pull request that also changes a lane source binds the security
        # review only from main (babysit_review_evidence `_main_bound`), so
        # a clean main-run review clears these too.
        for pattern in (*REVIEW_FLOOR, *AUTHOR_REVIEW_FLOOR):
            candidates = paths if pattern in REVIEW_FLOOR else reviewed
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


def lanes_clean_on_main(raw_lanes: Any) -> bool:
    """Whether both review lanes (`LANES`) each have one evidence entry bound
    to the head by a main-run review (`main_run`), with no unbound reason and
    no open finding at all. The evidence counts only findings and CRITICAL
    ones, so any open finding, a SUGGESTION included, keeps a person."""
    lanes = _sequence(raw_lanes)
    if lanes is None:
        return False
    for name in LANES:
        entries = [lane for lane in lanes if getattr(lane, "lane", None) == name]
        if len(entries) != 1:
            return False
        lane = entries[0]
        total = getattr(lane, "open_findings", None)
        count = blocking(lane)
        if not (
            getattr(lane, "bound", None) is True
            and getattr(lane, "main_run", None) is True
            and getattr(lane, "unbound_reason", None) is None
            and _is_count(total)
            and total == 0
            and _is_count(count)
            and count == 0
        ):
            return False
    return True


def lane_arm_pending(inp: RiskInput) -> bool:
    """Whether reading the open review threads could lane-arm `inp`: the
    switch is on, a changed path matches a lane-armed `gate` glob, and both
    lanes are clean on main. The caller reads them only then and scores again
    with `open_threads`."""
    if not LANE_ARMED_FLOOR or not lanes_clean_on_main(inp.lanes):
        return False
    files = _sequence(inp.files) or ()
    paths = [
        p
        for f in files
        for p in (getattr(f, "path", None), getattr(f, "previous_path", None))
    ]
    return any(
        isinstance(p, str) and glob_match(g, p) for p in paths for g in LANE_ARMED_FLOOR
    )


def lane_armed(inp: RiskInput) -> bool:
    """Whether the `LANE_ARMED_FLOOR` globs wait for no person: the switch is
    on, no review thread is open (`open_threads` read as 0), and both lanes
    are clean on main (`lanes_clean_on_main`). Anything unread holds."""
    threads = inp.open_threads
    return (
        bool(LANE_ARMED_FLOOR)
        and _is_count(threads)
        and threads == 0
        and lanes_clean_on_main(inp.lanes)
    )


def _author_reviewed(
    raw: Any, paths: list[str], configured: Iterable[str]
) -> list[str]:
    """The changed `paths` in `raw` (`RiskInput.author_reviewed`) that a
    `gate` glob matches and no other floor or configured glob does: only
    those leave `high-path:` for `review-path:`. Anything but a frozenset of
    strings names none."""
    if not (isinstance(raw, frozenset) and all(isinstance(p, str) for p in raw)):
        return []
    held = [*(g for g in HIGH_FLOOR if g not in AUTHOR_REVIEW_FLOOR), *configured]
    return [
        path
        for path in dict.fromkeys(paths)
        if path in raw
        and any(glob_match(g, path) for g in AUTHOR_REVIEW_FLOOR)
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
    r"\bsecrets\s*(?:\.\s*(?:[A-Za-z0-9_]+|\*)|\[[^\]]*\])|\bsecrets\b(?=\s*\))"
    r"|\bsecrets\s*:\s*inherit\b"
    rf"|{_EXPRESSION_SECRET}(?:[^}}]|\}}(?!\}}))*\}}\}}",
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


def _code_lines(lines: list[str]) -> list[str]:
    """Lines with YAML comments dropped: a whole-line comment, or the text
    after ` #`."""
    return [
        line.split(" #", 1)[0] for line in lines if not line.lstrip().startswith("#")
    ]


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
        widened += [f"added line {m}" for m in _net_added(_WRITE_TEXT, added, removed)]
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
    return _net_added(_SECRET_REF, _code_lines(head.split("\n")), before)


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
            secret = _net_added(_SECRET_REF, added, removed)
            if secret and f.path not in secret_files:
                secrets.append(f"{f.path}: new secrets reference {', '.join(secret)}")
            agent = [
                f"new model leg {n}" for n in _net_added(_MODEL_ACTION, added, removed)
            ] + [
                f"new model package run {n}"
                for n in _net_added(_MODEL_PACKAGE, added, removed)
            ]
            if agent:
                agents.append(f"{f.path}: {'; '.join(agent)}")
            # Hosted minutes and artifact storage are free only on a public
            # repository.
            if not public:
                charge += _raised_timeouts(f, raw, added, removed)
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
    if not needs_main_review(paths, head_file, inp.base_sha):
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
        if path.casefold().endswith(MEDIA_SUFFIXES):
            reasons.append(
                Reason(f"no-patch:{path}", Risk.MED, "no patch: line counts unknown")
            )
        else:
            detail = (
                "no patch, so no review read it (git calls a file with a NUL byte"
                " binary, and an over-size patch is not sent); a person reads it"
            )
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
        *_long_line_reasons(inp, files or [], list(raw_files or ())),
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
# A file with no patch passes unread only as an image, font or PDF, which
# nothing runs. Any other file (a script whose NUL byte makes git call it
# binary, an over-size patch) no review read, so a person does.
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
        PERMISSION_WIDENING_CODE,
        PRIVILEGED_TRIGGER_CODE,
        FILES_CAPPED_CODE,
    }
)
PERSON_PREFIXES = (
    TRUST_GATE_PREFIX,
    "high-path:",
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
