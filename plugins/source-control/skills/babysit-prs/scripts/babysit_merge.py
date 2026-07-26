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
  `--admin`. This helper cannot bypass branch protection, resolve or reply to
  review threads, force-push, or change settings.
- A PR authored by a dependency manager (Dependabot/Renovate-class) is held --
  never merged -- unless `--allow-dependency` is passed.
- A PR on an unprotected base (zero required reviews AND zero required contexts)
  authored by someone other than a configured self login is held unless
  `--allow-unprotected` is passed: on such a base `CLEAN` proves nothing.
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

Readiness is gated on GitHub's own `mergeStateStatus == CLEAN` (which integrates
required checks, up-to-date, approvals, and conversation resolution) plus
explicit cross-checks so the *reason* for a block is always reported: the
effective branch rules (`rules/branches`), the review decision, unresolved
review threads, and the status-check rollup.

Exit codes: 0 ready (or merged), 10 not ready (blockers), 2 usage/runtime
error, 3 owner out of scope (or no allowlist). Output is a single JSON object
on stdout.
"""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, cast

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
    fetch_issue_comments,
    fetch_pull_request_review_comments,
    fetch_pull_request_reviews,
    fetch_review_threads,
    gh_capture,
    gh_json,
    normalized_rest_author,
    parse_repo_number,
    resolve_authors,
)
from babysit_review_trigger import (
    ReviewTriggerConfig,
    fetch_review_evidence,
    has_current_head_review,
)
from babysit_util import MIN_HEAD_SHA_PREFIX_LENGTH, configure_stdio, is_json_object

# A plain human "do not merge" veto that is neither a formal CHANGES_REQUESTED
# review nor the configured label: the shared blocking-text predicate does not
# carry a do-not-merge pattern, so the tier's "no human blocking comment"
# criterion matches it here. Bounded to the merge-veto sense (do/don't/do-not
# merge) so ordinary prose does not false-block.
HUMAN_MERGE_VETO_RE = re.compile(r"\bdo(?:n['’]?t| not|-not)[\s-]*merge\b", re.I)

EXPECTED_HEAD_RE = re.compile(rf"^[0-9a-fA-F]{{{MIN_HEAD_SHA_PREFIX_LENGTH},64}}$")

# GitHub's own fixed enum contract. MergeStateStatus values meaning "mergeable,
# all commit status passing": CLEAN on github.com, HAS_HOOKS when the repo has
# pre-receive hooks (GHES) -- GitHub returns one OR the other, so both are ready.
READY_MERGE_STATES = {"CLEAN", "HAS_HOOKS"}


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


def parse_csv_set(raw: str | None) -> set[str]:
    if not raw:
        return set()
    return {part.strip() for part in raw.split(",") if part.strip()}


def split_owner(repo: str) -> str:
    return repo.split("/", 1)[0]


def parse_allowed_owners(raw: str | None) -> set[str]:
    if not raw:
        return set()
    return {part.strip().casefold() for part in raw.split(",") if part.strip()}


def unresolved_threads(repo: str, number: int) -> list[dict[str, object]]:
    """Unresolved review threads via the single shared paginator.

    One comment per thread is enough to attribute the finding; the paginator
    drops resolved threads and fails closed on a malformed connection, so a
    hidden page can never falsely report zero unresolved threads.
    """

    def project(thread: dict[str, Any]) -> dict[str, object]:
        comments = thread.get("comments")
        first = comments[0] if isinstance(comments, list) and comments else {}
        first_object = cast(dict[str, Any], first) if isinstance(first, dict) else {}
        author = first_object.get("author")
        author_object = (
            cast(dict[str, Any], author) if isinstance(author, dict) else {}
        )
        return {
            "author": author_object.get("login"),
            "path": first_object.get("path"),
            "isOutdated": thread.get("isOutdated", False),
        }

    return [
        cast(dict[str, object], record)
        for record in fetch_review_threads(
            repo, number, include_resolved=False, comments_first=1, projection=project
        )
    ]


def branch_rules(repo: str, branch: str) -> dict[str, object]:
    """Summarize the effective merge-governing rules for the base branch."""
    summary: dict[str, object] = {
        "requiredContexts": [],
        "requiredApprovingReviews": 0,
        "requireThreadResolution": False,
        "requireSignatures": False,
        "requireLinearHistory": False,
        "mergeQueueRequired": False,
    }
    try:
        rules = gh_json(["api", f"repos/{repo}/rules/branches/{branch}"])
    except (RuntimeError, json.JSONDecodeError) as exc:
        # Rules are advisory context; a read failure must never fail the run.
        summary["error"] = f"could not read branch rules: {exc}"
        return summary
    for rule in cast(list[Any], rules) if isinstance(rules, list) else []:
        if not isinstance(rule, dict):
            continue
        rule_object = cast(dict[str, Any], rule)
        rtype = rule_object.get("type")
        raw_params = rule_object.get("parameters")
        params = (
            cast(dict[str, Any], raw_params) if isinstance(raw_params, dict) else {}
        )
        if rtype == "required_status_checks":
            summary["requiredContexts"] = [
                cast(dict[str, Any], c).get("context")
                for c in params.get("required_status_checks", [])
                if isinstance(c, dict)
            ]
        elif rtype == "pull_request":
            summary["requiredApprovingReviews"] = params.get(
                "required_approving_review_count", 0
            )
            summary["requireThreadResolution"] = params.get(
                "required_review_thread_resolution", False
            )
        elif rtype == "required_signatures":
            summary["requireSignatures"] = True
        elif rtype == "required_linear_history":
            summary["requireLinearHistory"] = True
        elif rtype == "merge_queue":
            summary["mergeQueueRequired"] = True
    return summary


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
    exact live head commit — a stale approval left on a since-superseded commit is
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
        if normalize_login_set([login]) & author_norm:
            continue  # same identity as the PR author -- not a distinct approver
        if not is_bot(login, typename, approver_bot_logins):
            continue
        # A bot, but it must be the configured approver identity: `is_bot` accepts
        # any `[bot]`/Bot-typed login, so without this an arbitrary installed
        # App's approval would authorize a tier merge past the configured boundary.
        if not (normalize_login_set([login]) & approver_norm):
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
        label
        for label in tier.block_labels
        if label.casefold() in label_names
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
    decisive_reviews = latest_reviews_by_author({"reviews": reviews}, decisive_only=True)
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
    # as a bot here, so its clean review body ("no blocking issues") no longer
    # self-blocks the very approval `find_distinct_bot_approval` accepted --
    # extending the existing "a bot's blocking-looking prose is not a human stop"
    # rule to configured bots that lack a `[bot]` suffix.
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
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)


def head_committed_at(repo: str, head_sha: str) -> datetime | None:
    """Committer date of the head commit, or None when it cannot be read.

    The committer date is the gate's stand-in for "when this head appeared".
    They diverge when a commit is pushed long after it was written; a rebase or
    amend rewrites the committer date, so the common lane case -- commit, push,
    merge -- reads true. A head whose date cannot be read is not treated as old:
    the caller holds instead, because a transient read failure must not be the
    thing that silently disables the hold.
    """
    try:
        data = gh_json(["api", f"repos/{repo}/commits/{head_sha}"])
    except (RuntimeError, json.JSONDecodeError):
        return None
    if not is_json_object(data):
        return None
    commit = cast(dict[str, Any], data).get("commit")
    if not is_json_object(commit):
        return None
    committer = cast(dict[str, Any], commit).get("committer")
    if not is_json_object(committer):
        return None
    return parse_github_timestamp(str(cast(dict[str, Any], committer).get("date") or ""))


def evaluate_review_settle(
    repo: str,
    head: str | None,
    settle: ReviewSettleConfig,
    review_evidence: list[dict[str, str]],
    *,
    now: datetime | None = None,
) -> tuple[list[str], dict[str, Any]]:
    """Hold the merge while a configured reviewer's review of this head is due.

    Two conditions, in this order, so the common case costs nothing: a
    current-head review from the reviewer clears the hold outright, and only a
    head with no such review is aged against the settle window.
    """
    result: dict[str, Any] = {
        "enabled": True,
        "reviewerLogins": sorted(settle.reviewer_logins),
        "settleSeconds": settle.settle_seconds,
        "currentHeadReview": False,
        "headAgeSeconds": None,
        "state": "unknown",
    }
    if not head:
        result["state"] = "no-head"
        return [], result

    if has_current_head_review(
        {}, head, review_evidence,
        config=ReviewTriggerConfig(reviewer_logins=settle.reviewer_logins),
    ):
        result["currentHeadReview"] = True
        result["state"] = "reviewed"
        return [], result

    committed_at = head_committed_at(repo, head)
    if committed_at is None:
        result["state"] = "head-age-unreadable"
        return [
            "cannot read the head commit's date, so whether the configured "
            f"reviewer(s) {sorted(settle.reviewer_logins)} still owe this head a "
            "review is undecidable -- holding rather than merging on an "
            "unverifiable clock; re-run to retry"
        ], result

    age_seconds = int(
        ((now or datetime.now(timezone.utc)) - committed_at).total_seconds()
    )
    result["headAgeSeconds"] = age_seconds
    if age_seconds < settle.settle_seconds:
        result["state"] = "settling"
        return [
            f"no review of the live head from {sorted(settle.reviewer_logins)} and "
            f"the head is {age_seconds}s old (settle window "
            f"{settle.settle_seconds}s) -- a re-review may still be in flight; "
            "wait out the window rather than merging past it"
        ], result

    result["state"] = "settled"
    return [], result


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
) -> dict[str, Any]:
    owner = split_owner(repo)
    pr_data = gh_json(
        [
            "pr",
            "view",
            str(number),
            "-R",
            repo,
            "--json",
            "state,isDraft,mergeable,mergeStateStatus,reviewDecision,"
            "headRefOid,baseRefName,author,url,title,labels,statusCheckRollup,"
            "closingIssuesReferences",
        ]
    )
    pr = cast(dict[str, Any], pr_data) if isinstance(pr_data, dict) else {}
    threads = unresolved_threads(repo, number)
    checks = classify_checks(pr.get("statusCheckRollup"))
    failing = checks["failing"]
    pending = checks["pending"]
    checks_by_key: dict[tuple[str, str, str], dict[str, Any]] = {
        check_identity_key(check): check for check in checks["checks"]
    }
    rules = branch_rules(repo, str(pr.get("baseRefName") or "main"))
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
    required_check_status: list[dict[str, object]] = []
    for raw_context in (
        cast(list[Any], required_contexts)
        if isinstance(required_contexts, list)
        else []
    ):
        ctx = str(raw_context)
        match = next(
            (
                check
                for key, check in checks_by_key.items()
                if key[1] and (key[1] == ctx or ctx.endswith(key[1]) or key[1].endswith(ctx))
            ),
            None,
        )
        satisfied = bool(match) and (match or {}).get("category") == "success"
        required_check_status.append(
            {
                "context": ctx,
                "found": bool(match),
                "satisfied": satisfied,
                "category": (match or {}).get("category"),
            }
        )

    required_reviews = rules.get("requiredApprovingReviews") or 0
    required_context_list = (
        required_contexts if isinstance(required_contexts, list) else []
    )
    base_is_unprotected = not required_reviews and not required_context_list

    blockers: list[str] = []
    if owner not in allowed:
        blockers.append(f"owner {owner!r} out of scope")
    if pr.get("state") != "OPEN":
        blockers.append(f"state={pr.get('state')} (not OPEN)")
    if pr.get("isDraft"):
        blockers.append("PR is a draft -- mark ready first")
    if pr.get("mergeable") != "MERGEABLE":
        blockers.append(
            f"mergeable={pr.get('mergeable')} (conflict or still computing)"
        )
    if pr.get("mergeStateStatus") not in READY_MERGE_STATES:
        blockers.append(
            f"mergeStateStatus={pr.get('mergeStateStatus')} "
            + "(need CLEAN/HAS_HOOKS: integrates required checks, up-to-date, "
            + "approvals, conversation resolution)"
        )
    if review_decision == "CHANGES_REQUESTED":
        blockers.append(
            "reviewDecision=CHANGES_REQUESTED -- a reviewer requested changes (human stop)"
        )
    elif required_reviews and review_decision != "APPROVED":
        blockers.append(
            f"needs {required_reviews} approving review(s); "
            f"reviewDecision={review_decision or 'none'}"
        )
    if threads:
        who = ", ".join(sorted({str(t.get("author")) for t in threads}))
        blockers.append(
            f"{len(threads)} unresolved review thread(s) [{who}] "
            "-- resolve or address the finding"
        )
    if failing:
        blockers.append("failing checks: " + ", ".join(str(name) for name in failing))
    if pending:
        blockers.append("pending checks: " + ", ".join(str(name) for name in pending))
    unmet_required = [r["context"] for r in required_check_status if not r["satisfied"]]
    if unmet_required:
        blockers.append(
            "required checks not satisfied: "
            + ", ".join(str(c) for c in unmet_required)
        )
    if rules.get("mergeQueueRequired"):
        blockers.append(
            "base branch requires a merge queue -- a direct merge is not allowed; "
            "add to the queue"
        )
    if head_matches is False:
        blockers.append(
            f"head moved: live={str(head)[:12] if head else None} expected={expected_head}"
        )
    # A dependency-manager PR is held in every tier unless explicitly allowed:
    # its update should be reviewed, not auto-merged on a green gate alone.
    if (
        is_dependency_author(
            str(author_login or ""), extra_dependency_manager_logins
        )
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

    closing_issues = cast(
        list[Any], pr.get("closingIssuesReferences") or []
    )
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
                repo, number, reviews, review_comments,
                config=ReviewTriggerConfig(reviewer_logins=settle.reviewer_logins),
            ),
        )
        blockers.extend(settle_blockers)

    tier_result: dict[str, Any] = {"enabled": False}
    if tier is not None:
        tier_blockers, tier_result = evaluate_autopilot_tier(
            repo, number, str(head) if head else None, author_login, labels,
            closing_issues, tier, reviews, review_comments,
        )
        blockers.extend(tier_blockers)

    ready = not blockers
    return {
        "pr": f"{repo}#{number}",
        "autopilotMergeTier": tier_result,
        "reviewSettle": settle_result,
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
        "labels": labels,  # surfaced for agent reasoning; no hardcoded hold-label list
        "expectedHead": expected_head,
        "headMatches": head_matches,
        "effectiveRules": rules,
        "requiredChecks": required_check_status,
        "unresolvedThreadCount": len(threads),
        "unresolvedThreads": threads,
        "failingChecks": failing,
        "pendingChecks": pending,
        "ready": ready,
        "blockers": blockers,
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
    data = cast(dict[str, Any], data) if isinstance(data, dict) else {}
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
            "unprotected-base hold); '@me' resolves to your gh login"
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
        "--method",
        choices=("squash", "merge", "rebase"),
        default=None,
        help="force a merge method (must be enabled); default prefers squash",
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
        help="permit merging a non-self PR on an unprotected base (held by default)",
    )
    parser.add_argument(
        "--allow-unpinned-head",
        action="store_true",
        help=(
            "permit --merge without --expected-head (interactive only); disables "
            "the TOCTOU guard that pins the vetted head SHA"
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

    allowed = parse_allowed_owners(args.allowed_owners)
    if not allowed:
        print(
            json.dumps(
                {
                    "pr": args.pr,
                    "inScope": False,
                    "error": (
                        "--allowed-owners is required and must be non-empty; "
                        "refusing to act without an owner allowlist"
                    ),
                }
            )
        )
        return 3

    try:
        repo, number = parse_repo_number(args.pr)
    except ValueError as exc:
        print(json.dumps({"error": str(exc)}))
        return 2

    if args.expected_head and not EXPECTED_HEAD_RE.match(args.expected_head):
        print(
            json.dumps(
                {
                    "pr": args.pr,
                    "error": (
                        "--expected-head must be a hex SHA prefix of at least "
                        f"{MIN_HEAD_SHA_PREFIX_LENGTH} characters (a shorter prefix "
                        "is ambiguous and could match an unvetted push)"
                    ),
                }
            )
        )
        return 2

    owner = split_owner(repo)
    if owner not in allowed:
        print(
            json.dumps(
                {
                    "pr": args.pr,
                    "inScope": False,
                    "error": f"owner {owner!r} out of scope; allowed: {sorted(allowed)}",
                }
            )
        )
        return 3

    # The review-settle hold is paired configuration, resolved before any network
    # access. Both flags or neither: a reviewer set with no window would need this
    # gate to invent how long that reviewer takes, and a window with no reviewer
    # set has nothing to wait for. Either alone is a usage error rather than a
    # silently-inert flag, so a half-configured hold can never read as an active one.
    settle: ReviewSettleConfig | None = None
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
            print(
                json.dumps(
                    {
                        "pr": args.pr,
                        "error": (
                            "the review-settle hold requires both "
                            "--review-bot-logins and --review-settle-minutes; "
                            "missing " + ", ".join(missing)
                        ),
                    }
                )
            )
            return 2
        reviewer_logins = normalize_login_set(parse_csv_set(args.review_bot_logins))
        try:
            settle_minutes = float(args.review_settle_minutes)
        except ValueError:
            settle_minutes = float("nan")
        if not reviewer_logins or not settle_minutes > 0 or settle_minutes == float("inf"):
            print(
                json.dumps(
                    {
                        "pr": args.pr,
                        "error": (
                            "--review-bot-logins must be non-empty and "
                            "--review-settle-minutes must be a finite number "
                            "greater than zero; refusing to run the hold "
                            "under-specified"
                        ),
                    }
                )
            )
            return 2
        settle = ReviewSettleConfig(
            reviewer_logins=reviewer_logins,
            settle_seconds=int(settle_minutes * 60),
        )

    # Build the autopilot-merge-tier config before any network access, failing
    # closed on a partial configuration: the tier's whole point is that the three
    # sets are all supplied deliberately, so an umbrella flag with any of them
    # empty is a refusal, never a merge on an under-specified tier.
    tier: AutopilotMergeTierConfig | None = None
    if args.autopilot_merge_tier:
        lane = parse_csv_set(args.lane_logins)
        approver = parse_csv_set(args.approver_bot_logins)
        block = parse_csv_set(args.block_labels)
        missing = [
            name
            for name, value in (
                ("--lane-logins", lane),
                ("--approver-bot-logins", approver),
                ("--block-labels", block),
            )
            if not value
        ]
        if missing:
            print(
                json.dumps(
                    {
                        "pr": args.pr,
                        "error": (
                            "--autopilot-merge-tier requires non-empty "
                            + ", ".join(missing)
                            + "; refusing to run the tier under-specified"
                        ),
                    }
                )
            )
            return 3
        tier = AutopilotMergeTierConfig(
            lane_logins=frozenset(lane),
            approver_bot_logins=frozenset(approver),
            block_labels=frozenset(block),
        )
    elif any(
        (args.lane_logins, args.approver_bot_logins, args.block_labels)
    ):
        print(
            json.dumps(
                {
                    "pr": args.pr,
                    "error": (
                        "--lane-logins / --approver-bot-logins / --block-labels "
                        "are only meaningful with --autopilot-merge-tier"
                    ),
                }
            )
        )
        return 2

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

    extra_dependency_manager_logins = frozenset(
        parse_csv_set(args.extra_dependency_manager_logins)
    )

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
        )
    except (RuntimeError, ValueError, json.JSONDecodeError) as exc:
        # Surface any gh/parse failure as JSON rather than a traceback.
        print(json.dumps({"pr": args.pr, "error": f"{type(exc).__name__}: {exc}"}))
        return 2

    result["action"] = "merge" if args.merge else "check"
    result["merged"] = False
    result["merge"] = None

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

    if not result["ready"]:
        result["merge"] = {"attempted": False, "reason": "not ready"}
        print(json.dumps(result, indent=2))
        return 10

    try:
        method = allowed_method(repo, args.method)
    except (RuntimeError, json.JSONDecodeError) as exc:
        # A method-lookup failure is reported, not raised, so output stays JSON.
        result["error"] = f"{type(exc).__name__}: {exc}"
        print(json.dumps(result, indent=2))
        return 2

    result["mergeMethod"] = method
    merge_cmd = ["pr", "merge", str(number), "-R", repo, f"--{method}"]
    # Atomic head pin: GitHub refuses the merge unless the head still equals the
    # exact full SHA we vetted, closing the preflight-to-merge TOCTOU window.
    vetted_head = result.get("headRefOid")
    if args.expected_head and isinstance(vetted_head, str) and vetted_head:
        merge_cmd += ["--match-head-commit", vetted_head]
    proc = gh_capture(merge_cmd)
    result["merge"] = {
        "attempted": True,
        "success": proc.returncode == 0,
        "stdout": proc.stdout.strip(),
        "stderr": proc.stderr.strip(),
    }
    result["merged"] = proc.returncode == 0
    print(json.dumps(result, indent=2))
    return 0 if proc.returncode == 0 else 10


if __name__ == "__main__":
    raise SystemExit(main())
