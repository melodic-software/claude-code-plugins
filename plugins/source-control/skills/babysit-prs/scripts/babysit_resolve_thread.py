#!/usr/bin/env python3
"""Guarded resolver for BOT-authored review threads on babysit PRs.

Narrow, self-validating privileged helper -- the resolve counterpart to
`babysit_merge.py`. It grants exactly one capability, "resolve a bot review
thread," instead of a broad `gh api graphql` allow rule, and it enforces only
DETERMINISTIC guards. Every judgment that needs reasoning -- is this finding
security-sensitive, is it genuinely addressed, should it be resolved or
escalated -- stays with the evaluating agent, which vets threads and either
passes a specific `--thread-id` or restricts to the mechanical outdated set.

Deterministic guards encoded here:

- Owner must be in the caller-supplied `--allowed-owners` allowlist; an empty or
  missing allowlist hard-refuses (fail closed).
- HUMAN-authored threads are NEVER touched, and neither are the caller's OWN.
  Eligibility requires BOTH that the thread's OPENING comment is a Bot's (GraphQL
  `__typename == "Bot"`, or the structural `*[bot]` App-login suffix) -- a thread
  belongs to whoever opened it, and replying into it never changes that -- AND
  that every other fetched participant is a Bot too; a human thread is always
  skipped + reported. Bot identity comes from API-provided signals, with no
  hardcoded login list to go stale -- the sole exception is
  `--extra-bot-logins`, the operator-supplied logins
  (`babysit_extra_bot_logins`) for bot accounts structural detection cannot see
  (a plain `User` with no `[bot]` suffix). Those logins are treated as bots for
  eligibility, so a login named there that is actually a human's account makes
  that human's threads resolvable -- the flag is a deliberate operator opt-in,
  not a heuristic, and omitting it instead classifies a configured bot's threads
  as human.
- Default action is READ-ONLY: list eligible/ineligible threads and what WOULD
  happen. Nothing is resolved without `--resolve`.
- `--autonomous` is the UNATTENDED-worker guard: a self-resolved thread would
  otherwise satisfy the merge gate's "zero unresolved threads" predicate -- the
  actor signing its own permission slip. It requires the one deterministic
  "addressed" signal GitHub exposes, `isOutdated` (the referenced code changed
  since the finding), so the worker cannot resolve a still-current finding. It
  additionally REFUSES to bulk-resolve: a `--resolve` in `--autonomous` mode must
  carry a single pinned `--thread-id` (with its `--expected-comment-count` and
  `--expected-last-updated` pins), turning the call into a per-thread vetted loop.
  Those pins enforce comment-state ONLY: they refuse a thread whose comment count
  or latest comment-edit timestamp drifted after it was vetted (a reply added or a
  comment edited between vetting and execution). They do NOT catch displacement -- a
  worker's own push flips `isOutdated` to `true` without touching a comment, so both
  pins still match and such a thread is still resolved even though the push only
  moved the finding's anchored lines rather than addressing it. Keeping a
  displacement-outdated thread unresolved therefore rests on agent discipline (the
  pre-push-outdated rule in `reference/orchestration.md`), not on this guard; the
  machine-enforced displacement fix is tracked in #571. `--allow-unpinned-thread`
  is likewise refused in `--autonomous` mode -- there is no unpinned autonomous
  resolve.
- `--autonomous` additionally refuses any thread whose fetched comments carry
  a forbidden-class severity marker: a structured P0/P1 marker (shields badge
  `/badge/P0-` or `/badge/P1-`, or bracketed `[P0]` / `[P1]`), the word CRITICAL,
  or the word "security" in any case. Prose that merely *mentions* P0/P1 does not
  count — the morning-brief sweep adopted the same structured-marker rule after
  misclassifying P2 threads whose bodies discussed P1 properties (#1939).
  The permission grants that cover this helper state "never a security or P1
  thread" as an absolute condition; this guard is the code behind that
  sentence for the unattended path, and it is deliberately narrower than the
  shared P0-P3 vocabulary -- advisory P2/P3 threads are exactly what the
  worker is documented to resolve once outdated, so a wider guard would
  self-block the merge gate on its own advisory threads. It fails closed: a
  thread whose comment page is truncated cannot prove the absence of a marker
  and is refused the same way. Interactive modes are unaffected -- severity
  judgment there stays with the evaluating agent.
- `--independent-resolver` is a THIRD mode, parallel to `--autonomous` and not a
  relaxation of it. `--autonomous`'s `isOutdated` requirement is right about the
  merging worker, but `isOutdated` means "the referenced code moved" -- on a prose
  or documentation PR a finding is usually addressed by rewriting elsewhere in the
  file, so the anchor never moves, the finding is genuinely addressed, and the
  guard refuses. That leaves an autonomous prose lane with no sanctioned route to
  zero unresolved threads. This mode replaces `isOutdated` with two other
  properties: INDEPENDENCE (the caller is a fresh context that is not the merging
  worker and did not author the fix -- the actor resolving is not the actor whose
  permission slip it is) and validated DISPOSITION EVIDENCE. Independence is a
  property of the dispatch, not something this script can verify, which is exactly
  why the evidence half is machine-checked here. Everything else `--autonomous`
  guards stays: bot-authored threads only, a single pinned `--thread-id` with both
  TOCTOU pins (bulk refused, `--allow-unpinned-thread` refused), and the
  severity bright line -- this is still an unattended path, so "never a security or
  P1 thread" still holds. `--include-human` is refused too: widening authorship and
  dropping `isOutdated` in the same call is the combination nothing would guard.
  `--disposition` names one of three claims and its matching evidence flag, and the
  script validates the evidence AGAINST THE WORLD rather than trusting the claim:
  `fixed` + `--fix-commit <sha>` (must be reachable from the PR's head commit),
  `deferred` + `--tracker-item <id>` (must exist and be open), `incorrect` +
  `--counter-evidence <text>` (must appear in a reply already on the thread,
  posted by someone other than the thread's OPENER, so the finding's own author
  cannot supply the words that rebut it).
  Missing, unparsable, or unverifiable evidence REFUSES the resolve rather than
  warning: refusing leaves the thread unresolved, which is the recoverable
  direction, while a suppressed finding is not. A refusal names WHICH answer it
  got: only a confirmed HTTP 404 reports the evidence-specific refusal, while
  every other operational failure reports `refused-evidence-unverifiable`, so an
  outage is never read as a caller lying about its evidence. Evidence is validated
  in list mode too, so a dry run proves the evidence instead of merely predicting
  the resolve.
- Because one `--disposition` is a claim about ONE finding while resolution clears
  the WHOLE thread, this mode additionally refuses a thread carrying more than one
  source finding (`skipped-multi-finding-thread`). Resolving it on a single
  evidence tuple would drop the thread's other, unaddressed findings out of the
  readiness denominator and let the merge gate pass over them. The count fails
  closed: a truncated comment page could hide another finding, so an unknown count
  refuses too.
- `--only-outdated` independently restricts to `isOutdated` threads in any mode.
- `--thread-id` operates on one agent-vetted thread. Combined with `--resolve`,
  it requires `--expected-comment-count` AND `--expected-last-updated` to pin
  the comment count and the latest comment-edit timestamp observed when the
  thread was vetted -- a TOCTOU re-vetting guard mirroring
  `babysit_merge.py`'s `--expected-head`. The live thread is re-fetched at
  execution time regardless of how long ago it was vetted, so a stale pin would
  let a reply added after vetting but before execution be silently swept in.
  `--expected-comment-count` alone only catches a NEW reply; it stays unchanged
  when a reviewer instead EDITS an already-vetted comment, so
  `--expected-last-updated` independently pins the latest `updatedAt` among the
  thread's fetched comments, closing that gap. Either live value drifting from
  its pin refuses that thread's resolve; `--allow-unpinned-thread` overrides for
  interactive-only use. Either pin flag without `--thread-id` is a usage error.
- `--include-human` is the autopilot power-user opt-in: it lifts the bot-only
  bright line so human and AI-review threads are also eligible. It is OFF by
  default (safe and worker modes never touch human threads), and the caller
  owns the judgment that each finding is genuinely addressed before resolving.
- `--self-logins` neutralizes the CALLER'S OWN posting identity for the
  bot-only test. The worker replies to a bot thread under its own login (a
  classification reply, a `Fixed in <sha>` follow-up) before ever resolving
  it, and that reply is a real API comment like any other -- so without this
  flag it makes the thread's `botOnly` computation false the moment it posts,
  the same as a genuine third-party human joining the thread. `botOnly` false
  falls out of the default bot-only scope, `--include-human` is unset by
  default (by design: worker/safe modes must never touch a genuine human
  thread), and nothing lifts it back in -- the thread is then stranded outside
  BOTH resolution scopes forever, even though replying was exactly the correct,
  documented action. `--self-logins` (comma-separated; `@me` resolves to your
  `gh` login, matching `babysit_merge.py`'s `--self-logins`) marks the caller's
  own logins as neutral rather than bot or human -- neutral as a REPLY only.
  The thread's OPENING comment must still be an ACTUAL bot's for `botOnly`, so
  a thread the caller itself opened is never misclassified as a bot thread
  just because a bot later replied to it (the canonical rule in
  `reference/review-discipline.md` forbids resolving your own threads); what
  the flag changes is only that a self-authored reply UNDER a bot opener no
  longer counts against it. The same flag also protects the `--autonomous`
  severity guard above: the mandated classification-reply table
  (`reference/review-discipline.md`)
  restates the source finding's own severity marker as one of its columns, so
  fixing `botOnly` alone would just re-strand the thread under
  `skipped-severity-marked` the first time it reaches that guard. A
  self-authored comment therefore has its classification-table rows (not the
  whole body) stripped before the severity scan, mirroring
  `babysit_classify.count_findings`'s identical rule for the finding-count
  gate; non-table self content still flags. It ships empty, so an
  unconfigured caller's classification is unchanged.

This helper only resolves bot threads. It cannot merge, reply, comment, dismiss
reviews, force-push, touch human threads, or judge a finding's severity.

Exit codes: 0 ok (list mode, or `--resolve` with at least one thread actually
resolved), 10 `--resolve` requested but zero threads were resolved (skipped,
refused-stale-pin, or resolve-failed), 2 usage/runtime error, 3 owner out of
scope (or no allowlist). Always parse the JSON `action` field per thread and the
summary counts; never treat exit 0 alone as proof a specific thread resolved.
Output is a single JSON object on stdout.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from typing import Any, cast

from babysit_classify import (
    is_bot,
    is_self_login,
    normalize_self_logins,
    severity_occurrences,
    strip_classification_rows,
)
from babysit_gh import (
    GITHUB_OWNER_RE,
    GITHUB_REPOSITORY_RE,
    fetch_review_threads,
    gh_capture,
    parse_repo_number,
    resolve_authors,
)
from babysit_util import configure_stdio, dig, is_json_object


# Deterministic proxies for "a security or P1 thread" — deliberately NARROWER
# than the shared P0-P3 vocabulary in babysit_classify: the permission grants
# forbid the unattended path only for security/P1-class findings, while
# advisory P2/P3 threads are exactly what the worker is documented to resolve
# once outdated (reference/orchestration.md), so a P0-P3-wide guard would
# permanently self-block the merge gate on its own advisory threads. The word
# "security" is matched as prose (the shared vocabulary ignores prose words to
# avoid false READINESS counts, but the grant names it); uppercase CRITICAL is
# the word-form of the same forbidden class. A false positive only routes the
# thread to interactive judgment.
# Structured P0/P1 markers only — shields badge (/badge/P0- or /badge/P1-) or
# bracketed [P0]/[P1] — not bare prose mentions such as "P1/P4 defect" in a P2
# thread's body (#1939). Vetted `--resolve --thread-id` mode applies no severity
# screen; it trusts the calling agent's vetting. That asymmetry is intentional.
FORBIDDEN_P01_BADGE_RE = re.compile(r"/badge/P[01]-")
FORBIDDEN_P01_BRACKET_RE = re.compile(r"\[P[01]\]")
SEVERITY_BLOCK_WORD_RE = re.compile(r"\bCRITICAL\b")
SECURITY_TEXT_RE = re.compile(r"security", re.IGNORECASE)


def _has_severity_marker(body: str) -> bool:
    """True for the forbidden class only: structured P0/P1 markers (badge or
    bracket), the word CRITICAL, or the word "security"."""
    return (
        bool(FORBIDDEN_P01_BADGE_RE.search(body))
        or bool(FORBIDDEN_P01_BRACKET_RE.search(body))
        or bool(SEVERITY_BLOCK_WORD_RE.search(body))
        or bool(SECURITY_TEXT_RE.search(body))
    )


def _comment_author(comment: object) -> dict[str, object]:
    author: Any = (comment.get("author") if is_json_object(comment) else None) or {}
    return author if is_json_object(author) else {}


def _latest_comment_update(comments: list[Any]) -> str | None:
    """Max `updatedAt` among the fetched comment nodes. GitHub returns these as
    fixed-width RFC3339 UTC timestamps, so plain string `max()` orders them
    chronologically. `updatedAt` moves on any edit to a comment's body -- unlike
    the comment count, which only reacts to a NEW reply -- so this is the signal
    that catches an EXISTING already-vetted comment being edited after the pin."""
    values = [
        updated_at
        for c in comments
        if is_json_object(c) and isinstance(updated_at := c.get("updatedAt"), str)
    ]
    return max(values) if values else None


def project_thread(
    record: dict[str, Any],
    *,
    extra_bot_logins: frozenset[str] = frozenset(),
    self_logins: frozenset[str] = frozenset(),
) -> dict[str, object]:
    """Map one shared-paginator record to this CLI's thread shape.

    `botOnly` is TWO conditions, both required. The OPENING comment must be
    bot-authored -- the canonical rule (`reference/review-discipline.md` D7.5)
    scopes resolution to bot-opened threads and forbids resolving a human's or
    one's OWN thread, and a thread's author is the author of the comment that
    opened it, which replying into never changes. AND every remaining fetched
    participant must be a bot or a configured self-login, so a bot-started
    thread a third-party human joined is not mistaken for a pure-bot thread.
    The opener test is the same one `humanThreadsActed` applies (#512), so both
    `is_bot` call sites agree on what makes a thread a bot's; a "some
    participant is a bot" test would not, admitting a SELF-opened thread the
    moment a bot replied to it. `comments[0]` is the opener: the shared
    paginator requests the comment connection ascending, and anything past the
    fetched window sets `comments_truncated` rather than displacing the first
    node. `botOnly` and `lastCommentUpdatedAt` fail closed (False / None) when
    a comment page is undisclosed (`comments_truncated`), since a human reply
    or an edit could be hiding beyond the fetched page; `botOnly` likewise
    fails closed when there is no opening comment to attribute at all (no
    fetched comments, or an opener whose author the API withheld, e.g. a
    deleted account). `extra_bot_logins` extends structural bot detection the
    same way it does everywhere else `is_bot` is called (e.g. `actor_kind` in
    `babysit_classify.py`); it ships empty, so an unconfigured caller still
    relies on structure alone.

    `self_logins` (the caller's own posting identities) is the third
    admissible authorship alongside bot and third-party human, and it is
    admissible only as a REPLY: a comment authored by a configured self-login
    does not disqualify a bot-opened thread (unlike a genuine human reply),
    but neither can it open one (unlike a bot comment). Without this, a
    worker's own reply to a bot thread -- posted under its own login, exactly
    like `orchestration.md`'s documented classification-reply / `Fixed in
    <sha>` flow -- would flip `botOnly` false the moment it posts, stranding
    the thread outside both resolution scopes (`botOnly` false locks out the
    default path; `--include-human` stays unset by design in worker/safe
    modes, so nothing lifts it back in) even though replying was the correct
    action. It ships empty, so an unconfigured caller's classification is
    unchanged.
    """
    comments = cast(list[Any], record.get("comments") or [])
    truncated = bool(record.get("comments_truncated"))
    first_author = _comment_author(comments[0]) if comments else {}

    def _author_is_bot(comment: object) -> bool:
        author = _comment_author(comment)
        return is_bot(author.get("login"), author.get("__typename"), extra_bot_logins)

    def _author_is_self(comment: object) -> bool:
        return is_self_login(_comment_author(comment).get("login"), self_logins)

    bot_only = (
        not truncated
        and bool(comments)
        and _author_is_bot(comments[0])
        and all(_author_is_bot(c) or _author_is_self(c) for c in comments)
    )
    total_count = record.get("comments_total_count")

    def _severity_scan_body(comment: object) -> str | None:
        body = comment.get("body") if is_json_object(comment) else None
        if not isinstance(body, str):
            return None
        if _author_is_self(comment):
            # The mandated classification reply (review-discipline.md) restates
            # the source finding's own severity marker as one of its table
            # columns -- scanning a self-reply raw would re-trip this guard on
            # the worker's own echo, stranding the thread again right after
            # `bot_only` above stopped treating that same reply as a
            # disqualifying human participant. Stripping only the
            # classification-table rows (not the whole body) mirrors
            # `babysit_classify.count_findings`: non-table self content -- a
            # maintainer using a self-login to raise a genuine new finding --
            # still flags.
            return strip_classification_rows(body)
        return body

    # Fail closed on truncation: an unfetched comment could carry the marker,
    # so a truncated thread is treated as severity-flagged, not as clean.
    severity_flagged = truncated or any(
        (body := _severity_scan_body(c)) is not None and _has_severity_marker(body)
        for c in comments
    )

    # How many SOURCE findings this thread carries, over the same bodies the
    # severity scan reads -- so a self classification reply's table rows are
    # stripped here too and the worker's own echo of a finding is not counted a
    # second time. None means the count is unknown (a truncated comment page could
    # hide another finding), which the independent-resolver guard treats as
    # multi-finding rather than as one.
    finding_count = (
        None
        if truncated
        else sum(
            severity_occurrences(body)
            for c in comments
            if (body := _severity_scan_body(c)) is not None
        )
    )

    # The `incorrect` disposition is proven by counter-evidence someone POSTED IN
    # REPLY to the finding, and "someone" cannot be the finding's own author:
    # the opener is excluded, and so is every later reply under the OPENER'S
    # login. The mandated classification reply restates the finding's own text
    # (`reference/review-discipline.md`), so a finding bot that also replies on
    # its own thread would otherwise supply the very words asserted as the
    # rebuttal -- the finding rebutting itself. A DIFFERENT bot's reply, and the
    # caller's own reply under a self-login, both remain admissible: those are
    # the independent parties the disposition is about. An opener whose login the
    # API withheld cannot be excluded by identity, so no reply is admitted at
    # all (such a thread is already not `botOnly`).
    opener_login = first_author.get("login")
    opener_key = opener_login.casefold() if isinstance(opener_login, str) else None

    def _reply_body(comment: object) -> str | None:
        if opener_key is None or not is_json_object(comment):
            return None
        login = _comment_author(comment).get("login")
        if not isinstance(login, str) or login.casefold() == opener_key:
            return None
        body = comment.get("body")
        return body if isinstance(body, str) else None

    return {
        "id": record.get("id"),
        "isResolved": record.get("isResolved", False),
        "isOutdated": record.get("isOutdated", False),
        "author": first_author.get("login"),
        "authorType": first_author.get("__typename"),
        "botOnly": bot_only,
        "severityFlagged": severity_flagged,
        "findingCount": finding_count,
        # Live count of ALL comments (not just the fetched page) -- the TOCTOU
        # comparison signal, so a reply beyond the first fetched page is detected.
        "commentCount": total_count if isinstance(total_count, int) else None,
        # Latest comment-edit signal; None (fail closed) when a page is
        # undisclosed, since an edit could hide beyond page 1. None never matches
        # a real pinned timestamp, so the guard refuses rather than trusting an
        # incomplete view.
        "lastCommentUpdatedAt": None if truncated else _latest_comment_update(comments),
        "path": (
            comments[0].get("path")
            if comments and is_json_object(comments[0])
            else None
        ),
        "replyBodies": [
            body
            for c in comments[1:]
            if (body := _reply_body(c)) is not None
        ],
    }


def fetch_threads(
    repo: str,
    number: int,
    *,
    extra_bot_logins: frozenset[str] = frozenset(),
    self_logins: frozenset[str] = frozenset(),
) -> list[dict[str, object]]:
    # include_resolved so the caller can see (and skip) already-resolved threads;
    # comments_first=100 to inspect every participant for the bot-only test.
    def _project(record: dict[str, Any]) -> dict[str, object]:
        return project_thread(
            record, extra_bot_logins=extra_bot_logins, self_logins=self_logins
        )

    return [
        cast(dict[str, object], record)
        for record in fetch_review_threads(
            repo,
            number,
            include_resolved=True,
            comments_first=100,
            projection=_project,
        )
    ]


def resolve_thread(thread_id: str) -> tuple[bool, str]:
    mutation = (
        "mutation($id:ID!){resolveReviewThread(input:{threadId:$id})"
        "{thread{isResolved}}}"
    )
    proc = gh_capture(["api", "graphql", "-f", f"query={mutation}", "-f", f"id={thread_id}"])
    if proc.returncode != 0:
        return False, proc.stderr.strip()
    try:
        payload = json.loads(proc.stdout or "null")
    except json.JSONDecodeError as exc:
        return False, f"unexpected response: {exc}"
    ok = dig(payload, "data", "resolveReviewThread", "thread", "isResolved")
    return bool(ok), ""


def _is_single_finding(thread: dict[str, object]) -> bool:
    """True only when the thread provably carries at most ONE source finding.

    Fails closed on an absent or non-integer `findingCount`: the projection
    reports None when a truncated comment page could be hiding another finding,
    and an unknown count is not evidence of one. A thread with NO severity marker
    at all counts as one unmarked finding, which is the common shape -- most
    reviewers mark severity once per comment, or not at all.
    """
    count = thread.get("findingCount")
    return isinstance(count, int) and count <= 1


def classify(
    thread: dict[str, object],
    *,
    autonomous: bool,
    only_outdated: bool,
    include_human: bool = False,
    independent: bool = False,
) -> str:
    """Deterministic action label under the active guards.

    `independent` is the third mode's classifier half: it drops ONLY the
    `isOutdated` requirement, which the mode replaces with caller independence
    plus validated disposition evidence (validated in `main`, not here -- this
    function stays a pure function of the projected thread). Every other guard
    is retained deliberately: the bot-only bright line, and the severity bright
    line, because an independent resolver is still an unattended path and the
    permission grants' "never a security or P1 thread" is unconditional.
    """
    if thread["isResolved"]:
        return "skipped-already-resolved"
    if not thread["botOnly"] and not include_human:
        # bright line: never touch a thread unless a bot OPENED it and every
        # other participant is a bot too (checked across all comments, not just
        # the first), unless autopilot opts in
        return "skipped-human-thread"
    if (autonomous or only_outdated) and not thread["isOutdated"]:
        # unattended: require a deterministic "addressed" signal so the worker
        # cannot resolve a still-current finding and self-satisfy the merge gate
        return "skipped-not-outdated"
    if (autonomous or independent) and thread.get("severityFlagged", True):
        # unattended: never a security or P1 thread. Default True fails closed
        # when the projection did not compute the signal.
        return "skipped-severity-marked"
    if independent and not _is_single_finding(thread):
        # Resolution is a THREAD-level act while a disposition is a claim about ONE
        # finding, so a thread carrying several findings cannot be cleared on one
        # evidence tuple: `resolveReviewThread` drops every comment the thread
        # carries out of the readiness denominator
        # (`babysit_classify.thread_is_open`), so evidence for finding A would
        # suppress an unaddressed finding B and let the merge gate pass over it.
        # D7.5 (`reference/review-discipline.md`) states the same rule as a
        # property of the whole thread: every finding extracted from it needs its
        # own recorded disposition. This mode validates exactly one, so a
        # multi-finding thread is refused and escalates instead.
        #
        # Scoped to `independent` alone: `--autonomous`'s addressed signal is
        # `isOutdated`, which GitHub computes for the thread as a whole rather
        # than per finding, so there is no per-finding claim there to under-cover.
        return "skipped-multi-finding-thread"
    return "eligible"


# A disposition is admissible only with its own evidence flag, and only that
# flag -- the pairing is what makes the claim checkable, so a caller cannot
# assert `fixed` and hand over a tracker id.
DISPOSITION_EVIDENCE: dict[str, str] = {
    "fixed": "--fix-commit",
    "deferred": "--tracker-item",
    "incorrect": "--counter-evidence",
}

FIX_COMMIT_RE = re.compile(r"\A[0-9a-fA-F]{7,40}\Z")
# `gh api` reports the HTTP status in its stderr message, e.g.
# `gh: Not Found (HTTP 404)` (verified against gh 2.95.0). The exit code alone is
# 1 for every failure, so this is the only signal that separates "the world
# answered no" from "the world could not be reached".
GH_HTTP_STATUS_RE = re.compile(r"\(HTTP (\d{3})\)")


def gh_http_status(proc: subprocess.CompletedProcess[str]) -> int | None:
    """The HTTP status `gh` reported, or None when it reported none.

    None covers every operational failure that never reached an HTTP response --
    a timeout, an unreachable API, an expired credential, a `gh` that failed
    before dispatching -- and callers must treat it as "unverifiable", never as a
    negative answer. The LAST status in the stream wins: a retried request prints
    one line per attempt, and the final one is the outcome.

    This parses another tool's message text, so it is deliberately unparsable-safe
    rather than robust: if `gh` ever reformats or localizes that string, every
    failure returns None and every caller degrades to "unverifiable". That is the
    recoverable direction, so the coupling costs accuracy on a format change and
    never correctness.
    """
    matches = GH_HTTP_STATUS_RE.findall(proc.stderr or "")
    return int(matches[-1]) if matches else None
# owner/repo#N, #N, or a bare N (bare and #N default to the PR's own repo).
TRACKER_ITEM_RE = re.compile(
    r"\A(?:(?P<repo>[A-Za-z0-9._-]+/[A-Za-z0-9._-]+)#|#)?(?P<number>[0-9]+)\Z"
)


def verify_fix_commit(repo: str, number: int, sha: str) -> tuple[bool, str]:
    """True when `sha` is reachable from the PR's CURRENT head commit.

    Reachability, not existence: a SHA that exists somewhere in the repository
    (another branch, an abandoned attempt) is not evidence that this PR carries
    the fix. The comparison runs against the HEAD repository, which differs from
    the base repository on a fork PR, so resolving it from the PR rather than
    assuming `repo` is what makes the check work cross-fork.

    Returns (verified, refusal_action). The refusal action distinguishes "the
    world says no" from "the world could not be consulted" -- both refuse, but
    conflating them would report an API outage as a caller lying about a fix.
    """
    proc = gh_capture(
        [
            "pr",
            "view",
            str(number),
            "--repo",
            repo,
            "--json",
            "headRefOid,headRepository,headRepositoryOwner",
        ]
    )
    if proc.returncode != 0:
        return False, "refused-evidence-unverifiable"
    try:
        payload = json.loads(proc.stdout or "null")
    except json.JSONDecodeError:
        return False, "refused-evidence-unverifiable"
    head_oid = dig(payload, "headRefOid")
    head_name = dig(payload, "headRepository", "name")
    head_owner = dig(payload, "headRepositoryOwner", "login")
    if not (
        isinstance(head_oid, str)
        and isinstance(head_name, str)
        and isinstance(head_owner, str)
    ):
        return False, "refused-evidence-unverifiable"
    # Every segment interpolated into the compare path is FORMAT-VALIDATED first,
    # matching `babysit_gh.fetch_blocked_base_compare`'s rule for the identical
    # call shape. Two of the three arrive in an API response body, so "the API
    # said so" is their only provenance: a crafted or compromised response
    # carrying path syntax would otherwise redirect this request to an
    # unintended endpoint. `sha` is validated here too rather than resting on
    # `main`'s argument check, so the function's own contract holds for every
    # caller.
    if not (
        GITHUB_OWNER_RE.fullmatch(head_owner)
        and GITHUB_REPOSITORY_RE.fullmatch(head_name)
        and head_name not in {".", ".."}
        and FIX_COMMIT_RE.match(head_oid)
        and FIX_COMMIT_RE.match(sha)
    ):
        return False, "refused-evidence-unverifiable"

    compare = gh_capture(
        ["api", f"repos/{head_owner}/{head_name}/compare/{sha}...{head_oid}"]
    )
    if compare.returncode != 0:
        # A SHA absent from the head repository 404s here -- the world answering
        # "no such commit", which is a not-on-head refusal. Every OTHER failure
        # (403, 5xx, rate limit, timeout, no HTTP response at all) is the world
        # being unreachable, and reporting that as a not-on-head answer would send
        # the caller off to replace evidence that may be perfectly valid instead
        # of retrying the outage.
        return False, (
            "refused-fix-commit-not-on-head"
            if gh_http_status(compare) == 404
            else "refused-evidence-unverifiable"
        )
    try:
        result = json.loads(compare.stdout or "null")
    except json.JSONDecodeError:
        return False, "refused-evidence-unverifiable"
    status = dig(result, "status")
    behind_by = dig(result, "behind_by")
    # base=sha, head=head_oid: `identical` or `ahead` both mean head_oid
    # descends from sha with no divergence, i.e. sha IS in the head branch's
    # history. `behind_by == 0` restates that from the other side, so a
    # `diverged`/`behind` result cannot slip through on status alone.
    if status in ("identical", "ahead") and behind_by == 0:
        return True, ""
    return False, "refused-fix-commit-not-on-head"


def verify_tracker_item(default_repo: str, token: str) -> tuple[bool, str]:
    """True when the named tracker item exists and is OPEN.

    An item that is already closed is not a deferral -- it is a claim that the
    follow-up is filed pointing at work nobody will do, which is
    indistinguishable from suppressing the finding.
    """
    match = TRACKER_ITEM_RE.match(token.strip())
    if not match:
        return False, "refused-tracker-item-not-found"
    repo = match.group("repo") or default_repo
    # `TRACKER_ITEM_RE` admits an owner/repo SHAPE, not a valid one: its character
    # class allows a leading dot and a bare dot-dot, so a repository component of
    # `..` builds a `repos/<owner>/../issues/<n>` path that normalizes to something
    # that was never a GitHub endpoint. The same format validation
    # `verify_fix_commit` applies to the analogous compare URL therefore applies
    # here, so the refusal names the malformed reference rather than reporting a
    # lookup miss for an item nobody ever looked up. Applied to the RESOLVED repo,
    # which costs nothing on the `default_repo` path (already validated by
    # `parse_repo_number`) and keeps one rule instead of two.
    owner, _, name = repo.partition("/")
    if not (
        GITHUB_OWNER_RE.fullmatch(owner)
        and GITHUB_REPOSITORY_RE.fullmatch(name)
        and name not in {".", ".."}
    ):
        return False, "refused-evidence-unverifiable"
    proc = gh_capture(["api", f"repos/{repo}/issues/{match.group('number')}"])
    if proc.returncode != 0:
        # Only a confirmed 404 means the item is not there. A 403 on an issues
        # endpoint is a permission answer, not a lookup miss, and a 5xx or a
        # timeout is no answer at all -- telling the caller to fix a reference
        # that does not exist while the API is merely unavailable is exactly what
        # `refused-evidence-unverifiable` exists to prevent.
        return False, (
            "refused-tracker-item-not-found"
            if gh_http_status(proc) == 404
            else "refused-evidence-unverifiable"
        )
    try:
        payload = json.loads(proc.stdout or "null")
    except json.JSONDecodeError:
        return False, "refused-evidence-unverifiable"
    state = dig(payload, "state")
    if state == "open":
        return True, ""
    if isinstance(state, str):
        return False, "refused-tracker-item-not-open"
    return False, "refused-tracker-item-not-found"


def verify_counter_evidence(thread: dict[str, object], text: str) -> tuple[bool, str]:
    """True when `text` appears in a reply already posted on the thread.

    The evidence must be ON the thread, not merely asserted on the command line:
    the point of the `incorrect` disposition is that the rebuttal is visible to
    whoever reads the thread later. Case-insensitive substring, because the
    caller is quoting a fragment of a reply it did not necessarily author.
    """
    needle = text.strip().casefold()
    if not needle:
        return False, "refused-counter-evidence-not-found"
    replies = thread.get("replyBodies")
    if not isinstance(replies, list):
        return False, "refused-counter-evidence-not-found"
    if any(isinstance(body, str) and needle in body.casefold() for body in replies):
        return True, ""
    return False, "refused-counter-evidence-not-found"


def verify_disposition(
    thread: dict[str, object],
    *,
    repo: str,
    number: int,
    disposition: str,
    fix_commit: str | None,
    tracker_item: str | None,
    counter_evidence: str | None,
) -> tuple[bool, str]:
    """Dispatch to the validator for the claimed disposition.

    Every disposition is named explicitly and the fallthrough REFUSES: a
    disposition added to `DISPOSITION_EVIDENCE` without a validator here would
    otherwise reach whichever branch happened to be last and be reported as
    validated by a check that never looked at its evidence.
    """
    if disposition == "fixed":
        return verify_fix_commit(repo, number, str(fix_commit))
    if disposition == "deferred":
        return verify_tracker_item(repo, str(tracker_item))
    if disposition == "incorrect":
        return verify_counter_evidence(thread, str(counter_evidence))
    return False, "refused-evidence-unverifiable"


def parse_allowed_owners(raw: str | None) -> set[str]:
    if not raw:
        return set()
    return {part.strip().casefold() for part in raw.split(",") if part.strip()}


def parse_extra_bot_logins(raw: str | None) -> frozenset[str]:
    if not raw:
        return frozenset()
    return frozenset(part.strip() for part in raw.split(",") if part.strip())


def main() -> int:
    configure_stdio()
    # allow_abbrev=False: the permission grants covering this helper state
    # their conditions as the literal presence or absence of a flag in the
    # command text. Prefix abbreviation (argparse's default) lets `--i` resolve
    # to --include-human while the text contains neither, so the written
    # command and the resolved behavior diverge -- exactly what those
    # conditions must be able to rule out.
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument("pr", help="owner/repo#number or PR URL")
    parser.add_argument(
        "--allowed-owners",
        default=None,
        help="comma-separated owners the helper may act under (required; empty refuses)",
    )
    parser.add_argument(
        "--resolve",
        action="store_true",
        help="actually resolve eligible bot threads; default lists only",
    )
    parser.add_argument(
        "--autonomous",
        action="store_true",
        help="unattended-worker guard: resolve only outdated bot threads",
    )
    parser.add_argument(
        "--independent-resolver",
        action="store_true",
        help=(
            "third mode: a fresh non-merging context resolves ONE pinned bot "
            "thread on validated disposition evidence instead of isOutdated; "
            "requires --disposition and its matching evidence flag"
        ),
    )
    parser.add_argument(
        "--disposition",
        choices=sorted(DISPOSITION_EVIDENCE),
        default=None,
        help=(
            "the claim being made about the finding, for --independent-resolver: "
            "fixed (--fix-commit), deferred (--tracker-item), or incorrect "
            "(--counter-evidence). The script validates the evidence against the "
            "world, not the claim"
        ),
    )
    parser.add_argument(
        "--fix-commit",
        default=None,
        help=(
            "evidence for --disposition fixed: a commit SHA (7-40 hex) that must "
            "be reachable from the PR's current head commit"
        ),
    )
    parser.add_argument(
        "--tracker-item",
        default=None,
        help=(
            "evidence for --disposition deferred: owner/repo#N, #N, or N for the "
            "filed follow-up, which must exist and still be open"
        ),
    )
    parser.add_argument(
        "--counter-evidence",
        default=None,
        help=(
            "evidence for --disposition incorrect: text that must already appear "
            "in a reply on the thread, so the rebuttal is visible where the "
            "finding is"
        ),
    )
    parser.add_argument(
        "--only-outdated",
        action="store_true",
        help="restrict to threads GitHub marks isOutdated (code changed since)",
    )
    parser.add_argument(
        "--thread-id", default=None, help="operate on a single agent-vetted thread id"
    )
    parser.add_argument(
        "--expected-comment-count",
        type=int,
        default=None,
        help=(
            "TOCTOU re-vetting guard: require the --thread-id target's live "
            "comment count to still equal this value before resolving; required "
            "with --resolve --thread-id unless --allow-unpinned-thread is passed"
        ),
    )
    parser.add_argument(
        "--expected-last-updated",
        default=None,
        help=(
            "TOCTOU re-vetting guard: require the --thread-id target's live "
            "latest comment-edit timestamp to still equal this value before "
            "resolving; catches an EXISTING comment being edited after vetting, "
            "which --expected-comment-count alone cannot; required with "
            "--resolve --thread-id unless --allow-unpinned-thread is passed"
        ),
    )
    parser.add_argument(
        "--allow-unpinned-thread",
        action="store_true",
        help=(
            "permit --resolve --thread-id without --expected-comment-count and "
            "--expected-last-updated (interactive only)"
        ),
    )
    parser.add_argument(
        "--include-human",
        action="store_true",
        help=(
            "autopilot power-user opt-in: also resolve human/AI-review threads "
            "(lifts the default bot-only bright line). The caller owns the "
            "judgment that each finding is addressed."
        ),
    )
    parser.add_argument(
        "--extra-bot-logins",
        default=None,
        help=(
            "Comma-separated logins to treat as bots when structural detection "
            "cannot classify them (ships empty)."
        ),
    )
    parser.add_argument(
        "--self-logins",
        default=None,
        help=(
            "comma-separated logins treated as the caller's OWN posting "
            "identity for the bot-only test, so a reply the worker itself "
            "posts to a bot thread does not flip botOnly false and strand "
            "the thread outside every resolution scope; '@me' resolves to "
            "your gh login (ships empty)"
        ),
    )
    args = parser.parse_args()

    extra_bot_logins = parse_extra_bot_logins(args.extra_bot_logins)
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

    if args.expected_comment_count is not None and not args.thread_id:
        print(
            json.dumps(
                {
                    "pr": args.pr,
                    "error": (
                        "--expected-comment-count requires --thread-id -- a count "
                        "pin with no thread id to pin it to would silently fall "
                        "through to resolving every eligible thread instead of refusing"
                    ),
                }
            )
        )
        return 2

    if args.expected_last_updated is not None and not args.thread_id:
        print(
            json.dumps(
                {
                    "pr": args.pr,
                    "error": (
                        "--expected-last-updated requires --thread-id -- a "
                        "last-updated pin with no thread id to pin it to would "
                        "silently fall through to resolving every eligible thread"
                    ),
                }
            )
        )
        return 2

    def _usage_error(message: str) -> int:
        print(json.dumps({"pr": args.pr, "error": message}))
        return 2

    evidence_args: dict[str, str | None] = {
        "--fix-commit": args.fix_commit,
        "--tracker-item": args.tracker_item,
        "--counter-evidence": args.counter_evidence,
    }

    if not args.independent_resolver:
        # Evidence flags outside the mode that consumes them would be accepted
        # and ignored, which reads to the caller like the evidence was checked.
        stray = [flag for flag, value in evidence_args.items() if value is not None]
        if args.disposition is not None:
            stray.insert(0, "--disposition")
        if stray:
            return _usage_error(
                f"{', '.join(stray)} requires --independent-resolver -- these are "
                "the third mode's evidence contract, and accepting them in a mode "
                "that never validates them would silently report an unchecked "
                "claim as a checked one"
            )
    else:
        conflicting = [
            flag
            for flag, enabled in (
                ("--autonomous", args.autonomous),
                ("--include-human", args.include_human),
                ("--allow-unpinned-thread", args.allow_unpinned_thread),
            )
            if enabled
        ]
        if conflicting:
            return _usage_error(
                f"--independent-resolver is refused with {', '.join(conflicting)}. "
                "It is a parallel mode, never a relaxation: --autonomous is the "
                "merging worker's own guard and cannot also be the independent "
                "one, --include-human would widen authorship in the same call "
                "that drops the isOutdated requirement, and there is no unpinned "
                "unattended resolve"
            )
        if args.disposition is None:
            return _usage_error(
                "--independent-resolver requires --disposition "
                f"{{{','.join(sorted(DISPOSITION_EVIDENCE))}}} -- the mode "
                "resolves on validated evidence, and an unnamed disposition has "
                "no evidence to validate"
            )
        if not args.thread_id:
            return _usage_error(
                "--independent-resolver requires a single pinned --thread-id; "
                "bulk is refused. Evidence is a claim about ONE finding, so a "
                "bulk call would apply one thread's evidence to every thread"
            )
        required_flag = DISPOSITION_EVIDENCE[args.disposition]
        if evidence_args[required_flag] is None:
            return _usage_error(
                f"--disposition {args.disposition} requires {required_flag}; "
                "missing evidence refuses rather than resolving unproven"
            )
        surplus = [
            flag
            for flag, value in evidence_args.items()
            if value is not None and flag != required_flag
        ]
        if surplus:
            return _usage_error(
                f"--disposition {args.disposition} accepts only {required_flag}; "
                f"remove {', '.join(surplus)}. Evidence is paired to its claim so "
                "the script validates what was actually asserted"
            )
        if args.fix_commit is not None and not FIX_COMMIT_RE.match(args.fix_commit.strip()):
            return _usage_error(
                f"--fix-commit {args.fix_commit!r} is not a 7-40 character hex "
                "commit SHA; an unparsable SHA is refused, never looked up"
            )
        if args.tracker_item is not None and not TRACKER_ITEM_RE.match(
            args.tracker_item.strip()
        ):
            return _usage_error(
                f"--tracker-item {args.tracker_item!r} is not owner/repo#N, #N, "
                "or N; an unparsable item id is refused, never looked up"
            )

    if args.resolve and args.autonomous and not args.thread_id:
        print(
            json.dumps(
                {
                    "pr": args.pr,
                    "error": (
                        "--autonomous --resolve requires a single pinned "
                        "--thread-id (with --expected-comment-count and "
                        "--expected-last-updated); an unattended worker may not "
                        "bulk-resolve. A worker's own push marks a thread "
                        "isOutdated, so the bulk autonomous path would clear "
                        "threads that changed since they were vetted with no proof "
                        "the finding was addressed. Resolve each vetted thread "
                        "individually as a per-thread pinned loop instead"
                    ),
                }
            )
        )
        return 2

    if args.resolve and args.autonomous and args.allow_unpinned_thread:
        print(
            json.dumps(
                {
                    "pr": args.pr,
                    "error": (
                        "--allow-unpinned-thread is refused in --autonomous mode; "
                        "there is no unpinned autonomous resolve. An unattended "
                        "worker must pin every --thread-id resolve with "
                        "--expected-comment-count and --expected-last-updated. "
                        "--allow-unpinned-thread is an interactive-only override"
                    ),
                }
            )
        )
        return 2

    if args.resolve and args.thread_id and not args.allow_unpinned_thread:
        missing = [
            flag
            for flag, value in (
                ("--expected-comment-count", args.expected_comment_count),
                ("--expected-last-updated", args.expected_last_updated),
            )
            if value is None
        ]
        if missing:
            print(
                json.dumps(
                    {
                        "pr": args.pr,
                        "error": (
                            "--resolve --thread-id requires both "
                            "--expected-comment-count and --expected-last-updated "
                            "to pin the comment count and latest comment-edit "
                            "timestamp observed when the thread was vetted; "
                            f"missing: {', '.join(missing)}; pass "
                            "--allow-unpinned-thread to override interactively"
                        ),
                    }
                )
            )
            return 2

    owner = repo.split("/", 1)[0]
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

    # Resolve self logins only after the owner-scope refusal above: '@me'
    # resolution is a network call, mirroring babysit_merge.py's ordering, so
    # an out-of-scope owner refuses with no gh invocation at all.
    try:
        self_logins = normalize_self_logins(resolve_authors(args.self_logins))
    except RuntimeError:
        # '@me' could not be resolved to a gh login; fail closed by keeping
        # only the explicit non-'@me' logins -- an unresolved self identity
        # is simply not recognized as self, so a comment under it is judged a
        # third-party human same as before this flag existed, never silently
        # trusted as self on a guessed identity.
        self_logins = normalize_self_logins(
            token
            for token in (args.self_logins or "").split(",")
            if token.strip().casefold() != "@me"
        )

    try:
        threads = fetch_threads(
            repo, number, extra_bot_logins=extra_bot_logins, self_logins=self_logins
        )
    except (RuntimeError, ValueError, json.JSONDecodeError) as exc:
        print(json.dumps({"pr": args.pr, "error": f"{type(exc).__name__}: {exc}"}))
        return 2

    results: list[dict[str, object]] = []
    for thread in threads:
        if args.thread_id and thread["id"] != args.thread_id:
            continue
        verdict = classify(
            thread,
            autonomous=args.autonomous,
            only_outdated=args.only_outdated,
            include_human=args.include_human,
            independent=args.independent_resolver,
        )
        entry: dict[str, object] = {
            "id": thread["id"],
            "author": thread["author"],
            "authorType": thread["authorType"],
            "path": thread["path"],
            "isOutdated": thread["isOutdated"],
            "botOnly": thread["botOnly"],
            "severityFlagged": thread.get("severityFlagged"),
            "findingCount": thread.get("findingCount"),
            "commentCount": thread.get("commentCount"),
            "lastCommentUpdatedAt": thread.get("lastCommentUpdatedAt"),
        }
        count_stale = (
            args.expected_comment_count is not None
            and thread.get("commentCount") != args.expected_comment_count
        )
        last_updated_stale = (
            args.expected_last_updated is not None
            and thread.get("lastCommentUpdatedAt") != args.expected_last_updated
        )
        # Evaluated in list mode too, not only under --resolve. A dry run whose
        # pins have already drifted would otherwise report would-resolve for a
        # thread the very next --resolve refuses, making the prediction wrong in
        # the one direction that matters. Both pin flags already require
        # --thread-id (a usage error otherwise), so the pin has a target whenever
        # either comparison can be true.
        stale_pin = count_stale or last_updated_stale
        evidence_refusal = ""
        if verdict == "eligible" and not stale_pin and args.independent_resolver:
            # Validate in list mode too: a dry run of an evidence-gated mode that
            # skipped validation would report would-resolve for evidence the
            # world rejects, which is the one answer this mode exists to prevent.
            verified, evidence_refusal = verify_disposition(
                thread,
                repo=repo,
                number=number,
                disposition=args.disposition,
                fix_commit=args.fix_commit,
                tracker_item=args.tracker_item,
                counter_evidence=args.counter_evidence,
            )
            if verified:
                evidence_refusal = ""
                entry["disposition"] = args.disposition
        if verdict != "eligible":
            entry["action"] = verdict
        elif stale_pin:
            entry["action"] = "refused-stale-pin"
            if args.expected_comment_count is not None:
                entry["expectedCommentCount"] = args.expected_comment_count
            if args.expected_last_updated is not None:
                entry["expectedLastUpdated"] = args.expected_last_updated
        elif evidence_refusal:
            entry["action"] = evidence_refusal
            entry["disposition"] = args.disposition
        elif not args.resolve:
            entry["action"] = "would-resolve"
        else:
            ok, err = resolve_thread(str(thread["id"]))
            entry["action"] = "resolved" if ok else "resolve-failed"
            if err:
                entry["error"] = err
        results.append(entry)

    resolved_count = len([r for r in results if r["action"] == "resolved"])

    print(
        json.dumps(
            {
                "pr": f"{repo}#{number}",
                "mode": (
                    "autonomous"
                    if args.autonomous
                    else "independent-resolver"
                    if args.independent_resolver
                    else "explicit"
                ),
                "disposition": args.disposition,
                "action": "resolve" if args.resolve else "list",
                "onlyOutdated": args.only_outdated,
                "includeHuman": args.include_human,
                # Count only threads whose OPENING author is human. `botOnly`
                # (every comment in the thread is a bot) is the wrong gate: a
                # bot-opened thread carrying a later human reply is `botOnly:
                # false` yet was never a human's thread, so counting it here
                # reported a human-thread action that never happened (#512). The
                # opening-author test matches the `--include-human` eligibility
                # decision, via the shared `is_bot` authorship classifier.
                "humanThreadsActed": len(
                    [
                        r
                        for r in results
                        if not is_bot(r["author"], r["authorType"], extra_bot_logins)
                        and r["action"] in ("would-resolve", "resolved")
                    ]
                ),
                "eligibleCount": len(
                    [r for r in results if r["action"] in ("would-resolve", "resolved")]
                ),
                "resolvedCount": resolved_count,
                "skippedNotOutdated": len(
                    [r for r in results if r["action"] == "skipped-not-outdated"]
                ),
                "skippedSeverityMarked": len(
                    [r for r in results if r["action"] == "skipped-severity-marked"]
                ),
                "skippedMultiFinding": len(
                    [r for r in results if r["action"] == "skipped-multi-finding-thread"]
                ),
                # Independent-resolver refusals, rolled up alongside the other
                # skip counters so a caller sees "the evidence did not hold"
                # without re-deriving it from the per-thread action values.
                "refusedEvidence": len(
                    [
                        r
                        for r in results
                        if isinstance(r["action"], str)
                        and cast(str, r["action"]).startswith("refused-")
                        and r["action"] != "refused-stale-pin"
                    ]
                ),
                "humanThreads": len(
                    [r for r in results if r["action"] == "skipped-human-thread"]
                ),
                "threads": results,
            },
            indent=2,
        )
    )
    if args.resolve and resolved_count == 0:
        return 10
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
