#!/usr/bin/env python3
"""Actor typing and bot/human feedback classification for the babysit engine.

Actor typing is structural first (`__typename`/`is_bot`/`[bot]` suffix); any
login-based fallback comes from caller-supplied configuration and ships empty.
Downgrade heuristics likewise apply only to reviewer logins the caller names.
"""

from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass, field
from typing import Any

from babysit_gh import (
    fetch_issue_comments,
    fetch_pull_request_reviews,
    fetch_unresolved_review_comments,
)
from babysit_util import is_json_object, json_array, json_object

BLOCKING_TEXT_RE = re.compile(
    r"\b(p0|p1|p2|high[- ]severity|not approving|changes requested|"
    + r"request(?:s|ing)? changes|"
    + r"required fix|must fix|blocking|regression|vulnerability)\b",
    re.I,
)
BOT_ERROR_RE = re.compile(
    r"(encountered an error|could not|unable to|failed to run)", re.I
)
NEGATED_SEVERITY_LIST_RE = re.compile(
    r"\b(?:no|zero|without)\s+(?:actionable\s+)?p[012]"
    + r"(?:\s*,?\s*(?:(?:and|or)\s+)?p[012])*\s+"
    + r"(?:issues?|findings?|defects?|problems?|regressions?|vulnerabilities?)\b",
    re.I,
)
# Negated CRITICAL/IMPORTANT conclusions ("No CRITICAL or IMPORTANT findings",
# "No CRITICAL issues found") are the structured-severity analogue of
# NEGATED_SEVERITY_LIST_RE: a clean approval stating the absence of high-severity
# findings, not a live one. The severity tokens stay case-sensitive (uppercase
# only) for the same reason BLOCKING_SEVERITY_RE is -- lowercase "critical"/
# "important" are ordinary prose -- while the negator and trailing noun are not.
NEGATED_SEVERITY_MARKER_RE = re.compile(
    r"(?i:\b(?:no|zero|without)\s+(?:actionable\s+)?)"
    + r"(?:CRITICAL|IMPORTANT)"
    + r"(?:(?i:\s*,?\s*(?:(?:and|or)\s+)?)(?:CRITICAL|IMPORTANT))*"
    + r"(?i:\s+(?:issues?|findings?|defects?|problems?|regressions?|"
    + r"vulnerabilities?))\b"
)
NEGATED_BLOCKING_TERM_RE = re.compile(
    r"\b(?:no|zero|without)\s+(?:actionable\s+)?(?:p[012]|high[- ]severity|"
    + r"blocking|regressions?|vulnerabilities?|required fixes?|changes requested)\b|"
    + r"\bnot\s+(?:an?\s+)?(?:blocking|regression|vulnerability)\b",
    re.I,
)
APPROVAL_VERDICT_RE = re.compile(
    r"\bapproved?\b|\blgtm\b|\bready (?:for|to) merge\b|"
    + r"\b(?:pr|change|changes|implementation|code) (?:is|are|looks?) sound\b|"
    + r"\bnone of (?:the|these|my) (?:observations|findings|issues|comments|"
    + r"suggestions) (?:is|are) blocking\b|"
    + r"\bno blocking (?:issues?|findings?|defects?|problems?|concerns?)\b|"
    + r"\bnothing blocking\b",
    re.I,
)
NON_APPROVAL_RE = re.compile(
    r"\b(?:not?|cannot|can't|won't|wouldn't|unable to|refus\w+|declin\w+|"
    + r"do(?:es)?n't|isn't|aren't)\s+(?:be\s+|yet\s+)?"
    + r"(?:approv\w+|ready|sound|mergeable)\b|\bnot ready\b",
    re.I,
)
REQUIRED_FIX_RE = re.compile(
    r"\b(?:p0|p1|required fix(?:es)?|must fix|fix required|changes requested|"
    + r"request(?:s|ing)? changes|regression|vulnerability|high[- ]severity)\b",
    re.I,
)
# Blocking-severity markers, case-sensitive and whole-word, matching the
# vocabulary babysit-readiness-gate.sh counts as findings (CRITICAL/IMPORTANT).
# Deliberately NOT case-insensitive: lowercase "critical"/"important" occur
# constantly in ordinary review prose ("it is important to note", "critical
# path"), whereas the uppercase tokens are the reviewer's structured severity
# labels. SUGGESTION is intentionally excluded here -- like a 🟡 nit it is a
# non-blocking marker -- so an approval carrying only suggestions/nits stays
# non-blocking, consistent with the issue's "CRITICAL/IMPORTANT vs nits" split.
BLOCKING_SEVERITY_RE = re.compile(r"\b(?:CRITICAL|IMPORTANT)\b")
REVIEW_SKIP_RE = re.compile(
    r"\bbugbot\b[^\n.]{0,80}?\b(?:skipped|did(?:n't| not) run|"
    + r"could(?:n't| not) run|was not run|unable to run|usage limit)\b"
    + r"|\busage limit (?:reached|hit|exceeded)\b",
    re.I,
)
NOT_APPROVING_RE = re.compile(r"\bnot approving\b", re.I)
# Dependency-manager product bots (a tool taxonomy, not a tenant identity):
# their PRs feed the cross-tier hold-merge rule.
DEPENDENCY_MANAGER_LOGINS = frozenset(
    {
        "dependabot",
        "dependabot-preview",
        "renovate",
        "renovate-bot",
    }
)


@dataclass(frozen=True)
class FeedbackConfig:
    """Caller-supplied identity configuration; every set ships empty.

    `extra_bot_logins` supplements structural bot detection for accounts whose
    metadata misreports them as users. A clean approval (explicit approval
    verdict, no CRITICAL/IMPORTANT or required-fix marker) is treated as
    non-blocking for every bot structurally. `approval_downgrade_logins` names
    the reviewer logins whose approval is surfaced as a material finding rather
    than ignored in the one case the structural downgrade reaches: a review body
    carrying blocking-looking prose that still parses as an approval verdict. It
    does not affect a review already in the APPROVED state or a plain clean
    approval whose body carries no blocking-looking prose -- both are ignored
    regardless, since neither reaches the downgrade branch.
    `skip_downgrade_logins` names the reviewer logins
    whose not-approving text may be downgraded to material when their review
    provably could not run.
    """

    extra_bot_logins: frozenset[str] = field(default_factory=frozenset)
    approval_downgrade_logins: frozenset[str] = field(default_factory=frozenset)
    skip_downgrade_logins: frozenset[str] = field(default_factory=frozenset)


DEFAULT_FEEDBACK_CONFIG = FeedbackConfig()


def normalize_login_set(logins: Any) -> frozenset[str]:
    """Normalize a login collection for comparison: casefold, strip `[bot]`."""
    return frozenset(
        str(login).casefold().removesuffix("[bot]")
        for login in (logins or [])
        if str(login).strip()
    )


def author_login(item: dict[str, Any]) -> str:
    author = item.get("author")
    if is_json_object(author):
        return str(author.get("login") or author.get("name") or "")
    return str(author or "")


def actor_kind(
    item: dict[str, Any], config: FeedbackConfig = DEFAULT_FEEDBACK_CONFIG
) -> str:
    """Classify actors from authoritative type metadata, then exact fallbacks."""
    author = item.get("author")
    if is_json_object(author):
        typename = str(author.get("__typename") or "")
        if typename == "Bot" or author.get("is_bot") is True:
            return "bot"
        if (
            typename in {"Mannequin", "Organization", "User"}
            or author.get("is_bot") is False
        ):
            return "human"
    login = author_login(item).lower()
    normalized = login.removesuffix("[bot]")
    if login.endswith("[bot]") or normalized in normalize_login_set(
        config.extra_bot_logins
    ):
        return "bot"
    return "human"


def normalized_bot_login(item: dict[str, Any]) -> str:
    return author_login(item).casefold().removesuffix("[bot]")


def is_dependency_author(login: str) -> bool:
    """Pure dependency-manager author test feeding the cross-tier hold-merge rule."""
    normalized = str(login or "").casefold().removeprefix("app/").removesuffix("[bot]")
    return normalized in DEPENDENCY_MANAGER_LOGINS


def body_text(item: dict[str, Any]) -> str:
    parts: list[str] = []
    for key in ("body", "bodyText", "state", "comment", "message"):
        value = item.get(key)
        if isinstance(value, str):
            parts.append(value)
    return "\n".join(parts)


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
            login = author_login(review).lower()
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


def has_blocking_text(text: str) -> bool:
    """Apply blocking heuristics after redacting common negated findings."""
    redacted = NEGATED_SEVERITY_LIST_RE.sub("", text)
    redacted = NEGATED_BLOCKING_TERM_RE.sub("", redacted)
    return bool(BLOCKING_TEXT_RE.search(redacted))


def has_blocking_severity(text: str) -> bool:
    """True when a CRITICAL/IMPORTANT severity marker survives negation redaction.

    A companion to `has_blocking_text` for the structured severity vocabulary
    the readiness gate counts as findings. A bot review that raises a genuine
    high-severity finding is blocking even when its prose contains none of
    `BLOCKING_TEXT_RE`'s imperative terms.
    """
    redacted = NEGATED_SEVERITY_LIST_RE.sub("", text)
    redacted = NEGATED_SEVERITY_MARKER_RE.sub("", redacted)
    redacted = NEGATED_BLOCKING_TERM_RE.sub("", redacted)
    return bool(BLOCKING_SEVERITY_RE.search(redacted))


def approval_downgrade(text: str) -> bool:
    """True when a reviewer bot states an explicit approval verdict.

    Requires a clear approval/non-blocking conclusion, no negated approval
    language, and neither a required-fix term nor a CRITICAL/IMPORTANT severity
    marker surviving negation redaction. Anything ambiguous -- and any genuine
    high-severity finding raised under an approval verdict -- stays blocking.
    """
    if NON_APPROVAL_RE.search(text):
        return False
    if not APPROVAL_VERDICT_RE.search(text):
        return False
    redacted = NEGATED_SEVERITY_LIST_RE.sub("", text)
    redacted = NEGATED_SEVERITY_MARKER_RE.sub("", redacted)
    redacted = NEGATED_BLOCKING_TERM_RE.sub("", redacted)
    if BLOCKING_SEVERITY_RE.search(redacted):
        return False
    return not REQUIRED_FIX_RE.search(redacted)


def skip_downgrade(text: str) -> bool:
    """True when a reviewer bot withholds approval only because its review
    could not run.

    A not-approving comment whose stated reason is a skipped review run (for
    example a usage limit) and which carries no findings of its own is a
    user-triage item, not a code blocker. Any residual blocking language keeps
    it blocking.
    """
    if not REVIEW_SKIP_RE.search(text):
        return False
    remainder = NOT_APPROVING_RE.sub("", text)
    remainder = REVIEW_SKIP_RE.sub("", remainder)
    return not has_blocking_text(remainder)


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
    hydrated["reviews"] = fetch_pull_request_reviews(repo, number)
    inline_comments = fetch_unresolved_review_comments(repo, number)
    return human_stop_state(hydrated, inline_comments, config)
