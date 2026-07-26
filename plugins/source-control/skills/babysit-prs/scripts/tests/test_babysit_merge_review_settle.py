"""The review-settle hold (#1629) in `babysit_merge`.

A reviewer that re-reviews on every push posts minutes after the head moves,
while GitHub reports the PR mergeable throughout. These tests cover the hold
that closes that window: it fires only when the configured reviewer owes the
LIVE head a review, it clears immediately once that review exists, it expires
with the settle window so an absent reviewer cannot wedge a PR, and -- the
property that makes the whole feature safe to ship -- it makes no network call
at all when unconfigured.

Network is stubbed by monkeypatching `babysit_merge`'s gh seams; no real gh
process is spawned.
"""

from __future__ import annotations

import contextlib
import io
import pathlib
import sys
import unittest
from datetime import datetime, timedelta, timezone
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_merge as merge

HEAD = "a" * 40
STALE = "b" * 40
REVIEWER = "chatgpt-codex-connector"
PR_NUMBER = 1629
NOW = datetime(2026, 7, 26, 21, 48, 40, tzinfo=timezone.utc)

SETTLE = merge.ReviewSettleConfig(
    reviewer_logins=frozenset({REVIEWER}), settle_seconds=600
)

# Protected base needing one approving review and no required status contexts,
# so nothing but the hold under test can block an otherwise-clean PR.
RULES = [{"type": "pull_request", "parameters": {"required_approving_review_count": 1}}]


def _pr(**overrides: Any) -> dict[str, Any]:
    pr: dict[str, Any] = {
        "state": "OPEN",
        "isDraft": False,
        "mergeable": "MERGEABLE",
        "mergeStateStatus": "CLEAN",
        "reviewDecision": "APPROVED",
        "headRefOid": HEAD,
        "baseRefName": "main",
        "author": {"login": "someone"},
        "url": "https://example/pr",
        "title": "t",
        "labels": [],
        "statusCheckRollup": [],
        "closingIssuesReferences": [],
    }
    pr.update(overrides)
    return pr


def _review(oid: str, login: str = REVIEWER, state: str = "COMMENTED") -> dict[str, Any]:
    return {
        "id": f"r-{oid[:4]}-{login}",
        "state": state,
        "author": {"login": login, "__typename": "Bot", "is_bot": True},
        "commit": {"oid": oid},
        "submittedAt": "2026-07-26T21:49:06Z",
        "body": "",
    }


def _commit_payload(committed_at: str) -> dict[str, Any]:
    return {"commit": {"committer": {"date": committed_at}}}


class SettleHarness(unittest.TestCase):
    """Run `evaluate` with the gh seams stubbed and the hold configured."""

    def _evaluate(
        self,
        *,
        settle: merge.ReviewSettleConfig | None = SETTLE,
        reviews: list[dict[str, Any]] | None = None,
        review_comments: list[dict[str, Any]] | None = None,
        head_committed_at: str | None = "2026-07-26T21:44:00Z",
        commit_read_fails: bool = False,
        pr: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        calls: list[list[str]] = []

        def gh_json(args: list[str]) -> Any:
            calls.append(args)
            if args[:2] == ["pr", "view"]:
                return pr if pr is not None else _pr()
            if args[0] == "api" and "/rules/branches/" in args[1]:
                return RULES
            if args[0] == "api" and "/commits/" in args[1]:
                if commit_read_fails:
                    raise RuntimeError("simulated commit read failure")
                return _commit_payload(head_committed_at or "")
            raise AssertionError(f"unexpected gh_json call: {args}")

        with (
            mock.patch.object(merge, "gh_json", side_effect=gh_json),
            mock.patch.object(merge, "fetch_review_threads", return_value=[]),
            mock.patch.object(
                merge, "fetch_pull_request_reviews", return_value=(reviews or []),
            ) as reviews_mock,
            mock.patch.object(merge, "fetch_issue_comments", return_value=[]),
            mock.patch.object(
                merge, "fetch_pull_request_review_comments",
                return_value=(review_comments or []),
            ) as review_comments_mock,
            mock.patch.object(merge, "datetime", wraps=datetime) as clock,
        ):
            clock.now.return_value = NOW
            result = merge.evaluate(
                "owner/repo", PR_NUMBER, HEAD, {"owner"}, frozenset(),
                False, False, None, settle=settle,
            )
        result["_reviews_called"] = reviews_mock.called
        result["_review_comments_called"] = review_comments_mock.called
        result["_commit_reads"] = [a for a in calls if a[0] == "api" and "/commits/" in a[1]]
        return result

    def _settle_blockers(self, result: dict[str, Any]) -> list[str]:
        return [
            b
            for b in result["blockers"]
            if "settle window" in b or "unverifiable clock" in b
        ]


class UnconfiguredIsInert(SettleHarness):
    def test_absent_config_makes_no_review_call_and_does_not_hold(self) -> None:
        # The load-bearing claim of the whole change: with the hold unconfigured
        # the gate issues no request it did not issue before, so "byte-for-byte
        # its prior self" is asserted against call records, not just `ready`.
        result = self._evaluate(settle=None)
        self.assertTrue(result["ready"], result["blockers"])
        self.assertEqual(self._settle_blockers(result), [])
        self.assertFalse(result["_reviews_called"])
        self.assertFalse(result["_review_comments_called"])
        self.assertEqual(result["_commit_reads"], [])
        self.assertEqual(result["reviewSettle"], {"enabled": False})


class HoldFiresWhileAReviewIsDue(SettleHarness):
    def test_young_head_with_no_current_head_review_blocks(self) -> None:
        # #1594's exact shape: head 4m40s old, reviewer's round landed 26s later.
        result = self._evaluate(reviews=[_review(STALE)])
        self.assertFalse(result["ready"])
        blockers = self._settle_blockers(result)
        self.assertEqual(len(blockers), 1, result["blockers"])
        self.assertIn(REVIEWER, blockers[0])
        self.assertEqual(result["reviewSettle"]["state"], "settling")
        self.assertEqual(result["reviewSettle"]["headAgeSeconds"], 280)
        self.assertFalse(result["reviewSettle"]["currentHeadReview"])

    def test_a_review_of_another_head_does_not_clear_the_hold(self) -> None:
        # The stale review is by the configured reviewer but on the previous
        # head -- the case a login-only check would wrongly treat as reviewed.
        result = self._evaluate(reviews=[_review(STALE, state="APPROVED")])
        self.assertEqual(result["reviewSettle"]["state"], "settling")

    def test_another_bots_review_of_this_head_does_not_clear_the_hold(self) -> None:
        result = self._evaluate(reviews=[_review(HEAD, login="other-bot")])
        self.assertEqual(result["reviewSettle"]["state"], "settling")


class HoldClearsWithoutAddedLatency(SettleHarness):
    def test_current_head_review_merges_immediately(self) -> None:
        # The common case must cost nothing: a review of the live head clears
        # the hold before the clock is ever consulted, so no commit read happens
        # and no window is waited out.
        result = self._evaluate(reviews=[_review(HEAD)])
        self.assertTrue(result["ready"], result["blockers"])
        self.assertEqual(self._settle_blockers(result), [])
        self.assertTrue(result["reviewSettle"]["currentHeadReview"])
        self.assertEqual(result["reviewSettle"]["state"], "reviewed")
        self.assertEqual(result["_commit_reads"], [])

    def test_inline_review_comment_on_this_head_also_clears_it(self) -> None:
        # Codex posts its findings as inline review comments; those carry the
        # commit id too and are evidence the reviewer saw this head.
        inline = [{
            "id": 7,
            "user": {"login": f"{REVIEWER}[bot]", "type": "Bot"},
            "commit_id": HEAD,
            "html_url": "https://example/c",
            "body": "",
        }]
        result = self._evaluate(reviews=[], review_comments=inline)
        self.assertEqual(result["reviewSettle"]["state"], "reviewed")
        self.assertEqual(result["_commit_reads"], [])


class HoldIsBounded(SettleHarness):
    def test_head_older_than_the_window_stops_waiting(self) -> None:
        # A reviewer that never engages must not wedge the PR.
        result = self._evaluate(
            reviews=[], head_committed_at="2026-07-26T21:00:00Z",
        )
        self.assertTrue(result["ready"], result["blockers"])
        self.assertEqual(self._settle_blockers(result), [])
        self.assertEqual(result["reviewSettle"]["state"], "settled")
        self.assertEqual(result["reviewSettle"]["headAgeSeconds"], 2920)


class UnreadableClockHolds(SettleHarness):
    def test_commit_read_failure_holds_rather_than_merging(self) -> None:
        # A transient read failure must not be the thing that silently disables
        # the hold; the block is self-clearing on the next run.
        result = self._evaluate(reviews=[], commit_read_fails=True)
        self.assertFalse(result["ready"])
        blockers = self._settle_blockers(result)
        self.assertEqual(len(blockers), 1, result["blockers"])
        self.assertIn("unverifiable clock", blockers[0])
        self.assertEqual(result["reviewSettle"]["state"], "head-age-unreadable")

    def test_unparseable_commit_date_holds(self) -> None:
        result = self._evaluate(reviews=[], head_committed_at="not-a-date")
        self.assertEqual(result["reviewSettle"]["state"], "head-age-unreadable")


class ReviewCorpusIsFetchedOnce(unittest.TestCase):
    def test_settle_and_tier_share_one_reviews_fetch(self) -> None:
        # Both consumers read the same corpus; fetching it twice per run would
        # double a paginated call on every gated merge.
        tier = merge.AutopilotMergeTierConfig(
            lane_logins=frozenset({"lane-bot"}),
            approver_bot_logins=frozenset({"approver-bot"}),
            block_labels=frozenset({"do-not-merge"}),
        )
        pr = _pr(
            author={"login": "lane-bot"},
            closingIssuesReferences=[{"number": 4242}],
        )

        def gh_json(args: list[str]) -> Any:
            if args[:2] == ["pr", "view"]:
                return pr
            if args[0] == "api" and "/rules/branches/" in args[1]:
                return RULES
            if args[0] == "api" and "/commits/" in args[1]:
                return _commit_payload("2026-07-26T21:00:00Z")
            raise AssertionError(f"unexpected gh_json call: {args}")

        with (
            mock.patch.object(merge, "gh_json", side_effect=gh_json),
            mock.patch.object(merge, "fetch_review_threads", return_value=[]),
            mock.patch.object(
                merge, "fetch_pull_request_reviews",
                return_value=[_review(HEAD, login="approver-bot", state="APPROVED")],
            ) as reviews_mock,
            mock.patch.object(merge, "fetch_issue_comments", return_value=[]),
            mock.patch.object(
                merge, "fetch_pull_request_review_comments", return_value=[],
            ) as review_comments_mock,
            mock.patch.object(merge, "datetime", wraps=datetime) as clock,
        ):
            clock.now.return_value = NOW
            merge.evaluate(
                "owner/repo", PR_NUMBER, HEAD, {"owner"}, frozenset(),
                False, False, tier, settle=SETTLE,
            )
        self.assertEqual(reviews_mock.call_count, 1)
        self.assertEqual(review_comments_mock.call_count, 1)


class PairedConfigurationIsFailClosed(unittest.TestCase):
    """Either flag alone is a usage error, never a silently-inert hold."""

    def _run(self, *extra: str) -> tuple[int, str]:
        out = io.StringIO()
        with (
            mock.patch.object(
                sys, "argv",
                ["babysit_merge.py", "owner/repo#1", "--allowed-owners", "owner", *extra],
            ),
            contextlib.redirect_stdout(out),
            mock.patch("sys.stderr", new=io.StringIO()),
        ):
            code = merge.main()
        return code, out.getvalue()

    def test_logins_without_window_is_a_usage_error(self) -> None:
        code, out = self._run("--review-bot-logins", REVIEWER)
        self.assertEqual(code, 2)
        self.assertIn("--review-settle-minutes", out)

    def test_window_without_logins_is_a_usage_error(self) -> None:
        code, out = self._run("--review-settle-minutes", "10")
        self.assertEqual(code, 2)
        self.assertIn("--review-bot-logins", out)

    def test_empty_login_set_is_refused(self) -> None:
        code, out = self._run(
            "--review-bot-logins", " , ", "--review-settle-minutes", "10",
        )
        self.assertEqual(code, 2)
        self.assertIn("must be non-empty", out)

    def test_nonpositive_and_nonnumeric_windows_are_refused(self) -> None:
        for value in ("0", "-5", "abc", "nan", "inf"):
            with self.subTest(value=value):
                code, out = self._run(
                    "--review-bot-logins", REVIEWER,
                    "--review-settle-minutes", value,
                )
                self.assertEqual(code, 2)
                self.assertIn("finite number", out)


class SettleConfigUnit(unittest.TestCase):
    def test_head_age_boundary_is_exclusive(self) -> None:
        # Exactly at the window the head has settled: the hold is "younger than",
        # so a window of N seconds waits N seconds and not a run longer.
        committed = NOW - timedelta(seconds=SETTLE.settle_seconds)
        with mock.patch.object(
            merge, "head_committed_at", return_value=committed,
        ):
            blockers, result = merge.evaluate_review_settle(
                "owner/repo", HEAD, SETTLE, [], now=NOW,
            )
        self.assertEqual(blockers, [])
        self.assertEqual(result["state"], "settled")

    def test_one_second_inside_the_window_holds(self) -> None:
        committed = NOW - timedelta(seconds=SETTLE.settle_seconds - 1)
        with mock.patch.object(
            merge, "head_committed_at", return_value=committed,
        ):
            blockers, result = merge.evaluate_review_settle(
                "owner/repo", HEAD, SETTLE, [], now=NOW,
            )
        self.assertEqual(len(blockers), 1)
        self.assertEqual(result["state"], "settling")

    def test_missing_head_is_not_held_by_this_gate(self) -> None:
        # An absent head is already blocked upstream; the hold must not add a
        # second, more confusing blocker for the same condition.
        blockers, result = merge.evaluate_review_settle(
            "owner/repo", None, SETTLE, [], now=NOW,
        )
        self.assertEqual(blockers, [])
        self.assertEqual(result["state"], "no-head")

    def test_naive_timestamps_are_read_as_utc(self) -> None:
        parsed = merge.parse_github_timestamp("2026-07-26T21:44:00")
        self.assertEqual(parsed, datetime(2026, 7, 26, 21, 44, tzinfo=timezone.utc))

    def test_blank_timestamp_is_none(self) -> None:
        self.assertIsNone(merge.parse_github_timestamp("   "))


if __name__ == "__main__":
    unittest.main()
