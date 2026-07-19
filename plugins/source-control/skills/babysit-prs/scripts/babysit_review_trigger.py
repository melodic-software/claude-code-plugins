#!/usr/bin/env python3
"""Config-driven review-trigger gate and request-state machine.

Generalizes the bot-review trigger flow: the trigger phrase, reviewer logins,
gate context, and CI gateway context all come from caller configuration and
are ALL absent by default, leaving the module dormant (`gate_state ==
"absent"`). The trigger phrase is defined exactly once -- the posted comment
and the recognizer regex both derive from the same configured value.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any

from babysit_checks import summarized_state
from babysit_feedback import (
    author_login,
    normalize_login_set,
    review_commit_oid,
)
from babysit_gh import (
    fetch_issue_comments,
    fetch_paginated_api,
    fetch_pull_request_review_comments,
    fetch_pull_request_reviews,
)
from babysit_util import is_json_object, json_array, json_object, parse_timestamp

REACTION_CONTENTS = {"+1", "eyes"}
SUBMITTED_REVIEW_STATES = {"APPROVED", "CHANGES_REQUESTED", "COMMENTED"}


@dataclass(frozen=True)
class ReviewTriggerConfig:
    """Reviewer-bot integration configuration; every field ships absent.

    `trigger_phrase` is the exact comment body that requests a review (the
    recognizer regex derives from it -- one definition). `reviewer_logins`
    names the bot account(s) whose reviews/reactions count as engagement.
    `gate_context` is the StatusContext/CheckRun name of the review gate;
    `ci_gateway_context` the aggregate CI check the trigger waits on.
    """

    trigger_phrase: str = ""
    reviewer_logins: frozenset[str] = field(default_factory=frozenset)
    gate_context: str = ""
    ci_gateway_context: str = ""

    @property
    def configured(self) -> bool:
        return bool(self.trigger_phrase and self.reviewer_logins and self.gate_context)


DEFAULT_REVIEW_TRIGGER_CONFIG = ReviewTriggerConfig()


def trigger_regex(phrase: str) -> re.Pattern[str] | None:
    """Derive the trigger-comment recognizer from the configured phrase."""
    tokens = [re.escape(token) for token in phrase.split()]
    if not tokens:
        return None
    return re.compile(
        r"^\s*" + r"\s+".join(tokens) + r"(?:\s+.*)?\s*$", re.I | re.S
    )


def is_review_bot_item(item: dict[str, Any], config: ReviewTriggerConfig) -> bool:
    author = item.get("author")
    if not is_json_object(author):
        return False
    authoritative_bot = (
        str(author.get("__typename") or author.get("type") or "") == "Bot"
        or author.get("is_bot") is True
    )
    reviewer_logins = normalize_login_set(config.reviewer_logins)
    return (
        authoritative_bot
        and author_login(item).casefold().removesuffix("[bot]") in reviewer_logins
    )


def issue_comment_database_id(comment: dict[str, Any]) -> str:
    for key in ("databaseId", "fullDatabaseId", "id"):
        value = comment.get(key)
        if value is not None and str(value).isdigit():
            return str(value)
    match = re.search(r"issuecomment-(\d+)(?:$|[/?#])", str(comment.get("url") or ""))
    return match.group(1) if match else ""


def fetch_review_reactions(
    endpoint: str,
    *,
    scope: str,
    comment_id: str = "",
    config: ReviewTriggerConfig,
) -> list[dict[str, str]]:
    reactions = fetch_paginated_api(endpoint, endpoint)
    signals: list[dict[str, str]] = []
    for reaction in reactions:
        user = reaction.get("user")
        login = str(user.get("login") or "") if is_json_object(user) else ""
        content = str(reaction.get("content") or "")
        if not is_review_bot_item({"author": user}, config):
            continue
        if content not in REACTION_CONTENTS:
            continue
        reaction_id = str(reaction.get("id") or "")
        if not reaction_id:
            raise RuntimeError(f"Reviewer reaction from {endpoint} has no stable id")
        signals.append(
            {
                "id": f"{scope}:{reaction_id}",
                "reaction_id": reaction_id,
                "author": login,
                "content": content,
                "created_at": str(reaction.get("created_at") or ""),
                "scope": scope,
                "comment_id": comment_id,
            }
        )
    return signals


def fetch_reaction_signals(
    repo: str, number: int, pr: dict[str, Any], config: ReviewTriggerConfig
) -> list[dict[str, str]]:
    """Fetch reviewer-bot reaction signals on the PR and trigger comments."""
    recognizer = trigger_regex(config.trigger_phrase)
    signals = fetch_review_reactions(
        f"repos/{repo}/issues/{number}/reactions?per_page=100",
        scope="pull_request",
        config=config,
    )
    if recognizer is not None:
        comments = (
            list(pr.get("comments") or [])
            if pr.get("_issue_comments_complete") is True
            else fetch_issue_comments(repo, number)
        )
        for comment in comments:
            if not recognizer.fullmatch(str(comment.get("body") or "")):
                continue
            comment_id = issue_comment_database_id(comment)
            if not comment_id:
                raise RuntimeError(
                    f"Unable to resolve database id for review trigger comment in {repo}#{number}"
                )
            signals.extend(
                fetch_review_reactions(
                    f"repos/{repo}/issues/comments/{comment_id}/reactions?per_page=100",
                    scope="trigger_comment",
                    comment_id=comment_id,
                    config=config,
                )
            )
    unique = {signal["id"]: signal for signal in signals}
    return sorted(unique.values(), key=lambda signal: signal["id"])


def fetch_review_evidence(
    repo: str,
    number: int,
    reviews: list[dict[str, Any]] | None = None,
    review_comments: list[dict[str, Any]] | None = None,
    *,
    config: ReviewTriggerConfig,
) -> list[dict[str, str]]:
    """Fetch all submitted reviewer-bot reviews/comments with their commit ids."""
    review_records = (
        reviews if reviews is not None else fetch_pull_request_reviews(repo, number)
    )
    comment_records = (
        review_comments
        if review_comments is not None
        else fetch_pull_request_review_comments(repo, number)
    )
    evidence: list[dict[str, str]] = []
    for review in review_records:
        login = author_login(review)
        state = str(review.get("state") or "").upper()
        commit_oid = review_commit_oid(review)
        if (
            is_review_bot_item(review, config)
            and state in SUBMITTED_REVIEW_STATES
            and commit_oid
        ):
            evidence.append(
                {
                    "id": f"review:{review.get('id')}",
                    "kind": "review",
                    "author": login,
                    "state": state,
                    "commit_oid": commit_oid,
                    "url": str(review.get("url") or ""),
                }
            )
    for comment in comment_records:
        user = comment.get("user")
        login = str(user.get("login") or "") if is_json_object(user) else ""
        commit_oid = str(comment.get("commit_id") or "")
        if is_review_bot_item({"author": user}, config) and commit_oid:
            evidence.append(
                {
                    "id": f"review_comment:{comment.get('id')}",
                    "kind": "review_comment",
                    "author": login,
                    "state": "COMMENTED",
                    "commit_oid": commit_oid,
                    "url": str(comment.get("html_url") or ""),
                }
            )
    unique = {item["id"]: item for item in evidence}
    return sorted(unique.values(), key=lambda item: item["id"])


def has_current_head_review(
    pr: dict[str, Any],
    head_sha: str,
    review_evidence: list[dict[str, str]] | None = None,
    *,
    config: ReviewTriggerConfig,
) -> bool:
    if not head_sha:
        return False
    if review_evidence is not None:
        return any(
            evidence.get("commit_oid") == head_sha
            and evidence.get("state") in SUBMITTED_REVIEW_STATES
            for evidence in review_evidence
        )
    return any(
        is_review_bot_item(review, config)
        and str(review.get("state") or "").upper() in SUBMITTED_REVIEW_STATES
        and review_commit_oid(review) == head_sha
        for review in json_array(pr.get("reviews"))
        if is_json_object(review)
    )


def review_gate_state(
    checks: dict[str, Any], config: ReviewTriggerConfig
) -> dict[str, Any]:
    """Derive the review-gate view of a classified check rollup.

    With no configured contexts nothing matches, so every summarized state
    degrades to "absent" and the gateway/green signals stay False -- the
    dormant default.
    """
    gate_context = config.gate_context.casefold()
    ci_gateway_context = config.ci_gateway_context.casefold()
    all_checks = [
        check for check in json_array(checks.get("checks")) if is_json_object(check)
    ]
    gate_statuses = [
        check
        for check in all_checks
        if gate_context
        and check["type"] == "StatusContext"
        and check["name"].casefold() == gate_context
    ]
    gate_workflow_checks = [
        check
        for check in all_checks
        if gate_context
        and check["type"] == "CheckRun"
        and check["name"].casefold() == gate_context
    ]
    ci_gateway_checks = [
        check
        for check in all_checks
        if ci_gateway_context and check["name"].casefold() == ci_gateway_context
    ]
    non_review_checks = [
        check
        for check in all_checks
        if not (
            gate_context
            and check["type"] == "StatusContext"
            and check["name"].casefold() == gate_context
        )
    ]
    return {
        "gate_state": summarized_state(gate_statuses),
        "workflow_state": summarized_state(gate_workflow_checks),
        "request_signal_pending": any(
            check["effective_state"] == "PENDING" and not check["target_url"]
            for check in gate_statuses
        ),
        "ci_gateway_green": (not ci_gateway_context)
        or (
            bool(ci_gateway_checks)
            and all(check["category"] == "success" for check in ci_gateway_checks)
        ),
        "non_review_checks_green": bool(non_review_checks)
        and all(check["category"] == "success" for check in non_review_checks),
    }


def classify_review_request(
    pr: dict[str, Any],
    gate: dict[str, Any],
    previous: dict[str, Any],
    observed_at: str,
    review_evidence: list[dict[str, str]] | None = None,
    reaction_signals: list[dict[str, str]] | None = None,
    human_stop_required: bool = False,
    *,
    review_trigger_allowed: bool = False,
    config: ReviewTriggerConfig = DEFAULT_REVIEW_TRIGGER_CONFIG,
) -> dict[str, Any]:
    """Advance the review-request state machine for one PR.

    `review_trigger_allowed` is the caller's already-computed mutation-policy
    verdict (base repo allowed and not archived); passing it in keeps this
    module free of any trust-boundary policy import.
    """
    head_sha = str(pr.get("headRefOid") or "")
    merge_state = str(pr.get("mergeStateStatus") or "").upper()
    mergeable = str(pr.get("mergeable") or "").upper()
    prior = json_object(previous.get("review_trigger"))
    check_state = json_object(gate)
    evidence = list(review_evidence or [])
    reactions = list(reaction_signals or [])
    current_head_review = has_current_head_review(
        pr,
        head_sha,
        evidence if review_evidence is not None else None,
        config=config,
    )
    request_history = json_object(prior.get("request_history"))
    attempt_history = json_object(prior.get("request_attempt_history"))
    refresh_history = json_object(previous.get("branch_refresh_history"))
    requested_before = head_sha in request_history
    attempted_before = head_sha in attempt_history
    reaction_ids = {str(signal.get("id") or "") for signal in reactions}
    prior_reaction_ids: set[str] = (
        {str(value) for value in json_array(prior.get("reaction_signal_ids"))}
        if prior.get("reaction_head_sha") == head_sha
        else set()
    )
    associated_reaction_ids: set[str] = (
        {str(value) for value in json_array(prior.get("current_head_reaction_ids"))}
        if prior.get("reaction_head_sha") == head_sha
        else set()
    )
    known_trigger_comment_ids: set[str] = set()
    for history in (request_history, attempt_history):
        entry = history.get(head_sha)
        if is_json_object(entry) and entry.get("comment_id") is not None:
            known_trigger_comment_ids.add(str(entry["comment_id"]))
    associated_reaction_ids.update(
        str(signal.get("id") or "")
        for signal in reactions
        if signal.get("scope") == "trigger_comment"
        and str(signal.get("comment_id") or "") in known_trigger_comment_ids
    )
    if prior.get("reaction_head_sha") == head_sha:
        associated_reaction_ids.update(reaction_ids - prior_reaction_ids)
    associated_reaction_ids.intersection_update(reaction_ids)
    associated_reactions = [
        signal
        for signal in reactions
        if str(signal.get("id") or "") in associated_reaction_ids
    ]
    latest_associated_reaction = max(
        associated_reactions,
        key=lambda signal: (
            str(signal.get("created_at") or ""),
            str(signal.get("id") or ""),
        ),
        default=None,
    )
    associated_reaction_content = str(
        json_object(latest_associated_reaction).get("content") or ""
    )
    candidate = (
        bool(head_sha)
        and review_trigger_allowed
        and str(pr.get("state") or "").upper() == "OPEN"
        and head_sha not in refresh_history
        and not pr.get("isDraft")
        and merge_state not in {"", "BEHIND", "DIRTY", "DRAFT", "UNKNOWN"}
        and mergeable != "CONFLICTING"
        and not current_head_review
        # Only reactions tied to THIS head gate candidacy. Reactions carry no
        # commit SHA, so an earlier-head reaction persists across pushes; gating
        # on the raw `reactions` would let it suppress the new head's window
        # forever. `associated_reactions` is the current-head-scoped subset.
        and not associated_reactions
        and not human_stop_required
        and check_state["gate_state"] == "pending"
        and check_state["request_signal_pending"]
        and check_state["ci_gateway_green"]
        and check_state["non_review_checks_green"]
    )

    if candidate and prior.get("missing_head_sha") == head_sha:
        first_seen_at = str(prior.get("missing_first_seen_at") or observed_at)
        observations = int(prior.get("missing_observations") or 0) + 1
    elif candidate:
        first_seen_at = observed_at
        observations = 1
    else:
        first_seen_at = ""
        observations = 0

    first_seen = parse_timestamp(first_seen_at)
    observed = parse_timestamp(observed_at)
    elapsed_seconds = (
        max(0, int((observed - first_seen).total_seconds()))
        if first_seen is not None and observed is not None
        else 0
    )
    requested_head_sha = str(prior.get("requested_head_sha") or "")
    attempted_head_sha = str(prior.get("request_attempt_head_sha") or "")
    request_eligible = (
        candidate
        and observations >= 2
        and elapsed_seconds >= 180
        and not requested_before
        and not attempted_before
    )

    if current_head_review:
        state = "engaged_current_head"
    elif associated_reaction_content == "eyes":
        state = "engaged_reaction_reviewing"
    elif reactions:
        state = "engagement_signal_unverified"
    elif requested_before or requested_head_sha == head_sha:
        state = "requested"
    elif attempted_before or attempted_head_sha == head_sha:
        attempt = json_object(attempt_history.get(head_sha))
        state = str(
            attempt.get("status") or prior.get("request_attempt_status") or "attempted"
        )
    elif request_eligible:
        state = "eligible"
    elif candidate:
        state = "observing"
    elif check_state["gate_state"] == "success":
        state = "gate_success_unverified"
    else:
        state = check_state["gate_state"]

    return {
        **check_state,
        "state": state,
        "missing_head_sha": head_sha if candidate else "",
        "missing_first_seen_at": first_seen_at,
        "missing_last_seen_at": observed_at if candidate else "",
        "missing_observations": observations,
        "requested_head_sha": requested_head_sha,
        "current_head_review": current_head_review,
        "request_attempt_head_sha": attempted_head_sha,
        "request_attempted_at": str(prior.get("request_attempted_at") or ""),
        "request_attempt_status": str(prior.get("request_attempt_status") or ""),
        "request_attempt_error": str(prior.get("request_attempt_error") or ""),
        "request_history": request_history,
        "request_attempt_history": attempt_history,
        "review_evidence": evidence,
        "reaction_signals": reactions,
        "reaction_head_sha": head_sha,
        "reaction_signal_ids": sorted(reaction_ids),
        "current_head_reaction_ids": sorted(associated_reaction_ids),
        "request_comment_id": prior.get("request_comment_id"),
        "requested_at": str(prior.get("requested_at") or ""),
        "request_eligible": request_eligible,
    }
