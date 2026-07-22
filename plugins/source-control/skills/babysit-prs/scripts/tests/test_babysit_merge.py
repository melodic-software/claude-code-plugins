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
PR_NUMBER = 476
LINKED_ISSUE = 999  # distinct from the PR so the two comment fetches are separable
LINKED_REF = f"owner/repo#{LINKED_ISSUE}"


def _comment(
    login: str,
    body: str = "",
    *,
    typename: str = "User",
    association: str = "NONE",
    created_at: str = "2026-01-01T00:00:00Z",
) -> dict[str, Any]:
    return {
        "author": {"login": login, "__typename": typename, "is_bot": typename == "Bot"},
        "authorAssociation": association,
        "body": body,
        "createdAt": created_at,
    }


DECISION_MARKER = _comment(
    "triage-bot[bot]",
    "Decision defaulted: use squash — veto before merge",
    typename="Bot",
    created_at="2026-01-01T00:00:00Z",
)

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
        "closingIssuesReferences": [{"number": LINKED_ISSUE}],
    }
    pr.update(overrides)
    return pr


# A branch rule requiring one approving review and no required status contexts:
# the base is protected (so no unprotected hold) and needs reviewDecision APPROVED.
RULES = [{"type": "pull_request", "parameters": {"required_approving_review_count": 1}}]


def _approval(
    login: str,
    oid: str,
    typename: str = "Bot",
    state: str = "APPROVED",
    submitted_at: str = "2026-01-01T00:00:00Z",
) -> dict[str, Any]:
    return {
        "state": state,
        "author": {"login": login, "__typename": typename, "is_bot": typename == "Bot"},
        "commit": {"oid": oid},
        "submittedAt": submitted_at,
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
        review_comments: list[dict[str, Any]] | None = None,
        linked_issue_comments: list[dict[str, Any]] | None = None,
        linked_issue_error: bool = False,
        tier: merge.AutopilotMergeTierConfig | None = TIER,
    ) -> dict[str, Any]:
        def gh_json(args: list[str]) -> Any:
            if args[:2] == ["pr", "view"]:
                return pr
            if args[0] == "api":  # branch rules
                return RULES
            raise AssertionError(f"unexpected gh_json call: {args}")

        def issue_comments_side_effect(repo: str, n: int) -> list[dict[str, Any]]:
            # The linked-issue fetch (decision-default veto) is separable from the
            # PR's own comment fetch (human-blocking scan) by issue number.
            if n == LINKED_ISSUE:
                if linked_issue_error:
                    raise RuntimeError("simulated comment-fetch failure")
                return linked_issue_comments or []
            return issue_comments or []

        with (
            mock.patch.object(merge, "gh_json", side_effect=gh_json),
            mock.patch.object(merge, "fetch_review_threads", return_value=[]),
            mock.patch.object(
                merge, "fetch_pull_request_reviews",
                return_value=(CLEAN_APPROVAL if reviews is None else reviews),
            ) as reviews_mock,
            mock.patch.object(
                merge, "fetch_issue_comments",
                side_effect=issue_comments_side_effect,
            ) as comments_mock,
            mock.patch.object(
                merge, "fetch_pull_request_review_comments",
                return_value=(review_comments or []),
            ) as review_comments_mock,
        ):
            result = merge.evaluate(
                "owner/repo", PR_NUMBER, HEAD, {"owner"}, frozenset(), False, False, tier,
            )
        result["_reviews_called"] = reviews_mock.called
        result["_comments_called"] = comments_mock.called
        result["_review_comments_called"] = review_comments_mock.called
        result["_comments_calls"] = list(comments_mock.call_args_list)
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
        self.assertEqual(tier["decisionDefaultHeldIssues"], [])

    def test_ratified_decision_default_marker_passes(self) -> None:
        # A maintainer (OWNER) comment strictly after the marker ratifies it.
        ratify = _comment(
            "maintainer", "Ratified — proceed.", association="OWNER",
            created_at="2026-02-01T00:00:00Z",
        )
        result = self._evaluate(
            _pr(), linked_issue_comments=[DECISION_MARKER, ratify]
        )
        self.assertTrue(result["ready"], result["blockers"])
        self.assertEqual(
            result["autopilotMergeTier"]["decisionDefaultHeldIssues"], []
        )


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
        self.assertFalse(result["ready"])
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

    def test_unconfigured_bot_approval_is_rejected(self) -> None:
        # An unrelated installed App's [bot] approval must not satisfy the tier:
        # being a bot is not enough, it must be the configured approver identity.
        result = self._evaluate(
            _pr(), reviews=[_approval("random-app[bot]", HEAD)]
        )
        self.assertIsNone(result["autopilotMergeTier"]["distinctBotApproval"])
        self.assertFalse(result["ready"])

    def test_human_blocking_comment_blocks(self) -> None:
        comment = {
            "author": {"login": "maintainer", "__typename": "User", "is_bot": False},
            "body": "Please do not merge, this is a blocking regression.",
        }
        result = self._evaluate(_pr(), issue_comments=[comment])
        self.assertFalse(result["ready"])
        self.assertIn("maintainer", result["autopilotMergeTier"]["humanBlockingComments"])
        self.assertTrue(any("human blocking comment" in b for b in result["blockers"]))

    def test_superseded_bot_approval_is_ignored(self) -> None:
        # The approver bot approved, then requested changes on the same head; a
        # human approval keeps the base reviewDecision APPROVED. The bot's latest
        # decisive state is CHANGES_REQUESTED, so it is not a valid tier approver.
        result = self._evaluate(
            _pr(),
            reviews=[
                _approval(f"{APPROVER}[bot]", HEAD, submitted_at="2026-01-01T00:00:00Z"),
                _approval(
                    f"{APPROVER}[bot]", HEAD, state="CHANGES_REQUESTED",
                    submitted_at="2026-01-02T00:00:00Z",
                ),
            ],
        )
        self.assertIsNone(result["autopilotMergeTier"]["distinctBotApproval"])
        self.assertFalse(result["ready"])

    def test_plain_do_not_merge_comment_blocks(self) -> None:
        comment = {
            "author": {"login": "maintainer", "__typename": "User", "is_bot": False},
            "body": "Please do not merge this PR yet.",
        }
        result = self._evaluate(_pr(), issue_comments=[comment])
        self.assertIn("maintainer", result["autopilotMergeTier"]["humanBlockingComments"])
        self.assertFalse(result["ready"])

    def test_inline_review_comment_veto_blocks(self) -> None:
        # A human inline review comment on a since-resolved thread escapes the
        # base unresolved-thread gate; the tier still catches it.
        row = {
            "user": {"login": "maintainer", "type": "User"},
            "body": "This is a blocking regression.",
        }
        result = self._evaluate(_pr(), review_comments=[row])
        self.assertTrue(result["_review_comments_called"])
        self.assertIn("maintainer", result["autopilotMergeTier"]["humanBlockingComments"])
        self.assertFalse(result["ready"])

    def test_unratified_decision_default_marker_blocks(self) -> None:
        result = self._evaluate(_pr(), linked_issue_comments=[DECISION_MARKER])
        self.assertFalse(result["ready"])
        self.assertEqual(
            result["autopilotMergeTier"]["decisionDefaultHeldIssues"], [LINKED_REF]
        )
        self.assertTrue(any("Decision defaulted" in b for b in result["blockers"]))

    def test_non_maintainer_comment_does_not_ratify(self) -> None:
        # A later comment from a non-maintainer is not the veto-holder's ratification.
        later = _comment(
            "drive-by", "looks fine to me", association="NONE",
            created_at="2026-02-01T00:00:00Z",
        )
        result = self._evaluate(
            _pr(), linked_issue_comments=[DECISION_MARKER, later]
        )
        self.assertFalse(result["ready"])
        self.assertEqual(
            result["autopilotMergeTier"]["decisionDefaultHeldIssues"], [LINKED_REF]
        )

    def test_decision_default_fetch_error_holds(self) -> None:
        # Fail closed: a comment-fetch failure holds the PR for the human list.
        result = self._evaluate(_pr(), linked_issue_error=True)
        self.assertFalse(result["ready"])
        self.assertTrue(any("could not verify" in b for b in result["blockers"]))

    def test_cross_repo_linked_issue_read_from_its_own_repo(self) -> None:
        # A PR closing an issue in another repo must have the veto read from that
        # repo, not the PR's repo where a same-numbered issue could lack the marker.
        cross = _pr(
            closingIssuesReferences=[
                {
                    "number": LINKED_ISSUE,
                    "repository": {
                        "name": "other-repo",
                        "owner": {"login": "other-owner"},
                    },
                }
            ]
        )
        result = self._evaluate(cross, linked_issue_comments=[DECISION_MARKER])
        self.assertFalse(result["ready"])
        self.assertEqual(
            result["autopilotMergeTier"]["decisionDefaultHeldIssues"],
            [f"other-owner/other-repo#{LINKED_ISSUE}"],
        )
        self.assertIn(
            mock.call("other-owner/other-repo", LINKED_ISSUE),
            result["_comments_calls"],
        )

    def test_unrelated_maintainer_comment_does_not_ratify(self) -> None:
        # A later maintainer comment with no explicit ratification signal (a bare
        # "thanks") must not clear the veto.
        chatter = _comment(
            "maintainer", "thanks, nice work here", association="OWNER",
            created_at="2026-02-01T00:00:00Z",
        )
        result = self._evaluate(
            _pr(), linked_issue_comments=[DECISION_MARKER, chatter]
        )
        self.assertFalse(result["ready"])
        self.assertEqual(
            result["autopilotMergeTier"]["decisionDefaultHeldIssues"], [LINKED_REF]
        )

    def test_ratification_signal_before_marker_does_not_clear(self) -> None:
        # A ratification signal that predates the marker is not a ratification of it.
        early = _comment(
            "maintainer", "approved", association="OWNER",
            created_at="2025-12-01T00:00:00Z",
        )
        result = self._evaluate(
            _pr(), linked_issue_comments=[early, DECISION_MARKER]
        )
        self.assertFalse(result["ready"])
        self.assertEqual(
            result["autopilotMergeTier"]["decisionDefaultHeldIssues"], [LINKED_REF]
        )

    def test_negated_approval_does_not_ratify(self) -> None:
        # A withheld/negated approval must not clear the veto even though it
        # contains an approval token.
        negated = _comment(
            "maintainer", "not approved yet — hold this", association="OWNER",
            created_at="2026-02-01T00:00:00Z",
        )
        result = self._evaluate(
            _pr(), linked_issue_comments=[DECISION_MARKER, negated]
        )
        self.assertFalse(result["ready"])

    def test_ratified_then_revoked_holds(self) -> None:
        # The latest decisive maintainer signal wins: a later revocation ("do not
        # merge") re-holds a marker an earlier comment had ratified.
        ratify = _comment(
            "maintainer", "Ratified — proceed.", association="OWNER",
            created_at="2026-02-01T00:00:00Z",
        )
        revoke = _comment(
            "maintainer", "Actually, do not merge — hold this.", association="OWNER",
            created_at="2026-02-02T00:00:00Z",
        )
        result = self._evaluate(
            _pr(), linked_issue_comments=[DECISION_MARKER, ratify, revoke]
        )
        self.assertFalse(result["ready"])
        self.assertEqual(
            result["autopilotMergeTier"]["decisionDefaultHeldIssues"], [LINKED_REF]
        )

    def test_revoked_then_ratified_clears(self) -> None:
        # Latest wins in the other direction: a ratification newer than an earlier
        # revocation clears the veto.
        revoke = _comment(
            "maintainer", "not approved yet — hold this", association="OWNER",
            created_at="2026-02-01T00:00:00Z",
        )
        ratify = _comment(
            "maintainer", "Re-reviewed — ratified, proceed.", association="OWNER",
            created_at="2026-02-02T00:00:00Z",
        )
        result = self._evaluate(
            _pr(), linked_issue_comments=[DECISION_MARKER, revoke, ratify]
        )
        self.assertTrue(result["ready"], result["blockers"])
        self.assertEqual(
            result["autopilotMergeTier"]["decisionDefaultHeldIssues"], []
        )

    def test_non_decisive_comment_after_ratification_leaves_it_standing(self) -> None:
        # A non-decisive later comment (a bare "thanks") does not disturb a prior
        # ratification.
        ratify = _comment(
            "maintainer", "Ratified — proceed.", association="OWNER",
            created_at="2026-02-01T00:00:00Z",
        )
        chatter = _comment(
            "maintainer", "thanks, nice work here", association="OWNER",
            created_at="2026-02-02T00:00:00Z",
        )
        result = self._evaluate(
            _pr(), linked_issue_comments=[DECISION_MARKER, ratify, chatter]
        )
        self.assertTrue(result["ready"], result["blockers"])
        self.assertEqual(
            result["autopilotMergeTier"]["decisionDefaultHeldIssues"], []
        )

    def test_same_timestamp_ratify_and_revoke_holds(self) -> None:
        # Ambiguity is fail-closed: a ratify/revoke tie at the same timestamp holds
        # (ratification must be strictly newer than every revocation to clear).
        ratify = _comment(
            "maintainer", "Ratified — proceed.", association="OWNER",
            created_at="2026-02-01T00:00:00Z",
        )
        revoke = _comment(
            "maintainer", "do not merge", association="OWNER",
            created_at="2026-02-01T00:00:00Z",
        )
        result = self._evaluate(
            _pr(), linked_issue_comments=[DECISION_MARKER, ratify, revoke]
        )
        self.assertFalse(result["ready"])
        self.assertEqual(
            result["autopilotMergeTier"]["decisionDefaultHeldIssues"], [LINKED_REF]
        )

    def test_bot_comment_with_blocking_prose_does_not_block(self) -> None:
        # A bot review body carrying blocking-looking prose is not a human stop.
        comment = {
            "author": {"login": "some-bot[bot]", "__typename": "Bot", "is_bot": True},
            "body": "This is a blocking regression must fix.",
        }
        result = self._evaluate(_pr(), issue_comments=[comment])
        self.assertEqual(result["autopilotMergeTier"]["humanBlockingComments"], [])
        self.assertTrue(result["ready"], result["blockers"])

    def test_configured_user_approver_body_is_not_a_human_block(self) -> None:
        # The configured distinct-bot approver GitHub reports as a `User` (no
        # [bot] suffix): its own approving review body carrying blocking-looking
        # prose must not count as a human stop against the very approval it
        # provides. The same review satisfies find_distinct_bot_approval and no
        # longer self-blocks the merge.
        review = _approval(APPROVER, HEAD, typename="User")
        review["body"] = (
            "Approved. This change resolves the blocking regression "
            "from the linked issue."
        )
        result = self._evaluate(_pr(), reviews=[review])
        self.assertTrue(result["ready"], result["blockers"])
        self.assertEqual(result["autopilotMergeTier"]["humanBlockingComments"], [])
        self.assertIsNotNone(result["autopilotMergeTier"]["distinctBotApproval"])

    def test_configured_user_lane_does_not_ratify_decision_default(self) -> None:
        # A pipeline lane account GitHub reports as a `User` is automation for the
        # ratification scan: its "ratified" comment after the marker must not
        # clear the decision-default veto (the #450 hazard of automation ratifying
        # its own default). The OWNER association proves the bot classification --
        # not the association -- holds it.
        ratify = _comment(
            LANE, "Ratified — proceed.", typename="User", association="OWNER",
            created_at="2026-02-01T00:00:00Z",
        )
        result = self._evaluate(
            _pr(), linked_issue_comments=[DECISION_MARKER, ratify]
        )
        self.assertFalse(result["ready"])
        self.assertEqual(
            result["autopilotMergeTier"]["decisionDefaultHeldIssues"], [LINKED_REF]
        )


class TierApprovalBodySeverityGate(TierEvaluateHarness):
    """The accepted approver's own review body is severity-scanned (#621).

    A distinct-bot approval can ratify the live head while its body reports a live
    blocking finding; the human-blocking corpus scan skips bot-authored items and
    reviewDecision can stay APPROVED, so an approve-with-blocking-findings verdict
    would merge. The tier invalidates such an approval -- treated as no approval,
    never as a human block -- keying only on the shared classifier's structured
    severity vocabulary (CRITICAL/IMPORTANT, P0-P3 badge, bracketed [P0-P3]).
    """

    def _approval_body(self, body: str) -> dict[str, Any]:
        review = _approval(f"{APPROVER}[bot]", HEAD)
        review["body"] = body
        return review

    def _assert_rejected(self, result: dict[str, Any]) -> None:
        self.assertIsNone(result["autopilotMergeTier"]["distinctBotApproval"])
        self.assertFalse(result["ready"])
        # Treated as no approval, not a human blocker.
        self.assertEqual(result["autopilotMergeTier"]["humanBlockingComments"], [])
        self.assertTrue(
            any("blocking findings in its body" in b for b in result["blockers"]),
            result["blockers"],
        )

    def test_approval_with_shields_p1_badge_body_rejected(self) -> None:
        # A Codex-style shields.io P1 badge in the approval body is a structured
        # blocking finding; the approve-with-P1-body verdict is not clean (#621).
        review = self._approval_body(
            "Approved overall. "
            "![P1 Badge](https://img.shields.io/badge/P1-orange?style=flat) "
            "this introduces an authorization-bypass regression."
        )
        self._assert_rejected(self._evaluate(_pr(), reviews=[review]))

    def test_approval_with_bracketed_p1_body_rejected(self) -> None:
        review = self._approval_body("Approved. [P1] auth bypass introduced here.")
        self._assert_rejected(self._evaluate(_pr(), reviews=[review]))

    def test_approval_with_critical_body_rejected(self) -> None:
        review = self._approval_body("Approved. CRITICAL: authorization bypass.")
        self._assert_rejected(self._evaluate(_pr(), reviews=[review]))

    def test_approval_with_important_body_rejected(self) -> None:
        review = self._approval_body("Approving. IMPORTANT: unhandled error path.")
        self._assert_rejected(self._evaluate(_pr(), reviews=[review]))

    def test_clean_approval_body_accepted(self) -> None:
        review = self._approval_body("Approved. LGTM, no concerns.")
        result = self._evaluate(_pr(), reviews=[review])
        self.assertTrue(result["ready"], result["blockers"])
        self.assertIsNotNone(result["autopilotMergeTier"]["distinctBotApproval"])

    def test_negated_severity_approval_body_accepted(self) -> None:
        # Negation redaction: a body stating the ABSENCE of high-severity findings
        # is a clean approval, not a live one.
        review = self._approval_body("Approved. No CRITICAL or IMPORTANT findings.")
        result = self._evaluate(_pr(), reviews=[review])
        self.assertTrue(result["ready"], result["blockers"])
        self.assertIsNotNone(result["autopilotMergeTier"]["distinctBotApproval"])

    def test_lowercase_severity_prose_approval_accepted(self) -> None:
        # Lowercase "critical"/"important" are ordinary prose, not structured
        # severity labels: a clean approval describing a fix stays accepted.
        review = self._approval_body(
            "Approved. This resolves the blocking regression on the critical path."
        )
        result = self._evaluate(_pr(), reviews=[review])
        self.assertTrue(result["ready"], result["blockers"])
        self.assertIsNotNone(result["autopilotMergeTier"]["distinctBotApproval"])


class TierAbsentIsInert(TierEvaluateHarness):
    def test_no_tier_makes_no_tier_network_calls(self) -> None:
        result = self._evaluate(_pr(), tier=None)
        self.assertFalse(result["autopilotMergeTier"]["enabled"])
        self.assertFalse(result["_reviews_called"])
        self.assertFalse(result["_comments_called"])
        self.assertFalse(result["_review_comments_called"])
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


class ApprovalReportsBlockingUnit(unittest.TestCase):
    """The structured-severity scan of an approval body (#621)."""

    def test_structured_markers_are_blocking(self) -> None:
        for body in (
            "CRITICAL: bug",
            "IMPORTANT: bug",
            "see [P0] here",
            "see [P1] here",
            "![P1](https://img.shields.io/badge/P1-orange)",
        ):
            self.assertTrue(merge.approval_reports_blocking(body), body)

    def test_clean_and_prose_are_not_blocking(self) -> None:
        for body in (
            "",
            "Approved. LGTM.",
            "No CRITICAL or IMPORTANT findings.",
            "resolves the blocking regression on the critical path",
        ):
            self.assertFalse(merge.approval_reports_blocking(body), body)


class DependencyHoldIntegrationTests(unittest.TestCase):
    """The dependency-manager hold in `evaluate`'s base path, driven end-to-end
    through the real evaluate() with gh seams stubbed -- a pure-function test of
    `is_dependency_author` would pass even if the config never reached the call,
    so this exercises the actual wiring: CLI-arg-shaped frozenset -> evaluate()
    param -> the line-715 hold.
    """

    DEP_BOT = "acme-bot"

    def _evaluate(self, extra: frozenset[str]) -> dict[str, Any]:
        pr = _pr(author={"login": self.DEP_BOT}, reviewDecision="APPROVED")

        def gh_json(args: list[str]) -> Any:
            if args[:2] == ["pr", "view"]:
                return pr
            if args[0] == "api":
                return RULES
            raise AssertionError(f"unexpected gh_json call: {args}")

        with (
            mock.patch.object(merge, "gh_json", side_effect=gh_json),
            mock.patch.object(merge, "fetch_review_threads", return_value=[]),
            mock.patch.object(
                merge, "fetch_pull_request_reviews",
                return_value=[_approval("some-reviewer[bot]", HEAD)],
            ),
            mock.patch.object(merge, "fetch_issue_comments", return_value=[]),
            mock.patch.object(
                merge, "fetch_pull_request_review_comments", return_value=[],
            ),
        ):
            return merge.evaluate(
                "owner/repo", PR_NUMBER, HEAD, {"owner"}, frozenset(),
                False, False, None,
                extra_dependency_manager_logins=extra,
            )

    def _dependency_blockers(self, result: dict[str, Any]) -> list[str]:
        return [b for b in result["blockers"] if "dependency manager" in b]

    def test_unconfigured_does_not_hold_a_custom_dep_bot(self) -> None:
        # acme-bot is not a built-in dependency manager; absent config it is a
        # normal author and the dependency hold does not fire.
        result = self._evaluate(frozenset())
        self.assertEqual(self._dependency_blockers(result), [])

    def test_configured_extra_login_flips_the_hold(self) -> None:
        # Naming acme-bot in the extra set makes the very same PR held.
        result = self._evaluate(frozenset({self.DEP_BOT}))
        blockers = self._dependency_blockers(result)
        self.assertEqual(len(blockers), 1, result["blockers"])
        self.assertIn(self.DEP_BOT, blockers[0])


if __name__ == "__main__":
    unittest.main()
