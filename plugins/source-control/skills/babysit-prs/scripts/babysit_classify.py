#!/usr/bin/env python3
"""Shared authorship / finding / approval classifier for the babysit engine.

Single source of truth extracted per issue #534. Every babysit surface that
must agree on "who authored this", "is this a live finding", and "is this an
approval" consumes these primitives instead of hand-rolling its own copy:
`babysit_feedback` (snapshot bot/human feedback bucketing), `babysit_delta` and
`babysit_merge` (self-login self-exemption), `babysit_resolve_thread` (opening
author typing), and `babysit-readiness-gate.sh` (finding decomposition counting,
via the `babysit_findings.py` entrypoint). Divergence among those surfaces was
the six-issue misclassification class this module exists to close.

Leaf module: it depends only on `babysit_util`, never on the surfaces that
import it, so the dependency graph stays acyclic.

Three concern areas:

* Authorship (self / bot / human): `is_bot`, `actor_kind`, `normalize_login_set`,
  self-login normalization/membership, and the dependency-manager author test.
* Finding (severity occurrence + lifetime-vs-open state): the blocking-text and
  structured-severity heuristics, and the finding/classification counting the
  readiness gate delegates here (`count_findings` discounts markers carried in a
  resolved or outdated thread, so a lifetime badge no longer inflates the count;
  `count_effective_classified` credits classifications per surface so a stale
  PR-level row cannot offset an open-thread finding).
* Approval verdict: the approval / non-approval / required-fix heuristics and the
  structural approval and review-skip downgrades.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any

from babysit_util import is_json_object

# --- Finding + approval heuristics -------------------------------------------

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


# --- Authorship: self / bot / human ------------------------------------------


def normalize_login_set(logins: Any) -> frozenset[str]:
    """Normalize a login collection for comparison: casefold, strip `[bot]`."""
    return frozenset(
        str(login).casefold().removesuffix("[bot]")
        for login in (logins or [])
        if str(login).strip()
    )


def normalize_self_logins(logins: Any) -> frozenset[str]:
    """Casefold a self-login collection for membership tests.

    Unlike `normalize_login_set` this preserves any `[bot]` suffix: the self set
    is matched against a comment's raw author login (which carries the suffix for
    a bot posting identity), so stripping it here would make a personal login and
    a same-stem bot login collide. Empty tokens are dropped so an unset config
    yields an empty set and every self-gated behavior stays dormant.
    """
    return frozenset(
        str(login).casefold() for login in (logins or []) if str(login).strip()
    )


def is_self_login(login: Any, normalized_self: frozenset[str]) -> bool:
    """True when `login` is one of the configured self identities (casefolded)."""
    return str(login or "").casefold() in normalized_self


def author_login(item: dict[str, Any]) -> str:
    author = item.get("author")
    if is_json_object(author):
        return str(author.get("login") or author.get("name") or "")
    return str(author or "")


def is_bot(
    login: object, typename: object, extra_bot_logins: Any = frozenset()
) -> bool:
    """Bot iff GitHub's authoritative actor type says so, the login carries the
    structural `[bot]` suffix every GitHub App bot account uses, or the login is
    one the caller explicitly named a bot.

    Both structural signals come from the API and cannot go stale; the
    `extra_bot_logins` fallback ships empty, so an unconfigured caller relies on
    structure alone.
    """
    if typename == "Bot":
        return True
    if not isinstance(login, str):
        return False
    if login.endswith("[bot]"):
        return True
    if not extra_bot_logins:
        return False
    return login.casefold().removesuffix("[bot]") in normalize_login_set(
        extra_bot_logins
    )


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
    login = author_login(item).casefold()
    return "bot" if is_bot(login, None, config.extra_bot_logins) else "human"


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


# --- Finding heuristics -------------------------------------------------------


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


# --- Approval verdict --------------------------------------------------------


def approval_downgrade(text: str) -> bool:
    """True when a reviewer bot states an explicit approval verdict.

    Requires a clear approval/non-blocking conclusion, no negated approval
    language, and neither a required-fix term nor a CRITICAL/IMPORTANT severity
    marker surviving negation redaction. Anything ambiguous -- and any genuine
    high-severity finding carried in an approval-verdict body that reaches this
    check -- stays blocking. A review submitted in the formal APPROVED/DISMISSED
    state is routed to `ignored` upstream, before this predicate; whether that
    short-circuit should be severity-scanned first is tracked as a follow-up in
    issue #621.
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
    user-triage item, not a code blocker. Any residual blocking language --
    imperative blocking text or a surviving CRITICAL/IMPORTANT severity marker
    -- keeps it blocking.
    """
    if not REVIEW_SKIP_RE.search(text):
        return False
    remainder = NOT_APPROVING_RE.sub("", text)
    remainder = REVIEW_SKIP_RE.sub("", remainder)
    return not has_blocking_text(remainder) and not has_blocking_severity(remainder)


# --- Finding decomposition counting (readiness gate) -------------------------
#
# The readiness gate (babysit-readiness-gate.sh) delegates its finding and
# classification counts here so the severity vocabulary is defined once, not
# re-implemented in bash grep. The bash script retains an equivalent grep
# fallback ONLY for the Python-free safe-tier degrade (loop.md is that path);
# the convergence test pins the two counts together on thread-state-free
# fixtures. See babysit_findings.py for the CLI entrypoint.

# Whole-word severity words (claude's vocabulary). Case-sensitive so lowercase
# priority labels (priority:p0-critical) and prose ("it is important") do not
# false-count -- the same rationale as BLOCKING_SEVERITY_RE, plus SUGGESTION.
SEVERITY_WORDS_RE = re.compile(r"\b(?:CRITICAL|IMPORTANT|SUGGESTION)\b")
# codex's shields.io P-severity badge: the `/badge/P{N}-` URL segment appears
# exactly once per finding (the badge's alt text carries the same P-number token
# a second time, so a bare `P[0-3]` would double-count). `/badge/P0-` never
# matches a lowercase priority:p0-critical label.
SEVERITY_BADGE_RE = re.compile(r"/badge/P[0-3]-")
# Plain bracketed P-severity markers ([P0]..[P3]) -- neither a severity word nor
# a shields badge. Bounded to the documented P0-P3 range so incidental [P4]+
# text cannot inflate the count into a false READINESS_BLOCKED.
SEVERITY_PLAIN_RE = re.compile(r"\[P[0-3]\]")
CLASSIFY_TOKEN_RE = re.compile(r"\b(?:VALID|INCORRECT|UNCERTAIN)\b")
# A classification table row: a markdown `|`-prefixed line carrying a
# classification token bounded by non-letters (so "INVALID" rows still count as
# source content, not classifications).
CLASSIFY_ROW_RE = re.compile(r"^[ \t]*\|.*[^A-Za-z](?:VALID|INCORRECT|UNCERTAIN)(?:[^A-Za-z]|$)")
PIPE_ROW_RE = re.compile(r"^[ \t]*\|")


def thread_is_open(comment: dict[str, Any]) -> bool:
    """False when a comment is carried in a resolved or outdated review thread.

    This is the lifetime-vs-open discriminator behind #465: a severity marker in
    a thread GitHub reports `isResolved` or `isOutdated` is a lifetime artifact
    of an already-addressed round, not a currently-open finding, so it must not
    inflate the denominator. A comment with neither field set (issue-level or
    review-summary comments, which are not review threads, and the bash-compatible
    fixture shape) counts -- there is nothing to discount.
    """
    return not (
        bool(comment.get("isResolved")) or bool(comment.get("isOutdated"))
    )


def is_thread_comment(comment: dict[str, Any]) -> bool:
    """True when a comment belongs to a review thread rather than the PR-level
    issue/review-summary surface.

    The surface a comment lives on -- not just its resolution state -- is
    load-bearing for classification credit (#642): a review thread can be
    resolved (its findings and their in-thread classifications drop together),
    while a PR-level comment never can, so a stale classification posted there
    would otherwise count forever. Two signals identify the surface, in order:

    * `in_review_thread` -- the explicit stamp the live entrypoint applies when a
      comment is fetched from a review thread (and a fixture sets directly). When
      present it is authoritative, so a live PR-level comment (stamped false) is
      never re-inferred as a thread.
    * `type == "inline"` -- the `fetch-all-pr-comments.sh` schema tag for an
      inline review comment (vs `general`/`review` for the two PR-level
      surfaces), honored on the `--comments-json` reuse path so it is
      surface-aware too: without it an inline finding and a detached PR-level
      classification share the non-thread bucket and the row cross-credits the
      finding -- the #642 fail-open, on the reuse path.

    Absent both (the bash-degrade shape and legacy `{author, body}` fixtures) a
    comment is treated as PR-level -- there is no surface signal to infer a
    thread from.
    """
    if "in_review_thread" in comment:
        return bool(comment["in_review_thread"])
    return comment.get("type") == "inline"


def _severity_occurrences(text: str) -> int:
    return (
        len(SEVERITY_WORDS_RE.findall(text))
        + len(SEVERITY_BADGE_RE.findall(text))
        + len(SEVERITY_PLAIN_RE.findall(text))
    )


def count_findings(
    comments: list[dict[str, Any]], self_logins: frozenset[str]
) -> int:
    """Count currently-open source-finding occurrences across every comment body.

    Ports the readiness gate's occurrence counting (one marker per finding, not
    per line, so a multi-finding line is not under-counted) with two rules the
    gate documents:

    * Self classification-table rows are excluded from the finding corpus so a
      reply row that repeats the source severity word does not mint a phantom
      finding. Non-table self content (a maintainer authoring a genuine source
      finding) still counts.
    * A marker carried in a resolved or outdated thread does not count
      (`thread_is_open`), the #465 lifetime-vs-open discount.
    """
    total = 0
    for comment in comments:
        if not is_json_object(comment) or not thread_is_open(comment):
            continue
        author = str(comment.get("author") or "")
        body = str(comment.get("body") or "")
        if is_self_login(author, self_logins):
            body = _strip_classification_rows(body)
        total += _severity_occurrences(body)
    return total


def _strip_classification_rows(body: str) -> str:
    return "\n".join(
        line for line in body.splitlines() if not CLASSIFY_ROW_RE.search(line)
    )


def count_classified(
    comments: list[dict[str, Any]], self_logins: frozenset[str]
) -> int:
    """Count classification table rows across self comment bodies.

    A classification is a markdown `|`-prefixed line carrying a
    VALID/INCORRECT/UNCERTAIN token, counted one per line so prose repetition
    never inflates the count. Only self authors' bodies contribute -- the
    classification reply is the self surface's mandated per-finding format.

    A classification carried in a resolved or outdated thread is a lifetime
    artifact of an already-addressed round (`thread_is_open`), mirroring
    `count_findings`'s discount -- otherwise a stale classification could keep
    inflating the denominator against a fresh, still-unclassified finding.
    """
    total = 0
    for comment in comments:
        if not is_json_object(comment) or not thread_is_open(comment):
            continue
        if not is_self_login(str(comment.get("author") or ""), self_logins):
            continue
        for line in str(comment.get("body") or "").splitlines():
            if PIPE_ROW_RE.search(line) and CLASSIFY_TOKEN_RE.search(line):
                total += 1
    return total


def count_effective_classified(
    comments: list[dict[str, Any]], self_logins: frozenset[str]
) -> int:
    """Classifications that effectively cover findings, credited per surface.

    The readiness gate blocks while findings outnumber their classifications. A
    raw global count lets a classification row on one surface offset a finding on
    another: a stale pipe-row in a PR-level (non-thread) comment -- which can
    never be thread-resolved -- would keep covering a finding raised fresh in an
    open review thread, a fail-open past a live unclassified finding (#642).

    Credit is therefore bucketed by surface (review-thread vs PR-level) and
    capped within each bucket -- a non-thread classification can only offset a
    non-thread finding, an open-thread classification only an open-thread
    finding. Resolved/outdated thread comments are already discounted by
    `thread_is_open` inside both counters, so they contribute to neither bucket.
    On thread-state-free input (every comment PR-level, the bash-degrade shape)
    the thread bucket is empty and this collapses to `min(classified, findings)`,
    keeping the Python count convergent with the bash degrade's own cap.
    """
    thread = [c for c in comments if is_json_object(c) and is_thread_comment(c)]
    non_thread = [
        c for c in comments if is_json_object(c) and not is_thread_comment(c)
    ]
    return _capped_credit(thread, self_logins) + _capped_credit(
        non_thread, self_logins
    )


def _capped_credit(
    comments: list[dict[str, Any]], self_logins: frozenset[str]
) -> int:
    return min(
        count_classified(comments, self_logins),
        count_findings(comments, self_logins),
    )
