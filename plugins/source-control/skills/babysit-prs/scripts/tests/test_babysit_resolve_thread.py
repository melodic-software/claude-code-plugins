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
`botOnly` test (still requiring at least one ACTUAL bot comment) so a
self-reply no longer strands it -- and, since the mandated classification-
reply table restates the source finding's own severity marker, the severity
scan strips a self-authored comment's classification-table rows (not its
whole body) before scanning, so fixing `botOnly` does not just move the
stranding to `skipped-severity-marked` under `--autonomous`.
"""

from __future__ import annotations

import io
import json
import pathlib
import sys
import unittest
from contextlib import redirect_stdout
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
        "commentCount": 2,
        "lastCommentUpdatedAt": None,
    }


def _run(threads: list[dict[str, object]], argv: list[str]) -> dict[str, object]:
    buffer = io.StringIO()
    with (
        mock.patch.object(rt, "fetch_threads", return_value=threads),
        mock.patch.object(sys, "argv", ["babysit_resolve_thread.py", *argv]),
        redirect_stdout(buffer),
    ):
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
        with (
            mock.patch.object(
                rt,
                "fetch_review_threads",
                side_effect=lambda repo, number, **kw: [kw["projection"](record)],
            ),
            mock.patch.object(sys, "argv", ["babysit_resolve_thread.py", *argv]),
            redirect_stdout(buffer),
        ):
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

    def test_bare_p1_prose_forms_flag(self) -> None:
        for body in (
            "P1: this is a blocking regression",
            "P1 must fix",
            "p1: blocking regression",
            "[p1] lowercase marker",
        ):
            record = self._record([body])
            self.assertTrue(
                rt.project_thread(record)["severityFlagged"], body
            )

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


if __name__ == "__main__":
    unittest.main()
