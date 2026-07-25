#!/usr/bin/env python3
"""Actor typing and bot/human feedback classification for the babysit engine.

Actor typing is structural first (`__typename`/`is_bot`/`[bot]` suffix); any
login-based fallback comes from caller-supplied configuration and ships empty.
Downgrade heuristics likewise apply only to reviewer logins the caller names.

The authorship / finding / approval primitives live in the shared
`babysit_classify` module (extracted per #534 so every babysit surface agrees);
this module orchestrates them into the snapshot's feedback buckets. The moved
names are re-exported here so existing consumers keep importing them from
`babysit_feedback`.
"""

from __future__ import annotations

import hashlib
import json
from typing import Any

from babysit_classify import (
    BOT_ERROR_RE,
    DEFAULT_FEEDBACK_CONFIG,
    DEPENDENCY_MANAGER_LOGINS,
    FeedbackConfig,
    actor_kind,
    approval_downgrade,
    author_login,
    body_text,
    has_blocking_severity,
    has_blocking_text,
    is_bot,
    is_dependency_author,
    is_self_login,
    normalize_login_set,
    normalize_self_logins,
    normalized_bot_login,
    skip_downgrade,
)
from babysit_gh import (
    fetch_issue_comments,
    fetch_unresolved_review_comments,
    rest_hydrate_reviews,
)
from babysit_util import is_json_object, json_array, json_object

__all__ = [
    "BOT_ERROR_RE",
    "DEFAULT_FEEDBACK_CONFIG",
    "DEPENDENCY_MANAGER_LOGINS",
    "FeedbackConfig",
    "actor_kind",
    "approval_downgrade",
    "author_login",
    "body_text",
    "collect_feedback",
    "fetch_current_human_stop",
    "has_blocking_severity",
    "has_blocking_text",
    "human_stop_state",
    "is_bot",
    "is_dependency_author",
    "is_self_login",
    "item_id",
    "latest_reviews_by_author",
    "normalize_login_set",
    "normalize_self_logins",
    "normalized_bot_login",
    "review_commit_oid",
    "skip_downgrade",
]


def item_id(prefix: str, item: dict[str, Any]) -> str:
    for key in (
        "id",
        "databaseId",
        "fullDatabaseId",
        "url",
        "submittedAt",
        "createdAt",
        "updatedAt",
    ):
        value = item.get(key)
        if value:
            return f"{prefix}:{value}"
    payload = json.dumps(item, sort_keys=True, default=str).encode("utf-8")
    return f"{prefix}:sha256:{hashlib.sha256(payload).hexdigest()}"


def review_commit_oid(review: dict[str, Any]) -> str:
    commit = review.get("commit")
    if is_json_object(commit):
        return str(commit.get("oid") or "")
    return ""


def latest_reviews_by_author(
    pr: dict[str, Any], *, decisive_only: bool = False
) -> list[dict[str, Any]]:
    """Return one latest review per actor, preferring the richer full review.

    With `decisive_only`, only formal review decisions (APPROVED,
    CHANGES_REQUESTED, DISMISSED) participate: COMMENTED reviews are feedback,
    not a superseding decision, so a human changes request remains active
    until that actor approves or GitHub reports the review as dismissed.
    Without it, only PENDING reviews are excluded.
    """
    decisive_states = {"APPROVED", "CHANGES_REQUESTED", "DISMISSED"}
    latest: dict[str, tuple[tuple[str, bool, bool], dict[str, Any]]] = {}
    anonymous: list[dict[str, Any]] = []
    for collection in (
        json_array(pr.get("latestReviews")),
        json_array(pr.get("reviews")),
    ):
        for review in collection:
            if not is_json_object(review):
                continue
            state = str(review.get("state") or "").upper()
            if decisive_only:
                if state not in decisive_states:
                    continue
            elif state == "PENDING":
                continue
            login = author_login(review).casefold()
            if not login:
                anonymous.append(review)
                continue
            rank = (
                str(review.get("submittedAt") or ""),
                bool(review.get("id") or review.get("databaseId")),
                bool(review_commit_oid(review)),
            )
            if login not in latest or rank > latest[login][0]:
                latest[login] = (rank, review)
    return [entry[1] for entry in latest.values()] + anonymous


def collect_feedback(
    pr: dict[str, Any],
    inline_comments: list[dict[str, Any]] | None = None,
    dispositions: dict[str, Any] | None = None,
    config: FeedbackConfig = DEFAULT_FEEDBACK_CONFIG,
) -> dict[str, list[dict[str, str]]]:
    approval_downgrade_logins = normalize_login_set(config.approval_downgrade_logins)
    skip_downgrade_logins = normalize_login_set(config.skip_downgrade_logins)
    blocking: list[dict[str, str]] = []
    material: list[dict[str, str]] = []
    human_blocking: list[dict[str, str]] = []
    human: list[dict[str, str]] = []
    ignored: list[dict[str, str]] = []

    sources: list[tuple[str, dict[str, Any]]] = [
        ("comment", comment)
        for comment in json_array(pr.get("comments"))
        if is_json_object(comment)
    ]
    sources.extend(("review", review) for review in latest_reviews_by_author(pr))
    sources.extend(
        ("review", review)
        for review in latest_reviews_by_author(pr, decisive_only=True)
    )
    sources.extend(
        ("inlineReview", comment)
        for comment in inline_comments or []
        if is_json_object(comment)
    )

    seen_ids: set[str] = set()
    for prefix, item in sources:
        fid = item_id(prefix, item)
        if fid in seen_ids:
            continue
        seen_ids.add(fid)
        login = author_login(item)
        kind = actor_kind(item, config)
        text = body_text(item)
        preview = " ".join(text.split())[:180]
        state = str(item.get("state") or "").upper()
        record = {
            "id": fid,
            "author": login,
            "actor_type": kind,
            "kind": prefix,
            "path": str(item.get("path") or ""),
            "state": state,
            "preview": preview,
        }
        if kind != "bot":
            if state in {"APPROVED", "DISMISSED"}:
                ignored.append(record)
            elif (
                prefix == "inlineReview"
                or state == "CHANGES_REQUESTED"
                or has_blocking_text(text)
            ):
                human_blocking.append(record)
            else:
                human.append(record)
            continue
        if state == "CHANGES_REQUESTED":
            blocking.append(record)
        elif state in {"APPROVED", "DISMISSED"}:
            ignored.append(record)
        elif has_blocking_text(text) or has_blocking_severity(text):
            disposition = json_object((dispositions or {}).get(fid))
            current_head = str(pr.get("headRefOid") or "")
            # Only honor a disposition recorded at the current head. If the PR has
            # advanced, the same feedback id must be re-evaluated (a new P1 posted
            # under a sticky id at a new head must not inherit an old downgrade).
            disposition_applies = (
                is_json_object(disposition)
                and bool(current_head)
                and disposition.get("head_sha") == current_head
            )
            if disposition_applies:
                record["disposed_reason"] = str(disposition.get("reason") or "")
                material.append(record)
            elif approval_downgrade(text):
                # An explicit approval verdict with no genuine severity marker
                # (no CRITICAL/IMPORTANT, no required-fix term surviving negation
                # redaction): the blocking-looking text is descriptive prose --
                # e.g. "blocking criteria", "blocking checks", "no blocking
                # issues" -- not a live finding. This is structural, not
                # login-gated: a clean approval reads the same from any bot, and
                # this keeps the snapshot consistent with
                # babysit-readiness-gate.sh reporting findings=0 for the very
                # same review. A login named in `approval_downgrade_logins` opts
                # that bot's clean approvals into the more-conservative `material`
                # bucket (surfaced but non-blocking) instead of being fully
                # ignored; the safe default for every other bot is `ignored`.
                record["downgrade"] = "approval_verdict"
                if normalized_bot_login(item) in approval_downgrade_logins:
                    material.append(record)
                else:
                    ignored.append(record)
            elif normalized_bot_login(
                item
            ) in skip_downgrade_logins and skip_downgrade(text):
                record["downgrade"] = "review_skip"
                material.append(record)
            else:
                blocking.append(record)
        elif BOT_ERROR_RE.search(text):
            material.append(record)
        else:
            ignored.append(record)
    return {
        "blocking": blocking,
        "material": material,
        "human_blocking": human_blocking,
        "human": human,
        "ignored": ignored,
    }


def human_stop_state(
    pr: dict[str, Any],
    inline_comments: list[dict[str, Any]] | None,
    config: FeedbackConfig = DEFAULT_FEEDBACK_CONFIG,
) -> dict[str, Any]:
    feedback = collect_feedback(pr, inline_comments, config=config)
    human_changes_requested = any(
        item.get("kind") == "review" and item.get("state") == "CHANGES_REQUESTED"
        for item in feedback["human_blocking"]
    )
    return {
        "required": bool(feedback["human_blocking"]),
        "human_changes_requested": human_changes_requested,
        "human_blocking_count": len(feedback["human_blocking"]),
    }


def fetch_current_human_stop(
    repo: str,
    number: int,
    pr: dict[str, Any],
    config: FeedbackConfig = DEFAULT_FEEDBACK_CONFIG,
) -> dict[str, Any]:
    hydrated = dict(pr)
    hydrated["comments"] = fetch_issue_comments(repo, number)
    rest_hydrate_reviews(hydrated, repo, number)
    inline_comments = fetch_unresolved_review_comments(repo, number)
    return human_stop_state(hydrated, inline_comments, config)
