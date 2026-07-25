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
- HUMAN-authored threads are NEVER touched. Only threads whose participants are
  all Bots (GraphQL `__typename == "Bot"`, or the structural `*[bot]` App-login
  suffix) are eligible; a human thread is always skipped + reported. Bot identity
  comes only from API-provided signals -- no hardcoded login list to go stale.
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
from typing import Any, cast

from babysit_classify import is_bot
from babysit_gh import fetch_review_threads, gh_capture, parse_repo_number
from babysit_util import configure_stdio, dig, is_json_object


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


def project_thread(record: dict[str, Any]) -> dict[str, object]:
    """Map one shared-paginator record to this CLI's thread shape.

    Inspects EVERY fetched participant -- not just the first comment -- so a
    bot-started thread with a human reply is not mistaken for a pure-bot thread.
    `botOnly` and `lastCommentUpdatedAt` fail closed (False / None) when a
    comment page is undisclosed (`comments_truncated`), since a human reply or
    an edit could be hiding beyond the fetched page.
    """
    comments = cast(list[Any], record.get("comments") or [])
    truncated = bool(record.get("comments_truncated"))
    first_author = _comment_author(comments[0]) if comments else {}
    bot_only = (
        bool(comments)
        and not truncated
        and all(
            is_bot(
                _comment_author(c).get("login"),
                _comment_author(c).get("__typename"),
            )
            for c in comments
        )
    )
    total_count = record.get("comments_total_count")
    return {
        "id": record.get("id"),
        "isResolved": record.get("isResolved", False),
        "isOutdated": record.get("isOutdated", False),
        "author": first_author.get("login"),
        "authorType": first_author.get("__typename"),
        "botOnly": bot_only,
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
    }


def fetch_threads(repo: str, number: int) -> list[dict[str, object]]:
    # include_resolved so the caller can see (and skip) already-resolved threads;
    # comments_first=100 to inspect every participant for the bot-only test.
    return [
        cast(dict[str, object], record)
        for record in fetch_review_threads(
            repo,
            number,
            include_resolved=True,
            comments_first=100,
            projection=project_thread,
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


def classify(
    thread: dict[str, object],
    *,
    autonomous: bool,
    only_outdated: bool,
    include_human: bool = False,
) -> str:
    """Deterministic action label under the active guards."""
    if thread["isResolved"]:
        return "skipped-already-resolved"
    if not thread["botOnly"] and not include_human:
        # bright line: never touch a thread with any human participant (checked
        # across all comments, not just the first), unless autopilot opts in
        return "skipped-human-thread"
    if (autonomous or only_outdated) and not thread["isOutdated"]:
        # unattended: require a deterministic "addressed" signal so the worker
        # cannot resolve a still-current finding and self-satisfy the merge gate
        return "skipped-not-outdated"
    return "eligible"


def parse_allowed_owners(raw: str | None) -> set[str]:
    if not raw:
        return set()
    return {part.strip().casefold() for part in raw.split(",") if part.strip()}


def main() -> int:
    configure_stdio()
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

    try:
        threads = fetch_threads(repo, number)
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
        )
        entry: dict[str, object] = {
            "id": thread["id"],
            "author": thread["author"],
            "authorType": thread["authorType"],
            "path": thread["path"],
            "isOutdated": thread["isOutdated"],
            "botOnly": thread["botOnly"],
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
        stale_pin = (
            args.resolve and args.thread_id and (count_stale or last_updated_stale)
        )
        if verdict != "eligible":
            entry["action"] = verdict
        elif stale_pin:
            entry["action"] = "refused-stale-pin"
            if args.expected_comment_count is not None:
                entry["expectedCommentCount"] = args.expected_comment_count
            if args.expected_last_updated is not None:
                entry["expectedLastUpdated"] = args.expected_last_updated
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
                "mode": "autonomous" if args.autonomous else "explicit",
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
                        if not is_bot(r["author"], r["authorType"])
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
