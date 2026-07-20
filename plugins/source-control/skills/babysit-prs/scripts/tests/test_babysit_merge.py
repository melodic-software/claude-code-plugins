"""Autopilot-merge-tier (#476) criteria evaluated in `babysit_merge`.

The base readiness gate already blocks on state/mergeability/checks/approval/
threads; those paths are covered by the subprocess guard tests. This module
covers the five criteria the #476 tier layers on top -- issue-linked,
lane-authored, no blocking label, a distinct-bot approval on the live head, and
no human blocking comment -- each with a passing and a fall-back fixture, plus
the invariant that an absent tier makes zero tier-specific network calls.

Network is stubbed by monkeypatching `babysit_merge`'s gh seams; no real gh
process is spawned.
"""

from __future__ import annotations

import pathlib
import sys
import unittest
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_merge as merge

HEAD = "a" * 40
STALE = "b" * 40
LANE = "lane-bot"
APPROVER = "approver-bot"

TIER = merge.AutopilotMergeTierConfig(
    lane_logins=frozenset({LANE}),
    approver_bot_logins=frozenset({APPROVER}),
    block_labels=frozenset({"do-not-merge"}),
)


def _pr(**overrides: Any) -> dict[str, Any]:
    pr: dict[str, Any] = {
        "state": "OPEN",
        "isDraft": False,
        "mergeable": "MERGEABLE",
        "mergeStateStatus": "CLEAN",
        "reviewDecision": "APPROVED",
        "headRefOid": HEAD,
        "baseRefName": "main",
        "author": {"login": LANE},
        "url": "https://example/pr",
        "title": "t",
        "labels": [],
        "statusCheckRollup": [],
        "closingIssuesReferences": [{"number": 476}],
    }
    pr.update(overrides)
    return pr


# A branch rule requiring one approving review and no required status contexts:
# the base is protected (so no unprotected hold) and needs reviewDecision APPROVED.
RULES = [{"type": "pull_request", "parameters": {"required_approving_review_count": 1}}]


def _approval(login: str, oid: str, typename: str = "Bot", state: str = "APPROVED") -> dict[str, Any]:
    return {
        "state": state,
        "author": {"login": login, "__typename": typename, "is_bot": typename == "Bot"},
        "commit": {"oid": oid},
        "body": "",
    }


CLEAN_APPROVAL = [_approval(f"{APPROVER}[bot]", HEAD)]


class TierEvaluateHarness(unittest.TestCase):
    """Run `evaluate` with the gh seams stubbed and the tier engaged."""

    def _evaluate(
        self,
        pr: dict[str, Any],
        *,
        reviews: list[dict[str, Any]] | None = None,
        issue_comments: list[dict[str, Any]] | None = None,
        tier: merge.AutopilotMergeTierConfig | None = TIER,
    ) -> dict[str, Any]:
        def gh_json(args: list[str]) -> Any:
            if args[:2] == ["pr", "view"]:
                return pr
            if args[0] == "api":  # branch rules
                return RULES
            raise AssertionError(f"unexpected gh_json call: {args}")

        with (
            mock.patch.object(merge, "gh_json", side_effect=gh_json),
            mock.patch.object(merge, "fetch_review_threads", return_value=[]),
            mock.patch.object(
                merge, "fetch_pull_request_reviews",
                return_value=(CLEAN_APPROVAL if reviews is None else reviews),
            ) as reviews_mock,
            mock.patch.object(
                merge, "fetch_issue_comments",
                return_value=(issue_comments or []),
            ) as comments_mock,
        ):
            result = merge.evaluate(
                "owner/repo", 476, HEAD, {"owner"}, frozenset(), False, False, tier,
            )
        result["_reviews_called"] = reviews_mock.called
        result["_comments_called"] = comments_mock.called
        return result


class TierPassesWhenEveryCriterionHolds(TierEvaluateHarness):
    def test_all_criteria_met_is_ready(self) -> None:
        result = self._evaluate(_pr())
        self.assertTrue(result["ready"], result["blockers"])
        tier = result["autopilotMergeTier"]
        self.assertTrue(tier["enabled"])
        self.assertTrue(tier["issueLinked"])
        self.assertTrue(tier["laneAuthored"])
        self.assertEqual(tier["blockingLabels"], [])
        self.assertEqual(tier["distinctBotApproval"]["author"], f"{APPROVER}[bot]")
        self.assertEqual(tier["humanBlockingComments"], [])


class TierFallsBackPerCriterion(TierEvaluateHarness):
    def test_not_issue_linked_blocks(self) -> None:
        result = self._evaluate(_pr(closingIssuesReferences=[]))
        self.assertFalse(result["ready"])
        self.assertFalse(result["autopilotMergeTier"]["issueLinked"])
        self.assertTrue(any("issue-linked" in b for b in result["blockers"]))

    def test_blocking_label_blocks(self) -> None:
        result = self._evaluate(_pr(labels=[{"name": "do-not-merge"}]))
        self.assertFalse(result["ready"])
        self.assertEqual(
            result["autopilotMergeTier"]["blockingLabels"], ["do-not-merge"]
        )
        self.assertTrue(any("do-not-merge" in b for b in result["blockers"]))

    def test_label_match_is_case_insensitive(self) -> None:
        result = self._evaluate(_pr(labels=[{"name": "Do-Not-Merge"}]))
        self.assertEqual(
            result["autopilotMergeTier"]["blockingLabels"], ["do-not-merge"]
        )

    def test_non_lane_author_blocks(self) -> None:
        result = self._evaluate(_pr(author={"login": "outsider"}))
        self.assertFalse(result["ready"])
        self.assertFalse(result["autopilotMergeTier"]["laneAuthored"])
        self.assertTrue(any("pipeline lane" in b for b in result["blockers"]))

    def test_same_identity_approval_is_not_distinct(self) -> None:
        # Author and approver are the same login: author != approver fails.
        result = self._evaluate(
            _pr(author={"login": f"{APPROVER}[bot]"}),
            reviews=[_approval(f"{APPROVER}[bot]", HEAD)],
        )
        self.assertIsNone(result["autopilotMergeTier"]["distinctBotApproval"])
        self.assertTrue(any("author != approver" in b for b in result["blockers"]))

    def test_human_approval_is_not_a_bot_approver(self) -> None:
        result = self._evaluate(
            _pr(), reviews=[_approval("maintainer", HEAD, typename="User")]
        )
        self.assertIsNone(result["autopilotMergeTier"]["distinctBotApproval"])
        self.assertTrue(any("distinct-bot" in b for b in result["blockers"]))

    def test_stale_approval_off_head_blocks(self) -> None:
        # An approval left on a superseded commit is not "unchanged since review".
        result = self._evaluate(
            _pr(), reviews=[_approval(f"{APPROVER}[bot]", STALE)]
        )
        self.assertIsNone(result["autopilotMergeTier"]["distinctBotApproval"])
        self.assertTrue(any("distinct-bot" in b for b in result["blockers"]))

    def test_no_approving_review_blocks(self) -> None:
        result = self._evaluate(_pr(), reviews=[])
        self.assertIsNone(result["autopilotMergeTier"]["distinctBotApproval"])

    def test_human_blocking_comment_blocks(self) -> None:
        comment = {
            "author": {"login": "maintainer", "__typename": "User", "is_bot": False},
            "body": "Please do not merge, this is a blocking regression.",
        }
        result = self._evaluate(_pr(), issue_comments=[comment])
        self.assertFalse(result["ready"])
        self.assertIn("maintainer", result["autopilotMergeTier"]["humanBlockingComments"])
        self.assertTrue(any("human blocking comment" in b for b in result["blockers"]))

    def test_bot_comment_with_blocking_prose_does_not_block(self) -> None:
        # A bot review body carrying blocking-looking prose is not a human stop.
        comment = {
            "author": {"login": "some-bot[bot]", "__typename": "Bot", "is_bot": True},
            "body": "This is a blocking regression must fix.",
        }
        result = self._evaluate(_pr(), issue_comments=[comment])
        self.assertEqual(result["autopilotMergeTier"]["humanBlockingComments"], [])
        self.assertTrue(result["ready"], result["blockers"])


class TierAbsentIsInert(TierEvaluateHarness):
    def test_no_tier_makes_no_tier_network_calls(self) -> None:
        result = self._evaluate(_pr(), tier=None)
        self.assertFalse(result["autopilotMergeTier"]["enabled"])
        self.assertFalse(result["_reviews_called"])
        self.assertFalse(result["_comments_called"])
        self.assertTrue(result["ready"], result["blockers"])


class DistinctBotApprovalUnit(unittest.TestCase):
    def test_last_eligible_approval_on_head_wins(self) -> None:
        reviews = [
            _approval(f"{APPROVER}[bot]", STALE),
            _approval(f"{APPROVER}[bot]", HEAD),
        ]
        match = merge.find_distinct_bot_approval(
            reviews, LANE, HEAD, frozenset({APPROVER})
        )
        self.assertIsNotNone(match)
        self.assertEqual(match["commit"]["oid"], HEAD)

    def test_approver_matched_by_configured_login_without_bot_suffix(self) -> None:
        # A bot account whose review author carries no [bot] suffix and no Bot
        # typename is still an approver when named in approver_bot_logins.
        reviews = [_approval(APPROVER, HEAD, typename="User")]
        match = merge.find_distinct_bot_approval(
            reviews, LANE, HEAD, frozenset({APPROVER})
        )
        self.assertIsNotNone(match)

    def test_no_match_when_head_none(self) -> None:
        self.assertIsNone(
            merge.find_distinct_bot_approval(CLEAN_APPROVAL, LANE, None, frozenset())
        )


if __name__ == "__main__":
    unittest.main()
