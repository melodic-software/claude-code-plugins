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
- Merges use the repository's allowed method (squash preferred) and NEVER pass
  `--admin` or `bypass_rules`. This helper cannot bypass branch protection,
  resolve or reply to review threads, force-push, or change settings.
- A ready PR on the default branch merges through the async merge API with the
  vetted head as `sha`, polled to a terminal status; on a base that requires a
  merge queue it is enqueued instead (`enqueued` is queued, not merged). A host
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
  queue (`dequeued`).
- With `--stacked-prs`, a native stack layer is judged against the stack's
  trunk and every open layer below it runs the same gate, since the async
  merge lands them together. Without it a stack layer is held as before.
- A PR authored by a dependency manager (Dependabot/Renovate-class) is held --
  never merged -- unless `--allow-dependency` is passed.
- A PR on an unprotected base (zero required reviews AND zero required contexts)
  is held unless `--allow-unprotected` is passed: on such a base `CLEAN` proves
  nothing. A configured self login is exempt only when that base is the
  repository's default branch -- the solo-owner repo the exemption exists for.
  A self-authored PR onto an unprotected NON-default base (a stack layer, or any
  feature-onto-feature merge) is held: the default branch's required checks never
  governed it. `--stacked-prs` replaces that hold for a native stack layer only.
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

Readiness is gated on GitHub's own `mergeStateStatus == CLEAN` (which integrates
required checks, up-to-date, approvals, and conversation resolution) plus
explicit cross-checks so the *reason* for a block is always reported: the
effective branch rules (`rules/branches`), the review decision, unresolved
review threads, and the status-check rollup.

Exit codes: 0 ready (or merged, enqueued, or auto-merge armed), 10 not ready
(blockers, or a merge request that failed or is still pending), 2 usage/runtime
error, 3 owner out of scope (or no allowlist). Output is a single JSON object
on stdout.
"""

from __future__ import annotations

import argparse
import json
import re
import time
from collections.abc import Callable, Iterable
from dataclasses import dataclass, replace
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, cast
from urllib.parse import quote

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
from babysit_gh import (
    GraphQLUnavailableError,
    fetch_issue_comments,
    fetch_pull_request_commits,
    fetch_pull_request_review_comments,
    fetch_pull_request_reviews,
    fetch_review_threads,
    gh_capture,
    gh_http_status,
    gh_json,
    normalized_rest_author,
    parse_repo_number,
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
    configure_stdio,
    is_json_array,
    is_json_object,
    json_array,
    json_object,
    parse_allowed_owners,
    parse_csv_set,
    split_owner,
)

# A plain human "do not merge" veto that is neither a formal CHANGES_REQUESTED
# review nor the configured label: the shared blocking-text predicate does not
# carry a do-not-merge pattern, so the tier's "no human blocking comment"
# criterion matches it here. Bounded to the merge-veto sense (do/don't/do-not
# merge) so ordinary prose does not false-block.
HUMAN_MERGE_VETO_RE = re.compile(r"\bdo(?:n['’]?t| not|-not)[\s-]*merge\b", re.I)

# The PR author's own hold, written in the body ("Do not merge this draft"):
# the label is not the only way a PR says it must not merge. The hyphenated
# form is the label's name and is not matched, so a body that merely names the
# label does not block.
BODY_MERGE_HOLD_RE = re.compile(r"\bdo(?:n['’]?t| not)\s+merge\b", re.I)
# The label form of the same hold: blocks in every tier, whether or not the
# autopilot merge tier is engaged. `--block-labels` only adds to it.
MERGE_HOLD_LABEL = "do-not-merge"

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
# name: the security lane is one job named `security-review`, a name generic
# enough that another workflow's job could carry it, so it counts only as
# `security-review / security-review`. A pin that predates that fold reports
# `claude-security-review-status` beside it. Every matching check must succeed.
AI_REVIEW_CHECKS = {
    "claude-review-status": ("claude-review-status",),
    "claude-security-review-status": (
        "claude-security-review-status",
        "security-review / security-review",
    ),
}


def is_ai_review_check(check_name: str, names: tuple[str, ...]) -> bool:
    full = " / ".join(part.strip() for part in check_name.split("/"))
    segment = full.rsplit(" / ", 1)[-1]
    return any(full == n if " / " in n else segment == n for n in names)

# The async merge API (`PUT .../pulls/{n}/merge-async`) answers with a request
# UUID and runs the merge in the background; the gate polls it to a terminal
# status for at most this long. A request still pending past the bound is left
# to GitHub: the next run's PUT returns 409 with the same UUID and polls again.
ASYNC_MERGE_POLL_TIMEOUT_SECONDS = 60.0
ASYNC_MERGE_POLL_INTERVAL_SECONDS = 3.0
ASYNC_TERMINAL_STATUSES = frozenset({"merged", "enqueued", "failed"})
ASYNC_UUID_RE = re.compile(r"[0-9A-Za-z-]{1,64}")


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
    try:
        data = gh_json(["api", f"repos/{repo}", "--jq", "{name: .default_branch}"])
    except (RuntimeError, json.JSONDecodeError):
        return None
    if not is_json_object(data):
        return None
    name = data.get("name")
    return str(name) if name else None


def branch_rules(repo: str, branch: str) -> dict[str, object]:
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
    }
    try:
        # `{branch}` is one path parameter. Percent-encode it, including `/`,
        # so a base such as release/1.x stays a single segment. quote(..., safe="")
        # matches Go's url.PathEscape, which go-github uses for this endpoint
        # (github.com/google/go-github repos_rules.go, ListRulesForBranch).
        # gh 2.99.0 forwards that path unchanged.
        rules = gh_json(["api", f"repos/{repo}/rules/branches/{quote(branch, safe='')}"])
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
            required_contexts.update(
                str(c["context"])
                for c in params.get("required_status_checks", [])
                if is_json_object(c) and c.get("context")
            )
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
    repo: str, number: int
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
        commits = fetch_pull_request_commits(repo, number)
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

    # A human "do not merge"/blocking comment that is not a formal
    # CHANGES_REQUESTED and not an unresolved inline thread (both already gated
    # above) still halts the tier. Reuse the shared blocking-text/severity
    # predicates over every human-authored issue comment and review summary.
    human_blocking: list[str] = []
    corpus: list[dict[str, Any]] = list(fetch_issue_comments(repo, number))
    corpus.extend(reviews)
    # Inline review-thread comments are neither issue comments nor review
    # summaries; a human veto left inline whose thread is later resolved would
    # otherwise escape both the base unresolved-thread gate and this scan.
    if review_comments is None:
        review_comments = fetch_pull_request_review_comments(repo, number)
    corpus.extend(
        {"author": normalized_rest_author(row), "body": row.get("body")}
        for row in review_comments
    )
    # A configured approver/lane account GitHub misreports as a `User` classifies
    # as a bot here, so its clean review body ("no blocking issues") does not
    # self-block the very approval `find_distinct_bot_approval` accepted -- the
    # "a bot's blocking-looking prose is not a human stop" rule extends to
    # configured bots that lack a `[bot]` suffix.
    for item in corpus:
        if actor_kind(item, tier.automation_actor_config) != "human":
            continue
        body = str(item.get("body") or "")
        if (
            has_blocking_text(body)
            or has_blocking_severity(body)
            or HUMAN_MERGE_VETO_RE.search(body)
        ):
            login = item.get("author")
            login = login.get("login") if is_json_object(login) else login
            human_blocking.append(str(login or "unknown"))
    if human_blocking:
        blockers.append(
            "human blocking comment(s) from "
            + ", ".join(sorted(set(human_blocking)))
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
        "humanBlockingComments": sorted(set(human_blocking)),
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
            "PR body says do not merge -- a human hold, report it and leave it"
        )
    if any(str(name).casefold() == MERGE_HOLD_LABEL for name in labels):
        blockers.append(
            f"PR carries the {MERGE_HOLD_LABEL!r} label -- a human hold, "
            "report it and leave it"
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
        # remote execution) serve only a pinned set of GraphQL operations,
        # refusing the rest with HTTP 403. Every other input above was
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
            repo, number
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
            )

        layer_blockers, stack_result = evaluate_stack_layers(
            repo, number, base_ref, stack, evaluate_layer
        )
        stack_result["enabled"] = True
        blockers.extend(layer_blockers)

    ready = not blockers
    # `--auto` needs both AI review checks at SUCCESS in the rollup, which is the
    # live head's. A draft skips both lanes, so neither an absent nor a SKIPPED
    # check (which the check buckets count as success) passes.
    ai_review_holds = [
        f"AI review check {lane!r} has not succeeded on the live head"
        for lane, names in AI_REVIEW_CHECKS.items()
        if not (
            matches := [
                c
                for c in checks["checks"]
                if is_ai_review_check(c["name"], names)
            ]
        )
        or any(c["effective_state"] != "SUCCESS" for c in matches)
    ]
    ai_review_holds += stack_result.get("aiReviewHolds") or []
    auto_blockers = [b for b in blockers if b not in waiting] + ai_review_holds
    # GitHub auto-merge is armed only over a plain direct merge; a queue or a
    # stack is merged through the async API once the PR is fully ready.
    if not ready and merge_queue_required:
        auto_blockers.append(MERGE_QUEUE_AUTO_HOLD)
    if not ready and stack_mode:
        auto_blockers.append(STACK_AUTO_HOLD)
    return {
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
        "labels": labels,  # surfaced for agent reasoning; only do-not-merge is hardcoded
        "expectedHead": expected_head,
        "headMatches": head_matches,
        "effectiveRules": rules,
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
    }


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
    "mergeQueueEntry{state position} autoMergeRequest{enabledAt}}}}"
)


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
    }


def report_queue_routing(result: dict[str, Any], queue: dict[str, Any]) -> int:
    """Correct a successful `gh pr merge` report for a base with a merge queue,
    returning the exit code.

    `gh pr merge` routes every merge on a queue base into the queue, `--auto`
    or not, and exits 0 either way; a queue the rules read did not report is
    therefore seen only here. A base without a queue keeps the report as it was.
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
    result["merge"]["message"] = (
        "gh pr merge succeeded on a merge-queue base, but the pull request is not "
        "queued, armed to enter the queue, or merged -- re-run the read-only check"
    )
    return 10


def async_merge(
    repo: str,
    number: int,
    *,
    sha: str,
    merge_action: str,
    method: str | None,
) -> dict[str, Any]:
    """Request an async merge or enqueue, poll it, and verify a reported merge.

    Returns the `merge` record. `endpointMissing` marks a 404 on the request
    itself (a host without the endpoint, such as an older GitHub Enterprise
    Server): the PR was just read, so the 404 is the endpoint's, not the PR's.
    """
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


def check_pending_request(repo: str, number: int, path: Path) -> dict[str, Any] | None:
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
    """
    key = f"{repo}#{number}"
    with state_lock(path):
        entry = _load_pending(path).get(key)
    if not is_json_object(entry):
        return None
    if entry.get("queued"):
        return check_queued_entry(repo, number, path, entry)
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
    if current["expired"] or current["status"] in ASYNC_TERMINAL_STATUSES:
        update_pending(path, key, None)
    return report


def check_queued_entry(
    repo: str, number: int, path: Path, entry: dict[str, Any]
) -> dict[str, Any]:
    """A recorded merge-queue entry as GitHub reports it now.

    `queued` while the PR is still in the queue, `merged` once it landed
    (checked against the recorded head), and `dequeued` when it left the queue
    without merging. An unreadable queue, or a merge whose head cannot be read
    back, keeps the record with status None.
    """
    key = f"{repo}#{number}"
    queue = read_merge_queue(repo, number)
    report: dict[str, Any] = {**entry, "status": None, "message": ""}
    if queue["readError"]:
        report["message"] = queue["readError"]
        return report
    if queue["inQueue"]:
        report["status"] = "queued"
        report["mergeQueue"] = {"state": queue["state"], "position": queue["position"]}
        return report
    if queue["merged"]:
        report["status"] = "merged"
        report["verification"] = verify_request_landed(repo, number, entry)
        if report["verification"]["verified"] is None:
            return report
    else:
        report["status"] = "dequeued"
    update_pending(path, key, None)
    return report


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


def _queued_entry(pin: str) -> dict[str, Any]:
    return {
        "queued": True,
        "head": pin,
        "mergeAction": "merge_queue",
        "requestedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
    }


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
    if status is None:
        return (
            f"the merge-queue entry recorded at {since} could not be read "
            f"({prior.get('message')}) -- merge pending; it may still land; no new "
            "request is sent",
            None,
        )
    if status == "dequeued":
        dequeued = (
            f"left the merge queue without merging (queued at {since}): removed by "
            "hand or through the API, a failed or timed-out queue check, or a "
            "requirement it no longer meets -- dequeued, not merged; the record is "
            "cleared and the next run gates it again"
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
    configure_stdio()
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
    args = parser.parse_args()

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

    pending_path: Path | None = None
    if args.state_dir is not None:
        try:
            pending_path = resolve_state_dir(args.state_dir) / PENDING_MERGES_FILE
        except ValueError as exc:
            return _refuse(str(exc), 2)

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
            prior = check_pending_request(repo, number, pending_path)
        except (RuntimeError, OSError) as exc:
            return _refuse(f"pending merge record unreadable: {exc}", 2)

    try:
        result = evaluate(
            repo,
            number,
            args.expected_head,
            allowed,
            self_logins,
            args.allow_dependency,
            args.allow_unprotected,
            tier,
            extra_dependency_manager_logins=extra_dependency_manager_logins,
            settle=settle,
            stacked=args.stacked_prs,
        )
    except (RuntimeError, ValueError, json.JSONDecodeError) as exc:
        # Surface any gh/parse failure as JSON rather than a traceback.
        print(json.dumps({"pr": args.pr, "error": f"{type(exc).__name__}: {exc}"}))
        return 2

    result["action"] = "merge" if args.merge else "check"
    result["merged"] = False
    result["merge"] = None

    if prior is not None:
        result["pendingMergeRequest"] = prior
        verified = json_object(prior.get("verification")).get("verified", True)
        hold = reason = None
        if prior.get("queued"):
            hold, reason = queued_entry_hold(prior, verified)
            if prior.get("status") == "queued":
                result["enqueued"] = True
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
            result["merged"] = result["ready"] = True
            result["blockers"] = []
            result["merge"] = {
                **prior,
                "attempted": False,
                "source": "pendingMergeRequest",
            }
            print(json.dumps(result, indent=2))
            return 0

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
        print(json.dumps(result, indent=2))
        return 10
    if arm_auto:
        # Consumers treat `action: merge` as a performed merge; an arm is not one.
        result["action"] = "auto-merge"

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
    # GraphQL is refused), the only API that enqueues, and GitHub's required API
    # for merging any stacked PR, the bottom layer included. It is used on the
    # default branch, for a queue, and for a stack member; any other base keeps
    # `gh pr merge`. Auto-merge has no async form and keeps `gh pr merge`.
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
        exit_code = report_queue_routing(result, read_merge_queue(repo, number))
        if pending_path is not None and result.get("enqueued"):
            _write_pending(pending_path, f"{repo}#{number}", _queued_entry(pin), result)
    print(json.dumps(result, indent=2))
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
