#!/usr/bin/env python3
"""Guarded merge-readiness check and gated merge for babysit PRs.

This is a narrow, self-validating privileged helper. It exists so the babysit
workflow can be granted exactly one capability -- "merge a PR that is provably,
100% ready" -- instead of a broad `gh pr merge` / `gh api graphql` allow rule.

Contract enforced here (encoded as code, not convention):

- Owner must be in the caller-supplied `--allowed-owners` allowlist; an empty or
  missing allowlist hard-refuses (fail closed) rather than merging anything.
- Default action is READ-ONLY: report merge readiness plus every branch rule and
  check that governs the merge, and the exact blockers, so the caller can react.
- A merge only happens with `--merge` AND only when every readiness gate passes.
- A `--merge` run held on a failed AI review check re-runs that check's
  workflow run when its check run carries a `class=rate-limit` annotation, five
  hours after the failure, once per run on the pinned live head. No other
  failure class is re-run, and the re-run never counts as a pass: auto-merge
  still arms only on SUCCESS.
- Merges use the repository's allowed method (squash preferred) and NEVER pass
  `--admin` or `bypass_rules`. This helper cannot bypass branch protection,
  resolve or reply to review threads, force-push, or change settings.
- A ready PR on the default branch merges through the async merge API with the
  vetted head as `sha`, polled to a terminal status; on a base that requires a
  merge queue it is enqueued instead, through GraphQL `enqueuePullRequest` with
  the vetted head as `expectedHeadOid` (`enqueued` is queued, not merged). A host
  without the endpoint (404) falls back to `gh pr merge` for a direct merge.
  Under `--stacked-prs` every stack member, the bottom layer included, merges
  through the async API too (GitHub's required API for a stacked PR) and never
  falls back. Any other base, and every `--auto` arm, keeps `gh pr merge`,
  which GitHub routes into a merge queue on any base that has one: its result
  is read back and a PR found in the queue is reported enqueued, with its
  position. A request still pending at the poll bound is recorded under
  `--state-dir` (GitHub offers no cancel), and every later run reports it as
  merge pending until it finishes. A PR put in the queue is recorded the same
  way, and every later run reports it queued until it merges or leaves the
  queue (`dequeued`). A queue base that shows no result yet is recorded
  unconfirmed and held as merge pending until a later run reads one.
- With `--stacked-prs`, a native stack layer is judged against the stack's
  trunk and every open layer below it runs the same gate, since the async
  merge lands them together. Without it a stack layer is held as before.
- A PR authored by a dependency manager (Dependabot/Renovate-class) is held --
  never merged -- unless `--allow-dependency` is passed, or the pr-merge lane
  (`--authority pr-merge`) reads it as a mergeable Dependabot pull request.
- A PR on an unprotected base (zero required reviews AND zero required contexts)
  is held unless `--allow-unprotected` is passed: on such a base `CLEAN` proves
  nothing. A configured self login is exempt only when that base is the
  repository's default branch -- the solo-owner repo the exemption exists for.
  A self-authored PR onto an unprotected NON-default base (a stack layer, or any
  feature-onto-feature merge) is held: the default branch's required checks never
  governed it. `--stacked-prs` replaces that hold for a native stack layer only.
- A head behind its base is held on a base that requires neither up-to-date
  branches nor a merge queue, where GitHub reports a behind head `CLEAN`. One
  base compare per otherwise-ready PR proves it; an unreadable compare holds.
- A merge is held while a configured review bot still owes the LIVE head a
  review (`--review-bot-logins` with `--review-settle-minutes`, both or
  neither). A reviewer that re-reviews on push posts minutes after the head
  moves, and GitHub reports the PR mergeable throughout that window, so the
  gate waits it out rather than merging past findings that land seconds later.
  A review of the live head clears the hold immediately; the window bounds it
  so a reviewer that never engages cannot wedge the PR. Unset, the hold is
  dormant and the gate makes no request it did not make before.
- The #476 autopilot merge tier (`--autopilot-merge-tier`) layers five extra
  criteria on top of the base gate -- issue-linked, lane-authored, no blocking
  label, a distinct-bot approving review on the live head (author != approver via
  bot identity, unchanged since review, no blocking finding in its own body), and
  no human blocking comment. It is
  fail-closed: the umbrella flag refuses to run unless `--lane-logins`,
  `--approver-bot-logins`, and `--block-labels` are all non-empty. Any criterion
  failing is just another blocker, so the caller falls back to the human
  merge-ready list. Absent the flag the gate is byte-for-byte its prior self.
- The merge method, dependency-manager logins, and block labels are resolved for
  the PR's own repository from its default-branch `.claude/source-control.md`
  (`babysit_repo_config`); the matching flags are the deprecated `userConfig`
  fallback. The review-settle pair stays `userConfig`-only: a repository
  declaration of either key is ignored. A repository config that cannot be read
  refuses the run at exit 2.
- `--unattended` runs the gate under the unattended merge policy, in the
  wiring order: identity, the `gh auth status` credential chokepoint, the kill
  switch, the post-merge check (`babysit_postmerge`), demotion and cap, in
  flight, promotion evidence, eligibility, the review evidence and the diff
  score (`babysit_merge_policy`, `babysit_review_evidence`, `babysit_risk`).
  Any refusal is the blocker `unattended merge refused: <reason>` and the
  report's `unattended` block says which. With `--merge`, a stop refusal
  dequeues the identity's queued entries, a held identity entry leaves the
  queue, an eligible MED or HIGH pull request gets one upserted
  `<!-- babysit-merge-risk -->` comment (and the human-gated role label once
  an earlier run's identical comment has stood for
  `merge.risk-escalation-minutes`), a verifier refusal that
  needs a human gets the tracker's human-gated role label and one upserted
  `<!-- babysit-merge-verify-escalation -->` comment, a Dependabot update held
  under `merge.dependabot.majors: hold` gets the same label and one upserted
  `<!-- babysit-merge-dependabot-major -->` comment, and a ready pull request whose
  score does not hold it (`babysit_risk.holds`) is
  enqueued at its pinned head after a second kill-switch read, an armed
  auto-merge disarm (`disablePullRequestAutoMerge`) and a pin comment, unless
  the base changed a `merge.check-inputs` path since its merge base, when its
  branch is updated from the base (`update-branch`) instead, or, for a
  shared-copy canonical it carries, it gets the human-gated role label and one
  upserted `<!-- babysit-merge-shared-copy-escalation -->` comment; a later run that reads the queued entry back as merged at that head
  dispatches the full run. It refuses `--allow-dependency`, `--auto`,
  `--allow-unpinned-head`, `--stacked-prs` and `--allow-unprotected`. Absent
  the flag the gate is unchanged, except that plain `--merge` refuses at exit 10 when the token's
  acting login is the policy's configured agent identity, or cannot be read
  while one is configured. `--authority pr-merge` runs it as the CI pr-merge
  lane: `merge.authority` must read pr-merge, a pull request the identity
  opened with one closing issue, on a diff off `merge.diff-check.denied-paths`,
  is class C2 with no `work-class:` label read, `merge.require-verifier-verdict`
  must be true (`verifier-verdict-not-required` otherwise), no
  promotion evidence is read, the kill switch is the workflow's own check
  passed as `--lane-kill-switch proceed` (missing or any other value stops),
  the rung cap is the workflow's `--lane-rung-cap` (empty is no cap),
  only merges the identity enqueued are judged after the fact, a person whose
  newest comment says "do not merge" holds it until a later comment of theirs, and while
  `merge.report-only` is true `--merge` runs as a check that writes nothing.
  A Dependabot pull request there is its own class (`babysit_dependabot`):
  tier `auto` (every update non-major), or tier `review` with the review
  activity's `verdict=merge` marker at the head, on verified Dependabot
  commits and a green `ci-status` is eligible as C2 with no closing issue, no
  denied-path rule and no diff score, and `merge.dependabot.mode` (not
  `merge.report-only`) decides whether it writes.

Readiness is gated on GitHub's own `mergeStateStatus == CLEAN` (which integrates
required checks, approvals, conversation resolution, and up-to-date where the
base requires it) plus
explicit cross-checks so the *reason* for a block is always reported: the
effective branch rules (`rules/branches`), the review decision, unresolved
review threads, and the status-check rollup.

Exit codes: 0 ready (or merged, enqueued, or auto-merge armed), 10 not ready
(blockers, or a merge request that failed or is still pending), 11 unknown (the
pr-merge lane's `--candidate-deadline-seconds` passed before a read; no write
was cut short), 2 usage/runtime error, 3 owner out of scope (or no allowlist).
Output is a single JSON object on stdout.
"""

from __future__ import annotations

import argparse
import functools
import json
import os
import re
import time
from collections.abc import Callable, Iterable, Mapping, Sequence
from dataclasses import dataclass, replace
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any, cast
from urllib.parse import quote

import babysit_check_inputs as check_inputs
import babysit_merge_policy as merge_policy
import babysit_postmerge as postmerge
import babysit_review_evidence as review_evidence
import babysit_risk
import babysit_run_cache as run_cache
import babysit_verify_evidence as verify_evidence
import babysit_whole_review as whole_review
import babysit_repo_config as repo_policy
from babysit_state import resolve_state_dir, state_lock, write_state
from babysit_checks import check_identity_key, classify_checks
from babysit_classify import (
    DEFAULT_FEEDBACK_CONFIG,
    NON_APPROVAL_RE,
    SEVERITY_BADGE_RE,
    SEVERITY_PLAIN_RE,
    FeedbackConfig,
    actor_kind,
    has_blocking_severity,
    has_blocking_text,
    is_bot,
    is_dependency_author,
    is_self_login,
    normalize_login_set,
    normalize_self_logins,
)
from babysit_feedback import latest_reviews_by_author
from babysit_risk import LaneEvidence
from babysit_gh import (
    GraphQLUnavailableError,
    collect_lane_runs,
    compare_shows_behind,
    fetch_base_compare,
    fetch_issue_comments,
    fetch_paginated_api,
    fetch_pull_request_commits,
    fetch_pull_request_review_comments,
    fetch_pull_request_reviews,
    fetch_review_threads,
    candidate_reads,
    gh_capture,
    gh_http_status,
    gh_json,
    normalized_rest_author,
    parse_repo_number,
    pull_request_commits_once,
    resolve_author,
    resolve_authors,
    view_pr_fields,
)
from babysit_review_trigger import (
    ReviewTriggerConfig,
    fetch_review_evidence,
    has_current_head_review,
)
from babysit_util import (
    MIN_HEAD_SHA_PREFIX_LENGTH,
    DeadlineReached,
    configure_stdio,
    deadline_after,
    is_json_array,
    is_json_object,
    json_array,
    json_object,
    parse_allowed_owners,
    parse_csv_set,
    read_deadline,
    run_command,
    split_owner,
)

# A plain human "do not merge" veto that is neither a formal CHANGES_REQUESTED
# review nor the configured label: the shared blocking-text predicate does not
# carry a do-not-merge pattern, so the tier's "no human blocking comment"
# criterion matches it here. Bounded to the merge-veto sense (do/don't/do-not
# merge) so ordinary prose does not false-block.
HUMAN_MERGE_VETO_RE = re.compile(r"\bdo(?:n['’]?t| not|-not)[\s-]*merge\b", re.I)

BODY_MERGE_HOLD_RE = merge_policy.BODY_MERGE_HOLD_RE
MERGE_HOLD_LABELS = merge_policy.MERGE_HOLD_LABELS
# Where this process's gate processes share the resolved human-gated label.
HUMAN_GATED_SECTION = "human-gated-label"


def human_gated_label(repo: str) -> str:
    """The tracker's human-gated role label for `repo` (`needs-human` unless
    `.work-item-tracker.json` maps it): the label the verifier escalation adds
    and an autonomous merge holds on. Shared across a run's gate processes.
    A failed read other than a 404 raises `PostMergeReadError` and is never
    shared."""
    cached = run_cache.get(HUMAN_GATED_SECTION, repo, run_cache.MAX_AGE)
    if isinstance(cached, str) and cached:
        return cached
    owner, name = repo.split("/", 1)
    label = postmerge._role_label(owner, name, strict=True)
    run_cache.put(HUMAN_GATED_SECTION, repo, label)
    return label


def merge_hold_label(labels: Iterable[Any], *, human_gated: str | None) -> str | None:
    """The first hold label among `labels`, matched case-insensitively. An
    autonomous merge passes the resolved `human_gated` label, which holds it
    too: autonomous sessions must not resolve what carries it. An attended
    merge, the person that label asks for, passes None."""
    names = {str(name).casefold() for name in labels}
    holds = (*MERGE_HOLD_LABELS, *((human_gated,) if human_gated else ()))
    return next((label for label in holds if label.casefold() in names), None)


EXPECTED_HEAD_RE = re.compile(rf"^[0-9a-fA-F]{{{MIN_HEAD_SHA_PREFIX_LENGTH},64}}$")

# GitHub's own fixed enum contract. MergeStateStatus values meaning "mergeable,
# all commit status passing": CLEAN on github.com, HAS_HOOKS when the repo has
# pre-receive hooks (GHES) -- GitHub returns one OR the other, so both are ready.
READY_MERGE_STATES = {"CLEAN", "HAS_HOOKS"}

# The two AI review lanes `--auto` waits for. `ci-status` is the only required
# check and does not wait on these separate workflows, so auto-merge armed
# before both pass on the live head could merge ahead of their review. Each
# lane maps to the job segments its check may carry (`review /
# claude-review-status`). A name holding ` / ` must match the whole check
# name: the security job is named `security-review`, generic enough that
# another workflow's job could carry it, so it counts only under its own
# caller prefix. `pr-review-security / security-review` is the current caller,
# `security-review / security-review` the previous one, and
# `claude-security-review-status` the job of a pin that predates the fold. Old
# and new callers run side by side while repos migrate. Every matching check
# must succeed.
AI_REVIEW_CHECKS = {
    "claude-review-status": ("claude-review-status",),
    "claude-security-review-status": (
        "claude-security-review-status",
        "security-review / security-review",
        "pr-review-security / security-review",
    ),
}


def is_ai_review_check(check_name: str, names: tuple[str, ...]) -> bool:
    full = " / ".join(part.strip() for part in check_name.split("/"))
    segment = full.rsplit(" / ", 1)[-1]
    return any(full == n if " / " in n else segment == n for n in names)


# An AI review check that failed on the Claude usage limit carries a
# `class=rate-limit` annotation on its check run (ci-workflows
# `.github/actions/report-lane-outcome`). Under `--merge` the gate re-runs that
# check's workflow run once the limit has reset, instead of holding on it until
# a person re-runs it. "Reset" is conservative: the shortest plan limit is a
# five-hour session window (https://support.claude.com/en/articles/11145838,
# checked 2026-10-09), so five hours after the failure that window has reset
# whenever it started. A weekly limit outlasts it; the re-run then fails again
# and stays failed, since a run is re-run at most once.
RATE_LIMIT_CLASS_RE = re.compile(r"\bclass=rate-limit\b")
RATE_LIMIT_RERUN_DELAY = timedelta(hours=5)
ACTIONS_JOB_URL_RE = re.compile(r"/actions/runs/\d+/job/(\d+)")


def _now() -> datetime:
    return datetime.now(UTC)


def job_backs_check(job: dict[str, Any], job_id: str, check: dict[str, Any]) -> bool:
    """Whether the Actions job a check's `details_url` names is the job that
    emitted that check.

    `details_url` is set by whoever creates the check run, so it alone does not
    tie the job to the check. An Actions job's own check run shares its id, and
    its `name` and `workflow_name` are the rollup's check `name` and
    `workflowName`. The rollup's own check-run id is compared when the rollup
    carried one (the REST re-source does; `gh pr view` does not).
    """
    own_check_run = str(job.get("check_run_url") or "").rsplit("/", 1)[-1]
    if str(job.get("id")) != job_id or own_check_run != job_id:
        return False
    if check.get("id") and str(check["id"]) != job_id:
        return False
    if job.get("name") != check["name"]:
        return False
    workflow = check.get("workflow_name")
    return not workflow or job.get("workflow_name") == workflow


def rerun_rate_limited_review(
    repo: str, head: str, check: dict[str, Any]
) -> dict[str, Any]:
    """Re-run one failed AI review check's workflow run when it failed on the
    usage limit, the limit has reset, and the run was not re-run before.

    Every other case is reported with its reason and left alone: another
    failure class is never re-run. The whole run is re-run, not its failed
    jobs, because a lane whose status job reads a separate review job's output
    would re-read the cached rate-limit result and fail again.
    """
    report: dict[str, Any] = {"check": check["name"], "rerun": False}
    match = ACTIONS_JOB_URL_RE.search(check.get("details_url") or "")
    if not match:
        report["reason"] = "not a GitHub Actions job"
        return report
    job_id = match.group(1)
    try:
        job = json_object(gh_json(["api", f"repos/{repo}/actions/jobs/{job_id}"]))
        report["runId"] = run_id = job.get("run_id")
        if not job_backs_check(job, job_id, check):
            report["reason"] = "the job named by details_url did not emit this check"
            return report
        if job.get("head_sha") != head:
            report["reason"] = "the job ran on another head"
            return report
        if job.get("conclusion") != "failure":
            report["reason"] = f"job conclusion is {job.get('conclusion')!r}"
            return report
        if int(job.get("run_attempt") or 1) > 1:
            report["reason"] = "already re-run on this head; re-run at most once"
            return report
        completed = parse_github_timestamp(str(job.get("completed_at") or ""))
        if completed is None:
            report["reason"] = "job completion time unreadable"
            return report
        due = completed + RATE_LIMIT_RERUN_DELAY
        if _now() < due:
            report["reason"] = (
                "waiting for the usage limit to reset; re-run due at "
                + due.isoformat().replace("+00:00", "Z")
            )
            return report
        annotations = json_array(
            gh_json(
                [
                    "api",
                    f"repos/{repo}/check-runs/{job_id}/annotations?per_page=100",
                ]
            )
        )
    except (RuntimeError, ValueError, json.JSONDecodeError) as exc:
        report["reason"] = f"could not read the job: {type(exc).__name__}: {exc}"
        return report
    if not any(
        RATE_LIMIT_CLASS_RE.search(str(json_object(a).get("message") or ""))
        for a in annotations
    ):
        report["reason"] = "failure class is not rate-limit; never re-run"
        return report
    proc = gh_capture(
        ["api", "-X", "POST", f"repos/{repo}/actions/runs/{run_id}/rerun"]
    )
    report["rerun"] = proc.returncode == 0
    if proc.returncode != 0:
        report["reason"] = f"re-run request failed: {proc.stderr.strip()}"
    return report


def rerun_rate_limited_reviews(
    repo: str, result: dict[str, Any]
) -> list[dict[str, Any]]:
    """`rerun_rate_limited_review` over every failed AI review check of an
    open, non-draft PR whose live head is the pinned head, and of each stack
    layer below it the gate evaluated, since their holds bind this merge too."""
    layers = json_array(json_object(result.get("stack")).get("layers"))
    reruns = [
        {"pr": layer.get("pr"), **report}
        for layer in layers
        if is_json_object(layer)
        for report in rerun_rate_limited_reviews(repo, layer)
    ]
    head = result.get("headRefOid")
    if (
        result.get("headMatches") is not True
        or result.get("state") != "OPEN"
        or result.get("isDraft")
        or not isinstance(head, str)
    ):
        return reruns
    return [
        rerun_rate_limited_review(repo, head, check)
        for check in result.get("aiReviewChecks") or []
        if check.get("effective_state") == "FAILURE"
    ] + reruns


# The async merge API (`PUT .../pulls/{n}/merge-async`) answers with a request
# UUID and runs the merge in the background; the gate polls it to a terminal
# status for at most this long, at the API budget's 60-second wait cadence
# (reference/providers/github/README.md#api-budget). A request still pending
# past the bound is left to GitHub: the next run's PUT returns 409 with the
# same UUID and polls again.
ASYNC_MERGE_POLL_TIMEOUT_SECONDS = 60.0
ASYNC_MERGE_POLL_INTERVAL_SECONDS = 60.0
ASYNC_TERMINAL_STATUSES = frozenset({"merged", "enqueued", "failed"})
ASYNC_UUID_RE = re.compile(r"[0-9A-Za-z-]{1,64}")
# A `gh pr merge` the queue base took can read back as neither queued, armed,
# nor merged for a moment. The run reads the GraphQL-only queue state once,
# per the API budget; a result unseen is recorded unconfirmed. Later runs, at
# least one loop wake apart, hold it while it stays unseen, and the
# QUEUE_UNCONFIRMED_LATER_READS-th such run calls it dequeued.
QUEUE_UNCONFIRMED_LATER_READS = 2


def _poll_sleep(seconds: float) -> None:
    time.sleep(seconds)


def _poll_clock() -> float:
    return time.monotonic()


MERGE_QUEUE_AUTO_HOLD = (
    "base branch requires a merge queue -- auto-merge is not armed over a "
    "queue; the gate enqueues once the PR is fully ready"
)
STACK_AUTO_HOLD = (
    "stack layer -- auto-merge is not armed for a stack; the gate lands the "
    "stack through the async merge API once every layer is ready"
)


@dataclass(frozen=True)
class ReviewSettleConfig:
    """Hold a merge while a configured reviewer's current-head review is in flight.

    A reviewer that re-reviews on push posts minutes after the head moves, so a
    gate that reads only GitHub's mergeability can report CLEAN during that
    window and merge past findings that land seconds later (#1629). Both fields
    are required together: no duration is defaulted here, because how long a
    reviewer takes is a property of the reviewer, not of this gate.
    """

    reviewer_logins: frozenset[str]
    settle_seconds: int


@dataclass(frozen=True)
class AutopilotMergeTierConfig:
    """The extra criteria the #476 autopilot merge tier gates on, over the base
    readiness gate that every tier already shares.

    Present only when the caller passes `--autopilot-merge-tier`; absent (None)
    the gate behaves exactly as it always has, so worker/autopilot's existing
    gate-proven merges are unchanged. Every field is caller-supplied and the
    umbrella flag refuses to run with any of the three required sets empty, so
    the tier is fail-closed: it can never merge without knowing which authors are
    pipeline lanes, which login the distinct bot approver posts under, and which
    labels veto a merge.
    """

    lane_logins: frozenset[str]
    approver_bot_logins: frozenset[str]
    block_labels: frozenset[str]

    @property
    def automation_actor_config(self) -> FeedbackConfig:
        """Classify every configured pipeline identity as a bot for the veto and
        ratification scans.

        A lane or approver account GitHub misreports as a `User` (no `[bot]`
        suffix) passes the structural `is_bot` fallback in
        `find_distinct_bot_approval` but would otherwise read as a human here: a
        configured identity is *always* automation for these scans -- never a
        human merge veto, never a maintainer ratifying its own decision-default
        marker (the #450 attribution-drift hazard the ratification design
        excludes).
        """
        return FeedbackConfig(
            extra_bot_logins=self.approver_bot_logins | self.lane_logins
        )


def unresolved_threads(repo: str, number: int) -> list[dict[str, object]] | None:
    """Unresolved review threads via the single shared paginator.

    One comment per thread is enough to attribute the finding; the paginator
    drops resolved threads and fails closed on a malformed connection, so a
    hidden page can never falsely report zero unresolved threads.

    Returns None -- never `[]` -- when the session is not served GraphQL. Thread
    resolution is GraphQL-only, an empty list is indistinguishable from "zero
    unresolved threads", and that reading is the false-clean this gate exists to
    prevent. `evaluate` turns the None into a blocker naming the restriction.
    """

    def project(thread: dict[str, Any]) -> dict[str, object]:
        comments = thread.get("comments")
        first = comments[0] if isinstance(comments, list) and comments else {}
        first_object = first if is_json_object(first) else {}
        author = first_object.get("author")
        author_object = author if is_json_object(author) else {}
        return {
            "author": author_object.get("login"),
            "path": first_object.get("path"),
            "url": first_object.get("url"),
            "isOutdated": thread.get("isOutdated", False),
        }

    try:
        records = fetch_review_threads(
            repo, number, include_resolved=False, comments_first=1, projection=project
        )
    except GraphQLUnavailableError:
        return None
    return [cast(dict[str, object], record) for record in records]


def repository_default_branch(repo: str) -> str | None:
    """Return the repository's default branch, or None when it cannot be read.

    Called only when an unprotected base has already cleared every other blocker,
    so neither a protected-base run nor an already-held PR makes a request it did
    not make before. A read failure returns None, which leaves the pre-existing
    self-login exemption in place rather than inventing a hold from missing
    evidence.
    """
    cached = (
        run_cache.get(merge_policy.DEFAULT_BRANCH_SECTION, repo, run_cache.MAX_AGE)
        if SHARE_BASE_READS
        else None
    )
    if isinstance(cached, str) and cached:
        merge_policy.SHARED_DEFAULT_BRANCHES.add(repo)
        return cached
    try:
        data = gh_json(["api", f"repos/{repo}", "--jq", "{name: .default_branch}"])
    except (RuntimeError, json.JSONDecodeError):
        return None
    if not is_json_object(data):
        return None
    name = data.get("name")
    if not name:
        return None
    run_cache.put(merge_policy.DEFAULT_BRANCH_SECTION, repo, str(name))
    return str(name)


RULES_SECTION = "branch-rules"
# Whether this gate run may take the default branch and the base's rules
# from the run cache: the `--unattended` path only, whose enqueue reads them
# again (`main`). Every attended path reads them fresh.
SHARE_BASE_READS = False
# The rules this process took from the run cache, by the branch read, as
# summarized; `unattended_enqueue` reads each again before an enqueue.
SHARED_RULES: dict[str, dict[str, object]] = {}


def branch_rules(repo: str, branch: str, *, shared: bool = True) -> dict[str, object]:
    """Summarize the effective merge-governing rules for the base branch.

    Rulesets COMPOSE: `/rules/branches/{branch}` returns one rule of a given
    type PER RULESET governing the branch, so the single-rule assumption that
    held under classic branch protection does not hold here. Every repeatable
    rule is therefore folded across all rules rather than assigned from one:

    * `requiredContexts` is the union, deduped and sorted -- keeping a single
      rule's list drops every other ruleset's contexts from both
      `effectiveRules` and the unmet-required blocker. Two rulesets may
      legitimately require the same context, hence the dedupe; the sort makes
      the reported set stable regardless of the order rulesets are returned in.
    * `requireUpToDate` (strict required status checks) is the OR: one active
      strict rule that lists a required check is enough for GitHub to report
      a behind head BEHIND.
    * `requiredApprovingReviews` takes the max and `requireThreadResolution`
      the OR. That is the fail-closed direction whatever GitHub's own
      composition rule turns out to be: max/OR can only ever over-report, which
      holds a PR for a human, where last-wins can under-report and release one.
    """
    summary: dict[str, object] = {
        "requiredContexts": [],
        "requiredApprovingReviews": 0,
        "requireThreadResolution": False,
        "requireSignatures": False,
        "requireLinearHistory": False,
        "mergeQueueRequired": False,
        "requireUpToDate": False,
    }
    try:
        # `{branch}` is one path parameter. Percent-encode it, including `/`,
        # so a base such as release/1.x stays a single segment. quote(..., safe="")
        # matches Go's url.PathEscape, which go-github uses for this endpoint
        # (github.com/google/go-github repos_rules.go, ListRulesForBranch).
        # gh 2.99.0 forwards that path unchanged.
        key = f"{repo}|{branch}"
        rules = (
            run_cache.get(RULES_SECTION, key, run_cache.MAX_AGE)
            if shared and SHARE_BASE_READS
            else None
        )
        cached = is_json_array(rules)
        if not cached:
            rules = gh_json(
                ["api", f"repos/{repo}/rules/branches/{quote(branch, safe='')}"]
            )
            if is_json_array(rules):
                run_cache.put(RULES_SECTION, key, rules)
    except (RuntimeError, json.JSONDecodeError) as exc:
        # Rules are advisory context; a read failure must never fail the run.
        summary["error"] = f"could not read branch rules: {exc}"
        return summary
    required_contexts: set[str] = set()
    required_reviews = 0
    require_thread_resolution = False
    for rule in rules if is_json_array(rules) else []:
        if not is_json_object(rule):
            continue
        rtype = rule.get("type")
        raw_params = rule.get("parameters")
        params = raw_params if is_json_object(raw_params) else {}
        if rtype == "required_status_checks":
            # A context-less entry is dropped rather than carried: it names no
            # check to reconcile, and a None would sort-crash the union and
            # surface downstream as a literal "None" required context.
            rule_contexts = [
                str(c["context"])
                for c in json_array(params.get("required_status_checks"))
                if is_json_object(c) and c.get("context")
            ]
            required_contexts.update(rule_contexts)
            # The strict setting "will not take effect unless at least one status
            # check is enabled" (https://docs.github.com/en/rest/repos/rules).
            if (
                params.get("strict_required_status_checks_policy") is True
                and rule_contexts
            ):
                summary["requireUpToDate"] = True
        elif rtype == "pull_request":
            # Absence and unreadability are different facts. No key means the
            # rule requires no reviews, which is 0. A key holding anything this
            # code cannot read as a count -- null, "", 0.0, [], {} -- means a
            # requirement IS stated and its size is unknown, so it counts as
            # one: a falsy non-int must not collapse to 0, which would be the
            # single fail-OPEN step in a fold that may only ever over-report.
            if "required_approving_review_count" not in params:
                count = 0
            else:
                raw = params["required_approving_review_count"]
                count = int(raw) if isinstance(raw, int) else 1
            required_reviews = max(required_reviews, count)
            require_thread_resolution = require_thread_resolution or bool(
                params.get("required_review_thread_resolution", False)
            )
        elif rtype == "required_signatures":
            summary["requireSignatures"] = True
        elif rtype == "required_linear_history":
            summary["requireLinearHistory"] = True
        elif rtype == "merge_queue":
            summary["mergeQueueRequired"] = True
    summary["requiredContexts"] = sorted(required_contexts)
    summary["requiredApprovingReviews"] = required_reviews
    summary["requireThreadResolution"] = require_thread_resolution
    if cached:
        SHARED_RULES[branch] = summary
    return summary


# Distinct remedies per verification reason: `unsigned`, `no_user`, and
# `unknown_key` are different problems fixed in different places, so they must
# never collapse into one message. `no_user` in particular is the trap #2162
# keeps producing -- the signature itself is VALID, and nothing else in the
# loop says why GitHub still reports verified:false.
SIGNATURE_REMEDIES = {
    "unsigned": (
        "the commit carries no signature -- configure commit signing on the "
        "writing machine (never commit.gpgsign=false)"
    ),
    "no_user": (
        "the signature is valid but the author/committer email is not linked "
        "to any GitHub account -- link that email, or rewrite the commit with "
        "a linked identity (--reset-author)"
    ),
    "unknown_key": (
        "signed with a key that is not registered on the committer's GitHub "
        "account -- upload the public key to the account"
    ),
}


def evaluate_required_signatures(
    repo: str, number: int, head: str | None = None
) -> tuple[list[str], dict[str, Any]]:
    """Enforce a `required_signatures` rule against the PR's actual commits.

    `branch_rules` has always computed `requireSignatures` and, before #2265,
    nothing consumed it: a head held only by an unsigned or misattributed commit
    reported the generic `mergeStateStatus` line, whose enumeration named four
    other causes and omitted the real one. Called only when the rule is
    present, so an ungoverned base pays no extra request; a fetch failure holds
    rather than passes (the one direction this gate is allowed to be wrong in),
    stated as its own blocker so an operator sees "could not be read", never a
    fabricated "unsigned".
    """
    record: dict[str, Any] = {"required": True, "checked": False, "unverified": []}
    try:
        commits = fetch_pull_request_commits(repo, number, head)
    except (RuntimeError, json.JSONDecodeError) as exc:
        return (
            [
                "base branch requires signed commits and commit verification "
                f"could not be read ({exc}) -- held"
            ],
            record,
        )
    record["checked"] = True
    offending = [c for c in commits if not c.get("verified")]
    record["unverified"] = offending
    by_reason: dict[str, list[str]] = {}
    for commit in offending:
        sha = str(commit.get("sha") or "")[:12]
        by_reason.setdefault(str(commit.get("reason") or "unreadable"), []).append(sha)
    blockers = [
        f"base branch requires signed commits; verified:false reason={reason} "
        f"on {', '.join(shas)} -- "
        + SIGNATURE_REMEDIES.get(
            reason, f"GitHub reports verification reason {reason!r}"
        )
        for reason, shas in sorted(by_reason.items())
    ]
    return blockers, record


def approval_reports_blocking(body: str) -> bool:
    """True when an approving review's own body reports a live blocking finding.

    A distinct-bot approval can ratify the live head while its body raises a
    structured high-severity finding; the human-blocking corpus scan deliberately
    skips bot-authored items and GitHub can still return `reviewDecision=APPROVED`,
    so without this check an approve-with-blocking-findings verdict would merge.
    Only the shared classifier's *structured* severity vocabulary counts -- a
    CRITICAL/IMPORTANT marker surviving negation redaction (`has_blocking_severity`),
    or a P0-P3 severity badge / bracketed `[P0-P3]` marker. Prose severity words
    (`has_blocking_text`'s "blocking"/"regression"/"must fix") are intentionally not
    scanned: a clean approval routinely describes the fix it signs off ("resolves
    the blocking regression"), so keying on prose would over-hold legitimate
    approvals. This is the autopilot-tier answer to the open #621 question of
    whether formal APPROVED-state reviews should be severity-scanned.
    """
    return (
        has_blocking_severity(body)
        or bool(SEVERITY_BADGE_RE.search(body))
        or bool(SEVERITY_PLAIN_RE.search(body))
    )


def find_distinct_bot_approval(
    reviews: list[dict[str, Any]],
    author_login: str | None,
    head: str | None,
    approver_bot_logins: frozenset[str],
) -> dict[str, Any] | None:
    """The most recent APPROVED review by a distinct bot identity on the live head.

    Enforces two #476 criteria at once: author != approver (via bot identity) and
    head SHA unchanged since review. An approval is eligible only when its author
    is a bot (structural `[bot]`/`Bot` type, or a caller-named approver login), is
    not the PR author (normalized login compare), and was submitted against the
    exact live head commit -- a stale approval left on a since-superseded commit is
    not "unchanged since review". Reviews arrive oldest-first; the last eligible
    one wins so a re-approval on the current head is honored.
    """
    author_norm = normalize_login_set([author_login] if author_login else [])
    approver_norm = normalize_login_set(approver_bot_logins)
    match: dict[str, Any] | None = None
    for review in reviews:
        if str(review.get("state") or "") != "APPROVED":
            continue
        review_author = review.get("author")
        login = (
            review_author.get("login")
            if is_json_object(review_author)
            else review_author
        )
        typename = (
            review_author.get("__typename") if is_json_object(review_author) else None
        )
        login_norm = normalize_login_set([login])
        if login_norm & author_norm:
            continue  # same identity as the PR author -- not a distinct approver
        if not is_bot(login, typename, approver_bot_logins):
            continue
        # A bot, but it must be the configured approver identity: `is_bot` accepts
        # any `[bot]`/Bot-typed login, so without this an arbitrary installed
        # App's approval would authorize a tier merge past the configured boundary.
        if not (login_norm & approver_norm):
            continue
        commit = review.get("commit")
        commit_oid = commit.get("oid") if is_json_object(commit) else None
        if not (head and commit_oid and str(commit_oid) == str(head)):
            continue  # approval is on a superseded commit -- head moved since review
        match = review
    return match


DECISION_DEFAULT_MARKER_RE = re.compile(r"decision[ -]defaulted", re.I)
# GitHub author associations that identify a maintainer able to exercise the
# "veto before merge" window: the operators the ratification signal must come
# from. COLLABORATOR is deliberately excluded -- it is granted per-repo push
# access, not the maintainer role that owns the veto.
RATIFYING_ASSOCIATIONS = frozenset({"OWNER", "MEMBER"})
# A maintainer clears the veto only with an explicit ratification signal -- a
# small, closed, whole-word token set -- not merely any later comment (an
# unrelated "thanks" must not ratify). Matching is strict/fail-closed: a comment
# without a signal (or carrying a withheld-approval negation) does not clear, so
# an ambiguous maintainer comment over-holds to the human list. Keep this set in
# sync with the contract documented in reference/safety.md.
RATIFICATION_SIGNAL_RE = re.compile(
    r"\b(?:ratif(?:y|ied)|approved?|confirmed?)\b", re.I
)


def _decision_default_ratified(
    comments: list[dict[str, Any]],
    marker_ts: str,
    config: FeedbackConfig = DEFAULT_FEEDBACK_CONFIG,
) -> bool:
    """True when a maintainer's latest decisive comment after the marker ratifies.

    Every human-maintainer comment posted strictly after the marker is scanned and
    the latest *decisive* signal wins: a single early ratification no longer
    settles the question, so a maintainer who ratifies and then revokes ("not
    approved", "do not merge") re-holds the PR for the human list. A comment is
    decisive when it carries either an explicit ratification signal
    (`RATIFICATION_SIGNAL_RE`) or an explicit revocation signal reusing the shared
    veto vocabulary (`NON_APPROVAL_RE`, or `HUMAN_MERGE_VETO_RE`). Revocation is
    tested first, so a comment mixing both reads as a revoke (fail closed). An
    unrelated later comment ("thanks", a status question) is non-decisive and
    leaves any prior decisive signal standing.

    Ratification clears the veto only when a ratifying comment is strictly newer
    than every revoking one, so a ratify/revoke tie at the same timestamp -- like a
    bare marker with no decisive comment -- holds. Reactions are deliberately not
    consulted: the reactions API carries no author association, so a reaction
    cannot be attributed to a maintainer, and attributing it via the operator's own
    self-logins would let pipeline automation posting under that identity clear its
    own veto (the #450 attribution-drift hazard).
    """
    latest_ratify = ""
    latest_revoke = ""
    for comment in comments:
        created_at = str(comment.get("createdAt") or "")
        if created_at <= marker_ts:
            continue
        if actor_kind(comment, config) != "human":
            continue
        association = str(comment.get("authorAssociation") or "").upper()
        if association not in RATIFYING_ASSOCIATIONS:
            continue
        body = str(comment.get("body") or "")
        if NON_APPROVAL_RE.search(body) or HUMAN_MERGE_VETO_RE.search(body):
            latest_revoke = max(latest_revoke, created_at)
        elif RATIFICATION_SIGNAL_RE.search(body):
            latest_ratify = max(latest_ratify, created_at)
    return bool(latest_ratify) and latest_ratify > latest_revoke


def _ref_repo(ref: dict[str, Any]) -> str | None:
    """`owner/name` of a closing-issue reference's own repository, if present.

    A PR may close an issue in a different repository; the reference carries that
    repository, so the veto scan must read comments from it rather than assuming
    the PR's repo (where a same-numbered issue could carry no marker).
    """
    repository = ref.get("repository")
    if not is_json_object(repository):
        return None
    name = repository.get("name")
    owner = repository.get("owner")
    login = owner.get("login") if is_json_object(owner) else None
    return f"{login}/{name}" if login and name else None


def evaluate_decision_default_veto(
    repo: str,
    closing_issues: list[Any],
    config: FeedbackConfig = DEFAULT_FEEDBACK_CONFIG,
) -> tuple[list[str], list[str]]:
    """Hold when a linked issue carries an unratified 'Decision defaulted' marker.

    The triage lane records a defaulted (maintainer-vetoable) decision only as a
    `Decision defaulted: X -- veto before merge` issue comment, which a
    deterministic merge gate cannot see; the default may ride into an autopilot
    merge only once a maintainer has ratified it. Each linked issue is read from
    its own repository (a PR may close an issue in another repo). Marker matching
    is deliberately loose (over-matching merely holds more for the human). Fail
    closed: a comment-fetch failure holds the PR for the human list rather than
    merging on an unverifiable issue.
    """
    blockers: list[str] = []
    held: list[str] = []
    for ref in closing_issues:
        # Untyped either way: a linked-issue ref arrives as a raw number or as an
        # object whose "number" key may be absent. The int() below, guarded by
        # its own except, is the validation -- annotating the declared type here
        # keeps that the single place the shape is decided.
        number: Any
        if is_json_object(ref):
            number = ref.get("number")
            issue_repo = _ref_repo(ref) or repo
        else:
            number = ref
            issue_repo = repo
        try:
            issue_number = int(number)
        except (TypeError, ValueError):
            continue
        target = f"{issue_repo}#{issue_number}"
        try:
            comments = fetch_issue_comments(issue_repo, issue_number)
        except (RuntimeError, ValueError, json.JSONDecodeError) as exc:
            blockers.append(
                f"could not verify the decision-default veto on {target} "
                f"({type(exc).__name__}) -- holding for the human merge-ready list"
            )
            held.append(target)
            continue
        marker_timestamps = [
            str(c.get("createdAt") or "")
            for c in comments
            if is_json_object(c)
            and DECISION_DEFAULT_MARKER_RE.search(str(c.get("body") or ""))
        ]
        if not marker_timestamps:
            continue
        if _decision_default_ratified(comments, max(marker_timestamps), config):
            continue
        blockers.append(
            f"linked issue {target} carries an unratified 'Decision defaulted' "
            "marker -- a maintainer must ratify or veto before an autopilot merge"
        )
        held.append(target)
    return blockers, held


def _human_comments(
    repo: str,
    number: int,
    reviews: list[dict[str, Any]],
    review_comments: list[dict[str, Any]] | None,
    actor_config: FeedbackConfig,
) -> list[tuple[str, str, str]]:
    """(login, time, body, association) of every human-authored issue comment, review
    summary and inline review comment on the pull request."""
    corpus: list[dict[str, Any]] = list(fetch_issue_comments(repo, number))
    corpus.extend(reviews)
    # Inline review-thread comments are neither issue comments nor review
    # summaries; a human veto left inline whose thread is later resolved would
    # otherwise escape both the base unresolved-thread gate and this scan.
    if review_comments is None:
        review_comments = fetch_pull_request_review_comments(repo, number)
    corpus.extend(
        {
            "author": normalized_rest_author(row),
            "body": row.get("body"),
            "createdAt": row.get("created_at"),
            "authorAssociation": row.get("author_association"),
        }
        for row in review_comments
    )
    found = []
    for item in corpus:
        if actor_kind(item, actor_config) != "human":
            continue
        login = item.get("author")
        login = login.get("login") if is_json_object(login) else login
        at = item.get("submittedAt") or item.get("createdAt") or ""
        found.append(
            (
                str(login or "unknown"),
                str(at),
                str(item.get("body") or ""),
                str(item.get("authorAssociation") or "").upper(),
            )
        )
    return found


def human_blocking_logins(
    repo: str,
    number: int,
    reviews: list[dict[str, Any]],
    review_comments: list[dict[str, Any]] | None,
    actor_config: FeedbackConfig,
) -> list[str]:
    """The logins of the people with any blocking comment, sorted (the tier).

    A human "do not merge"/blocking comment that is not a formal
    CHANGES_REQUESTED and not an unresolved inline thread (both gated by the
    base gate) still halts the tier: the shared blocking-text and severity
    predicates and `HUMAN_MERGE_VETO_RE` run over every human comment.
    """
    return sorted(
        {
            login
            for login, _, body, _ in _human_comments(
                repo, number, reviews, review_comments, actor_config
            )
            if has_blocking_text(body)
            or has_blocking_severity(body)
            or HUMAN_MERGE_VETO_RE.search(body)
        }
    )


def human_veto_logins(
    repo: str,
    number: int,
    reviews: list[dict[str, Any]],
    review_comments: list[dict[str, Any]] | None,
    actor_config: FeedbackConfig,
) -> list[str]:
    """The people whose newest comment on the pull request says "do not
    merge" (`HUMAN_MERGE_VETO_RE` only), sorted (the pr-merge lane).

    Each person's newest comment, review or inline comment with text decides,
    so the same person lifts their hold with any later comment that does not
    say it, such as "go ahead", or by editing the veto away. An item with no
    text never lifts it: GitHub records an inline-only review, and an Approve
    with no text, as a review summary with an empty body. Only an OWNER,
    MEMBER or COLLABORATOR counts: on a public repository anyone else's
    comment holds nothing.
    """
    newest: dict[str, tuple[str, str]] = {}
    for login, at, body, association in _human_comments(
        repo, number, reviews, review_comments, actor_config
    ):
        if association not in merge_policy.BLOCKER_ASSOCIATIONS:
            continue
        if not body.strip():
            continue
        if login not in newest or at >= newest[login][0]:
            newest[login] = (at, body)
    return sorted(
        login for login, (_, body) in newest.items() if HUMAN_MERGE_VETO_RE.search(body)
    )


def evaluate_autopilot_tier(
    repo: str,
    number: int,
    head: str | None,
    author_login: str | None,
    labels: list[Any],
    closing_issues: list[Any],
    tier: AutopilotMergeTierConfig,
    reviews: list[dict[str, Any]] | None = None,
    review_comments: list[dict[str, Any]] | None = None,
) -> tuple[list[str], dict[str, Any]]:
    """Evaluate the #476 tier criteria that ride on top of the base gate.

    Returns the tier's own blockers plus a self-documenting per-criterion record.
    Every predicate is imported from the shared classifier (`babysit_classify`) so
    the tier never re-implements authorship, bot, or blocking-text detection. Any
    criterion failing simply adds a blocker; the caller falls back to reporting the
    PR on the human merge-ready list, never routing around the gate.
    """
    blockers: list[str] = []

    issue_linked = bool(closing_issues)
    if not issue_linked:
        blockers.append(
            "not issue-linked -- no closing-issue reference (autopilot merge tier)"
        )

    label_names = {str(name).casefold() for name in labels if name}
    blocking_labels = sorted(
        label for label in tier.block_labels if label.casefold() in label_names
    )
    if blocking_labels:
        blockers.append(
            "blocked by label(s) " + ", ".join(repr(b) for b in blocking_labels)
        )

    lane_authored = bool(
        normalize_login_set([author_login] if author_login else [])
        & normalize_login_set(tier.lane_logins)
    )
    if not lane_authored:
        blockers.append(
            f"author {author_login!r} is not a configured pipeline lane "
            "(autopilot merge tier requires a lane-authored PR)"
        )

    if reviews is None:
        reviews = fetch_pull_request_reviews(repo, number)
    # Collapse to each actor's latest decisive review before accepting a tier
    # approval: a bot that approved and then submitted CHANGES_REQUESTED (or had
    # its approval dismissed) on the same head must no longer count as the
    # approver, even when another approval keeps the base reviewDecision APPROVED.
    decisive_reviews = latest_reviews_by_author(
        {"reviews": reviews}, decisive_only=True
    )
    approval = find_distinct_bot_approval(
        decisive_reviews, author_login, head, tier.approver_bot_logins
    )
    if approval is not None and approval_reports_blocking(
        str(approval.get("body") or "")
    ):
        # The latest distinct-bot approval ratifies the live head but its own body
        # raises a structured high-severity finding. An approve-with-blocking-
        # findings verdict is not a clean tier approval, so it counts as no
        # approval (not a human blocker) -- a since-superseded earlier clean
        # approval must not be honored past the latest blocking verdict. See #621.
        blockers.append(
            "distinct-bot approving review reports blocking findings in its body "
            "(CRITICAL/IMPORTANT or a P0-P3 severity marker) -- an "
            "approve-with-blocking-findings verdict is not a clean tier approval, "
            "so it is treated as no approval"
        )
        approval = None
    elif approval is None:
        blockers.append(
            "no distinct-bot approving review on the live head "
            "(need author != approver via bot identity, approval unchanged since head)"
        )

    # A configured approver/lane account GitHub misreports as a `User` classifies
    # as a bot here, so its clean review body ("no blocking issues") does not
    # self-block the very approval `find_distinct_bot_approval` accepted -- the
    # "a bot's blocking-looking prose is not a human stop" rule extends to
    # configured bots that lack a `[bot]` suffix.
    human_blocking = human_blocking_logins(
        repo, number, reviews, review_comments, tier.automation_actor_config
    )
    if human_blocking:
        blockers.append(
            "human blocking comment(s) from "
            + ", ".join(human_blocking)
            + " -- resolve before an autopilot merge"
        )

    veto_blockers, decision_default_held = evaluate_decision_default_veto(
        repo, closing_issues, tier.automation_actor_config
    )
    blockers.extend(veto_blockers)

    tier_result = {
        "enabled": True,
        "issueLinked": issue_linked,
        "closingIssues": [
            c.get("number") if is_json_object(c) else c for c in closing_issues
        ],
        "laneAuthored": lane_authored,
        "blockingLabels": blocking_labels,
        "distinctBotApproval": (
            {
                "author": (
                    approval.get("author", {}).get("login")
                    if is_json_object(approval.get("author"))
                    else None
                ),
                "commit": (
                    approval.get("commit", {}).get("oid")
                    if is_json_object(approval.get("commit"))
                    else None
                ),
            }
            if approval
            else None
        ),
        "humanBlockingComments": human_blocking,
        "decisionDefaultHeldIssues": decision_default_held,
    }
    return blockers, tier_result


def parse_github_timestamp(raw: str) -> datetime | None:
    """Parse a GitHub ISO-8601 timestamp, tolerating the `Z` zone suffix."""
    text = raw.strip()
    if not text:
        return None
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=UTC)


def head_committed_at(repo: str, head_sha: str) -> datetime | None:
    """Committer date of the head commit, or None when it cannot be read."""
    try:
        data = gh_json(["api", f"repos/{repo}/commits/{head_sha}"])
    except (RuntimeError, json.JSONDecodeError):
        return None
    if not is_json_object(data):
        return None
    commit = data.get("commit")
    if not is_json_object(commit):
        return None
    committer = commit.get("committer")
    if not is_json_object(committer):
        return None
    return parse_github_timestamp(str(committer.get("date") or ""))


def latest_check_activity(status_rollup: Any) -> datetime | None:
    """The most recent CI start on the live head, per the rollup already fetched.

    A server-generated stand-in for "when this head appeared": the rollup is
    scoped to the live head and a run cannot start before its push.

    *Latest*, not earliest, and the direction is the whole safety property.
    Check runs live on the SHA, so a head that returns to a previously-checked
    SHA -- force-push A to B and back to A -- still carries A's original runs
    even though the re-push triggers a fresh review. Reading the oldest of them
    would call a brand-new head settled and merge straight through the window
    this gate exists to wait out. Reading the newest can only over-estimate how
    recent a head is, which errs toward holding.

    The cost of that direction is bounded and lands on latency, not safety: a
    re-run mints a fresh timestamp and extends the wait by up to one window.
    It rarely bites, because a re-run does not move the head -- if the reviewer
    already reviewed that SHA the caller short-circuits before reading this
    clock at all, and if it has not, holding is the correct answer anyway.

    Reads the RAW rollup, not `classify_checks`' output: that classifier keeps
    only the newest run per identity, which is lossy in a way this must not
    depend on.
    """
    starts = [
        parsed
        for entry in json_array(status_rollup)
        if is_json_object(entry)
        for parsed in [
            parse_github_timestamp(
                str(entry.get("startedAt") or entry.get("createdAt") or "")
            )
        ]
        if parsed is not None
    ]
    return max(starts) if starts else None


def head_appeared_at(
    repo: str, head_sha: str, status_rollup: Any
) -> tuple[datetime | None, str]:
    """Best available estimate of when the live head appeared, and its source.

    A server-observed CI start is preferred and costs no extra request: it is
    generated by GitHub after the push, so it can only over-estimate how recent
    the head is, which errs toward holding. The head commit's committer date is
    the fallback, and it is only a proxy -- a commit pushed long after it was
    written reads as older than the head really is, which errs toward merging.
    That is why it is second, not first.
    """
    server_seen = latest_check_activity(status_rollup)
    if server_seen is not None:
        return server_seen, "check-start"
    return head_committed_at(repo, head_sha), "committer-date"


def evaluate_review_settle(
    repo: str,
    head: str | None,
    settle: ReviewSettleConfig,
    review_evidence: list[dict[str, str]],
    status_rollup: Any,
    *,
    now: datetime | None = None,
) -> tuple[list[str], dict[str, Any]]:
    """Hold the merge while a configured reviewer's review of this head is due.

    Two conditions, in this order, so the common case costs nothing: a
    current-head review from the reviewer clears the hold outright, and only a
    head with no such review is aged against the settle window.

    The clearing review must postdate the newest CI start on the live head.
    GitHub keeps a review against the SHA rather than against the head
    position, so a force-push A -> B -> A restores a head that its FIRST
    occurrence's review still matches by `commit_oid`; without the bound that
    stale review cleared the hold before any clock was read, and the
    merge-before-review race this gate exists to prevent came back through the
    short-circuit instead of through the clock. `latest_check_activity` is the
    bound because it is the same server-observed signal the age is measured
    on, and it is read from the rollup already in hand, so the already-reviewed
    case still issues no request of its own.

    The bound cannot separate a restored head from a re-run on the standing
    head -- both mint a check start after the review -- so a re-run now pushes
    an already-reviewed head back into settling for up to one window instead of
    short-circuiting past it. That is the fail-closed direction: the cost is
    bounded latency, and the alternative is the safety failure.

    A head with no check starts at all has no bound, so a review of the SHA
    clears the hold as before. That is the residual `safety.md` already scopes:
    when a restored head mints no fresh runs, it reads as settled.
    """
    reviewers = ", ".join(repr(login) for login in sorted(settle.reviewer_logins))
    result: dict[str, Any] = {
        "enabled": True,
        "reviewerLogins": sorted(settle.reviewer_logins),
        "settleSeconds": settle.settle_seconds,
        "currentHeadReview": False,
        "reviewRecencyFloor": None,
        "headAgeSeconds": None,
        "headAgeSource": None,
        "state": "unknown",
    }
    # An absent head is already a blocker upstream (the expected-head pin, which
    # the wrapper makes mandatory), so adding a second blocker for one condition
    # would only obscure it. This is the sole fail-open branch here, and it is
    # unreachable through the wrapper.
    if not head:
        result["state"] = "no-head"
        return [], result

    recency_floor = latest_check_activity(status_rollup)
    if recency_floor is not None:
        result["reviewRecencyFloor"] = recency_floor.isoformat()
    if has_current_head_review(
        {},
        head,
        review_evidence,
        config=ReviewTriggerConfig(reviewer_logins=settle.reviewer_logins),
        not_before=recency_floor,
    ):
        result["currentHeadReview"] = True
        result["state"] = "reviewed"
        return [], result

    appeared_at, source = head_appeared_at(repo, head, status_rollup)
    result["headAgeSource"] = source
    if appeared_at is None:
        result["state"] = "head-age-unreadable"
        return [
            "cannot establish when the live head appeared, so whether the "
            f"configured reviewer(s) {reviewers} still owe it a review is "
            "undecidable -- holding rather than merging on an unverifiable "
            "clock; re-run to retry"
        ], result

    age_seconds = int(((now or datetime.now(UTC)) - appeared_at).total_seconds())
    result["headAgeSeconds"] = age_seconds
    if age_seconds < settle.settle_seconds:
        result["state"] = "settling"
        return [
            f"no review of the live head from {reviewers} and the head is "
            f"{age_seconds}s old by {source} (settle window "
            f"{settle.settle_seconds}s) -- a re-review may still be in flight; "
            "wait out the window rather than merging past it"
        ], result

    result["state"] = "settled"
    return [], result


def pull_request_stack(repo: str, number: int) -> dict[str, Any] | None:
    """The PR's native stack membership (`stack` on the REST pull), or None.

    Only a native stack lands its lower layers when a layer merges; a PR that
    merely targets another PR's branch has no `stack` object and merges into
    that branch. Raises on a read failure so the caller holds rather than
    guessing which of the two it is.
    """
    data = gh_json(["api", f"repos/{repo}/pulls/{number}", "--jq", "{stack: .stack}"])
    stack = data.get("stack") if is_json_object(data) else None
    return stack if is_json_object(stack) else None


def stack_members(repo: str, stack_number: int) -> list[dict[str, Any]]:
    """The stack's pull requests, bottom to top, as GitHub lists them."""
    data = gh_json(["api", f"repos/{repo}/stacks/{stack_number}"])
    members = data.get("pull_requests") if is_json_object(data) else None
    if not is_json_array(members) or not all(is_json_object(m) for m in members):
        raise RuntimeError(f"unexpected stack payload for {repo} stack {stack_number}")
    return cast(list[dict[str, Any]], members)


def evaluate_stack_layers(
    repo: str,
    number: int,
    base_ref: str,
    stack: dict[str, Any],
    evaluate_layer: Callable[[int, str], dict[str, Any]],
) -> tuple[list[str], dict[str, Any]]:
    """Run the full gate over every open layer the merge would land below this PR.

    Merging a stack layer through the async API lands every open layer below
    it, so each one must pass the same gate this PR does. The chain is checked
    as well: each open layer must target the head of the open layer below it,
    the lowest the stack's trunk, so an order this code assumed but the API
    did not state can only hold, never release. Every lower layer is pinned to
    the head the stack listing reported, so a push between listing and
    evaluation reads as a moved head.
    """
    trunk = str(json_object(stack.get("base")).get("ref") or "")
    stack_number = stack.get("number")
    record: dict[str, Any] = {
        "member": True,
        "number": stack_number,
        "trunk": trunk,
        "landsLowerLayers": True,
        "layers": [],
        "aiReviewHolds": [],
    }
    try:
        members = stack_members(repo, int(stack_number))
    except (RuntimeError, TypeError, ValueError, json.JSONDecodeError) as exc:
        return [f"stack {stack_number!r} could not be read ({exc}) -- held"], record
    numbers = [member.get("number") for member in members]
    if number not in numbers:
        return [f"stack {stack_number!r} does not list this PR -- held"], record
    blockers: list[str] = []
    expected_base = trunk
    for member in members[: numbers.index(number)]:
        layer_number = member.get("number")
        head = json_object(member.get("head"))
        head_ref = str(head.get("ref") or "")
        head_sha = str(head.get("sha") or "")
        label = f"stack layer {repo}#{layer_number}"
        if member.get("merged_at"):
            continue
        if member.get("state") != "open" or not isinstance(layer_number, int):
            blockers.append(f"{label} is closed without merging -- held")
            continue
        if not EXPECTED_HEAD_RE.match(head_sha):
            blockers.append(f"{label} reports no head SHA to pin -- held")
            continue
        layer = evaluate_layer(layer_number, head_sha)
        record["layers"].append(
            {
                "pr": f"{repo}#{layer_number}",
                "number": layer_number,
                "headRefOid": layer.get("headRefOid"),
                "baseRef": layer.get("baseRef"),
                "ready": layer.get("ready"),
                "blockers": layer.get("blockers"),
                # What `rerun_rate_limited_reviews` needs to re-run this
                # layer's rate-limited AI reviews.
                "state": layer.get("state"),
                "isDraft": layer.get("isDraft"),
                "headMatches": layer.get("headMatches"),
                "aiReviewChecks": layer.get("aiReviewChecks"),
            }
        )
        blockers.extend(f"{label}: {b}" for b in layer.get("blockers") or [])
        # A layer's AI-review holds bind wherever the top layer's do (`--auto`):
        # they live outside `blockers`, so they are carried separately.
        record["aiReviewHolds"].extend(
            f"{label}: {hold}" for hold in layer.get("aiReviewHolds") or []
        )
        if layer.get("baseRef") != expected_base:
            blockers.append(
                f"{label} targets {layer.get('baseRef')!r}, not {expected_base!r} "
                "-- the stack chain is broken; held"
            )
        expected_base = head_ref
    if base_ref != expected_base:
        blockers.append(
            f"this PR targets {base_ref!r}, not the open layer below it "
            f"({expected_base!r}) -- the stack chain is broken; held"
        )
    return blockers, record


def evaluate(
    repo: str,
    number: int,
    expected_head: str | None,
    allowed: set[str],
    self_logins: frozenset[str],
    allow_dependency: bool,
    allow_unprotected: bool,
    tier: AutopilotMergeTierConfig | None = None,
    extra_dependency_manager_logins: frozenset[str] = frozenset(),
    settle: ReviewSettleConfig | None = None,
    stacked: bool = False,
    rules_base: str | None = None,
    unattended: merge_policy.UnattendedPolicy | None = None,
) -> dict[str, Any]:
    owner = split_owner(repo)
    # `closingIssuesReferences` is requested only when the autopilot merge tier
    # is configured, because only the tier reads it. The field is GraphQL-only,
    # so asking for it on the default gate path made every run of the base gate
    # depend on a surface it never consumed.
    view_fields = [
        "state",
        "isDraft",
        "mergeable",
        "mergeStateStatus",
        "reviewDecision",
        "headRefOid",
        "baseRefName",
        "author",
        "url",
        "title",
        "labels",
        "body",
        "statusCheckRollup",
    ]
    if tier is not None:
        view_fields.append("closingIssuesReferences")
    # `run_json=gh_json` keeps this module's own gh seam in the path (the one
    # every gate test stubs) while the REST re-source lives once, in `babysit_gh`.
    pr, graphql_available = view_pr_fields(repo, number, view_fields, run_json=gh_json)
    threads = unresolved_threads(repo, number)
    checks = classify_checks(pr.get("statusCheckRollup"))
    failing = checks["failing"]
    pending = checks["pending"]
    checks_by_key: dict[tuple[str, str, str], dict[str, Any]] = {
        check_identity_key(check): check for check in checks["checks"]
    }
    # Stack membership is read only under `stacked` (the opt-in), so the default
    # gate makes no request it did not make before. A layer above the bottom is
    # governed by the stack's trunk, not its literal base: GitHub determines a
    # stack's merge requirements from the bottom layer's base branch.
    base_ref = str(pr.get("baseRefName") or "")
    stack: dict[str, Any] | None = None
    stack_error: str | None = None
    if stacked:
        try:
            stack = pull_request_stack(repo, number)
        except (RuntimeError, json.JSONDecodeError) as exc:
            stack_error = str(exc)
    trunk = str(json_object(json_object(stack).get("base")).get("ref") or "")
    stack_mode = bool(stack and trunk and base_ref and base_ref != trunk)
    landing_base = rules_base or (trunk if stack_mode else base_ref)
    rules = branch_rules(repo, landing_base or "main")
    head = pr.get("headRefOid")
    head_matches = (
        None
        if not expected_head
        else bool(head and str(head).startswith(expected_head))
    )
    review_decision = pr.get("reviewDecision") or ""
    labels = [
        label.get("name")
        for label in cast(list[Any], pr.get("labels") or [])
        if is_json_object(label) and label.get("name")
    ]
    author = pr.get("author")
    author_login = author.get("login") if is_json_object(author) else None

    # Reconcile each required status-check context against the deduped rollup.
    required_contexts = rules.get("requiredContexts")
    required_context_list = (
        required_contexts if is_json_array(required_contexts) else []
    )
    required_check_status: list[dict[str, object]] = []
    for raw_context in required_context_list:
        ctx = str(raw_context)
        match = next(
            (
                check
                for key, check in checks_by_key.items()
                if key[1]
                and (key[1] == ctx or ctx.endswith(key[1]) or key[1].endswith(ctx))
            ),
            None,
        )
        category = match.get("category") if match else None
        required_check_status.append(
            {
                "context": ctx,
                "found": bool(match),
                "satisfied": category == "success",
                "category": category,
            }
        )

    required_reviews = rules.get("requiredApprovingReviews") or 0
    base_is_unprotected = not required_reviews and not required_context_list
    unmet = [r for r in required_check_status if not r["satisfied"]]
    unmet_required = [r["context"] for r in unmet]
    # A required context that is pending or not yet reported is still running.
    unmet_only_running = all(r["category"] in (None, "pending") for r in unmet)

    blockers: list[str] = []
    # Blockers that only mean "a check is still running". `--auto` may arm over
    # them and nothing else: GitHub's auto-merge waits out a running required
    # check, the AI review checks are gated separately below, and any other
    # running check is advisory and does not hold a merge.
    waiting: list[str] = []
    if owner not in allowed:
        blockers.append(f"owner {owner!r} out of scope")
    if pr.get("state") != "OPEN":
        blockers.append(f"state={pr.get('state')} (not OPEN)")
    if pr.get("isDraft"):
        blockers.append("PR is a draft -- mark ready first")
    if BODY_MERGE_HOLD_RE.search(str(pr.get("body") or "")):
        blockers.append(
            "PR body holds the merge (do not merge, or a Hold: line) -- a human "
            "hold, report it and leave it"
        )
    # Autonomous: the unattended policy or the autopilot merge tier, both
    # merging with no person present; only an attended merge lifts the
    # human-gated hold.
    autonomous = unattended is not None or tier is not None
    try:
        human_gated = human_gated_label(repo) if autonomous else None
    except postmerge.PostMergeReadError as exc:
        human_gated = None
        blockers.append(
            f"the human-gated role label is unreadable ({exc}) -- an autonomous "
            "merge cannot tell which label holds it"
        )
    if held_by := merge_hold_label(labels, human_gated=human_gated):
        blockers.append(
            f"PR carries the {held_by!r} label -- a human hold, report it and leave it"
        )
    if pr.get("mergeable") != "MERGEABLE":
        blockers.append(
            f"mergeable={pr.get('mergeable')} (conflict or still computing)"
        )
    if pr.get("mergeStateStatus") not in READY_MERGE_STATES:
        blockers.append(
            f"mergeStateStatus={pr.get('mergeStateStatus')} "
            + "(need CLEAN/HAS_HOOKS: integrates required checks, up-to-date, "
            + "approvals, conversation resolution, signatures)"
        )
        if unmet_only_running and pr.get("mergeStateStatus") in ("BLOCKED", "UNSTABLE"):
            waiting.append(blockers[-1])
    if review_decision == "CHANGES_REQUESTED":
        blockers.append(
            "reviewDecision=CHANGES_REQUESTED -- a reviewer requested changes (human stop)"
        )
    elif required_reviews and review_decision != "APPROVED":
        blockers.append(
            f"needs {required_reviews} approving review(s); "
            f"reviewDecision={review_decision or 'none'}"
        )
    if threads is None:
        # Readiness is UNPROVEN, not clean: review-thread resolution is served
        # only over GraphQL, and sandboxed sessions (Claude Code on the web and
        # remote execution) refuse GraphQL; the pointer record sits beside
        # `GRAPHQL_UNAVAILABLE_MARKERS` in babysit_gh.py. Every other input above was
        # re-sourced over REST; this one has no REST equivalent, and
        # `reference/safety.md` forbids substituting a lesser signal for a gate
        # verdict, so the gate holds instead of approximating one.
        blockers.append(
            "unresolved review threads could not be read: GitHub's GraphQL API "
            "is not served to this session, and thread resolution has no REST "
            "equivalent -- readiness is UNPROVEN, not clean"
        )
    elif threads:
        who = ", ".join(sorted({str(t.get("author")) for t in threads}))
        blockers.append(
            f"{len(threads)} unresolved review thread(s) [{who}] "
            "-- resolve or address the finding"
        )
    if failing:
        blockers.append("failing checks: " + ", ".join(str(name) for name in failing))
    if pending:
        blockers.append("pending checks: " + ", ".join(str(name) for name in pending))
        waiting.append(blockers[-1])
    if unmet_required:
        blockers.append(
            "required checks not satisfied: "
            + ", ".join(str(c) for c in unmet_required)
        )
        if unmet_only_running:
            waiting.append(blockers[-1])
    merge_queue_required = bool(rules.get("mergeQueueRequired"))
    if stack_error is not None:
        blockers.append(
            f"stack membership could not be read ({stack_error}) -- held: a stack "
            "layer's merge lands the layers below it, so an unknown membership "
            "cannot be merged"
        )
    if stack_mode and merge_queue_required:
        blockers.append(
            f"stack trunk {trunk!r} requires a merge queue -- held: merge-queue "
            "support for stacks is not relied on yet; merge the stack by hand"
        )
    elif merge_queue_required and not stack_mode and not rules_base:
        # The async API enqueues a PR on the default branch. Any other base keeps
        # the prior hold: an unconfirmed stack layer there could enqueue the
        # layers below it with them.
        default_branch = repository_default_branch(repo)
        if not default_branch or base_ref != default_branch:
            blockers.append(
                "base branch requires a merge queue and is not the default branch "
                "-- a direct merge is not allowed; add to the queue by hand"
            )
    # Enforced in this read-only pass, not only at merge time: the wrapper's
    # documented purpose is reporting readiness so the caller can react, and a
    # signature hold discovered only under --merge defeats that.
    signature_result: dict[str, Any] = {
        "required": bool(rules.get("requireSignatures")),
        "checked": False,
        "unverified": [],
    }
    if rules.get("requireSignatures"):
        signature_blockers, signature_result = evaluate_required_signatures(
            repo, number, str(head) if head else None
        )
        blockers.extend(signature_blockers)
    if head_matches is False:
        blockers.append(
            f"head moved: live={str(head)[:12] if head else None} expected={expected_head}"
        )
    # A dependency-manager PR is held in every tier unless explicitly allowed:
    # its update should be reviewed, not auto-merged on a green gate alone.
    if (
        is_dependency_author(str(author_login or ""), extra_dependency_manager_logins)
        and not allow_dependency
    ):
        blockers.append(
            f"author {author_login!r} is a dependency manager "
            "-- held (pass --allow-dependency to override)"
        )
    # On an unprotected base, CLEAN proves nothing (no required checks/reviews).
    # A non-self author's PR there is held unless explicitly allowed.
    author_is_self = is_self_login(author_login, self_logins)
    if base_is_unprotected and not author_is_self and not allow_unprotected:
        blockers.append(
            "base branch is unprotected (0 required reviews AND 0 required "
            f"contexts) and author {author_login!r} is not a configured self "
            "login -- held (pass --allow-unprotected to override)"
        )

    closing_issues = cast(list[Any], pr.get("closingIssuesReferences") or [])
    # Fetch the review corpus at most once per run, and only when something
    # needs it: the settle hold and the tier both read it, and an unconfigured
    # gate must make no request it did not make before.
    reviews: list[dict[str, Any]] | None = None
    review_comments: list[dict[str, Any]] | None = None
    settle_result: dict[str, Any] = {"enabled": False}
    if settle is not None:
        reviews = fetch_pull_request_reviews(repo, number)
        review_comments = fetch_pull_request_review_comments(repo, number)
        settle_blockers, settle_result = evaluate_review_settle(
            repo,
            str(head) if head else None,
            settle,
            fetch_review_evidence(
                repo,
                number,
                reviews,
                review_comments,
                config=ReviewTriggerConfig(reviewer_logins=settle.reviewer_logins),
            ),
            pr.get("statusCheckRollup"),
        )
        blockers.extend(settle_blockers)

    tier_result: dict[str, Any] = {"enabled": False}
    if tier is not None:
        tier_blockers, tier_result = evaluate_autopilot_tier(
            repo,
            number,
            str(head) if head else None,
            author_login,
            labels,
            closing_issues,
            tier,
            reviews,
            review_comments,
        )
        blockers.extend(tier_blockers)

    # The pr-merge lane enqueues with no person present, so a person whose
    # newest comment says "do not merge" holds it before the enqueue. The tier,
    # when configured, already ran its wider scan.
    if (
        tier is None
        and unattended is not None
        and (unattended.inputs or {}).get("authority") == merge_policy.PR_MERGE
    ):
        if reviews is None:
            reviews = fetch_pull_request_reviews(repo, number)
        identity = unattended.agent_identity
        vetoes = human_veto_logins(
            repo,
            number,
            reviews,
            review_comments,
            FeedbackConfig(
                extra_bot_logins=frozenset({identity}) if identity else frozenset()
            ),
        )
        if vetoes:
            blockers.append(
                "human merge veto from "
                + ", ".join(vetoes)
                + " -- their newest comment says do not merge; a later comment "
                "from them lifts it"
            )

    # The self-login exemption from the unprotected-base hold above exists for a
    # repository whose DEFAULT branch carries no rules -- a solo owner merging
    # their own work, where holding every PR would make the gate useless. It must
    # not extend to a base that is not the default branch: there, "unprotected"
    # means the required checks that govern the default branch were never
    # evaluated for this merge at all, and the PR lands on an integration branch
    # instead of passing the gate. A stacked pull request is exactly that shape
    # (self-authored, base = the layer below), but so is any feature-onto-feature
    # merge. Under `stacked`, a native stack layer is judged against its trunk
    # instead, where the landing base is what this hold compares.
    #
    # Evaluated last, after the settle and tier blockers, so `not blockers` is the
    # COMPLETE set: the lookup below is a network call, and a PR already held for
    # any other reason cannot be made ready by this hold, so the fleet loop must
    # never pay that call per cycle for a PR it already knows is ineligible.
    if (
        not blockers
        and base_is_unprotected
        and author_is_self
        and not allow_unprotected
    ):
        default_branch = repository_default_branch(repo)
        if default_branch and landing_base and landing_base != default_branch:
            blockers.append(
                f"base branch {landing_base!r} is unprotected (0 required reviews AND "
                "0 required contexts) and is not the default branch "
                f"{default_branch!r} -- the default branch's required checks never "
                "governed this merge -- held (pass --allow-unprotected to override)"
            )

    # CLEAN proves an up-to-date head only where the base requires one: under
    # loose required checks GitHub merges a behind head, and a squash of it can
    # drop base commits. A merge queue tests the PR against the latest base
    # itself, so a queue base needs no compare. Evaluated after every other
    # hold but a running check, for the per-cycle cost reason above, and before
    # `--auto` arms over those running checks.
    freshness: dict[str, Any] = {"checked": False, "compare": None, "behind": None}
    if (
        not merge_queue_required
        and not rules.get("requireUpToDate")
        and all(b in waiting for b in blockers)
    ):
        compare = fetch_base_compare(repo, base_ref, str(head or ""), run_json=gh_json)
        behind = compare_shows_behind(compare)
        freshness = {"checked": True, "compare": compare, "behind": behind}
        if compare is None:
            blockers.append(
                f"head could not be compared against base {base_ref!r} -- the base "
                "does not require up-to-date branches, so CLEAN does not prove this "
                "head current; freshness is UNPROVEN, held"
            )
        elif behind:
            blockers.append(
                f"head is {compare['behind_by']} commit(s) behind base {base_ref!r}, "
                "which does not require up-to-date branches -- refresh the branch "
                "before merging"
            )

    # The layers below a stack layer land with it, so each runs the full gate --
    # only once this PR is otherwise ready, for the same per-cycle cost reason.
    stack_result: dict[str, Any] = {
        "enabled": stacked,
        "member": stack is not None,
        "landsLowerLayers": stack_mode,
    }
    if stack_mode and stack is not None and not blockers:

        def evaluate_layer(layer_number: int, layer_head: str) -> dict[str, Any]:
            return evaluate(
                repo,
                layer_number,
                layer_head,
                allowed,
                self_logins,
                allow_dependency,
                allow_unprotected,
                tier,
                extra_dependency_manager_logins,
                settle,
                rules_base=trunk,
                unattended=unattended,
            )

        layer_blockers, stack_result = evaluate_stack_layers(
            repo, number, base_ref, stack, evaluate_layer
        )
        stack_result["enabled"] = True
        blockers.extend(layer_blockers)

    # Absent, the unattended policy leaves the gate and its report unchanged.
    # Present and refusing, it is one more hold, added last: the
    # unprotected-base, freshness and stack checks above run only while no
    # hold stands, so an earlier refusal would hide the holds a plain check
    # reports. That costs their network reads on an otherwise-ready PR.
    if unattended is not None and unattended.reason is not None:
        blockers.append(f"{UNATTENDED_REFUSED}{unattended.reason}")

    ready = not blockers
    # `--auto` needs both AI review checks at SUCCESS in the rollup, which is the
    # live head's. A draft skips both lanes, so neither an absent nor a SKIPPED
    # check (which the check buckets count as success) passes.
    ai_review_holds = [
        f"AI review check {lane!r} has not succeeded on the live head"
        for lane, names in AI_REVIEW_CHECKS.items()
        if not (
            matches := [
                c for c in checks["checks"] if is_ai_review_check(c["name"], names)
            ]
        )
        or any(c["effective_state"] != "SUCCESS" for c in matches)
    ]
    ai_review_checks = [
        {
            "name": c["name"],
            "id": c["id"],
            "workflow_name": c["workflow_name"],
            "effective_state": c["effective_state"],
            "details_url": c["details_url"],
        }
        for c in checks["checks"]
        if any(is_ai_review_check(c["name"], n) for n in AI_REVIEW_CHECKS.values())
    ]
    ai_review_holds += stack_result.get("aiReviewHolds") or []
    auto_blockers = [b for b in blockers if b not in waiting] + ai_review_holds
    # GitHub auto-merge is armed only over a plain direct merge; a queue or a
    # stack is merged through the async API once the PR is fully ready.
    if not ready and merge_queue_required:
        auto_blockers.append(MERGE_QUEUE_AUTO_HOLD)
    if not ready and stack_mode:
        auto_blockers.append(STACK_AUTO_HOLD)
    report: dict[str, Any] = {
        "pr": f"{repo}#{number}",
        "autopilotMergeTier": tier_result,
        "reviewSettle": settle_result,
        "stack": stack_result,
        "landingBase": landing_base,
        "mergeAction": "merge_queue" if merge_queue_required else "direct_merge",
        "url": pr.get("url"),
        "title": pr.get("title"),
        "author": author_login,
        "owner": owner,
        "inScope": owner in allowed,
        "baseRef": pr.get("baseRefName"),
        "baseUnprotected": base_is_unprotected,
        "state": pr.get("state"),
        "isDraft": pr.get("isDraft"),
        "mergeable": pr.get("mergeable"),
        "mergeStateStatus": pr.get("mergeStateStatus"),
        "reviewDecision": review_decision,
        "headRefOid": head,
        "labels": labels,  # surfaced for agent reasoning; only the hold labels are hardcoded
        "expectedHead": expected_head,
        "headMatches": head_matches,
        "effectiveRules": rules,
        "baseFreshness": freshness,
        "requiredSignatures": signature_result,
        "requiredChecks": required_check_status,
        "graphqlAvailable": graphql_available,
        # None, never 0, when thread resolution could not be read: a count of
        # zero is a claim this run cannot make.
        "unresolvedThreadCount": None if threads is None else len(threads),
        "unresolvedThreads": threads,
        "threadResolutionProven": threads is not None,
        "failingChecks": failing,
        "pendingChecks": pending,
        "ready": ready,
        "blockers": blockers,
        "autoMerge": {"ready": not auto_blockers, "blockers": auto_blockers},
        "aiReviewHolds": ai_review_holds,
        "aiReviewChecks": ai_review_checks,
    }
    if unattended is not None:
        report["unattended"] = unattended.report()
    return report


def allowed_method(repo: str, requested: str | None) -> str:
    data = gh_json(
        [
            "repo",
            "view",
            repo,
            "--json",
            "squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed",
        ]
    )
    data = data if is_json_object(data) else {}
    allowed = {
        "squash": bool(data.get("squashMergeAllowed")),
        "merge": bool(data.get("mergeCommitAllowed")),
        "rebase": bool(data.get("rebaseMergeAllowed")),
    }
    if requested:
        if not allowed.get(requested):
            raise RuntimeError(f"merge method {requested!r} not enabled on {repo}")
        return requested
    for method in ("squash", "merge", "rebase"):
        if allowed[method]:
            return method
    raise RuntimeError(f"no merge method enabled on {repo}")


def _async_payload(text: str) -> dict[str, Any]:
    try:
        data = json.loads(text) if text.strip() else None
    except json.JSONDecodeError:
        return {}
    return data if is_json_object(data) else {}


def request_async_merge(
    repo: str,
    number: int,
    *,
    sha: str,
    merge_action: str,
    method: str | None,
) -> dict[str, Any]:
    """PUT one async merge request; never sets `bypass_rules`.

    `sha` is the vetted head, the server-side equivalent of
    `--match-head-commit`: GitHub cancels the merge if the head moved. A 409
    means a request is already pending for this PR and carries its UUID. The
    HTTP status of a failure comes from `gh`'s own message, since `gh api`
    exits 1 for every non-2xx response.
    """
    cmd = [
        "api",
        "-X",
        "PUT",
        f"repos/{repo}/pulls/{number}/merge-async",
        "-f",
        f"merge_action={merge_action}",
        "-F",
        "bypass_rules=false",
        "-f",
        f"sha={sha}",
    ]
    if method and merge_action == "direct_merge":
        cmd += ["-f", f"merge_method={method}"]
    proc = gh_capture(cmd)
    payload = _async_payload(proc.stdout)
    details = json_object(payload.get("details"))
    return {
        "httpStatus": None if proc.returncode == 0 else gh_http_status(proc.stderr),
        "ok": proc.returncode == 0,
        "status": str(payload.get("status") or ""),
        "uuid": str(details.get("uuid") or ""),
        "message": str(details.get("message") or payload.get("message") or ""),
        "stderr": proc.stderr.strip(),
        "options": {
            key: details[key]
            for key in ("expected_head_sha", "merge_action")
            if key in details
        },
    }


def poll_async_merge(
    repo: str,
    number: int,
    uuid: str,
    *,
    timeout_seconds: float = ASYNC_MERGE_POLL_TIMEOUT_SECONDS,
    interval_seconds: float = ASYNC_MERGE_POLL_INTERVAL_SECONDS,
    sleep: Callable[[float], None] | None = None,
    clock: Callable[[], float] | None = None,
) -> dict[str, Any]:
    """Poll one async merge request until it is terminal or the bound elapses."""
    sleep = sleep or _poll_sleep
    clock = clock or _poll_clock
    deadline = clock() + timeout_seconds
    while True:
        result = read_async_merge(repo, number, uuid)
        if (
            result["status"] in ASYNC_TERMINAL_STATUSES
            or result["readError"]
            or clock() >= deadline
        ):
            return result
        sleep(interval_seconds)


def read_async_merge(repo: str, number: int, uuid: str) -> dict[str, Any]:
    """One read of an async merge request. `expired` is a 404: GitHub keeps a
    result for 24 hours after its last update and then forgets the UUID.

    A UUID that is not GitHub's shape never reaches the API path: it reads as
    `corrupt`, which keeps a recorded request held.
    """
    if not ASYNC_UUID_RE.fullmatch(uuid):
        return {
            "status": "",
            "message": f"unusable async merge request id {uuid!r}",
            "readError": True,
            "expired": False,
            "corrupt": True,
        }
    try:
        payload = gh_json(["api", f"repos/{repo}/pulls/{number}/merge-async/{uuid}"])
    except (RuntimeError, json.JSONDecodeError) as exc:
        return {
            "status": "",
            "message": f"could not read the request: {exc}",
            "readError": True,
            "expired": gh_http_status(str(exc)) == 404,
        }
    payload = payload if is_json_object(payload) else {}
    return {
        "status": str(payload.get("status") or ""),
        "message": str(json_object(payload.get("details")).get("message") or ""),
        "readError": False,
        "expired": False,
    }


def pull_request_landed(repo: str, number: int) -> dict[str, Any]:
    """Whether GitHub reads the PR as merged, and its head SHA.

    `merged` is None, and `head` with it, when the PR cannot be read or reads
    merged with no head: the head a merge landed cannot then be confirmed.
    """
    try:
        data = gh_json(
            [
                "api",
                f"repos/{repo}/pulls/{number}",
                "--jq",
                "{merged: .merged, head: .head.sha}",
            ]
        )
    except (RuntimeError, json.JSONDecodeError):
        data = None
    data = data if is_json_object(data) else {}
    merged, head = data.get("merged"), data.get("head")
    head = head if isinstance(head, str) and head else None
    if not isinstance(merged, bool) or (merged and head is None):
        return {"merged": None, "head": None}
    return {"merged": merged, "head": head}


MERGE_QUEUE_QUERY = (
    "query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){"
    "pullRequest(number:$n){merged isInMergeQueue isMergeQueueEnabled "
    "mergeQueueEntry{state position} autoMergeRequest{enabledAt} "
    f"timelineItems(last:{merge_policy.MAX_QUEUE_EJECTIONS_LIMIT},itemTypes:["
    "REMOVED_FROM_MERGE_QUEUE_EVENT,PULL_REQUEST_COMMIT,HEAD_REF_FORCE_PUSHED_EVENT])"
    "{nodes{__typename ... on RemovedFromMergeQueueEvent{reason}}}}}}"
)
# A head change: a pushed commit or a force push.
HEAD_CHANGES = ("PullRequestCommit", "HeadRefForcePushedEvent")


def _failed_ejections(pr: dict[str, Any]) -> int | None:
    """The merge queue's removals of the pull request for failed checks since
    its newest head change, read from the timeline items (oldest first), or
    None when they cannot be read: a malformed item, or a full window with no
    head change in it, whose older removals the read did not reach.

    The timeline places a commit by its date, not its push (UNVERIFIED: no
    GitHub page or schema field states either; `PullRequestCommit` carries no
    date of its own). A commit made before a removal but pushed after it then
    sorts before the removal, which is charged to the new head: the count
    only grows, so the gate refuses rather than enqueues. Only a commit dated
    after a removal it was pushed before (a skewed clock) would hide one."""
    nodes = json_object(pr.get("timelineItems")).get("nodes")
    if not is_json_array(nodes):
        return None
    count = 0
    for node in reversed(nodes):
        kind = json_object(node).get("__typename")
        if kind in HEAD_CHANGES:
            return count
        if kind != "RemovedFromMergeQueueEvent":
            return None
        count += json_object(node).get("reason") == "failed_checks"
    return count if len(nodes) < merge_policy.MAX_QUEUE_EJECTIONS_LIMIT else None


def _last_removal_reason(pr: dict[str, Any]) -> str | None:
    """The reason of the queue's newest removal of the pull request, or None
    when a head change is newer than every removal or none can be read."""
    nodes = json_object(pr.get("timelineItems")).get("nodes")
    for node in reversed(nodes if is_json_array(nodes) else []):
        node = json_object(node)
        if node.get("__typename") != "RemovedFromMergeQueueEvent":
            return None
        reason = node.get("reason")
        return reason if isinstance(reason, str) and reason else None
    return None


def read_merge_queue(repo: str, number: int) -> dict[str, Any]:
    """The PR's merge-queue standing as GitHub reports it now.

    GraphQL-only: REST exposes neither queue membership nor position. Any
    failure, the session's GraphQL refusal included, sets `readError`, and the
    caller reports the queue standing as unconfirmed rather than absent.
    """
    owner, name = repo.split("/", 1)
    try:
        data = gh_json(
            [
                "api",
                "graphql",
                "-f",
                f"query={MERGE_QUEUE_QUERY}",
                "-F",
                f"o={owner}",
                "-F",
                f"r={name}",
                "-F",
                f"n={number}",
            ]
        )
    except (RuntimeError, json.JSONDecodeError) as exc:
        return {"readError": f"could not read the merge queue: {exc}"}
    pr = json_object(
        json_object(json_object(json_object(data).get("data")).get("repository")).get(
            "pullRequest"
        )
    )
    flags = (pr.get("merged"), pr.get("isInMergeQueue"), pr.get("isMergeQueueEnabled"))
    if not all(isinstance(flag, bool) for flag in flags):
        return {"readError": "the merge queue read returned no pull request state"}
    entry = pr.get("mergeQueueEntry")
    entry = entry if is_json_object(entry) else None
    return {
        "readError": None,
        "merged": pr["merged"],
        "inQueue": pr["isInMergeQueue"] or entry is not None,
        "queueRequired": pr["isMergeQueueEnabled"],
        "autoMergeArmed": is_json_object(pr.get("autoMergeRequest")),
        "state": entry.get("state") if entry else None,
        "position": entry.get("position") if entry else None,
        "failedEjections": _failed_ejections(pr),
        "lastRemovalReason": _last_removal_reason(pr),
    }


def report_queue_routing(result: dict[str, Any], queue: dict[str, Any]) -> int:
    """Correct a successful `gh pr merge` report for a base with a merge queue,
    returning the exit code.

    `gh pr merge` routes every merge on a queue base into the queue, `--auto`
    or not, and exits 0 either way; a queue the rules read did not report is
    therefore seen only here. A base without a queue keeps the report as it was.
    A queue base that shows no result yet reports `merge-pending` with
    `mergeQueue.unconfirmed`, since the request may still be taking effect.
    """
    if queue["readError"]:
        result["merge"]["queueReadError"] = queue["readError"]
        return 0
    if queue["inQueue"]:
        result["action"] = "enqueue"
        result["merged"] = result["autoMergeEnabled"] = False
        result["enqueued"] = True
        result["mergeQueue"] = {"state": queue["state"], "position": queue["position"]}
        return 0
    if not queue["queueRequired"] or queue["merged"]:
        return 0
    result["merged"] = False
    result["autoMergeEnabled"] = queue["autoMergeArmed"]
    result["mergeQueue"] = {
        "state": None,
        "position": None,
        "entersWhenReady": queue["autoMergeArmed"],
    }
    if queue["autoMergeArmed"]:
        result["action"] = "auto-merge"
        return 0
    hold = (
        "gh pr merge succeeded on a merge-queue base, but the pull request does not "
        "yet read back as queued, armed to enter the queue, or merged -- merge "
        "pending, unconfirmed; it may still land; no new request is sent"
    )
    result["action"] = "merge-pending"
    result["ready"] = False
    result["mergeQueue"]["unconfirmed"] = True
    result.setdefault("blockers", []).insert(0, hold)
    result["autoMerge"] = {"ready": False, "blockers": [hold]}
    result["merge"]["message"] = hold
    return 10


# https://docs.github.com/en/graphql/reference/pulls#enqueuepullrequest
# `jump` is never sent: it puts the PR at the front of the queue.
ENQUEUE_MUTATION = (
    "mutation($id:ID!,$head:GitObjectID!){enqueuePullRequest("
    "input:{pullRequestId:$id,expectedHeadOid:$head}){mergeQueueEntry{state position}}}"
)


def enqueue_pull_request(repo: str, number: int, *, sha: str) -> dict[str, Any]:
    """Add the PR to its base's merge queue at the vetted head.

    GraphQL `enqueuePullRequest`, which enqueues for an App installation token
    where REST `merge-async` with `merge_action=merge_queue` answers "Enqueuer
    is not authorized to merge". `expectedHeadOid` is the server-side pin.
    Returns the `merge` record; `success` only when GitHub answers with the new
    queue entry. The call returns before the queue lands the PR: a later run
    reads the recorded entry back as merged and dispatches the verifying run.
    """
    record: dict[str, Any] = {
        "attempted": True,
        "auto": False,
        "api": "graphql",
        "mergeAction": "merge_queue",
        "uuid": None,
        "status": None,
        "message": "",
        "success": False,
        "endpointMissing": False,
    }
    try:
        node = gh_json(
            ["api", f"repos/{repo}/pulls/{number}", "--jq", "{id: .node_id}"]
        )
    except (RuntimeError, json.JSONDecodeError) as exc:
        node = None
        record["message"] = f"could not read the pull request id: {exc}"
    node_id = json_object(node).get("id")
    if not isinstance(node_id, str) or not node_id:
        record["attempted"] = False
        record["message"] = (
            record["message"] or "the pull request read returned no id"
        ) + " -- not enqueued"
        return record
    proc = gh_capture(
        ["api", "graphql", "-f", f"query={ENQUEUE_MUTATION}"]
        + ["-f", f"id={node_id}", "-f", f"head={sha}"]
    )
    payload = _async_payload(proc.stdout)
    data = json_object(json_object(payload.get("data")).get("enqueuePullRequest"))
    entry = data.get("mergeQueueEntry")
    errors = [
        str(json_object(error).get("message") or "")
        for error in payload.get("errors") or []
        if is_json_object(error)
    ]
    if is_json_object(entry):
        # An entry is a live enqueue even beside errors: reported enqueued so
        # it is recorded and checked against the merge.max-in-flight cap.
        record["status"] = "enqueued"
        record["success"] = True
        record["mergeQueue"] = {
            "state": entry.get("state"),
            "position": entry.get("position"),
        }
        if errors:
            record["message"] = "; ".join(e for e in errors if e)
        return record
    record["status"] = "failed" if errors else None
    record["message"] = "; ".join(e for e in errors if e) or (
        proc.stderr.strip() or "enqueuePullRequest returned no merge queue entry"
    )
    if proc.stderr.strip():
        record["stderr"] = proc.stderr.strip()
    return record


def async_merge(
    repo: str,
    number: int,
    *,
    sha: str,
    merge_action: str,
    method: str | None,
) -> dict[str, Any]:
    """Request an async merge or enqueue, poll it, and verify a reported merge.

    Returns the `merge` record. An enqueue goes through
    `enqueue_pull_request`; only a direct merge uses `merge-async`.
    `endpointMissing` marks a 404 on the request itself (a host without the
    endpoint, such as an older GitHub Enterprise Server): the PR was just read,
    so the 404 is the endpoint's, not the PR's.
    """
    if merge_action == "merge_queue":
        return enqueue_pull_request(repo, number, sha=sha)
    request = request_async_merge(
        repo, number, sha=sha, merge_action=merge_action, method=method
    )
    record: dict[str, Any] = {
        "attempted": True,
        "auto": False,
        "api": "merge-async",
        "mergeAction": merge_action,
        "httpStatus": request["httpStatus"],
        "uuid": request["uuid"] or None,
        "status": request["status"] or None,
        "message": request["message"],
        "success": False,
        "endpointMissing": not request["ok"] and request["httpStatus"] == 404,
    }
    if not request["ok"] and request["stderr"]:
        record["stderr"] = request["stderr"]
    accepted = request["ok"] or request["httpStatus"] == 409
    if not accepted:
        return record
    # A 409 names a request this run did not send, possibly another actor's.
    # Options it states must be this run's; options it omits leave the
    # read-back below to confirm the head that merged.
    expected = {"expected_head_sha": sha, "merge_action": merge_action}
    if request["httpStatus"] == 409 and any(
        request["options"].get(key, value) != value for key, value in expected.items()
    ):
        record["conflictingRequest"] = request["options"]
        record["message"] = (
            f"another async merge request is pending for this pull request "
            f"({request['options']}), not this run's vetted merge -- held; it "
            "can still merge"
        )
        return record
    status = request["status"]
    if status not in ASYNC_TERMINAL_STATUSES:
        polled = poll_async_merge(repo, number, request["uuid"])
        status = polled["status"]
        record["message"] = polled["message"] or record["message"]
    record["status"] = status or None
    if status == "merged":
        landed = pull_request_landed(repo, number)
        verified = landed["merged"]
        # None (the read failed) is surfaced as unconfirmed, never as a merge.
        record["verifiedMerged"] = verified
        record["mergedHead"] = landed["head"]
        record["success"] = verified is True and landed["head"] == sha
        if verified is True and landed["head"] != sha:
            record["message"] = (
                f"the pull request merged at head {landed['head']}, not the vetted "
                f"head {sha} -- escalate to a human"
            )
        elif verified is False:
            record["message"] = (
                "the async merge API reported merged but the pull request reads "
                "unmerged -- not counted as merged"
            )
        elif verified is None:
            record["message"] = (
                "the async merge API reported merged but the pull request could "
                "not be read back -- unconfirmed; re-run the read-only check"
            )
    elif status == "enqueued":
        record["success"] = merge_action == "merge_queue"
    elif status == "pending":
        record["message"] = (
            f"still pending after {int(ASYNC_MERGE_POLL_TIMEOUT_SECONDS)}s; the "
            "next run's request returns this one and polls it again"
        )
    return record


def _open_lower_layers(
    repo: str, number: int, stack_number: Any
) -> list[tuple[int, str]]:
    """`(number, head sha)` of every open, unmerged layer below this PR, read now."""
    members = stack_members(repo, int(stack_number))
    numbers = [member.get("number") for member in members]
    if number not in numbers:
        raise RuntimeError(f"stack {stack_number!r} no longer lists this PR")
    return [
        (int(member["number"]), str(json_object(member.get("head")).get("sha") or ""))
        for member in members[: numbers.index(number)]
        if not member.get("merged_at") and member.get("state") == "open"
    ]


def _evaluated_layers(result: dict[str, Any]) -> list[tuple[int, str]]:
    return [
        (int(layer["number"]), str(layer.get("headRefOid") or ""))
        for layer in json_array(json_object(result.get("stack")).get("layers"))
        if is_json_object(layer) and isinstance(layer.get("number"), int)
    ]


def stack_drift(repo: str, number: int, result: dict[str, Any]) -> str | None:
    """Why the lower layers no longer match what the gate evaluated, or None.

    The request's `sha` pins only this PR, so the layers below are re-read
    immediately before the request: a push, a new layer, or a closed one since
    evaluation refuses the merge instead of landing an unvetted head.
    """
    try:
        live = _open_lower_layers(
            repo, number, json_object(result["stack"]).get("number")
        )
    except (RuntimeError, KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
        return f"stack could not be re-read before merging ({exc}) -- held"
    evaluated = _evaluated_layers(result)
    if live != evaluated:
        return (
            f"the stack's open lower layers changed since evaluation (evaluated "
            f"{evaluated}, now {live}) -- held; re-run the gate"
        )
    return None


def verify_stack_landed(repo: str, result: dict[str, Any]) -> dict[str, Any]:
    """Whether every evaluated lower layer merged at the head the gate evaluated.

    `verified` is None when the stack cannot be read back. A layer GitHub
    reports at a different head lands as a mismatch for a human to judge,
    whatever the cause.
    """
    evaluated = _evaluated_layers(result)
    try:
        members = stack_members(repo, int(json_object(result["stack"]).get("number")))
    except (RuntimeError, KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
        return {
            "verified": None,
            "mismatches": [],
            "message": f"stack unreadable: {exc}",
        }
    by_number = {member.get("number"): member for member in members}
    mismatches = []
    for layer_number, head in evaluated:
        member = json_object(by_number.get(layer_number))
        landed_head = str(json_object(member.get("head")).get("sha") or "")
        if not member.get("merged_at") or landed_head != head:
            mismatches.append(
                {
                    "pr": f"{repo}#{layer_number}",
                    "evaluatedHead": head,
                    "reportedHead": landed_head or None,
                    "merged": bool(member.get("merged_at")),
                }
            )
    return {"verified": not mismatches, "mismatches": mismatches}


def verify_request_landed(
    repo: str, number: int, entry: dict[str, Any]
) -> dict[str, Any]:
    """Whether a recorded request merged every head the gate evaluated: the PR
    at its recorded head and, for a stack, each lower layer at its own."""
    landed = pull_request_landed(repo, number)
    if landed["merged"] is None:
        return {
            "verified": None,
            "mismatches": [],
            "message": "pull request unreadable",
        }
    head = str(entry.get("head") or "")
    mismatches = []
    if not landed["merged"] or landed["head"] != head:
        mismatches.append(
            {
                "pr": f"{repo}#{number}",
                "evaluatedHead": head,
                "reportedHead": landed["head"],
                "merged": landed["merged"],
            }
        )
    if is_json_object(entry.get("stack")):
        stack = verify_stack_landed(repo, entry)
        if stack["verified"] is None:
            return stack
        mismatches += stack["mismatches"]
    return {"verified": not mismatches, "mismatches": mismatches}


PENDING_MERGES_FILE = "merge-requests.json"


def _load_pending(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}
    except (OSError, ValueError) as exc:
        raise RuntimeError(
            f"pending merge records unreadable at {path}: {exc}"
        ) from exc
    requests = data.get("requests") if is_json_object(data) else None
    if not is_json_object(requests):
        raise RuntimeError(f"pending merge records malformed at {path}")
    return cast(dict[str, Any], requests)


def update_pending(path: Path, key: str, entry: dict[str, Any] | None) -> None:
    """Record (or with None, clear) the one live async merge request for a PR."""
    with state_lock(path):
        requests = _load_pending(path)
        if entry is None:
            if key not in requests:
                return
            requests.pop(key)
        else:
            requests[key] = entry
        write_state(path, {"schema_version": 1, "requests": requests})


def check_pending_request(
    repo: str, number: int, path: Path, *, write: bool = True
) -> dict[str, Any] | None:
    """The PR's recorded async merge request as GitHub reports it now.

    A request left pending stays live on GitHub: it can still merge after a
    hold appears that would refuse a new one. There is no route to cancel it,
    so every later run reads it first. A terminal request, or one GitHub no
    longer returns (404: it keeps a result 24 hours after its latest update),
    clears the record; an unreadable one stays recorded and counts as pending,
    and a corrupt one (an unusable request id) is held however old it is.

    A merged request is checked against every head the gate evaluated
    (`verification`), since its `sha` pinned only this PR. A check that cannot
    read the heads back keeps the record for the next run.

    With `write` False (a report-only run) the report is the same and the
    record is left as it was.
    """
    key = f"{repo}#{number}"
    with state_lock(path):
        entry = _load_pending(path).get(key)
    if not is_json_object(entry):
        return None
    if entry.get("queued"):
        return check_queued_entry(repo, number, path, entry, write=write)
    current = read_async_merge(repo, number, str(entry.get("uuid") or ""))
    report = {
        **entry,
        "status": current["status"] or None,
        "message": current["message"],
    }
    if current.get("corrupt"):
        report["corrupt"] = True
    if current["expired"]:
        report["status"] = "expired"
    if current["status"] == "merged":
        report["verification"] = verify_request_landed(repo, number, entry)
        if report["verification"]["verified"] is None:
            return report
    if write and (current["expired"] or current["status"] in ASYNC_TERMINAL_STATUSES):
        update_pending(path, key, None)
    return report


def check_queued_entry(
    repo: str, number: int, path: Path, entry: dict[str, Any], *, write: bool = True
) -> dict[str, Any]:
    """A recorded merge-queue entry as GitHub reports it now.

    `queued` while the PR is still in the queue, `armed` while auto-merge will
    put it there, `merged` once it landed (checked against the recorded head),
    and `dequeued` when it left the queue without merging. An entry recorded
    `unconfirmed` (the queue showed no result yet) that reads back queued or
    armed is confirmed; one still showing nothing reads `unconfirmed` for
    `QUEUE_UNCONFIRMED_LATER_READS` runs and then `dequeued`. An unreadable
    queue keeps the record with status None; a merge whose head cannot be read
    back keeps it with status `merged` and `verified` None, and
    `queued_entry_hold` holds a merged entry on `verified`.
    """
    key = f"{repo}#{number}"
    queue = read_merge_queue(repo, number)
    report: dict[str, Any] = {**entry, "status": None, "message": ""}
    if queue["readError"]:
        report["message"] = queue["readError"]
        return report
    if queue["inQueue"] or (queue["autoMergeArmed"] and not queue["merged"]):
        if queue["inQueue"]:
            report["status"] = "queued"
            report["mergeQueue"] = {
                "state": queue["state"],
                "position": queue["position"],
            }
        else:
            report["status"] = "armed"
            report["mergeQueue"] = {
                "state": None,
                "position": None,
                "entersWhenReady": True,
            }
        if write and entry.get("unconfirmed"):
            confirmed = {
                field: value
                for field, value in entry.items()
                if field not in ("unconfirmed", "unseenReads")
            }
            update_pending(path, key, confirmed)
        return report
    if queue["merged"]:
        report["status"] = "merged"
        report["verification"] = verify_request_landed(repo, number, entry)
        if report["verification"]["verified"] is None:
            return report
    elif entry.get("unconfirmed"):
        unseen = _unseen_reads(entry) + 1
        report["unseenReads"] = unseen
        if unseen < QUEUE_UNCONFIRMED_LATER_READS:
            report["status"] = "unconfirmed"
            report["mergeQueue"] = {
                "state": None,
                "position": None,
                "unconfirmed": True,
            }
            if write:
                update_pending(path, key, {**entry, "unseenReads": unseen})
            return report
        report["status"] = "dequeued"
    else:
        report["status"] = "dequeued"
        report["removalReason"] = queue.get("lastRemovalReason")
    if write:
        update_pending(path, key, None)
    return report


def _unseen_reads(entry: dict[str, Any]) -> int:
    count = entry.get("unseenReads")
    return count if isinstance(count, int) and not isinstance(count, bool) else 0


def _record_pending(
    path: Path,
    repo: str,
    number: int,
    record: dict[str, Any],
    pin: str,
    result: dict[str, Any],
) -> None:
    """Keep a request that is still live on GitHub, or a PR it put in the merge
    queue; forget a finished one."""
    key = f"{repo}#{number}"
    live = (
        bool(record.get("uuid")) and record.get("status") not in ASYNC_TERMINAL_STATUSES
    )
    entry: dict[str, Any] | None = None
    if record.get("success") and record.get("status") == "enqueued":
        entry = _queued_entry(pin)
    elif live:
        entry = {
            "uuid": record["uuid"],
            "head": pin,
            "mergeAction": record.get("mergeAction"),
            "requestedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
        }
        stack = json_object(result.get("stack"))
        if stack.get("landsLowerLayers"):
            # The heads a later run checks the landed layers against.
            entry["stack"] = {
                "number": stack.get("number"),
                "layers": [
                    {"number": layer, "headRefOid": head}
                    for layer, head in _evaluated_layers(result)
                ],
            }
    _write_pending(path, key, entry, result)


def _queued_entry(pin: str, *, unconfirmed: bool = False) -> dict[str, Any]:
    entry: dict[str, Any] = {
        "queued": True,
        "head": pin,
        "mergeAction": "merge_queue",
        "requestedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
    }
    if unconfirmed:
        entry["unconfirmed"] = True
        entry["unseenReads"] = 0
    return entry


def _write_pending(
    path: Path, key: str, entry: dict[str, Any] | None, result: dict[str, Any]
) -> None:
    try:
        update_pending(path, key, entry)
    except (RuntimeError, OSError) as exc:
        result["pendingRecordError"] = (
            f"could not record the pending merge request ({exc}); a later run will "
            "not know it is live"
        )


def _queue_position(queue: dict[str, Any]) -> str:
    position = queue.get("position")
    where = "position unknown" if position is None else f"position {position}"
    return f"{where}, state {queue.get('state') or 'unknown'}"


# A queue push the signed-commit rule refuses is removed as
# `branch_protection_failure`. One known cause: GitHub wraps the body into the
# squash message, and a message line starting with `committer ` breaks
# the commit's signature (#7279, #7360). Requeuing rebuilds the same message.
SQUASH_SIGNATURE_CAUSE = (
    "if the base requires signed commits, the likely cause is a body line that "
    "GitHub's 72-character wrap starts with 'committer ', which breaks the squash "
    "commit's signature; reword the body before requeuing"
)


def queued_entry_hold(
    prior: dict[str, Any], verified: Any
) -> tuple[str | None, str | None]:
    """`(hold, reason)` for a recorded merge-queue entry. A hold with no reason
    is a merge that may still land; `(None, None)` is a confirmed merge."""
    status = prior.get("status")
    since = prior.get("requestedAt")
    if status == "queued":
        queue = json_object(prior.get("mergeQueue"))
        return (
            f"in the merge queue ({_queue_position(queue)}) since {since} -- "
            "queued, not merged; it may still land; no new request is sent",
            None,
        )
    if status == "armed":
        return (
            f"armed since {since} to enter the merge queue when its requirements "
            "pass -- not merged; it may still land; no new request is sent",
            None,
        )
    if status == "unconfirmed":
        return (
            f"gh pr merge succeeded at {since} on a merge-queue base, and the pull "
            f"request still reads back as neither queued, armed, nor merged (later "
            f"read {prior.get('unseenReads')} of {QUEUE_UNCONFIRMED_LATER_READS}) -- "
            "merge pending, unconfirmed; it may still land; no new request is sent",
            None,
        )
    if status == "dequeued" and prior.get("unconfirmed"):
        unseen = (
            f"gh pr merge succeeded at {since} on a merge-queue base, but the pull "
            f"request read back as neither queued, armed, nor merged on "
            f"{prior.get('unseenReads')} later runs -- dequeued, not merged; the "
            "record is cleared and the next run gates it again"
        )
        return unseen, unseen
    if status is None:
        return (
            f"the merge-queue entry recorded at {since} could not be read "
            f"({prior.get('message')}) -- merge pending; it may still land; no new "
            "request is sent",
            None,
        )
    if status == "dequeued":
        removal = prior.get("removalReason")
        cause = (
            f"the queue removed it as {removal!r}"
            if removal
            else "removed by hand or through the API, a failed or timed-out queue "
            "check, or a requirement it no longer meets"
        )
        if removal == "branch_protection_failure":
            cause += f"; {SQUASH_SIGNATURE_CAUSE}"
        dequeued = (
            f"left the merge queue without merging (queued at {since}): {cause} -- "
            "dequeued, not merged; the record is cleared and the next run gates it "
            "again"
        )
        return dequeued, dequeued
    if verified is not True:
        unconfirmed = "the merge-queue entry merged, but " + (
            "the head it landed could not be read back -- unconfirmed; the record "
            "is kept and re-checked next run"
            if verified is None
            else "the head it landed is not the head the gate evaluated -- "
            "escalate to a human"
        )
        return unconfirmed, unconfirmed
    return None, None


# --- The unattended path ------------------------------------------------------------------------

RISK_MARKER = whole_review.RISK_MARKER
# Appended to the reasons comment when its refusal persisted: the rewrite
# stamps the comment beside the label it explains, which the head-moved
# clear (clear-escalations.mjs) needs to pair them.
RISK_ESCALATION_LINE = (
    "This refusal has stood unchanged at this head, so a person is needed: "
    "the pr-merge lane added the human-gated label."
)
VERIFY_ESCALATION_MARKER = "<!-- babysit-merge-verify-escalation -->"
# The most of a verdict's summary a verify:repeated-fail escalation quotes
# (judgment).
VERIFY_SUMMARY_MAX = 1500
QUEUE_EJECTION_MARKER = "<!-- babysit-merge-queue-ejections -->"
MAJOR_ESCALATION_MARKER = "<!-- babysit-merge-dependabot-major -->"
# Cleared by clear-escalations.mjs once the head moves, like the verify one.
SHARED_COPY_ESCALATION_MARKER = "<!-- babysit-merge-shared-copy-escalation -->"
# The attended queue's escalation marker (work-items reference
# escalation-marker.md): first line of the held-major comment, so
# /work-items:attend-queue lists the pull request as escalated.
ATTEND_QUEUE_MARKER = "<!-- work-items:escalation lane=pr-merge kind=escalated -->"
UNATTENDED_REFUSED = "unattended merge refused: "
# Refusals that stop the path: the identity's own queued entries leave the queue.
STOP_REFUSALS = (
    "kill-switch:",
    "post-merge:",
    "rung-off:",
    merge_policy.DEFAULT_BRANCH_UNREADABLE,
    merge_policy.AUTHORITY_DIFFERS,
)
# The run-cache section of queued entries a gate process judged and kept.
SWEEP = "queue-sweep"
UNATTENDED_QUEUE_QUERY = (
    "query($o:String!,$r:String!,$b:String!){repository(owner:$o,name:$r){"
    "mergeQueue(branch:$b){entries(first:100){totalCount nodes{enqueuedAt position "
    "enqueuer{__typename login} pullRequest{id number}}}}}}"
)
DISARM_MUTATION = postmerge.DISARM_MUTATION
_CONTROL = re.compile(r"[\x00-\x08\x0b-\x1f\x7f-\x9f  ]")


def _checkout() -> Path:
    """The checkout the lane runs in, which the promotion evidence must sit
    outside; the working directory when it is not a git checkout."""
    try:
        proc = run_command(
            ["git", "rev-parse", "--show-toplevel"],
            allowed_executables=("git",),
            check=False,
        )
    except (RuntimeError, ValueError, OSError):
        return Path.cwd()
    top = proc.stdout.strip()
    return Path(top) if proc.returncode == 0 and top else Path.cwd()


class HeadPusherUnproven(Exception):
    """A head commit's pusher cannot be shown not to be a human."""


def _lane_evidence(
    repo: str,
    number: int,
    pr: dict[str, Any],
    identity: str,
    self_logins: frozenset[str],
    permission: Callable[[str], str | None],
    changed_paths: Sequence[str] | None,
) -> tuple[tuple[LaneEvidence, ...], list[dict[str, Any]]]:
    """Each lane's evidence for the pull request's head, and its comments.
    `changed_paths` is `bind()`'s: None when the changed files are unproven.

    The human test bound into `bind()` is the merge policy's, and it also
    returns False for the pull request's author and every head pusher (commit
    authors and committers, force-push actors): none of them may resolve a
    finding away. A commit with no linked author or committer, or a head with
    more commits than the list returns, raises `HeadPusherUnproven`. A retargeted base unbinds every lane.

    The timeline, the comments and the lane runs are read under the verdict
    reader's token when one is set, keeping them off the lane App's quota;
    every read here is a GET. A refused read, a rate limit included, raises
    and is never made again with the lane token: GitHub's Terms of Service
    bar sharing tokens to exceed its rate limits, so the candidate holds."""
    head = json_object(pr.get("head"))
    token = os.environ.get(verify_evidence.TOKEN_ENV)
    read_env = {"GH_TOKEN": token} if token else None
    timeline = fetch_paginated_api(
        f"repos/{repo}/issues/{number}/timeline?per_page=100",
        f"#{number} timeline",
        env_overrides=read_env,
    )
    commits = pull_request_commits_once(
        repo,
        number,
        head.get("sha"),
        lambda: fetch_paginated_api(
            f"repos/{repo}/pulls/{number}/commits?per_page=100", f"#{number} commits"
        ),
    )
    # The commits list is capped: a longer head has pushers no list names.
    total = pr.get("commits")
    if not isinstance(total, int) or isinstance(total, bool) or total > len(commits):
        raise HeadPusherUnproven(
            f"head-pusher-unproven:commits-listed:{len(commits)}-of:{total}"
        )
    # A commit whose author or committer email no account claims names no
    # login to exclude, so whoever pushed it is not proven non-human.
    unlinked = [
        str(item.get("sha") or "?")[:12]
        for item in commits
        if not all(
            json_object(item.get(role)).get("login") for role in ("author", "committer")
        )
    ]
    if unlinked:
        raise HeadPusherUnproven(f"head-pusher-unproven:{','.join(unlinked)}")
    excluded = {
        str(json_object(item.get(role)).get("login") or "").casefold()
        for item in commits
        for role in ("author", "committer")
    }
    excluded |= {
        str(json_object(e.get("actor")).get("login") or "").casefold()
        for e in timeline
        if e.get("event") == "head_ref_force_pushed"
    }
    excluded.add(str(json_object(pr.get("user")).get("login") or "").casefold())
    excluded.discard("")
    comments = fetch_paginated_api(
        f"repos/{repo}/issues/{number}/comments?per_page=100",
        f"#{number} comments",
        env_overrides=read_env,
    )
    try:
        threads: list[Any] | None = fetch_review_threads(
            repo, number, include_resolved=True
        )
    except GraphQLUnavailableError:
        threads = None
    runs = collect_lane_runs(
        repo,
        number,
        str(head.get("ref")),
        review_evidence.LANES.values(),
        str(pr.get("created_at") or ""),
        read_env,
    )

    def human(actor: Any) -> bool:
        return merge_policy.actor_key(actor) not in excluded and merge_policy.is_human(
            actor,
            repo=repo,
            agent_identity=identity,
            self_logins=self_logins,
            permission=permission,
        )

    lanes = review_evidence.bind(
        str(head.get("sha")),
        runs,
        comments,
        threads,
        is_human=human,
        changed_paths=changed_paths,
        base_changed=any(e.get("event") == "base_ref_changed" for e in timeline),
        head_file=_head_file(repo, str(head.get("sha"))),
    )
    return lanes, comments


def _head_file(repo: str, head: str) -> Callable[[str, str], str | None]:
    """`bind()`'s `head_file`: a file's text at `head`, or None only when the
    comparison from the thread's commit lists it removed. A rename, a capped
    file list or any other failure raises, so the thread keeps its human test."""
    cache: dict[tuple[str, str], str | None] = {}

    def read(path: str, original: str) -> str | None:
        if (path, original) in cache:
            return cache[(path, original)]
        proc = gh_capture(
            [
                "api",
                "-H",
                "Accept: application/vnd.github.raw",
                f"repos/{repo}/contents/{quote(path)}?ref={head}",
            ]
        )
        if proc.returncode == 0:
            text: str | None = proc.stdout
        elif gh_http_status(proc.stderr or "") != 404:
            raise RuntimeError(f"head-file-unread:{path}")
        else:
            files = json_object(
                gh_json(["api", f"repos/{repo}/compare/{original}...{head}"])
            ).get("files")
            # The comparison lists at most 300 files; a full page may hide one.
            if (
                not is_json_array(files)
                or len(files) >= 300
                or not any(
                    is_json_object(item)
                    and item.get("filename") == path
                    and item.get("status") == "removed"
                    for item in files
                )
            ):
                raise RuntimeError(f"head-file-unproven:{path}")
            text = None
        cache[(path, original)] = text
        return text

    return read


def score_unattended(
    repo: str,
    number: int,
    policy: merge_policy.UnattendedPolicy,
    self_logins: frozenset[str],
) -> merge_policy.UnattendedPolicy:
    """Bind the review evidence and score the diff (Design T2, T6) for an
    eligible pull request on a live path; an ineligible one is not scored
    (T3). A score that holds (`babysit_risk.holds`) refuses the merge as
    `risk:<score>`."""
    inputs = dict(policy.inputs or {})
    eligible = inputs.get("eligibility")
    if not policy.enabled or eligible is None or not eligible.eligible:
        return policy
    if eligible.dependabot is not None:
        # The Dependabot class is not scored: `ci-status` is its gate, and a
        # workflow pin bump sits on a HIGH path by definition.
        details = {
            **(policy.details or {}),
            "headSha": json_object(inputs["pr"].get("head")).get("sha"),
            "risk": {"score": None, "reason": "not-scored:dependabot"},
        }
        return replace(policy, details=details)
    pr, config = inputs["pr"], inputs["config"]
    details = {
        **(policy.details or {}),
        "headSha": json_object(pr.get("head")).get("sha"),
    }
    # The pr-merge lane also needs a passing verifier verdict at the head,
    # judged first: a refusal stands whatever the diff scores, so its lane
    # evidence and changed files are not read and its reasons comment waits
    # for a run the verifier passes. A refusal makes this pull request's own
    # queued entry leave too.
    reader: verify_evidence.Reader | None = None
    if (
        inputs.get("authority") == merge_policy.PR_MERGE
        and config.require_verifier_verdict
    ):
        reader = verify_evidence.Reader(
            repo, str(inputs["branch"]), max_fails=config.max_verify_fails
        )
        verdict = reader.evidence(number, str(details["headSha"]), pr)
        details["verify"] = verdict.report()
        inputs["verify_reader"] = reader
        if verdict.refusal:
            inputs["own_refusal"] = inputs.get("own_refusal") or verdict.refusal
            reason = policy.reason or verdict.refusal
            return replace(policy, reason=reason, details=details, inputs=inputs)
    try:
        files, complete = merge_policy.changed_files(repo, pr)
    except merge_policy.PolicyReadError:
        files, complete = (), False
    comments: list[dict[str, Any]] | None = None
    try:
        lanes, comments = _lane_evidence(
            repo,
            number,
            pr,
            inputs["identity"],
            self_logins,
            inputs["permission"],
            [p for f in files for p in (f.path, f.previous_path) if p]
            if complete
            else None,
        )
    except HeadPusherUnproven as exc:
        # Fail closed: refused, and its own queued entry leaves.
        inputs["own_refusal"] = inputs.get("own_refusal") or str(exc)
        return replace(policy, reason=policy.reason or str(exc), inputs=inputs)
    except (RuntimeError, ValueError, json.JSONDecodeError):
        lanes = tuple(
            LaneEvidence(lane, False, "evidence-missing", None)
            for lane in review_evidence.LANES
        )
    # An adopted pull request's trusted author: the denied paths and manifest review hold only
    # paths someone else's commits touched, a lane's fix among them. A
    # model-driven App's own lines count only under `MODEL_APP_OWN` (Q14 (c)).
    own = (
        merge_policy.own_paths(
            repo,
            pr,
            frozenset(p for f in files for p in (f.path, f.previous_path) if p),
            None if eligible.body_is_intent else merge_policy.MODEL_APP_OWN,
        )
        if eligible.adoption
        else frozenset()
    )
    # The manifest review compares base and head text; the cost hold reads a
    # workflow's head text for its model legs.
    files = merge_policy.with_contents(repo, pr, files)
    # The pr-merge lane's switches (owner decision Q624); the local lane
    # keeps HIGH_FLOOR, both caps and the C2 contradictions.
    lane_switches = (
        {
            "high_floor": config.high_path_floor,
            "c2_contradictions": config.c2_contradictions,
            "max_changed_files": config.max_changed_files,
            "lines_optional": True,
        }
        if inputs.get("authority") == merge_policy.PR_MERGE
        else {}
    )
    private = json_object(json_object(pr.get("base")).get("repo")).get("private")
    risk_input = babysit_risk.RiskInput(
        work_class=eligible.work_class,
        rung=babysit_risk.Rung[inputs["rung"].upper()],
        files=files,
        files_complete=complete,
        max_changed_lines=config.max_changed_lines,
        high_paths=config.denied_paths,
        lanes=lanes,
        blast_radius=None,
        floor_exempt=own,
        public=True if private is False else None,
        pulumi_dirs=merge_policy.pulumi_dirs_at(repo, pr),
        **lane_switches,
    )
    risk = babysit_risk.score(risk_input)
    if any(r.code == babysit_risk.COST_CODE for r in risk.reasons):
        # Read only for a cost hold: an owner decision the body cites clears it.
        decision = merge_policy.cost_decision(
            repo,
            pr,
            eligible.issue,
            permission=inputs["permission"],
            agent_identity=inputs.get("identity"),
            self_logins=self_logins,
        )
        if decision:
            details["costDecision"] = decision
            risk = babysit_risk.score(replace(risk_input, cost_decision=decision))
    details |= {
        "risk": {
            "score": risk.score.name,
            "reasons": [
                {"code": r.code, "severity": r.severity.name, "detail": r.detail}
                for r in risk.reasons
            ],
        },
        "evidence": [
            {
                "lane": lane.lane,
                "bound": lane.bound,
                "unboundReason": lane.unbound_reason,
                "openFindings": lane.open_findings,
            }
            for lane in lanes
        ],
    }
    # Every other gate passed and only findings a clean whole review of the
    # head would close hold it (babysit_whole_review.py).
    details["wholeReviewWanted"] = whole_review.wanted(policy.reason, risk, lanes)
    inputs.update(risk=risk, comments=comments)
    reason = policy.reason or (
        f"risk:{risk.score.name}" if babysit_risk.holds(risk) else None
    )
    if reader is not None and reason is None and reader.saved:
        # The run's saved listing lacks anything uploaded since; allow only
        # on a listing of this gate run's own. A candidate refused already is
        # not enqueued, so it does not page the listing again.
        reader.refresh()
        verdict = reader.evidence(number, str(details["headSha"]), pr)
        details["verify"] = verdict.report()
        if verdict.refusal:
            inputs["own_refusal"] = inputs.get("own_refusal") or verdict.refusal
        reason = verdict.refusal
    return replace(policy, reason=reason, details=details, inputs=inputs)


def assess_unattended(
    repo: str,
    number: int,
    *,
    self_logins: frozenset[str],
    authority: str = merge_policy.LOCAL_BABYSIT,
    lane_kill_switch: str | None = None,
    lane_rung_cap: str | None = None,
    shared: merge_policy.SharedPostMerge | None = None,
    share: Callable[[merge_policy.SharedPostMerge], object] | None = None,
) -> merge_policy.UnattendedPolicy:
    """The unattended decision for one pull request, in the wiring order:
    identity, the credential chokepoint, the kill switch, a default-branch
    base, the post-merge check (or the run's `shared` answer), demotion and cap, in flight, promotion evidence, eligibility, then
    the review evidence and the score. Raises `PolicyReadError` when the
    pull request or its pipeline config cannot be read."""

    def post_merge(floor: datetime, identity: str) -> merge_policy.PostMergeGate:
        verdict = postmerge.check(
            repo,
            agent_identity=identity,
            is_human=postmerge._default_is_human(repo, identity, self_logins),
            merged_since=floor,
            pinned_sha=postmerge.pin_reader(repo, identity),
            lane_merges_only=authority == merge_policy.PR_MERGE,
        )
        return postmerge.gate_from_report(verdict.report())

    def promotion(window_start: datetime | None) -> merge_policy.Promotion:
        return merge_policy.read_promotion(
            checkout=_checkout(),
            window_start=window_start,
        )

    # The label an adopted owner pull request holds on; unreadable adopts none.
    human_gated = None
    if authority == merge_policy.PR_MERGE:
        try:
            human_gated = human_gated_label(repo)
        except postmerge.PostMergeReadError:
            pass
    policy = merge_policy.assess(
        repo,
        number,
        human_gated=human_gated,
        self_logins=self_logins,
        post_merge=post_merge,
        promotion=promotion,
        authority=authority,
        lane_kill_switch=lane_kill_switch,
        lane_rung_cap=lane_rung_cap,
        shared=shared,
        share=share,
    )
    return score_unattended(repo, number, policy, self_logins)


def _first_line(text: Any) -> str:
    return str(text or "").split("\n", 1)[0].rstrip("\r")


def _floor_held(risk: babysit_risk.RiskResult) -> bool:
    """Whether the HIGH floor or a trust gate holds the pull request: a
    `high-path:` reason for a floor or configured path, or a `trust-gate:`
    one. An unsafe path scores HIGH with the floor off, so it is not a floor
    hold."""
    return any(
        r.severity is babysit_risk.Risk.HIGH
        and r.code.startswith(("high-", babysit_risk.TRUST_GATE_PREFIX))
        and r.code != babysit_risk.UNSAFE_PATH_CODE
        for r in risk.reasons
    )


def _marker_lines(text: Any) -> list[str]:
    """The first two lines, where a lane comment carries its markers."""
    return [line.rstrip("\r") for line in str(text or "").split("\n", 2)[:2]]


def risk_comment_body(risk: babysit_risk.RiskResult, head: str) -> str:
    """The reasons comment: a function of the score, the reasons and the head
    only, so an unchanged assessment renders the same body."""
    wait = (
        "A floor path holds it: a human merges it in person, never an agent or a lane."
        if _floor_held(risk)
        else "This pull request waits for one."
    )
    lines = [
        RISK_MARKER,
        f"Unattended merge: risk **{risk.score.name}** at head `{head}`. Only LOW, "
        "or MED on class, size and reported review-finding reasons alone, merges "
        f"without a human. {wait}",
        "",
        "```text",
    ]
    for reason in risk.reasons:
        text = f"{reason.severity.name} {reason.code}: {reason.detail}"
        lines.append(_CONTROL.sub("?", text).replace("```", "'''"))
    lines.append("```")
    return "\n".join(lines)


def risk_cleared_body(head: str) -> str:
    """The reasons comment once the head's score no longer holds it: a refusal there later
    renders a different body, so its time starts then, not at the old one."""
    return "\n".join(
        [
            RISK_MARKER,
            f"Unattended merge: no risk reason holds the merge at head `{head}`. "
            "The earlier refusal no longer holds.",
        ]
    )


def _newest_marker_comment(
    comments: list[dict[str, Any]], identity: str, marker: str
) -> dict[str, Any] | None:
    """The identity's newest comment whose first or second line is `marker`."""
    mine = [
        c
        for c in comments
        if merge_policy.actor_key(
            {
                "__typename": json_object(c.get("user")).get("type"),
                "login": json_object(c.get("user")).get("login"),
            }
        )
        == identity.casefold()
        and marker in _marker_lines(c.get("body"))
    ]
    if not mine:
        return None
    return max(mine, key=lambda c: (str(c.get("created_at")), c.get("id") or 0))


def _stood_unchanged(comment: dict[str, Any], body: str, minutes: int) -> bool:
    """Whether `comment` already reads `body` (the same score, reasons and
    head) and has for at least `minutes`, timed from its last change: a
    rewrite of its reasons restarts the time."""
    if str(comment.get("body") or "") != body:
        return False
    changed = parse_github_timestamp(
        str(comment.get("updated_at") or comment.get("created_at") or "")
    )
    return changed is not None and _now() - changed >= timedelta(minutes=minutes)


def upsert_marker_comment(
    repo: str,
    number: int,
    identity: str,
    body: str,
    comments: list[dict[str, Any]] | None,
    marker: str = RISK_MARKER,
) -> str:
    """Post or rewrite the identity's one comment whose first or second line
    is `marker` (the reasons comment, Design T14, by default): `unchanged` when
    the newest one already says this, else
    `updated` or `created`. Raises `RuntimeError` on a failed read or write."""
    if comments is None:
        comments = fetch_paginated_api(
            f"repos/{repo}/issues/{number}/comments?per_page=100", f"#{number} comments"
        )
    newest = _newest_marker_comment(comments, identity, marker)
    if newest is not None:
        if str(newest.get("body") or "") == body:
            return "unchanged"
        args = [
            "api",
            "-X",
            "PATCH",
            f"repos/{repo}/issues/comments/{newest.get('id')}",
        ]
        outcome = "updated"
    else:
        args = ["api", "-X", "POST", f"repos/{repo}/issues/{number}/comments"]
        outcome = "created"
    proc = gh_capture([*args, "-f", f"body={body}"])
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip())
    return outcome


def verify_escalation_body(
    refusal: str,
    head: str,
    summary: str | None = None,
    carried: tuple[str, str] | None = None,
) -> str:
    """The needs-human comment for a verifier refusal: a function of the
    refusal, the head and the quoted fail summary only, so a rerun renders the
    same body. The summary is model text, quoted as data in a text fence and
    cut to `VERIFY_SUMMARY_MAX` characters. `carried`, the (head, text) an
    earlier comment quoted (`_carried_quote`), is quoted as it was when there
    is no `summary`."""
    lines = [
        VERIFY_ESCALATION_MARKER,
        f"Unattended merge: the verifier verdict refuses `{refusal}` at head "
        f"`{head}`. That refusal needs a human, who merges in person; the "
        "pr-merge lane will not merge this pull request.",
    ]
    quote = carried
    if summary:
        text = _CONTROL.sub("?", summary.replace("\r\n", "\n"))
        if len(text) > VERIFY_SUMMARY_MAX:
            text = text[:VERIFY_SUMMARY_MAX] + " [cut]"
        # A lone surrogate from a JSON escape cannot be encoded for `gh`.
        text = text.encode("utf-8", "replace").decode("utf-8")
        quote = (head, text.replace("```", "'''"))
    if quote:
        lines += [
            "",
            f"The verifier's summary of its fail verdict at `{quote[0]}`, as it "
            "wrote it:",
            "",
            "```text",
            quote[1],
            "```",
        ]
    return "\n".join(lines)


_QUOTE_RE = re.compile(
    r"\nThe verifier's summary of its fail verdict at `([0-9a-f]{40})`, as it "
    r"wrote it:\n\n```text\n(.*)\n```\Z",
    re.S,
)


def _carried_quote(
    comments: list[dict[str, Any]], identity: str
) -> tuple[str, str] | None:
    """The (head, text) the identity's newest verify escalation quotes, read
    back verbatim so a rerun that cannot read the summary renders the same
    body, and an earlier-fail keeps the reason of the fail before it."""
    newest = _newest_marker_comment(comments, identity, VERIFY_ESCALATION_MARKER)
    if newest is None:
        return None
    match = _QUOTE_RE.search(str(newest.get("body") or ""))
    return (match[1], match[2]) if match else None


def major_escalation_body(majors: str, head: str) -> str:
    """The needs-human comment for a Dependabot major update held under
    `merge.dependabot.majors: hold`: a function of the updates and the head
    only, so a rerun renders the same body."""
    return "\n".join(
        [
            ATTEND_QUEUE_MARKER,
            MAJOR_ESCALATION_MARKER,
            f"Unattended merge: `{majors}` is a major version update, one whose "
            "version cannot be read (`(unreadable)`), or one whose title and "
            f"commit metadata disagree (`(disagree)`), at head `{head}`. This "
            "repository "
            "holds those Dependabot updates for a human "
            "(`merge.dependabot.majors: hold`), whatever the review verdict "
            "says; the pr-merge lane will not merge this pull request.",
        ]
    )


def shared_copy_escalation_body(
    reason: str, sources: list[str], branch: str, merge_base: str, head: str
) -> str:
    """The needs-human comment for a pull request whose carried shared-copy
    canonicals changed on the base: a function of its arguments only, so a
    rerun at the same head renders the same body."""
    names = ", ".join(f"`{s.replace('`', "'")}`" for s in sources)
    return "\n".join(
        [
            SHARED_COPY_ESCALATION_MARKER,
            f"Unattended merge: the shared-library canonical source {names} changed "
            f"on `{branch}` since merge base `{merge_base}`, so the generated "
            f"copies this pull request carries are stale at head `{head}`.",
            "",
            f"Refusal: `{reason}`",
            "",
            "Updating the branch from the base cannot regenerate them, so the "
            "pr-merge lane will not enqueue it. To fix: merge "
            f"`{branch}` into this branch, run `scripts/sync-shared-copies.sh`, "
            "commit the regenerated copies, and push. pr-merge judges the new "
            "head afresh.",
        ]
    )


def escalate_verify(
    repo: str,
    number: int,
    identity: str,
    refusal: str,
    inputs: Mapping[str, Any],
    summary: str | None = None,
) -> dict[str, Any]:
    """`escalate` for a needs-human verifier refusal. A
    `verify:repeated-fail` with no `summary` (unreadable, or no fail at the
    head) quotes the last fail summary its comment carried, so an unreadable
    artifact rewrites nothing and the reason outlives the head."""
    head = str(json_object(json_object(inputs.get("pr")).get("head")).get("sha"))
    carried = None
    if summary is None and refusal == verify_evidence.REPEATED_FAIL:
        comments = inputs.get("comments")
        if comments is None:
            comments = fetch_paginated_api(
                f"repos/{repo}/issues/{number}/comments?per_page=100",
                f"#{number} comments",
            )
            inputs = {**inputs, "comments": comments}
        carried = _carried_quote(comments, identity)
    body = verify_escalation_body(refusal, head, summary, carried)
    return escalate(repo, number, identity, body, VERIFY_ESCALATION_MARKER, inputs)


def _fail_summary(
    verify: Mapping[str, Any], inputs: Mapping[str, Any], number: int
) -> str | None:
    """The summary of the head FAIL a `verify:repeated-fail` refusal names,
    read through the gate's verdict reader; None for any other refusal, with
    no FAIL at the head, or when the record cannot be read."""
    fail = json_object(verify.get("headFail"))
    reader = inputs.get("verify_reader")
    run_id, name = fail.get("run"), fail.get("artifact")
    if (
        verify.get("refusal") != verify_evidence.REPEATED_FAIL
        or not isinstance(reader, verify_evidence.Reader)
        or not isinstance(run_id, int)
        or not isinstance(name, str)
    ):
        return None
    try:
        return reader.fail_summary(run_id, name, number, str(verify.get("head")))
    except verify_evidence.SummaryUnreadable:
        return None


def escalate(
    repo: str,
    number: int,
    identity: str,
    body: str,
    marker: str,
    inputs: Mapping[str, Any],
) -> dict[str, Any]:
    """The escalation contract (loop-lane README §2): one comment carrying
    `marker`, then the tracker's human-gated role label on the pull request,
    added only when no label matches it case-insensitively. The comment goes
    first so a label never stands unexplained; a failed label is retried by
    the next run, which finds the comment unchanged. A label a person removed
    after that comment last changed is not a failed write but a lift
    (`_lifted_by_person`): it stays off, as `lifted`, until the comment
    changes (a new head or reason). Raises `RuntimeError` on a failed write."""
    pr = json_object(inputs.get("pr"))
    # Read once here, so the lift check reuses what the upsert read.
    comments = inputs.get("comments")
    if comments is None:
        comments = fetch_paginated_api(
            f"repos/{repo}/issues/{number}/comments?per_page=100", f"#{number} comments"
        )
    comment = upsert_marker_comment(
        repo, number, identity, body, comments, marker=marker
    )
    try:
        label = human_gated_label(repo)
    except postmerge.PostMergeReadError:
        label = postmerge.DEFAULT_ROLE_LABEL
    labels = pr.get("labels")
    present = is_json_array(labels) and any(
        str(json_object(item).get("name") or "").casefold() == label.casefold()
        for item in labels
    )
    unread = ""
    if not present and comment == "unchanged":
        lifted, unread = _lifted_by_person(
            repo, number, identity, label, marker, comments, inputs
        )
        if lifted:
            return {"label": "lifted", "comment": comment}
    if not present:
        proc = gh_capture(
            ["api", "-X", "POST", f"repos/{repo}/issues/{number}/labels"]
            + ["-f", f"labels[]={label}"]
        )
        if proc.returncode != 0:
            raise RuntimeError(f"label {label}: {proc.stderr.strip()}")
    result = {"label": "present" if present else "added", "comment": comment}
    if unread:
        result["liftUnread"] = unread
    return result


def _lifted_by_person(
    repo: str,
    number: int,
    identity: str,
    label: str,
    marker: str,
    comments: list[dict[str, Any]],
    inputs: Mapping[str, Any],
) -> tuple[bool, str]:
    """Whether the newest removal of `label` came strictly after the
    identity's `marker` comment last changed and was a person's, acting in
    person (no `performed_via_github_app`): a User of kind `human` on the
    trusted-actor list read at the repository's default branch (never the
    head, nor a base a retarget could pick), who also passes
    `merge_policy.is_human` (write access, not a bot, the agent identity or
    a self-login). That comment names the head and the reasons, so the
    removal lifted this escalation. The timeline is read under the verdict
    reader's token when one is set; any failure, unreadable list or default
    branch, or unparsable time is no lift, so the label goes on. The second
    value names a read that failed, empty otherwise."""
    token = os.environ.get(verify_evidence.TOKEN_ENV)
    try:
        prior = _newest_marker_comment(comments, identity, marker) or {}
        escalated = parse_github_timestamp(
            str(prior.get("updated_at") or prior.get("created_at") or "")
        )
        if escalated is None:
            return False, ""
        timeline = fetch_paginated_api(
            f"repos/{repo}/issues/{number}/timeline?per_page=100",
            f"#{number} timeline",
            env_overrides={"GH_TOKEN": token} if token else None,
        )
        removals = [
            (at, event)
            for event in timeline
            if event.get("event") == "unlabeled"
            and str(json_object(event.get("label")).get("name") or "").casefold()
            == label.casefold()
            and (at := parse_github_timestamp(str(event.get("created_at") or "")))
            is not None
        ]
        if not removals:
            return False, ""
        default = repository_default_branch(repo)
        if not default:
            return False, "default branch unread"
        # The newest removal decides; a tie keeps the later timeline item.
        at, event = max(enumerate(removals), key=lambda r: (r[1][0], r[0]))[1]
        actor = json_object(event.get("actor"))
        return (
            at > escalated
            and event.get("performed_via_github_app") is None
            and actor.get("type") == "User"
            and actor.get("id") in merge_policy.trusted_actors(repo, default)[1]
            and merge_policy.is_human(
                {"__typename": "User", "login": actor.get("login")},
                repo=repo,
                agent_identity=identity or None,
                self_logins=inputs.get("self_logins") or frozenset(),
                permission=inputs.get("permission"),
            )
        ), ""
    except Exception as exc:  # noqa: BLE001 -- any failure escalates as before
        return False, f"{type(exc).__name__}: {exc}"


def _failed_merge_group_runs(repo: str, branch: str, number: int) -> list[str] | None:
    """The links of the pull request's failed merge_group runs among the
    repository's newest 100, newest first, or None when they cannot be read.
    Read under the verdict reader's Actions token when one is set."""
    token = os.environ.get(verify_evidence.TOKEN_ENV)
    proc = gh_capture(
        [
            "api",
            f"repos/{repo}/actions/runs?event=merge_group&status=failure&per_page=100",
        ],
        env_overrides={"GH_TOKEN": token} if token else None,
    )
    if proc.returncode != 0:
        return None
    try:
        runs = json_object(json.loads(proc.stdout)).get("workflow_runs")
    except ValueError:
        return None
    if not is_json_array(runs):
        return None
    prefix = f"gh-readonly-queue/{branch}/pr-{number}-"
    return [
        str(run.get("html_url"))
        for run in map(json_object, runs)
        if str(run.get("head_branch") or "").startswith(prefix) and run.get("html_url")
    ]


def queue_ejection_body(head: str, count: int, runs: list[str] | None) -> str:
    """The comment for a head the gate stopped enqueuing: a function of the
    head, the count and the runs read, so a rerun renders the same body."""
    lines = [
        QUEUE_EJECTION_MARKER,
        f"Unattended merge: the merge queue removed head `{head}` {count} times "
        "for failed checks, so the pr-merge lane will not enqueue it again. "
        "A push resets the count.",
        "",
    ]
    if runs is None:
        lines.append("The failing merge_group runs could not be read.")
    elif not runs:
        lines.append("No failing merge_group run was found among the newest 100.")
    else:
        lines += ["Failing merge_group runs:", *(f"- {url}" for url in runs)]
    return "\n".join(lines)


def _queued_verify_hold(verifier: verify_evidence.Reader, number: int) -> str | None:
    """One queued entry's verifier hold. An unexpected error refuses that
    entry, so it leaves the queue and the sweep goes on to the next."""
    try:
        return verifier.queued_hold(number)
    except Exception:  # noqa: BLE001 -- any crash refuses this entry alone
        return verify_evidence.UNREADABLE


def _sweep_key(repo: str, branch: str, identity: str, number: int) -> str:
    return f"{repo}|{branch}|{identity.casefold()}|{number}"


def _kept_recently(repo: str, branch: str, identity: str, number: int) -> bool:
    """Whether a gate process of this run kept the queued entry on reads
    taken at most `run_cache.MAX_AGE` ago, dated by its oldest input (a
    shared permission, trusted list or verdict listing included): the bound
    every judgment of an entry already keeps."""
    stamp = run_cache.get(SWEEP, _sweep_key(repo, branch, identity, number), None)
    try:
        at = datetime.fromisoformat(stamp)
    except (TypeError, ValueError):
        return False
    return (
        at.tzinfo is not None
        and timedelta(0) <= run_cache.now() - at <= run_cache.MAX_AGE
    )


def unattended_writes(
    repo: str, number: int, policy: merge_policy.UnattendedPolicy
) -> dict[str, Any]:
    """The writes that come before any merge decision, under `--merge` only.

    A stop refusal (kill switch, post-merge, rung off) dequeues every entry
    the identity enqueued; otherwise each queued identity entry carrying a
    hold (D3) leaves the queue, as does this pull request's own entry when
    this run refused it for itself (`own_refusal`) or its score holds it
    (`risk:<score>`). Then the reasons comment for an eligible
    pull request its score holds, on a path not stopped, escalated (`escalate`)
    when the comment read before this run already says the same and has for
    `merge.risk-escalation-minutes` (`_stood_unchanged`), the comment first
    rewritten to end with `RISK_ESCALATION_LINE` (once); once the score no longer holds it, a refusal
    comment naming the head becomes `risk_cleared_body`; and the escalation
    (`escalate_verify`) for a verifier refusal that needs a human, or for a
    Dependabot update held under `merge.dependabot.majors: hold`, keyed on the
    eligibility reason. Nothing is written before
    the identity and the credential chokepoint passed (`inputs["identity"]`)."""
    inputs = policy.inputs or {}
    identity, branch = inputs.get("identity"), inputs.get("branch")
    report: dict[str, Any] = {"dequeued": [], "holds": {}, "errors": []}
    if not identity or not branch:
        return report
    stopped = (policy.reason or "").startswith(STOP_REFUSALS)
    risk = inputs.get("risk")
    try:
        if stopped:
            numbers = None
        else:
            queued, _ = postmerge.identity_queue(repo, branch, identity)
            # In the pr-merge lane a queued entry also leaves without a
            # passing verifier verdict at its head now.
            config = inputs.get("config")
            verifier = inputs.get("verify_reader") or (
                verify_evidence.Reader(repo, branch, max_fails=config.max_verify_fails)
                if inputs.get("authority") == merge_policy.PR_MERGE
                and config is not None
                and config.require_verifier_verdict
                else None
            )
            # When each kept entry's reads began (`_kept_recently`).
            kept_at: dict[int, datetime] = {}

            def judge(n: int) -> str | None:
                # Dated by its oldest input: a shared permission, trusted
                # list or verdict listing may predate the judgment.
                with run_cache.track() as taken:
                    began = run_cache.now()
                    hold = merge_policy.entry_hold(
                        repo,
                        n,
                        identity,
                        self_logins=inputs.get("self_logins") or frozenset(),
                        permission=inputs.get("permission"),
                    ) or (
                        _queued_verify_hold(verifier, n)
                        if verifier is not None and n != number
                        else None
                    )
                kept_at[n] = min([began, *taken])
                return hold

            report["holds"] = {
                n: hold
                for n in queued
                if (n == number or not _kept_recently(repo, branch, identity, n))
                and (hold := judge(n))
            }
            # This run's own read of a queued entry also counts: the pull
            # request it just found ineligible, above the rung, unpromoted
            # for its class, on another base or held by its score leaves the
            # queue.
            own = inputs.get("own_refusal") or (
                f"risk:{risk.score.name}"
                if risk is not None and babysit_risk.holds(risk)
                else None
            )
            if number in queued and own:
                report["holds"].setdefault(number, own)
            numbers = set(report["holds"])
        if numbers is None or numbers:
            unknown = postmerge.dequeue_identity_entries(
                repo, branch, identity, numbers=numbers, dequeued=report["dequeued"]
            )
            if unknown:
                report["errors"].append(
                    f"{unknown} queue entries have an unknown enqueuer"
                )
        # Only an entry this process judged and kept, never its own (which
        # its gate judges in full) or one it skipped.
        for n, at in kept_at.items() if numbers is not None else ():
            if n != number and n not in numbers:
                run_cache.put(
                    SWEEP, _sweep_key(repo, branch, identity, n), at.isoformat()
                )
    except (postmerge.PostMergeReadError, postmerge.PostMergeWriteError) as exc:
        report["errors"].append(f"dequeue: {exc}")
    # A stopped path (demoted, capped off, switched off) merges nothing, so a
    # reasons comment would only say so on every pull request.
    if not stopped and risk is not None and babysit_risk.holds(risk):
        head = str(json_object(inputs["pr"].get("head")).get("sha"))
        body = risk_comment_body(risk, head)
        try:
            comments = inputs.get("comments")
            if comments is None:
                comments = fetch_paginated_api(
                    f"repos/{repo}/issues/{number}/comments?per_page=100",
                    f"#{number} comments",
                )
            # An earlier run's reasons comment saying the same thing at this
            # head for long enough means the refusal persisted: escalate it.
            # A shorter stand may be a review still running at the head.
            config = inputs.get("config")
            minutes = (
                config.risk_escalation_minutes
                if config is not None
                else merge_policy.RISK_ESCALATION_MINUTES
            )
            prior = _newest_marker_comment(comments, identity, RISK_MARKER)
            body, report["wholeReview"] = _whole_review_record(
                repo, policy, body, head, prior
            )
            escalated = f"{body}\n\n{RISK_ESCALATION_LINE}"
            if prior is not None and (
                str(prior.get("body") or "") == escalated
                or _stood_unchanged(prior, body, minutes)
            ):
                escalation = escalate(
                    repo, number, identity, escalated, RISK_MARKER,
                    {**inputs, "comments": comments},
                )  # fmt: skip
                report["riskComment"] = escalation["comment"]
                report["riskEscalation"] = escalation
            else:
                report["riskComment"] = upsert_marker_comment(
                    repo, number, identity, body, comments
                )
            # Recorded first, so a failed write never toggles twice at a head.
            if report["wholeReview"] == {"toggle": True}:
                node_id = str(json_object(inputs.get("pr")).get("node_id") or "")
                report["wholeReview"] = whole_review.toggle(node_id)
        except (RuntimeError, ValueError, json.JSONDecodeError) as exc:
            report["errors"].append(f"reasons comment: {exc}")
        if report.get("wholeReview") is None:
            report.pop("wholeReview", None)
    # A score that no longer holds ends the refusal at this head: the identity's refusal
    # comment naming it says so once, from comments already read. An
    # escalated one stays beside the label it explains.
    elif not stopped and risk is not None and inputs.get("comments") is not None:
        head = str(json_object(inputs["pr"].get("head")).get("sha"))
        prior = _newest_marker_comment(inputs["comments"], identity, RISK_MARKER)
        text = str((prior or {}).get("body") or "")
        # Every whole-review record stays, so the cap counts across heads.
        cleared = whole_review.with_records(
            risk_cleared_body(head), whole_review.record_lines(text)
        )
        if (
            prior is not None
            and f" at head `{head}`" in text
            and text != cleared
            and not text.endswith(RISK_ESCALATION_LINE)
        ):
            try:
                report["riskComment"] = upsert_marker_comment(
                    repo, number, identity, cleared, inputs["comments"]
                )
            except RuntimeError as exc:
                report["errors"].append(f"reasons comment: {exc}")
    # A verifier refusal that needs a human gets the durable escalation
    # signal; report-only never reaches here.
    verify = json_object((policy.details or {}).get("verify"))
    if not stopped and verify.get("needsHuman") is True:
        try:
            report["escalation"] = escalate_verify(
                repo,
                number,
                identity,
                str(verify.get("refusal")),
                inputs,
                _fail_summary(verify, inputs, number),
            )
        except (RuntimeError, ValueError, json.JSONDecodeError) as exc:
            report["errors"].append(f"escalation: {exc}")
    # A held major Dependabot update gets the same signal, so it reaches the
    # human queue, whatever refusal tops it (an `in-flight:` one included).
    held = f"{merge_policy.MAJOR_HELD}:"
    eligibility = str(
        json_object((policy.details or {}).get("eligibility")).get("reason") or ""
    )
    if not stopped and eligibility.startswith(held):
        head = str(json_object(json_object(inputs.get("pr")).get("head")).get("sha"))
        try:
            report["majorEscalation"] = escalate(
                repo,
                number,
                identity,
                major_escalation_body(eligibility.removeprefix(held), head),
                MAJOR_ESCALATION_MARKER,
                inputs,
            )
        except (RuntimeError, ValueError, json.JSONDecodeError) as exc:
            report["errors"].append(f"major escalation: {exc}")
    return report


def _whole_review_record(
    repo: str,
    policy: merge_policy.UnattendedPolicy,
    body: str,
    head: str,
    prior: dict[str, Any] | None,
) -> tuple[str, dict[str, Any] | None]:
    """The reasons comment body with every whole-review record line the
    prior comment holds, and the request: `{"toggle": True}` when this run
    records a new one. A lane pull request scored `wholeReviewWanted` whose
    comment is not escalated, with no record at this head and fewer than
    `MAX_TOGGLES` in all (record lines and the identity's conversions to
    draft on the timeline), is recorded when this sweep's limits allow it."""
    text = str((prior or {}).get("body") or "")
    lines = whole_review.record_lines(text)
    kept = whole_review.with_records(body, lines)
    if whole_review.recorded(text, head):
        return kept, None
    inputs = policy.inputs or {}
    pr = json_object(inputs.get("pr"))
    user = json_object(pr.get("user"))
    author = merge_policy.actor_key(
        {"__typename": user.get("type"), "login": user.get("login")}
    )
    if (
        (policy.details or {}).get("wholeReviewWanted") is not True
        or author != str(inputs.get("identity") or "").casefold()
        or text.endswith(RISK_ESCALATION_LINE)
    ):
        return kept, None
    if len(lines) >= whole_review.MAX_TOGGLES:
        return kept, {"toggled": False, "skipped": f"toggle-cap:{len(lines)}"}
    # The timeline, not the comment the lane token can edit, holds the count.
    toggled = whole_review.lane_toggles(
        str(pr.get("node_id") or ""), str(inputs.get("identity") or "")
    )
    if toggled is None:
        return kept, {"toggled": False, "skipped": "toggle-cap:unread"}
    if toggled >= whole_review.MAX_TOGGLES:
        return kept, {"toggled": False, "skipped": f"toggle-cap:{toggled}"}
    refusal = whole_review.limits(repo)
    if refusal is not None:
        return kept, {"toggled": False, "skipped": refusal}
    line = whole_review.record_line(head, _now())
    return whole_review.with_records(body, [*lines, line]), {"toggle": True}


def _identity_queue_entries(
    repo: str, branch: str, identity: str
) -> list[dict[str, Any]] | None:
    """The identity's merge-queue entries, earliest-enqueued first, or None
    when the queue cannot be read whole."""
    owner, name = repo.split("/", 1)
    try:
        data = gh_json(
            ["api", "graphql", "-f", f"query={UNATTENDED_QUEUE_QUERY}"]
            # `-f`: a raw string; `-F` would read `@path` and coerce
            # `true`, `null` or digits.
            + ["-f", f"o={owner}", "-f", f"r={name}", "-f", f"b={branch}"]
        )
    except (RuntimeError, json.JSONDecodeError):
        return None
    queue = json_object(
        json_object(json_object(json_object(data).get("data")).get("repository")).get(
            "mergeQueue"
        )
    )
    entries = json_object(queue.get("entries"))
    nodes = [json_object(n) for n in json_array(entries.get("nodes"))]
    if entries.get("totalCount") != len(nodes):
        return None
    mine = [
        n
        for n in nodes
        if merge_policy.actor_key(n.get("enqueuer")) == identity.casefold()
    ]
    return sorted(
        mine, key=lambda n: (str(n.get("enqueuedAt")), n.get("position") or 0)
    )


def _graphql_write(query: str, node_id: str) -> bool:
    proc = gh_capture(["api", "graphql", "-f", f"query={query}", "-f", f"id={node_id}"])
    return proc.returncode == 0


def update_error(proc: Any) -> dict[str, Any]:
    """The status and message of a refused `update-branch` call: whether the
    lane token may write a merge that brings in base workflow changes is
    learned from these."""
    message = ""
    try:
        body = json.loads(proc.stdout or "")
        if isinstance(body, dict) and isinstance(body.get("message"), str):
            message = body["message"]
    except ValueError:
        pass
    return {
        "status": gh_http_status(proc.stderr or ""),
        "message": (message or (proc.stderr or "").strip())[:500],
    }


def unattended_enqueue(
    repo: str,
    number: int,
    result: dict[str, Any],
    policy: merge_policy.UnattendedPolicy,
    pending_path: Path | None,
) -> int:
    """Enqueue a ready, permitted pull request its score does not hold at its pinned head (C4,
    D4, D22), returning the exit code.

    Only a merge-queue base; an armed auto-merge is disarmed and refused; the
    kill switch and the opt-in label are read again; the pin comment is
    posted before the enqueue and the enqueue goes nowhere without it; after
    the enqueue the queue is
    re-read and, when the identity entries enqueued earlier and the unverified
    lane merges already fill `merge.max-in-flight`, this one dequeues itself.
    In the pr-merge lane the kill switch "read again" is the value the
    workflow passed at the start of its run, so a flip during the run does not
    stop this enqueue."""
    inputs = policy.inputs or {}
    identity, branch = str(inputs["identity"]), str(inputs["branch"])
    pin = str(result.get("headRefOid") or "")
    step: dict[str, Any] = {"pin": pin}
    result["unattended"]["enqueue"] = step

    def hold(reason: str) -> int:
        result["ready"] = False
        result["blockers"].append(f"{UNATTENDED_REFUSED}{reason}")
        result["merge"] = result.get("merge") or {"attempted": False, "reason": reason}
        print(json.dumps(result, indent=2))
        return 10

    scored = str((inputs["pr"].get("head") or {}).get("sha") or "")
    if not merge_policy.SHA_RE.match(pin) or pin != scored:
        return hold("the head to enqueue is not the head the policy scored")
    if result.get("mergeAction") != "merge_queue":
        return hold("the base has no merge queue; unattended merges only enqueue")
    queue = read_merge_queue(repo, number)
    if queue["readError"]:
        return hold(f"merge queue unreadable ({queue['readError']})")
    if queue["autoMergeArmed"]:
        node_id = str(inputs["pr"].get("node_id") or "")
        step["disarmed"] = bool(node_id) and _graphql_write(DISARM_MUTATION, node_id)
        return hold("auto-merge is armed on this pull request; disarmed, not enqueued")
    if queue["inQueue"] or queue["merged"]:
        return hold("the pull request is already queued or merged")
    # A head the queue keeps ejecting for failed checks fails again on the
    # same commits; only a push (which resets the count) can change that.
    ejections = queue.get("failedEjections")
    step["failedEjections"] = ejections
    if ejections is None:
        return hold("the merge queue's removals of this head are unreadable")
    if ejections >= inputs["config"].max_queue_ejections:
        # One marked comment, so fix-ci or a person sees why the lane stopped.
        try:
            step["ejectionComment"] = upsert_marker_comment(
                repo,
                number,
                identity,
                queue_ejection_body(
                    pin, ejections, _failed_merge_group_runs(repo, branch, number)
                ),
                inputs.get("comments"),
                marker=QUEUE_EJECTION_MARKER,
            )
        except (RuntimeError, ValueError, json.JSONDecodeError) as exc:
            step["ejectionComment"] = f"error: {exc}"
        return hold(
            f"queue-ejected:{ejections} failed-check removals from the merge queue "
            f"at head {pin}; a push resets the count"
        )
    kill = merge_policy.kill_switch(
        repo,
        authority=str(inputs.get("authority")),
        lane_value=inputs.get("lane_kill_switch"),
    )
    step["killSwitch"] = {"proceed": kill.proceed, "reason": kill.reason}
    if not kill.proceed:
        try:
            step["dequeued"] = []
            postmerge.dequeue_identity_entries(
                repo, branch, identity, dequeued=step["dequeued"]
            )
        except (postmerge.PostMergeReadError, postmerge.PostMergeWriteError) as exc:
            step["dequeueError"] = str(exc)
        return hold(f"kill-switch:{kill.reason}")
    # The opt-in, like the kill switch, is read again here: for the local
    # lane a removal (or a removal and a non-human re-add) since the
    # eligibility read refuses; for the pr-merge lane a changed closing issue.
    eligible = inputs.get("eligibility")
    eligible_dependabot = getattr(eligible, "dependabot", None)
    if eligible_dependabot is not None:
        # The Dependabot class is read again whole: a human blocking comment
        # or a `ci-status` rerun since the first read refuses.
        opt_in = merge_policy.dependabot_eligibility(
            repo,
            number,
            pr=inputs["pr"],
            agent_identity=identity,
            hold_majors=inputs["config"].dependabot_majors == "hold",
        ).reason
    elif inputs.get("authority") == merge_policy.PR_MERGE:
        opt_in = merge_policy.recheck_lane_issue(
            repo, number, issue=getattr(eligible, "issue", None)
        )
    else:
        opt_in = merge_policy.recheck_opt_in(
            repo,
            number,
            agent_identity=identity,
            self_logins=inputs.get("self_logins") or frozenset(),
            permission=inputs.get("permission"),
        )
    step["optIn"] = opt_in
    if opt_in:
        return hold(f"ineligible:{opt_in}")
    # An enqueue never rests on a read shared within the run: a default
    # branch, its head's merge config or base rules the gate took from the
    # run cache are read again, and any change holds.
    if (cached_head := merge_policy.SHARED_HEAD_CONFIGS.get(repo)) is not None:
        try:
            _, head = merge_policy._default_branch_head(repo, branch)
            if head != cached_head:
                config = inputs["config"]
                main = merge_policy.read_config_at(repo, head)
                if main.error:
                    raise merge_policy.PolicyReadError(main.error)
                fresh = merge_policy.stricter_config(config, main)
                if replace(fresh, notes=()) != replace(config, notes=()):
                    return hold(
                        "the default branch's merge config changed since the "
                        "gate read it"
                    )
        except merge_policy.PolicyReadError as exc:
            return hold(f"the default branch's merge config is unreadable: {exc}")
    if repo in merge_policy.SHARED_DEFAULT_BRANCHES:
        try:
            default = merge_policy._default_branch(repo)
        except merge_policy.PolicyReadError:
            return hold(merge_policy.DEFAULT_BRANCH_UNREADABLE)
        if default != branch:
            return hold(f"base-not-default:{branch}")
    if any(
        branch_rules(repo, base, shared=False) != served
        for base, served in list(SHARED_RULES.items())
    ):
        return hold("the base branch's rules changed since the gate read them")
    # A head green on an old base can fail the queue's merge with the base
    # tip, and every entry built behind it fails too. When the base changed
    # what the checks read since the merge base, the branch is updated from
    # the base instead; a later run enqueues the new head once its checks
    # pass. A Dependabot head is not written (its own rebases stop), and a
    # doubtful read or an update the API refused (4xx) enqueues as before. An
    # update with no answer (a timeout, no status, a server error) may have
    # landed, so the old head is held rather than pinned.
    inputs_read = check_inputs.changed_since_merge_base(
        inputs["config"].check_inputs,
        pin,
        branch,
        extra=inputs["config"].head_check_inputs,
    )
    step["checkInputs"] = inputs_read
    # Updating merges the base's canonical but not the copies the pull request
    # generated from its own, so the drift check fails until they are
    # regenerated: refused, with the fix named, instead of updated.
    # No lane acts on the refusal, so it is escalated to a person.
    if sources := inputs_read.get("regenerate"):
        reason = (
            f"shared-copy-sources-changed:{','.join(sources)} "
            f"changed on {branch} since merge base {inputs_read['mergeBase']}; "
            f"merge {branch} and run scripts/sync-shared-copies.sh, then the new "
            "head is enqueued once its checks pass"
        )
        body = shared_copy_escalation_body(
            reason, sources, branch, str(inputs_read["mergeBase"]), pin
        )
        try:
            step["escalation"] = escalate(
                repo, number, identity, body, SHARED_COPY_ESCALATION_MARKER, inputs
            )
        except (RuntimeError, ValueError, json.JSONDecodeError) as exc:
            step["escalationError"] = str(exc)
        return hold(reason)
    # A standards-sync head is not written either: the sync App is its only
    # writer, and a merge commit fails its managed-files guard. An unreadable
    # label holds, since the stale head would fail the queue's merge.
    stale_update = inputs_read["state"] == "stale" and eligible_dependabot is None
    skip = None
    if stale_update:
        owner, name = repo.split("/", 1)
        try:
            skip = postmerge.standards_sync_skip(
                owner, name, inputs["pr"].get("labels")
            )
        except postmerge.PostMergeReadError as exc:
            return hold(f"the standards-sync role label is unreadable ({exc})")
    if skip:
        inputs_read.update(updated=False, updateSkipped=skip)
    elif stale_update:
        stale = (
            f"check-inputs-changed:{','.join(inputs_read['changed'])} changed on "
            f"{branch} since merge base {inputs_read['mergeBase']}"
        )
        try:
            proc = gh_capture(
                ["api", "-X", "PUT", f"repos/{repo}/pulls/{number}/update-branch"]
                + ["-f", f"expected_head_sha={pin}"]
            )
        except (RuntimeError, ValueError, OSError) as exc:
            proc = None
            inputs_read["updateError"] = {"status": None, "message": str(exc)[:500]}
        if proc is not None and proc.returncode == 0:
            inputs_read["updated"] = True
            return hold(
                f"{stale}; the branch was updated from the base, so the new head "
                "is enqueued once its checks pass"
            )
        if proc is not None:
            inputs_read["updateError"] = update_error(proc)
        status = inputs_read["updateError"]["status"]
        if status is None or not 400 <= status < 500:
            inputs_read["updated"] = None
            return hold(
                f"{stale}; the update from the base got no answer "
                f"({status or 'no status'}) and may have landed, so this head "
                "is not enqueued"
            )
        inputs_read["updated"] = False
    proc = gh_capture(
        ["api", "-X", "POST", f"repos/{repo}/issues/{number}/comments"]
        + ["-f", f"body={postmerge.pin_comment(pin)}"]
    )
    if proc.returncode != 0:
        return hold(f"the pin comment could not be posted ({proc.stderr.strip()})")
    step["pinned"] = True
    result["action"] = "enqueue"
    record = async_merge(repo, number, sha=pin, merge_action="merge_queue", method=None)
    result["merge"] = record
    result["enqueued"] = record["success"] and record["status"] == "enqueued"
    if pending_path is not None:
        _record_pending(pending_path, repo, number, record, pin, result)
    if not result["enqueued"]:
        print(json.dumps(result, indent=2))
        return 10
    entries = _identity_queue_entries(repo, branch, identity)
    numbers = [json_object(e.get("pullRequest")).get("number") for e in entries or []]
    step["identityEntries"] = numbers
    # Room for queued entries: `merge.max-in-flight`, read again uncached at
    # the default branch head, less the unverified lane merges the policy
    # counted. A failed read keeps the lower of the base's cap and the one
    # the assessment applied, so a cap lowered on main still holds.
    cap, source = merge_policy._run_max_in_flight(
        repo, branch, None, inputs["config"], shared=False
    )
    if source == "base":
        cap = min(cap, inputs.get("flight_cap", cap))
    room = cap - inputs["flight"].unverified
    if entries is None or number not in numbers[: max(room, 0)]:
        # Earlier entries (another host's) fill the room, or the order cannot
        # be read: this entry leaves so no more than `merge.max-in-flight`
        # unattended merges are in flight.
        mine = next(
            (
                e
                for e in entries or []
                if json_object(e.get("pullRequest")).get("number") == number
            ),
            None,
        )
        node_id = str(
            json_object((mine or {}).get("pullRequest")).get("id")
            or inputs["pr"].get("node_id")
            or ""
        )
        step["dequeuedSelf"] = bool(node_id) and _graphql_write(
            postmerge.DEQUEUE_MUTATION, node_id
        )
        why = (
            "the merge.max-in-flight cap is full"
            if entries is not None
            else "the queue could not be re-read whole"
        )
        if step["dequeuedSelf"]:
            result["enqueued"] = False
            return hold(f"{why}; this entry dequeued itself")
        return hold(
            f"{why}; this entry could not be dequeued and may still merge -- "
            "escalate to a human"
        )
    print(json.dumps(result, indent=2))
    return 0


def build_settle(logins: Iterable[str], minutes: str) -> ReviewSettleConfig | None:
    """The review-settle hold, or None when it would be inert.

    Inert means no reviewer logins, or a window that is not a finite number
    converting to at least one second.
    """
    reviewer_logins = normalize_login_set(logins)
    try:
        settle_minutes = float(minutes)
    except ValueError:
        settle_minutes = float("nan")
    # Round, then floor the RESULT at one second. Truncating a positive
    # sub-second window to zero would pass the greater-than-zero test and then
    # hold nothing, which is exactly the active-looking inert configuration the
    # paired-flag rule exists to make impossible.
    settle_seconds = (
        round(settle_minutes * 60)
        if settle_minutes > 0 and settle_minutes != float("inf")
        else 0
    )
    if not reviewer_logins or settle_seconds < 1:
        return None
    return ReviewSettleConfig(
        reviewer_logins=reviewer_logins,
        settle_seconds=settle_seconds,
    )


def main() -> int:
    # One candidate per gate process: its PR commits are read once per head.
    with candidate_reads():
        return _main()


def _main() -> int:
    configure_stdio()
    # This gate run's own record of what it took from the run cache.
    global SHARE_BASE_READS
    SHARED_RULES.clear()
    merge_policy.SHARED_DEFAULT_BRANCHES.clear()
    merge_policy.SHARED_HEAD_CONFIGS.clear()
    # allow_abbrev=False: the permission grants covering this gate state their
    # conditions as the literal presence or absence of a flag in the command
    # text -- above all "no --merge means check-only". Prefix abbreviation
    # (argparse's default) lets `--mer` resolve to --merge while the text
    # contains no such flag, so the written command and the resolved behavior
    # diverge -- exactly what those conditions must be able to rule out.
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument("pr", help="owner/repo#number or PR URL")
    parser.add_argument(
        "--allowed-owners",
        default=None,
        help="comma-separated owners the helper may act under (required; empty refuses)",
    )
    parser.add_argument(
        "--self-logins",
        default=None,
        help=(
            "comma-separated logins treated as self (exempt from the "
            "unprotected-base hold on the DEFAULT branch only); '@me' resolves "
            "to your gh login"
        ),
    )
    parser.add_argument(
        "--merge",
        action="store_true",
        help="merge iff the PR is 100%% ready; default is check-only",
    )
    parser.add_argument(
        "--expected-head",
        default=None,
        help=(
            "require the live head SHA to match this hex SHA (or a prefix of at "
            f"least {MIN_HEAD_SHA_PREFIX_LENGTH} chars) before merging"
        ),
    )
    parser.add_argument(
        "--auto",
        action="store_true",
        help=(
            "merge lane only, with --merge and --expected-head: when the PR is "
            "ready except for running checks and both AI review lanes have "
            "completed on the live head, arm GitHub auto-merge (squash) instead "
            "of holding"
        ),
    )
    parser.add_argument(
        "--method",
        choices=("auto", "squash", "merge", "rebase"),
        default=None,
        help=(
            "force a merge method (must be enabled); auto or unset uses the repo "
            "convention, then squash"
        ),
    )
    parser.add_argument(
        "--allow-dependency",
        action="store_true",
        help="permit merging a dependency-manager-authored PR (held by default)",
    )
    parser.add_argument(
        "--extra-dependency-manager-logins",
        default=None,
        help=(
            "comma-separated extra dependency-manager bot logins beyond the "
            "built-in dependabot/renovate set; their PRs are held absent "
            "--allow-dependency, same as the built-ins"
        ),
    )
    parser.add_argument(
        "--allow-unprotected",
        action="store_true",
        help=(
            "permit merging on an unprotected base (held by default): a non-self "
            "PR anywhere, or a self PR onto a non-default base"
        ),
    )
    parser.add_argument(
        "--stacked-prs",
        action="store_true",
        help=(
            "treat a native stack layer as mergeable: judge it against the stack's "
            "trunk and run the full gate over every open layer below it, which the "
            "async merge lands with it. Unset, a stack layer is held as before"
        ),
    )
    parser.add_argument(
        "--state-dir",
        default=None,
        help=(
            "babysit state directory; records an async merge request left pending "
            "so every later run reports it as merge pending until GitHub finishes it"
        ),
    )
    parser.add_argument(
        "--allow-unpinned-head",
        action="store_true",
        help=(
            "permit --merge without --expected-head (interactive only); the merge "
            "still pins the head this run evaluates, but nothing ties that head "
            "to one you vetted"
        ),
    )
    parser.add_argument(
        "--review-bot-logins",
        default=None,
        help=(
            "comma-separated review-bot logins whose review of the LIVE head the "
            "gate waits for; requires --review-settle-minutes. Unset on both "
            "leaves the hold dormant and the gate exactly its prior self"
        ),
    )
    parser.add_argument(
        "--review-settle-minutes",
        default=None,
        help=(
            "how long after the head appears a --review-bot-logins re-review may "
            "still be in flight; the gate holds for that window when no review of "
            "the live head exists yet, then stops waiting. Requires "
            "--review-bot-logins"
        ),
    )
    parser.add_argument(
        "--autopilot-merge-tier",
        action="store_true",
        help=(
            "gate on the #476 autopilot-merge-tier criteria in addition to the "
            "base readiness gate: issue-linked, lane-authored, no blocking label, "
            "a distinct-bot approving review on the live head, and no human "
            "blocking comment. Fail-closed: requires --lane-logins, "
            "--approver-bot-logins, and --block-labels to be non-empty"
        ),
    )
    parser.add_argument(
        "--lane-logins",
        default=None,
        help="comma-separated pipeline lane author logins (autopilot merge tier)",
    )
    parser.add_argument(
        "--approver-bot-logins",
        default=None,
        help=(
            "comma-separated bot logins whose approving review satisfies the "
            "author != approver criterion (autopilot merge tier)"
        ),
    )
    parser.add_argument(
        "--block-labels",
        default=None,
        help=(
            "comma-separated labels that veto a tier merge, e.g. do-not-merge "
            "(autopilot merge tier)"
        ),
    )
    parser.add_argument(
        "--unattended",
        action="store_true",
        help=(
            "gate under the unattended merge policy (babysit_merge_policy): "
            "check-only reports the decision; with --merge an eligible, promoted "
            "pull request its risk score does not hold is enqueued at the pinned head under the "
            "configured merge.agent-identity. Refuses --allow-dependency, "
            "--auto, --allow-unpinned-head, --stacked-prs and --allow-unprotected"
        ),
    )
    parser.add_argument(
        "--authority",
        choices=(merge_policy.LOCAL_BABYSIT, merge_policy.PR_MERGE),
        default=None,
        help=(
            "with --unattended, the merge authority this run is (default "
            "local-babysit); merge.authority at the base and at the default "
            "branch head must name it. "
            "pr-merge is the CI lane: a CI-labeled C2 pull request off the "
            "denied paths, or a mergeable Dependabot pull request on a green "
            "ci-status, no promotion read, and nothing written while "
            "merge.report-only (merge.dependabot.mode short of enforce, for "
            "Dependabot) holds"
        ),
    )
    parser.add_argument(
        "--lane-kill-switch",
        default=None,
        help=(
            "with --authority pr-merge, the result of the workflow's own "
            "kill-switch check (the lane token cannot read Actions variables): "
            "only the exact value 'proceed' proceeds; missing or any other "
            "value stops the lane"
        ),
    )
    parser.add_argument(
        "--lane-rung-cap",
        default=None,
        help=(
            "with --authority pr-merge, the CLAUDE_LANES_MERGE_RUNG_CAP value the "
            "workflow read: empty is no cap, a rung name caps the rung; missing "
            "or any other value holds the rung at off"
        ),
    )
    parser.add_argument(
        "--postmerge-result",
        default=None,
        help=(
            "with --authority pr-merge, this run's babysit_postmerge.py report: "
            "its demotion, floor and post-merge verdict stand in for this pull "
            "request's own reads when its base has the same floor and no merge "
            "the check would judge landed since; unreadable or unbound, they "
            "are read as without it"
        ),
    )
    parser.add_argument(
        "--candidate-deadline-seconds",
        type=float,
        default=None,
        help=(
            "with --authority pr-merge, how long this pull request's gate may "
            "read: a read phase (the policy, then the verdict) starts no command "
            "past it and the gate reports the pull request unknown (exit 11) for "
            "a later run; a write is never stopped"
        ),
    )
    args = parser.parse_args()
    SHARE_BASE_READS = bool(args.unattended)
    deadline = deadline_after(args.candidate_deadline_seconds)

    def _refuse(message: str, code: int, **envelope: object) -> int:
        """Emit one refusal envelope on stdout and return its exit code.

        `envelope` carries the extra fields a caller branches on before the
        error text (`inScope`), so the key order every consumer already reads
        is fixed here rather than restated per refusal.
        """
        print(json.dumps({"pr": args.pr, **envelope, "error": message}))
        return code

    allowed = parse_allowed_owners(args.allowed_owners)
    if not allowed:
        return _refuse(
            "--allowed-owners is required and must be non-empty; "
            "refusing to act without an owner allowlist",
            3,
            inScope=False,
        )

    try:
        repo, number = parse_repo_number(args.pr)
    except ValueError as exc:
        # The one refusal that predates a usable `pr` value: `args.pr` is the
        # string that failed to parse, so it is reported inside the message
        # rather than echoed as a `pr` field naming a PR nobody can resolve.
        print(json.dumps({"error": str(exc)}))
        return 2

    if args.expected_head and not EXPECTED_HEAD_RE.match(args.expected_head):
        return _refuse(
            "--expected-head must be a hex SHA prefix of at least "
            f"{MIN_HEAD_SHA_PREFIX_LENGTH} characters (a shorter prefix "
            "is ambiguous and could match an unvetted push)",
            2,
        )

    owner = split_owner(repo)
    if owner not in allowed:
        return _refuse(
            f"owner {owner!r} out of scope; allowed: {sorted(allowed)}",
            3,
            inScope=False,
        )

    # The review-settle hold is paired configuration, resolved before any network
    # access. Both flags or neither: a reviewer set with no window would need this
    # gate to invent how long that reviewer takes, and a window with no reviewer
    # set has nothing to wait for. Either alone is a usage error rather than a
    # silently-inert flag, so a half-configured hold can never read as an active one.
    # The pair is `userConfig`-only, so a half-set or invalid flag is a usage
    # error whatever the target repository declares.
    if args.review_bot_logins is not None or args.review_settle_minutes is not None:
        missing = [
            name
            for name, value in (
                ("--review-bot-logins", args.review_bot_logins),
                ("--review-settle-minutes", args.review_settle_minutes),
            )
            if value is None
        ]
        if missing:
            return _refuse(
                "the review-settle hold requires both "
                "--review-bot-logins and --review-settle-minutes; "
                "missing " + ", ".join(missing),
                2,
            )
        if (
            build_settle(
                parse_csv_set(args.review_bot_logins), args.review_settle_minutes
            )
            is None
        ):
            return _refuse(
                "--review-bot-logins must be non-empty and "
                "--review-settle-minutes must be a finite number "
                "that converts to at least one second; refusing to "
                "run the hold under-specified",
                2,
            )

    # Build the autopilot-merge-tier config before any network access, failing
    # closed on a partial configuration: the tier's whole point is that its sets are
    # all supplied deliberately, so an umbrella flag with any of them empty is a
    # refusal, never a merge on an under-specified tier. The block labels are the
    # exception: the target repository may declare them, so their non-empty check
    # runs once the repository's policy is read.
    tier: AutopilotMergeTierConfig | None = None
    if args.autopilot_merge_tier:
        lane = parse_csv_set(args.lane_logins)
        approver = parse_csv_set(args.approver_bot_logins)
        missing = [
            name
            for name, value in (
                ("--lane-logins", lane),
                ("--approver-bot-logins", approver),
            )
            if not value
        ]
        if missing:
            return _refuse(
                "--autopilot-merge-tier requires non-empty "
                + ", ".join(missing)
                + "; refusing to run the tier under-specified",
                3,
            )
        tier = AutopilotMergeTierConfig(
            lane_logins=frozenset(lane),
            approver_bot_logins=frozenset(approver),
            block_labels=frozenset(parse_csv_set(args.block_labels)),
        )
    elif any((args.lane_logins, args.approver_bot_logins, args.block_labels)):
        return _refuse(
            "--lane-logins / --approver-bot-logins / --block-labels "
            "are only meaningful with --autopilot-merge-tier",
            2,
        )

    if args.auto and not (args.merge and args.expected_head):
        return _refuse("--auto requires --merge and --expected-head", 2)
    if args.authority is not None and not args.unattended:
        return _refuse("--authority is only meaningful with --unattended", 2)
    if args.authority != merge_policy.PR_MERGE and (
        args.lane_kill_switch is not None
        or args.lane_rung_cap is not None
        or args.postmerge_result is not None
        or args.candidate_deadline_seconds is not None
    ):
        return _refuse(
            "--lane-kill-switch, --lane-rung-cap, --postmerge-result and "
            "--candidate-deadline-seconds are only meaningful with --authority pr-merge",
            2,
        )
    if args.candidate_deadline_seconds is not None and not (
        0 < args.candidate_deadline_seconds < float("inf")
    ):
        return _refuse("--candidate-deadline-seconds must be a positive number", 2)

    def _deadline_stop() -> int:
        return _refuse(
            "unknown:candidate-deadline; the gate passed its "
            f"{args.candidate_deadline_seconds:g}-second limit for one pull request "
            "before its next read and stopped there, with no write cut short; "
            "a later run gates it again",
            11,
        )

    pending_path: Path | None = None
    if args.state_dir is not None:
        try:
            pending_path = resolve_state_dir(args.state_dir) / PENDING_MERGES_FILE
        except ValueError as exc:
            return _refuse(str(exc), 2)

    # An unattended merge never takes a dependency-manager PR, arms auto-merge,
    # merges an unvetted head or lands a stack's lower layers, so the flags that
    # would widen it are usage errors, not ignored options.
    if args.unattended:
        widening = [
            flag
            for flag, given in (
                ("--allow-dependency", args.allow_dependency),
                ("--auto", args.auto),
                ("--allow-unpinned-head", args.allow_unpinned_head),
                ("--stacked-prs", args.stacked_prs),
                ("--allow-unprotected", args.allow_unprotected),
            )
            if given
        ]
        if widening:
            return _refuse(
                "--unattended refuses "
                + ", ".join(widening)
                + ": an unattended merge never merges a dependency-manager PR "
                "outside the pr-merge lane's Dependabot class, arms auto-merge, merges an unpinned head, lands a stack or "
                "merges onto an unprotected base",
                2,
            )
        if args.merge and not args.expected_head:
            return _refuse("--unattended --merge requires --expected-head", 2)

    # Any policy failure refuses: this decides who may merge, and an
    # unreadable answer is not a permissive one.
    unattended: merge_policy.UnattendedPolicy | None = None
    report_only = False
    if args.unattended:
        # Only lane or bot self logins reach the policy's human test: the
        # operator's own login there would make the operator non-human.
        bot_selves = frozenset(
            token.strip()
            for token in (args.self_logins or "").split(",")
            if token.strip().casefold().endswith("[bot]")
        )
        shared = (
            postmerge.read_shared(args.postmerge_result)
            if args.postmerge_result is not None
            else None
        )
        try:
            with read_deadline(deadline):
                unattended = assess_unattended(
                    repo,
                    number,
                    self_logins=bot_selves,
                    authority=args.authority or merge_policy.LOCAL_BABYSIT,
                    lane_kill_switch=args.lane_kill_switch,
                    lane_rung_cap=args.lane_rung_cap,
                    shared=shared,
                    # Each recompute goes back to the file for the next candidate.
                    share=(
                        None
                        if args.postmerge_result is None
                        else functools.partial(
                            postmerge.write_shared, args.postmerge_result
                        )
                    ),
                )
        except (RuntimeError, ValueError, OSError) as exc:
            return _refuse(f"unattended merge policy unreadable: {exc}", 10)
        except DeadlineReached:
            return _deadline_stop()
        if args.postmerge_result is not None and shared is None:
            unattended = replace(
                unattended,
                details={
                    **(unattended.details or {}),
                    "postMergeShared": "unused:unreadable",
                },
            )
        # Report-only: the decision is reported and nothing is written, so
        # `--merge` runs as a check.
        report_only = bool((unattended.details or {}).get("reportOnly"))
        if report_only:
            args.merge = False
        if args.merge:
            writes = unattended_writes(repo, number, unattended)
            unattended = replace(
                unattended, details={**(unattended.details or {}), "writes": writes}
            )
    elif args.merge:
        # Resolved for the plain path so it can refuse the agent identity's token.
        try:
            unattended = merge_policy.resolve(repo, number)
        except (RuntimeError, ValueError, OSError) as exc:
            return _refuse(f"unattended merge policy unreadable: {exc}", 10)
    # The agent identity merges only through `--unattended`; its token on the
    # plain path would bypass every unattended check.
    identity = unattended.agent_identity if unattended is not None else None
    if args.merge and not args.unattended and identity:
        try:
            acting = (resolve_author("@me") or "").strip()
        except (RuntimeError, ValueError, OSError) as exc:
            return _refuse(
                f"the token's acting login could not be read ({exc}) while "
                f"merge.agent-identity is {identity!r}; refusing a plain --merge",
                10,
                actingLogin=None,
                agentIdentity=identity,
            )
        # Each identity the base or the default branch head sets: a rotation
        # leaves both able to bypass the unattended checks until it lands.
        named = [
            str(i)
            for i in (unattended.details or {}).get("agentIdentities") or [identity]
        ]
        matched = next(
            (i for i in named if acting.casefold() == i.strip().casefold()), None
        )
        if not acting or matched:
            identity = matched or identity
            return _refuse(
                f"the token acts as {acting or 'an unknown login'!r}, the configured "
                f"merge.agent-identity {identity!r}; it merges only through "
                "--unattended, never plain --merge",
                10,
                actingLogin=acting or None,
                agentIdentity=identity,
            )

    # The target repository's policy, read from its default branch with the flags
    # as the deprecated `userConfig` fallback. Unreadable policy refuses the
    # check as well as the merge: a verdict computed without the repository's
    # holds would read as ready when it may not be.
    try:
        policy = repo_policy.resolve(repo, repo_policy.fallback_from_args(args))
    except repo_policy.RepoConfigError as exc:
        return _refuse(
            f"repository policy unreadable: {exc}; refusing to run the gate without it",
            2,
        )
    if args.auto and policy.merge_method not in (None, "squash"):
        return _refuse(
            "--auto arms a squash merge; the effective merge method must be "
            f"squash, not {policy.merge_method!r}",
            2,
        )
    settle: ReviewSettleConfig | None = None
    if policy.review_bot_logins is not None or policy.review_settle_minutes is not None:
        settle = build_settle(
            policy.review_bot_logins or (), policy.review_settle_minutes or ""
        )
        if settle is None:
            return _refuse(
                "the effective review-settle pair is under-specified; refusing "
                "to run the hold without it",
                2,
            )
    if tier is not None:
        # Add-only: the effective labels are the flag set plus the repository's, and
        # an empty union is an under-specified tier.
        if not policy.merge_block_labels:
            return _refuse(
                "--autopilot-merge-tier requires non-empty block labels, from "
                "--block-labels or the repository's babysit_merge_block_labels; "
                "refusing to run the tier under-specified",
                3,
            )
        tier = replace(tier, block_labels=policy.merge_block_labels)

    # Resolve self logins only after every argument-shape refusal above: '@me'
    # resolution is a network call, and the guard's contract is that malformed
    # input is rejected before any network access.
    try:
        self_logins = normalize_self_logins(resolve_authors(args.self_logins))
    except RuntimeError:
        # '@me' could not be resolved to a gh login; fail closed by keeping only
        # the explicit non-'@me' logins -- an unresolved self identity holds own
        # PRs on an unprotected base rather than merging on a guessed identity.
        self_logins = normalize_self_logins(
            token
            for token in (args.self_logins or "").split(",")
            if token.strip().casefold() != "@me"
        )

    extra_dependency_manager_logins = policy.extra_dependency_manager_logins

    prior: dict[str, Any] | None = None
    if pending_path is not None:
        try:
            prior = check_pending_request(
                repo, number, pending_path, write=not report_only
            )
        except (RuntimeError, OSError) as exc:
            return _refuse(f"pending merge record unreadable: {exc}", 2)

    # The pr-merge lane's mergeable Dependabot pull request is the one
    # dependency-manager PR an unattended run may merge.
    lane_dependabot = getattr(
        ((unattended.inputs or {}) if unattended else {}).get("eligibility"),
        "dependabot",
        None,
    )
    try:
        with read_deadline(deadline):
            result = evaluate(
                repo,
                number,
                args.expected_head,
                allowed,
                self_logins,
                args.allow_dependency
                or (
                    args.unattended
                    and lane_dependabot is not None
                    and lane_dependabot.mergeable
                ),
                args.allow_unprotected,
                tier,
                extra_dependency_manager_logins=extra_dependency_manager_logins,
                settle=settle,
                stacked=args.stacked_prs,
                unattended=unattended if args.unattended else None,
            )
    except (RuntimeError, ValueError, json.JSONDecodeError) as exc:
        # Surface any gh/parse failure as JSON rather than a traceback.
        print(json.dumps({"pr": args.pr, "error": f"{type(exc).__name__}: {exc}"}))
        return 2
    except DeadlineReached:
        return _deadline_stop()

    result["action"] = "merge" if args.merge else "check"
    result["merged"] = False
    result["merge"] = None

    if prior is not None:
        result["pendingMergeRequest"] = prior
        verified = json_object(prior.get("verification")).get("verified", True)
        hold = reason = None
        if prior.get("queued"):
            hold, reason = queued_entry_hold(prior, verified)
            if prior.get("status") in ("queued", "armed", "unconfirmed"):
                result["enqueued"] = prior.get("status") == "queued"
                result["mergeQueue"] = prior.get("mergeQueue")
            elif prior.get("status") == "dequeued":
                result["dequeued"] = True
        elif prior.get("corrupt"):
            hold = (
                f"the recorded async merge request for this PR is corrupt "
                f"({prior.get('message')}) -- merge pending until a human "
                "inspects the record; no new request is sent"
            )
        elif prior.get("status") in (None, "pending"):
            # Live (or unreadable) on GitHub: it can still merge whatever this run
            # found, so no verdict here may read as settled and no new request goes.
            hold = (
                f"an async merge request ({prior.get('uuid')}) sent at "
                f"{prior.get('requestedAt')} is still pending on GitHub and can "
                "still merge regardless of this verdict -- merge pending; no new "
                "request is sent"
            )
        elif verified is not True:
            reason = hold = (
                f"the async merge request ({prior.get('uuid')}) merged, but "
                + (
                    "the heads it landed could not be read back -- unconfirmed; "
                    "the record is kept and re-checked next run"
                    if verified is None
                    else "a head it landed is not the head the gate evaluated -- "
                    "escalate to a human"
                )
            )
        if hold:
            if reason is None:
                result["action"] = "merge-pending"
            result["ready"] = False
            result["blockers"].insert(0, hold)
            result["autoMerge"] = {"ready": False, "blockers": [hold]}
            result["merge"] = {"attempted": False, "reason": reason or "merge pending"}
            print(json.dumps(result, indent=2))
            return 10
        if prior.get("status") == "merged":
            # The recorded request landed at every evaluated head. The gate now
            # reads a merged (closed) PR, but that merge is this run's outcome.
            # A refusing unattended check still reports the merge, and stays
            # not ready on its refusal.
            refused = (
                [b for b in result["blockers"] if b.startswith(UNATTENDED_REFUSED)]
                if args.unattended
                else []
            )
            result["merged"] = True
            result["ready"] = not refused
            result["blockers"] = refused
            result["merge"] = {
                **prior,
                "attempted": False,
                "source": "pendingMergeRequest",
            }
            # The read-back held: the head that landed is the pinned one. The
            # full run the post-merge check verifies this merge with is
            # dispatched now, under the identity, while no identity,
            # credential, kill-switch or post-merge refusal stands.
            inputs = (unattended.inputs or {}) if unattended is not None else {}
            if (
                args.unattended
                and args.merge
                and unattended is not None
                and unattended.enabled
                and inputs.get("identity")
            ):
                try:
                    postmerge.dispatch_full_run(repo, ref=str(inputs["branch"]))
                    result["unattended"]["dispatched"] = True
                except postmerge.PostMergeWriteError as exc:
                    result["unattended"]["dispatched"] = False
                    result["unattended"]["dispatchError"] = str(exc)
            print(json.dumps(result, indent=2))
            return 10 if refused else 0

    if not args.merge:
        print(json.dumps(result, indent=2))
        return 0 if result["ready"] else 10

    # TOCTOU guard: never merge whatever head happens to be live at run time. The
    # worker/autopilot flow must pass the SHA it vetted; unpinned merges are an
    # explicit interactive override only.
    if not args.expected_head and not args.allow_unpinned_head:
        reason = (
            "--merge requires --expected-head to pin the vetted head SHA "
            "(a newer push could be CLEAN yet unvetted); pass "
            "--allow-unpinned-head to override interactively"
        )
        result["ready"] = False
        result["blockers"].append(reason)
        result["merge"] = {"attempted": False, "reason": reason}
        print(json.dumps(result, indent=2))
        return 10

    # Under --auto the AI-review holds bind a synchronous merge too.
    go = result["autoMerge"]["ready"] if args.auto else result["ready"]
    arm_auto = go and args.auto and not result["ready"]
    if not go:
        result["merge"] = {"attempted": False, "reason": "not ready"}
        # Under --unattended a re-run is a write: only a session that passed
        # the identity and credential chokepoint makes it.
        if not args.unattended or (
            unattended is not None and (unattended.inputs or {}).get("identity")
        ):
            result["aiReviewReruns"] = rerun_rate_limited_reviews(repo, result)
        print(json.dumps(result, indent=2))
        return 10
    if arm_auto:
        # Consumers treat `action: merge` as a performed merge; an arm is not one.
        result["action"] = "auto-merge"
    if args.unattended and unattended is not None:
        # Ready means every required check is green and the policy refused
        # nothing: its score does not hold it, and it is eligible, promoted and alone.
        return unattended_enqueue(repo, number, result, unattended, pending_path)

    try:
        method = allowed_method(repo, "squash" if arm_auto else policy.merge_method)
    except (RuntimeError, json.JSONDecodeError) as exc:
        # A method-lookup failure is reported, not raised, so output stays JSON.
        result["error"] = f"{type(exc).__name__}: {exc}"
        print(json.dumps(result, indent=2))
        return 2

    result["mergeMethod"] = method
    # Atomic head pin: GitHub refuses the merge unless the head still equals the
    # exact full SHA the gate just evaluated, closing the preflight-to-merge
    # TOCTOU window. `--allow-unpinned-head` waives only the `--expected-head`
    # argument, never this pin.
    pin = result.get("headRefOid")
    if not isinstance(pin, str) or not pin:
        reason = "the gate read no head SHA to pin the merge to -- held"
        result["ready"] = False
        result["blockers"].append(reason)
        result["merge"] = {"attempted": False, "reason": reason}
        print(json.dumps(result, indent=2))
        return 10

    # A ready PR merges through the async merge API: REST (so it works where
    # GraphQL is refused) and GitHub's required API for merging any stacked PR,
    # the bottom layer included. It is used on the default branch and for a
    # stack member; a queue base is enqueued through GraphQL instead
    # (`enqueue_pull_request`). Any other base keeps `gh pr merge`. Auto-merge
    # has no async form and keeps `gh pr merge`.
    if not arm_auto:
        stack = json_object(result.get("stack"))
        stack_lands = bool(stack.get("landsLowerLayers"))
        stack_member = bool(stack.get("member"))
        queue = result.get("mergeAction") == "merge_queue"
        use_async = stack_member or stack_lands or queue
        if not use_async:
            default_branch = repository_default_branch(repo)
            use_async = bool(default_branch) and result.get("baseRef") == default_branch
        if use_async:
            if queue:
                result["action"] = "enqueue"
            if stack_lands and (drift := stack_drift(repo, number, result)):
                result["ready"] = False
                result["blockers"].append(drift)
                result["merge"] = {"attempted": False, "reason": drift}
                print(json.dumps(result, indent=2))
                return 10
            record = async_merge(
                repo,
                number,
                sha=pin,
                merge_action="merge_queue" if queue else "direct_merge",
                method=method,
            )
            if not record["endpointMissing"] or stack_member or stack_lands or queue:
                if record["endpointMissing"]:
                    record["message"] = (
                        "the async merge endpoint returned 404 on this host; a queue "
                        "or stack merge has no other API -- held"
                    )
                result["merge"] = record
                # A merge read back at another head is still a merge, reported
                # with exit 10 for a human, like a stack layer landing elsewhere.
                result["merged"] = (
                    record["status"] == "merged"
                    and record.get("verifiedMerged") is True
                )
                result["enqueued"] = (
                    record["success"] and record["status"] == "enqueued"
                )
                result["mergeUnconfirmed"] = (
                    record["status"] == "merged"
                    and record.get("verifiedMerged") is None
                )
                exit_code = 0 if record["success"] else 10
                if result["merged"] and stack_lands:
                    verification = verify_stack_landed(repo, result)
                    result["stackVerification"] = verification
                    if verification["verified"] is not True:
                        verification["message"] = verification.get("message") or (
                            "a lower stack layer did not land at the head the gate "
                            "evaluated -- escalate to a human"
                        )
                        exit_code = 10
                if pending_path is not None:
                    _record_pending(pending_path, repo, number, record, pin, result)
                print(json.dumps(result, indent=2))
                return exit_code
            result["asyncFallback"] = (
                "the async merge endpoint returned 404 on this host; merged with "
                "gh pr merge instead"
            )

    merge_cmd = ["pr", "merge", str(number), "-R", repo, f"--{method}"]
    if arm_auto:
        merge_cmd.append("--auto")
    merge_cmd += ["--match-head-commit", pin]
    proc = gh_capture(merge_cmd)
    result["merge"] = {
        "attempted": True,
        "auto": arm_auto,
        "success": proc.returncode == 0,
        "stdout": proc.stdout.strip(),
        "stderr": proc.stderr.strip(),
    }
    result["merged"] = proc.returncode == 0 and not arm_auto
    result["autoMergeEnabled"] = proc.returncode == 0 and arm_auto
    exit_code = 0 if proc.returncode == 0 else 10
    if proc.returncode == 0:
        queue = read_merge_queue(repo, number)
        exit_code = report_queue_routing(result, queue)
        unconfirmed = bool(json_object(result.get("mergeQueue")).get("unconfirmed"))
        if pending_path is not None and (result.get("enqueued") or unconfirmed):
            _write_pending(
                pending_path,
                f"{repo}#{number}",
                _queued_entry(pin, unconfirmed=unconfirmed),
                result,
            )
        elif unconfirmed:
            result["merge"]["message"] += (
                "; without --state-dir nothing is recorded, so a later run cannot "
                "confirm it"
            )
    print(json.dumps(result, indent=2))
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
