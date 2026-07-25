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
    thread_id: str, author: str, author_type: str, *, bot_only: bool
) -> dict[str, object]:
    return {
        "id": thread_id,
        "author": author,
        "authorType": author_type,
        "path": "a.py",
        "isResolved": False,
        "isOutdated": False,
        "botOnly": bot_only,
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


def _comment(login: str, typename: str) -> dict[str, object]:
    return {"author": {"login": login, "__typename": typename}}


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


if __name__ == "__main__":
    unittest.main()
