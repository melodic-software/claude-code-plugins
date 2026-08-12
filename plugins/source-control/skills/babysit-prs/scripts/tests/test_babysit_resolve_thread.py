"""Resolve-thread reporting counters.

Golden regression for #512: `humanThreadsActed` must count only threads whose
OPENING author is human, gated through the shared `is_bot` authorship
classifier -- not `botOnly` (every comment is a bot), which mislabels a
bot-opened thread carrying a later human reply as a human-thread action that
never happened.

Golden regression for #637: both `is_bot` call sites -- `project_thread`'s
`botOnly` computation and the `humanThreadsActed` counter -- must thread the
caller's `extra_bot_logins` through, consistent with every other classifier
call site (e.g. `actor_kind` in `babysit_classify.py`). Before the fix, an
operator-registered non-structural bot account (no `[bot]` suffix, API
`__typename` reports `User`) was miscategorized at both sites.

Golden regression for the self-reply strands-the-thread bug (#1729): replying
to a bot thread under the caller's own login is the documented, correct
action (`orchestration.md`'s classification-reply / `Fixed in <sha>` flow) --
but that reply is a real API comment, so before `--self-logins` existed it
flipped `project_thread`'s `botOnly` false the moment it posted. `botOnly`
false locks the thread out of the default bot-only scope, `--include-human`
stays unset by design in worker/safe modes, and nothing lifted it back in: a
correctly handled bot thread was permanently unresolvable by the normal flow.
`--self-logins` neutralizes the caller's own posting identity for the
`botOnly` test so a self-reply no longer strands it -- and, since the mandated
classification-reply table restates the source finding's own severity marker,
the severity scan strips a self-authored comment's classification-table rows
(not its whole body) before scanning, so fixing `botOnly` does not just move
the stranding to `skipped-severity-marked` under `--autonomous`.

Golden regression for the converse hole that widening opened: neutralizing
self authorship must not make a SELF-OPENED thread `botOnly` the moment a bot
replies to it. `botOnly` therefore requires the thread's OPENING comment to be
bot-authored -- the canonical rule (`reference/review-discipline.md` D7.5:
resolve only bot-opened threads, never a human's, never your OWN) -- rather
than settling for a bot somewhere among participants who are otherwise all
self. Self authorship is admissible as a REPLY only. See
`BotOnlyRequiresABotOpener` for the full matrix.
"""

from __future__ import annotations

import contextlib
import io
import json
import pathlib
import subprocess
import sys
import unittest
from contextlib import redirect_stdout
from typing import cast
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_resolve_thread as rt


def _thread(
    thread_id: str,
    author: str,
    author_type: str,
    *,
    bot_only: bool,
    is_outdated: bool = False,
    severity_flagged: bool = False,
    last_updated: str | None = None,
    reply_bodies: list[str] | None = None,
    finding_count: int | None = 1,
) -> dict[str, object]:
    return {
        "id": thread_id,
        "author": author,
        "authorType": author_type,
        "path": "a.py",
        "isResolved": False,
        "isOutdated": is_outdated,
        "botOnly": bot_only,
        "severityFlagged": severity_flagged,
        "findingCount": finding_count,
        "commentCount": 2,
        "lastCommentUpdatedAt": last_updated,
        "replyBodies": list(reply_bodies or []),
    }


def _run(threads: list[dict[str, object]], argv: list[str]) -> dict[str, object]:
    buffer = io.StringIO()
    with contextlib.ExitStack() as stack:
        stack.enter_context(mock.patch.object(rt, "fetch_threads", return_value=threads))
        if "--autonomous" in argv or "--independent-resolver" in argv:
            stack.enter_context(
                mock.patch.object(
                    rt, "fetch_pull_request_author", return_value="someone-else"
                )
            )
        stack.enter_context(
            mock.patch.object(sys, "argv", ["babysit_resolve_thread.py", *argv])
        )
        stack.enter_context(redirect_stdout(buffer))
        rt.main()
    return json.loads(buffer.getvalue())


class HumanThreadsActedCounter(unittest.TestCase):
    def test_bot_opened_thread_with_human_reply_is_not_a_human_thread(self) -> None:
        # #512: authorType "Bot", botOnly False (a human replied). Eligible under
        # --include-human, so it is acted on -- but the OPENING author is a bot,
        # so it must not count toward humanThreadsActed.
        result = _run(
            [_thread("T_bot", "codex[bot]", "Bot", bot_only=False)],
            ["owner/repo#1", "--allowed-owners", "owner", "--include-human"],
        )
        self.assertEqual(result["eligibleCount"], 1)
        self.assertEqual(result["humanThreadsActed"], 0)

    def test_human_opened_thread_counts(self) -> None:
        result = _run(
            [_thread("T_human", "alice", "User", bot_only=False)],
            ["owner/repo#1", "--allowed-owners", "owner", "--include-human"],
        )
        self.assertEqual(result["eligibleCount"], 1)
        self.assertEqual(result["humanThreadsActed"], 1)

    def test_mixed_counts_only_the_human_opener(self) -> None:
        result = _run(
            [
                _thread("T_bot", "codex[bot]", "Bot", bot_only=False),
                _thread("T_human", "alice", "User", bot_only=False),
            ],
            ["owner/repo#1", "--allowed-owners", "owner", "--include-human"],
        )
        self.assertEqual(result["eligibleCount"], 2)
        self.assertEqual(result["humanThreadsActed"], 1)


def _comment(login: str, typename: str, body: str | None = None) -> dict[str, object]:
    comment: dict[str, object] = {"author": {"login": login, "__typename": typename}}
    if body is not None:
        comment["body"] = body
    return comment


class ProjectThreadExtraBotLogins(unittest.TestCase):
    """#637 site 1: `project_thread`'s `botOnly` computation (L117-120)."""

    def test_configured_login_is_bot_only(self) -> None:
        record = {
            "id": "T1",
            "comments": [_comment("svc-account", "User")],
            "comments_truncated": False,
        }
        projected = rt.project_thread(
            record, extra_bot_logins=frozenset({"svc-account"})
        )
        self.assertTrue(projected["botOnly"])

    def test_unconfigured_login_is_not_bot_only(self) -> None:
        # Same non-structural account, but the caller never registered it --
        # falls back to structural detection alone and is correctly a human
        # thread.
        record = {
            "id": "T1",
            "comments": [_comment("svc-account", "User")],
            "comments_truncated": False,
        }
        projected = rt.project_thread(record)
        self.assertFalse(projected["botOnly"])


class SelfLoginsNeutralizeOwnReply(unittest.TestCase):
    """Reproduces the self-reply-strands-the-thread bug and proves the fix.

    The worker's documented reply to a bot thread (a classification reply or a
    `Fixed in <sha>` follow-up, `orchestration.md`) posts under its own login --
    a real API comment. Before `--self-logins` existed, `project_thread` could
    not tell that comment apart from a genuine third-party human joining the
    thread: `botOnly` went false, which locks the thread out of the default
    bot-only scope, `--include-human` stays unset by design in worker/safe
    modes, and nothing lifted it back in -- a bot thread the worker correctly
    handled was permanently unresolvable by the normal flow.
    """

    def test_self_reply_flips_bot_only_off_without_self_logins(self) -> None:
        # The bug, pinned: absent --self-logins, the worker's own reply is
        # indistinguishable from a genuine human joining the thread.
        record = {
            "id": "T1",
            "comments": [_comment("codex[bot]", "Bot"), _comment("worker-bot", "User")],
            "comments_truncated": False,
        }
        self.assertFalse(rt.project_thread(record)["botOnly"])

    def test_self_logins_neutralizes_the_workers_own_reply(self) -> None:
        record = {
            "id": "T1",
            "comments": [_comment("codex[bot]", "Bot"), _comment("worker-bot", "User")],
            "comments_truncated": False,
        }
        projected = rt.project_thread(record, self_logins=frozenset({"worker-bot"}))
        self.assertTrue(projected["botOnly"])

    def test_self_only_thread_is_not_bot_only(self) -> None:
        # self_logins is neutral, not a bot substitute: a thread with no
        # ACTUAL bot participant is not botOnly just because every comment
        # happens to be self-authored.
        record = {
            "id": "T1",
            "comments": [_comment("worker-bot", "User")],
            "comments_truncated": False,
        }
        projected = rt.project_thread(record, self_logins=frozenset({"worker-bot"}))
        self.assertFalse(projected["botOnly"])

    def test_genuine_third_party_human_still_blocks_bot_only(self) -> None:
        # A configured self-login does not widen to "any non-bot" -- an actual
        # third party in the thread still disqualifies it.
        record = {
            "id": "T1",
            "comments": [
                _comment("codex[bot]", "Bot"),
                _comment("worker-bot", "User"),
                _comment("alice", "User"),
            ],
            "comments_truncated": False,
        }
        projected = rt.project_thread(record, self_logins=frozenset({"worker-bot"}))
        self.assertFalse(projected["botOnly"])

    def test_truncated_page_still_fails_closed_regardless_of_self_logins(self) -> None:
        # self_logins narrows WHICH non-bot authors are neutral; it must not
        # loosen the independent truncation guard, since an undisclosed page
        # could hide a genuine third-party human beyond it.
        record = {
            "id": "T1",
            "comments": [_comment("codex[bot]", "Bot")],
            "comments_truncated": True,
        }
        projected = rt.project_thread(record, self_logins=frozenset({"worker-bot"}))
        self.assertFalse(projected["botOnly"])

    def test_self_classification_reply_does_not_re_strand_under_autonomous(self) -> None:
        # The second half of the bug: fixing botOnly alone is not enough. The
        # mandated classification-reply table (review-discipline.md) restates
        # the source finding's own severity word as one of its columns, e.g.
        # "| 1 | CRITICAL | ... |" or "VALID -- not a security concern, fixed
        # in abc123" -- a raw severity scan over that self-reply would re-trip
        # skipped-severity-marked under --autonomous, stranding the thread
        # again under a different verdict right after self_logins recovered
        # botOnly. `self_logins` must also be threaded into the severity scan.
        record = {
            "id": "T1",
            "isResolved": False,
            "isOutdated": True,
            "comments": [
                _comment("codex[bot]", "Bot", "P2: rename this variable for clarity"),
                _comment(
                    "worker-bot",
                    "User",
                    "| 1 | CRITICAL | path.py:1 | rename | VALID -- fixing | 👍 |",
                ),
            ],
            "comments_truncated": False,
        }
        projected = rt.project_thread(record, self_logins=frozenset({"worker-bot"}))
        self.assertTrue(projected["botOnly"])
        self.assertFalse(projected["severityFlagged"])

    def test_self_non_table_prose_still_flags_severity(self) -> None:
        # Mirrors count_findings's own rule: stripping is scoped to
        # classification-TABLE rows, not to every self-authored body. A
        # self-login also used by a maintainer to raise a genuine new finding
        # in ordinary prose must still flag.
        record = {
            "id": "T1",
            "comments": [
                _comment("codex[bot]", "Bot", "Rename this variable."),
                _comment("worker-bot", "User", "CRITICAL: this also needs a fix"),
            ],
            "comments_truncated": False,
        }
        projected = rt.project_thread(record, self_logins=frozenset({"worker-bot"}))
        self.assertTrue(projected["severityFlagged"])

    def test_third_party_severity_still_flags_regardless_of_self_logins(self) -> None:
        # self_logins narrows which AUTHOR's body is stripped of table rows;
        # it must not narrow which bodies are scanned at all. A genuine bot
        # severity marker still flags even when a self-login is configured.
        record = {
            "id": "T1",
            "comments": [_comment("codex[bot]", "Bot", "CRITICAL: SQL injection")],
            "comments_truncated": False,
        }
        projected = rt.project_thread(record, self_logins=frozenset({"worker-bot"}))
        self.assertTrue(projected["severityFlagged"])

    def _raw_run(self, record: dict[str, object], argv: list[str]) -> dict[str, object]:
        # Mocks one level deeper than `_run`/`fetch_threads`, at the shared
        # paginator, so the REAL `project_thread` runs over the raw record --
        # exercising the CLI's `--self-logins` parsing together with the
        # classifier fix, not a pre-projected fixture that bypasses both.
        buffer = io.StringIO()
        with contextlib.ExitStack() as stack:
            stack.enter_context(
                mock.patch.object(
                    rt,
                    "fetch_review_threads",
                    side_effect=lambda repo, number, **kw: [kw["projection"](record)],
                )
            )
            if "--autonomous" in argv or "--independent-resolver" in argv:
                stack.enter_context(
                    mock.patch.object(
                        rt, "fetch_pull_request_author", return_value="someone-else"
                    )
                )
            stack.enter_context(
                mock.patch.object(sys, "argv", ["babysit_resolve_thread.py", *argv])
            )
            stack.enter_context(redirect_stdout(buffer))
            rt.main()
        return json.loads(buffer.getvalue())

    def test_end_to_end_self_reply_strands_the_thread_without_the_flag(self) -> None:
        record = {
            "id": "T1",
            "isResolved": False,
            "isOutdated": False,
            "comments": [_comment("codex[bot]", "Bot"), _comment("worker-bot", "User")],
            "comments_total_count": 2,
            "comments_truncated": False,
        }
        result = self._raw_run(record, ["owner/repo#1", "--allowed-owners", "owner"])
        self.assertEqual(result["threads"][0]["action"], "skipped-human-thread")
        self.assertEqual(result["eligibleCount"], 0)

    def test_end_to_end_self_logins_recovers_eligibility_without_include_human(
        self,
    ) -> None:
        record = {
            "id": "T1",
            "isResolved": False,
            "isOutdated": False,
            "comments": [_comment("codex[bot]", "Bot"), _comment("worker-bot", "User")],
            "comments_total_count": 2,
            "comments_truncated": False,
        }
        result = self._raw_run(
            record,
            ["owner/repo#1", "--allowed-owners", "owner", "--self-logins", "worker-bot"],
        )
        self.assertEqual(result["threads"][0]["action"], "would-resolve")
        self.assertEqual(result["eligibleCount"], 1)
        # Recovered through the default bot-only scope, not by widening it --
        # --include-human was never passed.
        self.assertFalse(result["includeHuman"])

    def test_end_to_end_autonomous_worker_tier_the_bug_actually_occurs_in(self) -> None:
        # The production combination: a worker-tier invocation
        # (--autonomous --only-outdated) against a pre-push-outdated bot
        # thread the worker already replied to with a classification table
        # that restates the source finding's severity. Both halves of the fix
        # -- botOnly and severityFlagged -- must hold together here, or the
        # thread is stranded under skipped-severity-marked instead.
        record = {
            "id": "T1",
            "isResolved": False,
            "isOutdated": True,
            "comments": [
                _comment("codex[bot]", "Bot", "P2: rename this variable for clarity"),
                _comment(
                    "worker-bot",
                    "User",
                    "| 1 | rename | VALID -- not a security concern, fixed in abc123 | 👍 |",
                ),
            ],
            "comments_total_count": 2,
            "comments_truncated": False,
        }
        result = self._raw_run(
            record,
            [
                "owner/repo#1",
                "--allowed-owners",
                "owner",
                "--self-logins",
                "worker-bot",
                "--autonomous",
                "--only-outdated",
            ],
        )
        self.assertEqual(result["threads"][0]["action"], "would-resolve")
        self.assertEqual(result["eligibleCount"], 1)


class BotOnlyRequiresABotOpener(unittest.TestCase):
    """`botOnly` demands a BOT-authored OPENING comment, not a bot anywhere.

    `review-discipline.md` D7.5 is the canonical policy: resolve ONLY threads
    whose OPENING comment is authored by a bot reviewer, never a human's
    thread, and never one of your OWN threads. A "some participant is a bot
    and none is a third-party human" test satisfies that rule for every
    bot-opened thread but ALSO admits a self-OPENED thread the moment a bot
    replies to it -- every comment is then bot or self, so the thread reports
    `botOnly` and becomes resolvable with no `--include-human`, and under
    `--autonomous` once outdated. The opening-author test is the same one
    `humanThreadsActed` has used since #512; both `is_bot` call sites now
    agree on what makes a thread a bot's.
    """

    def test_bot_opened_with_self_reply_is_bot_only(self) -> None:
        # The stranding fix this PR exists for: a self-reply UNDER a bot
        # opener must stay botOnly, or the thread falls out of every scope.
        record = {
            "id": "T1",
            "comments": [_comment("codex[bot]", "Bot"), _comment("worker-bot", "User")],
            "comments_truncated": False,
        }
        projected = rt.project_thread(record, self_logins=frozenset({"worker-bot"}))
        self.assertTrue(projected["botOnly"])

    def test_self_opened_with_bot_reply_is_not_bot_only(self) -> None:
        # The hole the opposite direction: the caller's own thread, joined by
        # a bot. Every comment is bot-or-self, but the thread is the caller's
        # OWN -- "NEVER resolve your OWN threads" (review-discipline.md D7.5).
        record = {
            "id": "T1",
            "comments": [_comment("worker-bot", "User"), _comment("codex[bot]", "Bot")],
            "comments_truncated": False,
        }
        projected = rt.project_thread(record, self_logins=frozenset({"worker-bot"}))
        self.assertFalse(projected["botOnly"])

    def test_bot_opened_with_third_party_human_reply_is_not_bot_only(self) -> None:
        # A bot opener is necessary, never sufficient: a genuine third party
        # anywhere in the thread still disqualifies it.
        record = {
            "id": "T1",
            "comments": [_comment("codex[bot]", "Bot"), _comment("alice", "User")],
            "comments_truncated": False,
        }
        projected = rt.project_thread(record, self_logins=frozenset({"worker-bot"}))
        self.assertFalse(projected["botOnly"])

    def test_bot_opened_alone_is_bot_only(self) -> None:
        record = {
            "id": "T1",
            "comments": [_comment("codex[bot]", "Bot")],
            "comments_truncated": False,
        }
        self.assertTrue(rt.project_thread(record)["botOnly"])

    def test_human_opened_with_bot_reply_is_not_bot_only(self) -> None:
        # The third-party form of the same shape, with no self-login involved.
        record = {
            "id": "T1",
            "comments": [_comment("alice", "User"), _comment("codex[bot]", "Bot")],
            "comments_truncated": False,
        }
        self.assertFalse(rt.project_thread(record)["botOnly"])

    def test_no_comments_is_not_bot_only(self) -> None:
        # Fail closed: with no opening comment there is nothing to prove a bot
        # authored it.
        record = {"id": "T1", "comments": [], "comments_truncated": False}
        self.assertFalse(rt.project_thread(record)["botOnly"])

    def test_opener_with_no_author_is_not_bot_only(self) -> None:
        # A deleted/ghost account leaves the opener's author null -- the
        # opening authorship is undeterminable, so it cannot be a bot's.
        record = {
            "id": "T1",
            "comments": [{"author": None}, _comment("codex[bot]", "Bot")],
            "comments_truncated": False,
        }
        self.assertFalse(rt.project_thread(record)["botOnly"])

    def test_truncated_page_is_not_bot_only_even_with_a_bot_opener(self) -> None:
        # Truncation stays an independent fail-closed guard on top of the
        # opener test: an undisclosed page could hide a third-party human.
        record = {
            "id": "T1",
            "comments": [_comment("codex[bot]", "Bot")],
            "comments_truncated": True,
        }
        self.assertFalse(rt.project_thread(record)["botOnly"])

    def test_end_to_end_self_opened_thread_is_skipped_under_autonomous(self) -> None:
        # The exploit path end to end, through the REAL projection: an
        # outdated self-opened thread with a bot reply, under the worker
        # tier's own flags, must be refused without --include-human.
        buffer = io.StringIO()
        record = {
            "id": "T1",
            "isResolved": False,
            "isOutdated": True,
            "comments": [
                _comment("worker-bot", "User", "Should we rename this?"),
                _comment("codex[bot]", "Bot", "Agreed, renaming reads better."),
            ],
            "comments_total_count": 2,
            "comments_truncated": False,
        }
        with (
            mock.patch.object(
                rt,
                "fetch_review_threads",
                side_effect=lambda repo, number, **kw: [kw["projection"](record)],
            ),
            mock.patch.object(
                rt, "fetch_pull_request_author", return_value="someone-else"
            ),
            mock.patch.object(
                sys,
                "argv",
                [
                    "babysit_resolve_thread.py",
                    "owner/repo#1",
                    "--allowed-owners",
                    "owner",
                    "--self-logins",
                    "worker-bot",
                    "--autonomous",
                    "--only-outdated",
                ],
            ),
            redirect_stdout(buffer),
        ):
            rt.main()
        result = json.loads(buffer.getvalue())
        self.assertFalse(result["threads"][0]["botOnly"])
        self.assertEqual(result["threads"][0]["action"], "skipped-human-thread")
        self.assertEqual(result["eligibleCount"], 0)


class HumanThreadsActedExtraBotLogins(unittest.TestCase):
    """#637 site 2: the `humanThreadsActed` counter's `is_bot` call (L477)."""

    def test_configured_login_excluded_from_human_count(self) -> None:
        # A non-structural bot account, pre-classified botOnly=True (as
        # project_thread would produce once site 1 is fixed) so it is
        # eligible without --include-human. With --extra-bot-logins naming
        # it, the opening-author is_bot check must also recognize it as a
        # bot and exclude it from humanThreadsActed.
        result = _run(
            [_thread("T1", "svc-account", "User", bot_only=True)],
            ["owner/repo#1", "--allowed-owners", "owner", "--extra-bot-logins", "svc-account"],
        )
        self.assertEqual(result["eligibleCount"], 1)
        self.assertEqual(result["humanThreadsActed"], 0)

    def test_unconfigured_login_counts_as_human(self) -> None:
        # Same account, but the caller never registered it -- the counter
        # falls back to structural detection alone and correctly counts it.
        result = _run(
            [_thread("T1", "svc-account", "User", bot_only=True)],
            ["owner/repo#1", "--allowed-owners", "owner"],
        )
        self.assertEqual(result["eligibleCount"], 1)
        self.assertEqual(result["humanThreadsActed"], 1)


class AutonomousSeverityGuard(unittest.TestCase):
    def test_own_pr_is_refused_in_autonomous_mode(self) -> None:
        with (
            mock.patch.object(rt, "fetch_threads") as fetch_threads,
            mock.patch.object(
                rt, "fetch_pull_request_author", return_value="worker-bot"
            ),
            mock.patch.object(
                sys,
                "argv",
                [
                    "babysit_resolve_thread.py",
                    "owner/repo#1",
                    "--allowed-owners",
                    "owner",
                    "--self-logins",
                    "worker-bot",
                    "--autonomous",
                ],
            ),
            redirect_stdout(io.StringIO()) as buffer,
        ):
            code = rt.main()
        fetch_threads.assert_not_called()
        result = json.loads(buffer.getvalue())
        self.assertTrue(result["skippedOwnPr"])
        self.assertEqual(result["prAuthor"], "worker-bot")
        self.assertEqual(code, 0)

    def test_own_pr_resolve_exits_2(self) -> None:
        with (
            mock.patch.object(rt, "fetch_threads") as fetch_threads,
            mock.patch.object(
                rt, "fetch_pull_request_author", return_value="worker-bot"
            ),
            mock.patch.object(
                sys,
                "argv",
                [
                    "babysit_resolve_thread.py",
                    "owner/repo#1",
                    "--allowed-owners",
                    "owner",
                    "--self-logins",
                    "worker-bot",
                    "--autonomous",
                    "--resolve",
                    "--thread-id",
                    "T1",
                    "--expected-comment-count",
                    "2",
                    "--expected-last-updated",
                    "2026-01-01T00:00:00Z",
                ],
            ),
            redirect_stdout(io.StringIO()) as buffer,
        ):
            code = rt.main()
        fetch_threads.assert_not_called()
        result = json.loads(buffer.getvalue())
        self.assertTrue(result["skippedOwnPr"])
        self.assertEqual(code, 2)

    def test_non_self_pr_author_proceeds_in_autonomous_mode(self) -> None:
        with mock.patch.object(
            rt, "fetch_pull_request_author", return_value="someone-else"
        ):
            result = _run(
                [_thread("T_ok", "codex[bot]", "Bot", bot_only=True, is_outdated=True)],
                [
                    "owner/repo#1",
                    "--allowed-owners",
                    "owner",
                    "--self-logins",
                    "worker-bot",
                    "--autonomous",
                ],
            )
        self.assertEqual(result["threads"][0]["action"], "would-resolve")

    def test_severity_marked_thread_is_skipped_in_autonomous_mode(self) -> None:
        result = _run(
            [
                _thread(
                    "T_sev",
                    "codex[bot]",
                    "Bot",
                    bot_only=True,
                    is_outdated=True,
                    severity_flagged=True,
                )
            ],
            ["owner/repo#1", "--allowed-owners", "owner", "--autonomous"],
        )
        self.assertEqual(result["threads"][0]["action"], "skipped-severity-marked")
        self.assertEqual(result["skippedSeverityMarked"], 1)
        self.assertEqual(result["eligibleCount"], 0)

    def test_clean_outdated_bot_thread_stays_eligible_in_autonomous_mode(self) -> None:
        result = _run(
            [_thread("T_ok", "codex[bot]", "Bot", bot_only=True, is_outdated=True)],
            ["owner/repo#1", "--allowed-owners", "owner", "--autonomous"],
        )
        self.assertEqual(result["threads"][0]["action"], "would-resolve")
        self.assertEqual(result["eligibleCount"], 1)

    def test_missing_severity_signal_fails_closed_in_autonomous_mode(self) -> None:
        thread = _thread("T_na", "codex[bot]", "Bot", bot_only=True, is_outdated=True)
        del thread["severityFlagged"]
        result = _run(
            [thread], ["owner/repo#1", "--allowed-owners", "owner", "--autonomous"]
        )
        self.assertEqual(result["threads"][0]["action"], "skipped-severity-marked")

    def test_severity_marked_thread_stays_eligible_interactively(self) -> None:
        # Interactive judgment stays with the evaluating agent; the guard is an
        # unattended-mode bright line, not a new capability restriction.
        result = _run(
            [_thread("T_sev", "codex[bot]", "Bot", bot_only=True, severity_flagged=True)],
            ["owner/repo#1", "--allowed-owners", "owner"],
        )
        self.assertEqual(result["threads"][0]["action"], "would-resolve")


class SeverityProjection(unittest.TestCase):
    def _record(self, bodies: list[str], *, truncated: bool = False) -> dict[str, object]:
        return {
            "id": "T1",
            "isResolved": False,
            "isOutdated": True,
            "comments": [
                {
                    "author": {"login": "codex[bot]", "__typename": "Bot"},
                    "body": body,
                    "path": "a.py",
                    "updatedAt": "2026-01-01T00:00:00Z",
                }
                for body in bodies
            ],
            "comments_total_count": len(bodies),
            "comments_truncated": truncated,
        }

    def test_p1_badge_body_flags(self) -> None:
        record = self._record(["![P1 Badge](https://img.shields.io/badge/P1-orange)"])
        self.assertTrue(rt.project_thread(record)["severityFlagged"])

    def test_security_word_flags_case_insensitively(self) -> None:
        record = self._record(["This has a Security implication."])
        self.assertTrue(rt.project_thread(record)["severityFlagged"])

    def test_bracketed_p1_marker_flags(self) -> None:
        record = self._record(["[P1] Unvalidated redirect target"])
        self.assertTrue(rt.project_thread(record)["severityFlagged"])

    def test_bare_p1_prose_does_not_flag(self) -> None:
        record = self._record(["Discussing a P1/P4 defect class in prose"])
        self.assertFalse(rt.project_thread(record)["severityFlagged"])

    def test_p1_prefix_declarations_flag(self) -> None:
        for body in (
            "P1: this is a blocking regression",
            "P1 must fix",
            "p1: blocking regression",
        ):
            record = self._record([body])
            self.assertTrue(
                rt.project_thread(record)["severityFlagged"], body
            )

    def test_lowercase_bracketed_p1_flags(self) -> None:
        record = self._record(["[p1] lowercase marker"])
        self.assertTrue(rt.project_thread(record)["severityFlagged"])

    def test_advisory_p2_marker_does_not_flag(self) -> None:
        # The forbidden class is security/P0/P1 only: advisory P2/P3 threads
        # are exactly what the worker resolves once outdated, so flagging
        # them would self-block the merge gate on its own advisory threads.
        record = self._record(
            ["![P2 Badge](https://img.shields.io/badge/P2-yellow)", "[P3] nit"]
        )
        self.assertFalse(rt.project_thread(record)["severityFlagged"])

    def test_critical_marker_flags(self) -> None:
        record = self._record(["CRITICAL: guard defeated by prefix match"])
        self.assertTrue(rt.project_thread(record)["severityFlagged"])

    def test_plain_body_does_not_flag(self) -> None:
        record = self._record(["Rename this variable for clarity."])
        self.assertFalse(rt.project_thread(record)["severityFlagged"])

    def test_p1_substring_inside_word_does_not_flag(self) -> None:
        record = self._record(["See the AP1000 spec."])
        self.assertFalse(rt.project_thread(record)["severityFlagged"])

    def test_truncated_comment_page_fails_closed(self) -> None:
        record = self._record(["Rename this variable."], truncated=True)
        self.assertTrue(rt.project_thread(record)["severityFlagged"])


class NoAbbreviatedFlags(unittest.TestCase):
    def test_include_human_abbreviation_is_rejected(self) -> None:
        # The permission grants state conditions as literal flag text; an
        # abbreviation resolving to --include-human while the text lacks it
        # would let the written command and resolved behavior diverge.
        with (
            mock.patch.object(
                sys, "argv",
                ["babysit_resolve_thread.py", "owner/repo#1",
                 "--allowed-owners", "owner", "--i"],
            ),
            redirect_stdout(io.StringIO()),
            mock.patch("sys.stderr", new=io.StringIO()),
        ):
            with self.assertRaises(SystemExit) as ctx:
                rt.main()
        self.assertEqual(ctx.exception.code, 2)


PINNED_UPDATED = "2026-07-30T00:00:00Z"
HEAD_OID = "1111111111111111111111111111111111111111"
FIX_SHA = "abc1234"


def _proc(
    returncode: int, stdout: str = "", stderr: str = ""
) -> subprocess.CompletedProcess[str]:
    return subprocess.CompletedProcess(
        args=["gh"], returncode=returncode, stdout=stdout, stderr=stderr
    )


# The verbatim shapes `gh` writes to stderr (gh 2.95.0), because the HTTP status
# it carries is the only signal separating a negative answer from an outage.
GH_404 = "gh: Not Found (HTTP 404)\n"
GH_403 = "gh: Forbidden (HTTP 403)\n"
GH_500 = "gh: Internal Server Error (HTTP 500)\n"
GH_NO_RESPONSE = "error connecting to api.github.com\n"


def _pr_view_ok() -> subprocess.CompletedProcess[str]:
    return _proc(
        0,
        json.dumps(
            {
                "headRefOid": HEAD_OID,
                "headRepository": {"name": "repo"},
                "headRepositoryOwner": {"login": "owner"},
            }
        ),
    )


def _run_independent(
    threads: list[dict[str, object]],
    argv: list[str],
    *,
    gh_results: list[subprocess.CompletedProcess[str]] | None = None,
    resolve_ok: bool = True,
) -> tuple[int, dict[str, object]]:
    """Drive `main` with gh responses scripted in call order."""
    buffer = io.StringIO()
    with (
        mock.patch.object(rt, "fetch_threads", return_value=threads),
        mock.patch.object(
            rt, "fetch_pull_request_author", return_value="someone-else"
        ),
        mock.patch.object(rt, "gh_capture", side_effect=list(gh_results or [])),
        mock.patch.object(rt, "resolve_thread", return_value=(resolve_ok, "")),
        mock.patch.object(sys, "argv", ["babysit_resolve_thread.py", *argv]),
        redirect_stdout(buffer),
    ):
        code = rt.main()
    return code, json.loads(buffer.getvalue())


def _independent_argv(*evidence: str) -> list[str]:
    return [
        "owner/repo#1",
        "--allowed-owners",
        "owner",
        "--resolve",
        "--independent-resolver",
        "--thread-id",
        "T_bot",
        "--expected-comment-count",
        "2",
        "--expected-last-updated",
        PINNED_UPDATED,
        *evidence,
    ]


def _bot_thread(**kwargs: object) -> dict[str, object]:
    params: dict[str, object] = {
        "bot_only": True,
        "last_updated": PINNED_UPDATED,
    }
    params.update(kwargs)
    return _thread("T_bot", "codex[bot]", "Bot", **params)  # type: ignore[arg-type]


class IndependentResolverUsageGates(unittest.TestCase):
    """#1632: the third mode's argument contract, refused at exit 2.

    Every refusal here is a usage error rather than a silent narrowing: the
    mode's whole claim is that evidence was validated, so a call that cannot be
    validated must not be accepted and quietly downgraded.
    """

    def _usage(self, argv: list[str]) -> dict[str, object]:
        buffer = io.StringIO()
        with (
            mock.patch.object(sys, "argv", ["babysit_resolve_thread.py", *argv]),
            redirect_stdout(buffer),
        ):
            code = rt.main()
        self.assertEqual(code, 2)
        return json.loads(buffer.getvalue())

    def test_evidence_flag_without_the_mode_is_refused(self) -> None:
        payload = self._usage(
            ["owner/repo#1", "--allowed-owners", "owner", "--fix-commit", FIX_SHA]
        )
        self.assertIn("--independent-resolver", str(payload["error"]))

    def test_disposition_without_the_mode_is_refused(self) -> None:
        payload = self._usage(
            ["owner/repo#1", "--allowed-owners", "owner", "--disposition", "fixed"]
        )
        self.assertIn("--independent-resolver", str(payload["error"]))

    def test_autonomous_combination_is_refused(self) -> None:
        # The two modes answer for different actors; combining them would let the
        # merging worker wear the independent resolver's evidence exemption.
        payload = self._usage(
            [
                "owner/repo#1", "--allowed-owners", "owner",
                "--independent-resolver", "--autonomous",
            ]
        )
        self.assertIn("--autonomous", str(payload["error"]))

    def test_include_human_combination_is_refused(self) -> None:
        payload = self._usage(
            [
                "owner/repo#1", "--allowed-owners", "owner",
                "--independent-resolver", "--include-human",
            ]
        )
        self.assertIn("--include-human", str(payload["error"]))

    def test_allow_unpinned_thread_combination_is_refused(self) -> None:
        payload = self._usage(
            [
                "owner/repo#1", "--allowed-owners", "owner",
                "--independent-resolver", "--allow-unpinned-thread",
            ]
        )
        self.assertIn("--allow-unpinned-thread", str(payload["error"]))

    def test_missing_disposition_is_refused(self) -> None:
        payload = self._usage(
            ["owner/repo#1", "--allowed-owners", "owner", "--independent-resolver"]
        )
        self.assertIn("--disposition", str(payload["error"]))

    def test_bulk_is_refused_without_a_thread_id(self) -> None:
        payload = self._usage(
            [
                "owner/repo#1", "--allowed-owners", "owner",
                "--independent-resolver", "--disposition", "incorrect",
                "--counter-evidence", "the anchor is wrong",
            ]
        )
        self.assertIn("--thread-id", str(payload["error"]))

    def test_disposition_without_its_evidence_is_refused(self) -> None:
        payload = self._usage(
            [
                "owner/repo#1", "--allowed-owners", "owner",
                "--independent-resolver", "--disposition", "fixed",
                "--thread-id", "T_bot",
            ]
        )
        self.assertIn("--fix-commit", str(payload["error"]))

    def test_mismatched_evidence_flag_is_refused(self) -> None:
        # Asserting `fixed` while handing over a tracker id would have the
        # script validate something other than the claim being made.
        payload = self._usage(
            [
                "owner/repo#1", "--allowed-owners", "owner",
                "--independent-resolver", "--disposition", "fixed",
                "--thread-id", "T_bot",
                "--fix-commit", FIX_SHA, "--tracker-item", "#7",
            ]
        )
        self.assertIn("--tracker-item", str(payload["error"]))

    def test_unparsable_sha_is_refused_before_any_lookup(self) -> None:
        payload = self._usage(
            [
                "owner/repo#1", "--allowed-owners", "owner",
                "--independent-resolver", "--disposition", "fixed",
                "--thread-id", "T_bot", "--fix-commit", "not-a-sha",
            ]
        )
        self.assertIn("--fix-commit", str(payload["error"]))

    def test_unparsable_tracker_item_is_refused_before_any_lookup(self) -> None:
        payload = self._usage(
            [
                "owner/repo#1", "--allowed-owners", "owner",
                "--independent-resolver", "--disposition", "deferred",
                "--thread-id", "T_bot", "--tracker-item", "not/an/item",
            ]
        )
        self.assertIn("--tracker-item", str(payload["error"]))


class IndependentResolverBrightLines(unittest.TestCase):
    """The guards the third mode keeps: human threads and severity."""

    def test_human_thread_is_still_refused(self) -> None:
        # Dropping isOutdated does not widen authorship. --include-human is
        # refused in this mode, so nothing can lift the bot-only line here.
        code, payload = _run_independent(
            [_thread("T_bot", "alice", "User", bot_only=False,
                     last_updated=PINNED_UPDATED)],
            _independent_argv("--disposition", "incorrect",
                              "--counter-evidence", "anything"),
        )
        threads = cast(list[dict[str, object]], payload["threads"])
        self.assertEqual(threads[0]["action"], "skipped-human-thread")
        self.assertEqual(payload["resolvedCount"], 0)
        self.assertEqual(code, 10)

    def test_severity_marked_thread_is_still_refused(self) -> None:
        # Still an unattended path: "never a security or P1 thread" is
        # unconditional, so evidence cannot buy past it.
        code, payload = _run_independent(
            [_bot_thread(severity_flagged=True)],
            _independent_argv("--disposition", "incorrect",
                              "--counter-evidence", "anything"),
        )
        threads = cast(list[dict[str, object]], payload["threads"])
        self.assertEqual(threads[0]["action"], "skipped-severity-marked")
        self.assertEqual(code, 10)

    def test_stale_pin_still_refuses_before_evidence_is_consulted(self) -> None:
        # gh_capture has no scripted results: reaching a lookup would raise
        # StopIteration, so this passing proves the pin is checked first.
        code, payload = _run_independent(
            [_bot_thread(last_updated="2026-07-29T00:00:00Z")],
            _independent_argv("--disposition", "fixed", "--fix-commit", FIX_SHA),
        )
        threads = cast(list[dict[str, object]], payload["threads"])
        self.assertEqual(threads[0]["action"], "refused-stale-pin")
        self.assertEqual(code, 10)


class IndependentResolverEvidence(unittest.TestCase):
    """Evidence is validated against the world, never against the assertion."""

    def test_fixed_resolves_when_the_sha_is_reachable_from_head(self) -> None:
        code, payload = _run_independent(
            [_bot_thread()],
            _independent_argv("--disposition", "fixed", "--fix-commit", FIX_SHA),
            gh_results=[
                _pr_view_ok(),
                _proc(0, json.dumps({"status": "ahead", "behind_by": 0})),
            ],
        )
        threads = cast(list[dict[str, object]], payload["threads"])
        self.assertEqual(threads[0]["action"], "resolved")
        self.assertEqual(threads[0]["disposition"], "fixed")
        self.assertEqual(payload["mode"], "independent-resolver")
        self.assertEqual(payload["resolvedCount"], 1)
        self.assertEqual(code, 0)

    def test_fixed_refuses_a_sha_that_is_not_on_head(self) -> None:
        # A commit that exists but diverged from head is not evidence that THIS
        # PR carries the fix.
        code, payload = _run_independent(
            [_bot_thread()],
            _independent_argv("--disposition", "fixed", "--fix-commit", FIX_SHA),
            gh_results=[
                _pr_view_ok(),
                _proc(0, json.dumps({"status": "diverged", "behind_by": 3})),
            ],
        )
        threads = cast(list[dict[str, object]], payload["threads"])
        self.assertEqual(threads[0]["action"], "refused-fix-commit-not-on-head")
        self.assertEqual(payload["refusedEvidence"], 1)
        self.assertEqual(payload["resolvedCount"], 0)
        self.assertEqual(code, 10)

    def test_fixed_refuses_when_the_world_cannot_be_consulted(self) -> None:
        # An API failure is not the same answer as "the fix is not there", and
        # both refuse — but reporting the outage as a false claim would send a
        # caller to fix the wrong thing.
        code, payload = _run_independent(
            [_bot_thread()],
            _independent_argv("--disposition", "fixed", "--fix-commit", FIX_SHA),
            gh_results=[_proc(1)],
        )
        threads = cast(list[dict[str, object]], payload["threads"])
        self.assertEqual(threads[0]["action"], "refused-evidence-unverifiable")
        self.assertEqual(code, 10)

    def test_deferred_resolves_for_an_open_tracker_item(self) -> None:
        code, payload = _run_independent(
            [_bot_thread()],
            _independent_argv("--disposition", "deferred", "--tracker-item", "#42"),
            gh_results=[_proc(0, json.dumps({"state": "open"}))],
        )
        threads = cast(list[dict[str, object]], payload["threads"])
        self.assertEqual(threads[0]["action"], "resolved")
        self.assertEqual(threads[0]["disposition"], "deferred")
        self.assertEqual(code, 0)

    def test_deferred_refuses_a_closed_tracker_item(self) -> None:
        # A closed follow-up is not a deferral; it is the finding disappearing.
        code, payload = _run_independent(
            [_bot_thread()],
            _independent_argv("--disposition", "deferred", "--tracker-item", "#42"),
            gh_results=[_proc(0, json.dumps({"state": "closed"}))],
        )
        threads = cast(list[dict[str, object]], payload["threads"])
        self.assertEqual(threads[0]["action"], "refused-tracker-item-not-open")
        self.assertEqual(code, 10)

    def test_deferred_refuses_a_tracker_item_that_does_not_exist(self) -> None:
        code, payload = _run_independent(
            [_bot_thread()],
            _independent_argv("--disposition", "deferred", "--tracker-item", "#42"),
            gh_results=[_proc(1, stderr=GH_404)],
        )
        threads = cast(list[dict[str, object]], payload["threads"])
        self.assertEqual(threads[0]["action"], "refused-tracker-item-not-found")
        self.assertEqual(code, 10)

    def test_incorrect_resolves_when_the_rebuttal_is_on_the_thread(self) -> None:
        code, payload = _run_independent(
            [_bot_thread(reply_bodies=["The anchor points at generated output."])],
            _independent_argv(
                "--disposition", "incorrect",
                "--counter-evidence", "anchor points at generated output",
            ),
        )
        threads = cast(list[dict[str, object]], payload["threads"])
        self.assertEqual(threads[0]["action"], "resolved")
        self.assertEqual(threads[0]["disposition"], "incorrect")
        self.assertEqual(code, 0)

    def test_incorrect_refuses_when_the_rebuttal_is_only_asserted(self) -> None:
        # The rebuttal has to be visible where the finding is, not just on the
        # command line of the process resolving it.
        code, payload = _run_independent(
            [_bot_thread(reply_bodies=["Acknowledged."])],
            _independent_argv(
                "--disposition", "incorrect",
                "--counter-evidence", "anchor points at generated output",
            ),
        )
        threads = cast(list[dict[str, object]], payload["threads"])
        self.assertEqual(threads[0]["action"], "refused-counter-evidence-not-found")
        self.assertEqual(code, 10)

    def test_incorrect_ignores_the_opening_comment(self) -> None:
        # replyBodies excludes the opener, so the bot's own finding text can
        # never satisfy the claim that the finding is wrong.
        code, payload = _run_independent(
            [_bot_thread(reply_bodies=[])],
            _independent_argv(
                "--disposition", "incorrect", "--counter-evidence", "a.py",
            ),
        )
        threads = cast(list[dict[str, object]], payload["threads"])
        self.assertEqual(threads[0]["action"], "refused-counter-evidence-not-found")
        self.assertEqual(code, 10)

    def test_list_mode_validates_evidence_too(self) -> None:
        # A dry run that skipped validation would predict would-resolve for
        # evidence the world rejects — the one answer this mode exists to stop.
        _, payload = _run_independent(
            [_bot_thread(reply_bodies=["Acknowledged."])],
            [
                "owner/repo#1", "--allowed-owners", "owner",
                "--independent-resolver", "--thread-id", "T_bot",
                "--disposition", "incorrect", "--counter-evidence", "not present",
            ],
        )
        threads = cast(list[dict[str, object]], payload["threads"])
        self.assertEqual(threads[0]["action"], "refused-counter-evidence-not-found")


class OutageIsNotARejection(unittest.TestCase):
    """A failed lookup must name WHICH answer it got.

    Collapsing every nonzero `gh` exit onto the evidence-specific refusal sends a
    caller to replace evidence that may be perfectly valid, when the actual
    problem was an outage it should have retried. Only a confirmed HTTP 404 is the
    world answering "not there".
    """

    def _tracker(
        self, proc: subprocess.CompletedProcess[str]
    ) -> tuple[bool, str]:
        with mock.patch.object(rt, "gh_capture", return_value=proc):
            return rt.verify_tracker_item("owner/repo", "#42")

    def test_tracker_item_403_is_unverifiable_not_missing(self) -> None:
        self.assertEqual(
            self._tracker(_proc(1, stderr=GH_403)),
            (False, "refused-evidence-unverifiable"),
        )

    def test_tracker_item_500_is_unverifiable_not_missing(self) -> None:
        self.assertEqual(
            self._tracker(_proc(1, stderr=GH_500)),
            (False, "refused-evidence-unverifiable"),
        )

    def test_tracker_item_with_no_http_response_is_unverifiable(self) -> None:
        # A timeout or an unreachable API never produced a status at all.
        self.assertEqual(
            self._tracker(_proc(1, stderr=GH_NO_RESPONSE)),
            (False, "refused-evidence-unverifiable"),
        )

    def test_tracker_item_404_is_the_missing_item_refusal(self) -> None:
        self.assertEqual(
            self._tracker(_proc(1, stderr=GH_404)),
            (False, "refused-tracker-item-not-found"),
        )

    def test_tracker_item_owner_carrying_path_syntax_is_unverifiable(self) -> None:
        # TRACKER_ITEM_RE admits an owner/repo SHAPE, not a valid one, so a `..`
        # component builds a path that was never a GitHub endpoint. Reporting that
        # as a missing item would name the wrong problem. A single scripted
        # response would be reached only if the guard did not fire first.
        with mock.patch.object(rt, "gh_capture", side_effect=[]):
            self.assertEqual(
                rt.verify_tracker_item("owner/repo", "validowner/..#1"),
                (False, "refused-evidence-unverifiable"),
            )

    def test_tracker_item_leading_dot_owner_is_unverifiable(self) -> None:
        with mock.patch.object(rt, "gh_capture", side_effect=[]):
            self.assertEqual(
                rt.verify_tracker_item("owner/repo", ".org/repo#1"),
                (False, "refused-evidence-unverifiable"),
            )

    def test_a_well_formed_explicit_repo_is_still_looked_up(self) -> None:
        with mock.patch.object(
            rt, "gh_capture", return_value=_proc(0, json.dumps({"state": "open"}))
        ):
            self.assertEqual(
                rt.verify_tracker_item("owner/repo", "other-owner/other.repo#1"),
                (True, ""),
            )

    def _compare(
        self, compare: subprocess.CompletedProcess[str]
    ) -> tuple[bool, str]:
        with mock.patch.object(
            rt, "gh_capture", side_effect=[_pr_view_ok(), compare]
        ):
            return rt.verify_fix_commit("owner/repo", 1, FIX_SHA)

    def test_compare_404_is_the_not_on_head_refusal(self) -> None:
        # A SHA absent from the head repository is the world answering "no such
        # commit" — the one failure that IS about the evidence.
        self.assertEqual(
            self._compare(_proc(1, stderr=GH_404)),
            (False, "refused-fix-commit-not-on-head"),
        )

    def test_compare_500_is_unverifiable_not_a_rejected_sha(self) -> None:
        self.assertEqual(
            self._compare(_proc(1, stderr=GH_500)),
            (False, "refused-evidence-unverifiable"),
        )

    def test_compare_rate_limit_is_unverifiable_not_a_rejected_sha(self) -> None:
        self.assertEqual(
            self._compare(_proc(1, stderr="gh: rate limit exceeded (HTTP 429)\n")),
            (False, "refused-evidence-unverifiable"),
        )

    def test_last_reported_status_wins_over_an_earlier_retry(self) -> None:
        # gh prints one line per attempt; the final one is the outcome.
        self.assertEqual(
            rt.gh_http_status(_proc(1, stderr=GH_500 + GH_404)), 404
        )

    def test_no_status_at_all_reports_none(self) -> None:
        self.assertIsNone(rt.gh_http_status(_proc(1, stderr=GH_NO_RESPONSE)))


class FixCommitReachability(unittest.TestCase):
    """`fixed` accepts only a SHA in the head branch's actual history."""

    def _compare_result(self, payload: object) -> tuple[bool, str]:
        with mock.patch.object(
            rt,
            "gh_capture",
            side_effect=[_pr_view_ok(), _proc(0, json.dumps(payload))],
        ):
            return rt.verify_fix_commit("owner/repo", 1, FIX_SHA)

    def test_identical_status_is_reachable(self) -> None:
        # base=sha, head=head_oid: identical means the fix IS the head commit.
        self.assertEqual(
            self._compare_result({"status": "identical", "behind_by": 0}), (True, "")
        )

    def test_ahead_with_nonzero_behind_by_is_refused(self) -> None:
        # A contradictory status/behind_by pair must not slip through on status
        # alone — the belt-and-suspenders half of the reachability check.
        self.assertEqual(
            self._compare_result({"status": "ahead", "behind_by": 2}),
            (False, "refused-fix-commit-not-on-head"),
        )

    def test_missing_behind_by_is_refused(self) -> None:
        self.assertEqual(
            self._compare_result({"status": "ahead"}),
            (False, "refused-fix-commit-not-on-head"),
        )


class CompareUrlFieldsAreValidated(unittest.TestCase):
    """API-returned path segments are format-checked before interpolation.

    `head_owner` and `head_name` come from a response body, so "the API said so"
    is their only provenance. A crafted or compromised response carrying path
    syntax would otherwise redirect the compare request to another endpoint.
    """

    def _with_pr_view(self, payload: dict[str, object]) -> tuple[bool, str]:
        # A single scripted response: reaching the compare call would raise
        # StopIteration, so passing proves the refusal came first.
        with mock.patch.object(
            rt, "gh_capture", side_effect=[_proc(0, json.dumps(payload))]
        ):
            return rt.verify_fix_commit("owner/repo", 1, FIX_SHA)

    def test_owner_carrying_path_syntax_is_refused_before_the_compare(self) -> None:
        self.assertEqual(
            self._with_pr_view(
                {
                    "headRefOid": HEAD_OID,
                    "headRepository": {"name": "repo"},
                    "headRepositoryOwner": {"login": "owner/../../meta"},
                }
            ),
            (False, "refused-evidence-unverifiable"),
        )

    def test_repository_name_carrying_path_syntax_is_refused(self) -> None:
        self.assertEqual(
            self._with_pr_view(
                {
                    "headRefOid": HEAD_OID,
                    "headRepository": {"name": "repo/compare/x"},
                    "headRepositoryOwner": {"login": "owner"},
                }
            ),
            (False, "refused-evidence-unverifiable"),
        )

    def test_dot_dot_repository_name_is_refused(self) -> None:
        self.assertEqual(
            self._with_pr_view(
                {
                    "headRefOid": HEAD_OID,
                    "headRepository": {"name": ".."},
                    "headRepositoryOwner": {"login": "owner"},
                }
            ),
            (False, "refused-evidence-unverifiable"),
        )

    def test_non_hex_head_oid_is_refused(self) -> None:
        self.assertEqual(
            self._with_pr_view(
                {
                    "headRefOid": "main...HEAD",
                    "headRepository": {"name": "repo"},
                    "headRepositoryOwner": {"login": "owner"},
                }
            ),
            (False, "refused-evidence-unverifiable"),
        )

    def test_unparsable_sha_is_refused_at_the_function_boundary(self) -> None:
        # `main` validates --fix-commit, but the function owns its own contract.
        with mock.patch.object(
            rt, "gh_capture", side_effect=[_pr_view_ok()]
        ):
            self.assertEqual(
                rt.verify_fix_commit("owner/repo", 1, "../../etc"),
                (False, "refused-evidence-unverifiable"),
            )


class CounterEvidenceExcludesTheFindingsAuthor(unittest.TestCase):
    """`incorrect` needs an INDEPENDENT rebuttal, not the finding restating itself.

    The mandated classification reply restates the finding's own text
    (`review-discipline.md`), so a finding bot that also replies on its own thread
    would supply the very words asserted as the rebuttal. Excluding the opener's
    login — not merely the opening comment — is what makes the disposition mean
    "someone else said this finding is wrong".
    """

    @staticmethod
    def _record(*comments: dict[str, object]) -> dict[str, object]:
        return {"id": "T", "comments": list(comments)}

    @staticmethod
    def _comment(login: str, body: str, typename: str = "Bot") -> dict[str, object]:
        return {
            "author": {"login": login, "__typename": typename},
            "body": body,
            "updatedAt": PINNED_UPDATED,
        }

    def test_opener_own_later_reply_is_not_admissible_evidence(self) -> None:
        projected = rt.project_thread(
            self._record(
                self._comment("codex", "The anchor points at generated output."),
                self._comment("codex", "Status: the anchor points at generated output."),
            )
        )
        self.assertEqual(projected["replyBodies"], [])

    def test_a_different_bots_reply_is_admissible(self) -> None:
        projected = rt.project_thread(
            self._record(
                self._comment("codex", "The anchor points at generated output."),
                self._comment("claude", "Confirmed: the anchor is generated output."),
            )
        )
        self.assertEqual(
            projected["replyBodies"], ["Confirmed: the anchor is generated output."]
        )

    def test_the_callers_own_reply_is_still_admissible(self) -> None:
        # The worker's own D5 rebuttal is the INTENDED evidence source; excluding
        # self-logins here would break the mode outright.
        projected = rt.project_thread(
            self._record(
                self._comment("codex", "The anchor points at generated output."),
                self._comment("kyle-sexton", "The anchor is generated.", "User"),
            ),
            self_logins=frozenset({"kyle-sexton"}),
        )
        self.assertEqual(projected["replyBodies"], ["The anchor is generated."])

    def test_opener_login_match_is_case_insensitive(self) -> None:
        projected = rt.project_thread(
            self._record(
                self._comment("Codex", "the finding"),
                self._comment("codex", "the finding restated"),
            )
        )
        self.assertEqual(projected["replyBodies"], [])

    def test_a_withheld_opener_login_admits_no_evidence(self) -> None:
        # Independence cannot be established against an unknown opener.
        projected = rt.project_thread(
            {
                "id": "T",
                "comments": [
                    {"author": None, "body": "the finding"},
                    self._comment("claude", "a rebuttal"),
                ],
            }
        )
        self.assertEqual(projected["replyBodies"], [])

    def test_end_to_end_opener_reply_cannot_satisfy_the_claim(self) -> None:
        # Projected through `project_thread` rather than the fixture helper: the
        # helper takes `replyBodies` as a literal, so a hardcoded empty list would
        # assert nothing about the exclusion and would pass with the fix reverted.
        # Here the OPENER posts the later reply carrying the exact counter-evidence
        # text, so reverting the exclusion admits that body and resolves the thread.
        projected = rt.project_thread(
            self._record(
                self._comment("codex", "The anchor points at generated output."),
                self._comment("codex", "Status: the anchor points at generated output."),
            )
        )
        self.assertEqual(projected["replyBodies"], [])
        code, payload = _run_independent(
            [
                dict(
                    projected,
                    id="T_bot",
                    isResolved=False,
                    botOnly=True,
                    severityFlagged=False,
                    findingCount=1,
                    commentCount=2,
                    lastCommentUpdatedAt=PINNED_UPDATED,
                )
            ],
            _independent_argv(
                "--disposition", "incorrect",
                "--counter-evidence", "the anchor points at generated output",
            ),
        )
        threads = cast(list[dict[str, object]], payload["threads"])
        self.assertEqual(threads[0]["action"], "refused-counter-evidence-not-found")
        self.assertEqual(code, 10)


class MultiFindingThreadsAreRefused(unittest.TestCase):
    """One disposition is a claim about ONE finding; resolution clears the thread.

    Resolving a multi-finding thread on a single evidence tuple drops every
    comment it carries out of the readiness denominator
    (`babysit_classify.thread_is_open`), so evidence for finding A would suppress
    an unaddressed finding B and let the merge gate pass over it — the D7.5
    whole-thread eligibility rule this guard enforces mechanically.
    """

    def test_two_findings_refuse_under_the_independent_mode(self) -> None:
        code, payload = _run_independent(
            [_bot_thread(finding_count=2)],
            _independent_argv("--disposition", "fixed", "--fix-commit", FIX_SHA),
        )
        threads = cast(list[dict[str, object]], payload["threads"])
        self.assertEqual(threads[0]["action"], "skipped-multi-finding-thread")
        self.assertEqual(payload["skippedMultiFinding"], 1)
        self.assertEqual(payload["resolvedCount"], 0)
        self.assertEqual(code, 10)

    def test_the_refusal_precedes_any_evidence_lookup(self) -> None:
        # gh_capture has no scripted results: reaching a lookup would raise
        # StopIteration, so this passing proves the thread is refused first.
        _, payload = _run_independent(
            [_bot_thread(finding_count=3)],
            _independent_argv("--disposition", "deferred", "--tracker-item", "#42"),
        )
        threads = cast(list[dict[str, object]], payload["threads"])
        self.assertEqual(threads[0]["action"], "skipped-multi-finding-thread")

    def test_an_unknown_count_fails_closed(self) -> None:
        # None is what the projection reports for a truncated comment page, where
        # an unfetched comment could carry another finding.
        _, payload = _run_independent(
            [_bot_thread(finding_count=None)],
            _independent_argv("--disposition", "fixed", "--fix-commit", FIX_SHA),
        )
        threads = cast(list[dict[str, object]], payload["threads"])
        self.assertEqual(threads[0]["action"], "skipped-multi-finding-thread")

    def test_a_single_finding_thread_is_still_eligible(self) -> None:
        code, payload = _run_independent(
            [_bot_thread(finding_count=1)],
            _independent_argv("--disposition", "fixed", "--fix-commit", FIX_SHA),
            gh_results=[
                _pr_view_ok(),
                _proc(0, json.dumps({"status": "ahead", "behind_by": 0})),
            ],
        )
        threads = cast(list[dict[str, object]], payload["threads"])
        self.assertEqual(threads[0]["action"], "resolved")
        self.assertEqual(code, 0)

    def test_an_unmarked_thread_stays_eligible(self) -> None:
        # Most reviewers mark severity once per comment, or not at all. An
        # unmarked body yields a zero count, which the guard admits: the rule is
        # "not provably more than one", so only a SECOND marker refuses.
        projected = rt.project_thread(
            {
                "id": "T",
                "comments": [
                    {
                        "author": {"login": "codex", "__typename": "Bot"},
                        "body": "This reads oddly.",
                    }
                ],
            }
        )
        self.assertEqual(projected["findingCount"], 0)
        self.assertEqual(
            rt.classify(
                dict(projected, isResolved=False, botOnly=True, severityFlagged=False),
                autonomous=False,
                only_outdated=False,
                independent=True,
            ),
            "eligible",
        )

    def test_two_badges_in_one_thread_are_counted(self) -> None:
        projected = rt.project_thread(
            {
                "id": "T",
                "comments": [
                    {
                        "author": {"login": "codex", "__typename": "Bot"},
                        "body": (
                            "![P2 Badge](https://img.shields.io/badge/P2-yellow) one\n"
                            "![P3 Badge](https://img.shields.io/badge/P3-blue) two"
                        ),
                    }
                ],
            }
        )
        self.assertEqual(projected["findingCount"], 2)

    def test_a_self_classification_table_does_not_mint_a_finding(self) -> None:
        # The mandated reply restates the source severity marker in a table cell;
        # counting it would permanently block the thread on the worker's own echo.
        projected = rt.project_thread(
            {
                "id": "T",
                "comments": [
                    {
                        "author": {"login": "codex", "__typename": "Bot"},
                        "body": "![P2 Badge](https://img.shields.io/badge/P2-yellow) one",
                    },
                    {
                        "author": {"login": "kyle-sexton", "__typename": "User"},
                        "body": "| 1 | SUGGESTION: naming | VALID — fixing | ref | 👍 |",
                    },
                ],
            },
            self_logins=frozenset({"kyle-sexton"}),
        )
        self.assertEqual(projected["findingCount"], 1)

    def test_a_truncated_page_reports_an_unknown_count(self) -> None:
        projected = rt.project_thread(
            {
                "id": "T",
                "comments_truncated": True,
                "comments": [
                    {
                        "author": {"login": "codex", "__typename": "Bot"},
                        "body": "a finding",
                    }
                ],
            }
        )
        self.assertIsNone(projected["findingCount"])

    def test_autonomous_mode_is_not_narrowed_by_the_guard(self) -> None:
        # isOutdated is GitHub's own thread-level signal, so there is no
        # per-finding claim there to under-cover.
        result = _run(
            [
                _thread(
                    "T_bot", "codex[bot]", "Bot",
                    bot_only=True, is_outdated=True, finding_count=4,
                )
            ],
            ["owner/repo#1", "--allowed-owners", "owner", "--autonomous"],
        )
        threads = cast(list[dict[str, object]], result["threads"])
        self.assertEqual(threads[0]["action"], "would-resolve")


class ListModePredictsTheResolve(unittest.TestCase):
    """A dry run must predict what --resolve would actually do."""

    def test_list_mode_reports_a_stale_pin_instead_of_would_resolve(self) -> None:
        # Reporting would-resolve for pins that have already drifted makes the
        # prediction wrong in the one direction that matters.
        _, payload = _run_independent(
            [_bot_thread(last_updated="2026-07-29T00:00:00Z")],
            [
                "owner/repo#1", "--allowed-owners", "owner",
                "--independent-resolver", "--thread-id", "T_bot",
                "--disposition", "fixed", "--fix-commit", FIX_SHA,
                "--expected-comment-count", "2",
                "--expected-last-updated", PINNED_UPDATED,
            ],
        )
        threads = cast(list[dict[str, object]], payload["threads"])
        self.assertEqual(threads[0]["action"], "refused-stale-pin")

    def test_list_mode_reports_a_stale_comment_count(self) -> None:
        _, payload = _run_independent(
            [_bot_thread()],
            [
                "owner/repo#1", "--allowed-owners", "owner",
                "--independent-resolver", "--thread-id", "T_bot",
                "--disposition", "fixed", "--fix-commit", FIX_SHA,
                "--expected-comment-count", "9",
                "--expected-last-updated", PINNED_UPDATED,
            ],
        )
        threads = cast(list[dict[str, object]], payload["threads"])
        self.assertEqual(threads[0]["action"], "refused-stale-pin")

    def test_autonomous_list_mode_reports_a_stale_pin_too(self) -> None:
        result = _run(
            [
                _thread(
                    "T_bot", "codex[bot]", "Bot", bot_only=True,
                    is_outdated=True, last_updated="2026-07-29T00:00:00Z",
                )
            ],
            [
                "owner/repo#1", "--allowed-owners", "owner", "--autonomous",
                "--thread-id", "T_bot",
                "--expected-comment-count", "2",
                "--expected-last-updated", PINNED_UPDATED,
            ],
        )
        threads = cast(list[dict[str, object]], result["threads"])
        self.assertEqual(threads[0]["action"], "refused-stale-pin")

    def test_matching_pins_still_predict_the_resolve(self) -> None:
        _, payload = _run_independent(
            [_bot_thread()],
            [
                "owner/repo#1", "--allowed-owners", "owner",
                "--independent-resolver", "--thread-id", "T_bot",
                "--disposition", "fixed", "--fix-commit", FIX_SHA,
                "--expected-comment-count", "2",
                "--expected-last-updated", PINNED_UPDATED,
            ],
            gh_results=[
                _pr_view_ok(),
                _proc(0, json.dumps({"status": "ahead", "behind_by": 0})),
            ],
        )
        threads = cast(list[dict[str, object]], payload["threads"])
        self.assertEqual(threads[0]["action"], "would-resolve")


class DispositionDispatchIsExplicit(unittest.TestCase):
    """An unrecognized disposition refuses rather than falling through."""

    def test_an_unknown_disposition_is_refused_not_counter_evidence_checked(
        self,
    ) -> None:
        # A disposition added to DISPOSITION_EVIDENCE without a validator here
        # would otherwise be reported as validated by a check that never looked
        # at its evidence.
        self.assertEqual(
            rt.verify_disposition(
                _bot_thread(reply_bodies=["anything at all"]),
                repo="owner/repo",
                number=1,
                disposition="withdrawn",
                fix_commit=None,
                tracker_item=None,
                counter_evidence="anything",
            ),
            (False, "refused-evidence-unverifiable"),
        )


class ExistingModesUnchanged(unittest.TestCase):
    """#1632 regression: the new mode is parallel, not a relaxation."""

    def test_autonomous_still_refuses_a_current_thread(self) -> None:
        result = _run(
            [_thread("T_bot", "codex[bot]", "Bot", bot_only=True, is_outdated=False)],
            ["owner/repo#1", "--allowed-owners", "owner", "--autonomous"],
        )
        threads = cast(list[dict[str, object]], result["threads"])
        self.assertEqual(threads[0]["action"], "skipped-not-outdated")
        self.assertEqual(result["mode"], "autonomous")

    def test_explicit_mode_reports_no_disposition(self) -> None:
        result = _run(
            [_thread("T_bot", "codex[bot]", "Bot", bot_only=True)],
            ["owner/repo#1", "--allowed-owners", "owner"],
        )
        self.assertEqual(result["mode"], "explicit")
        self.assertIsNone(result["disposition"])


if __name__ == "__main__":
    unittest.main()
