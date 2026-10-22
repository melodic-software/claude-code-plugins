"""`cost_decision`: only an owner `**Decision recorded.**` comment on the
closing issue or the pull request, linked from the body, clears a cost hold."""

from __future__ import annotations

import pathlib
import sys
import unittest
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_merge_policy as policy

REPO = "owner/repo"
LINK = "https://github.com/owner/repo/issues/40#issuecomment-7"
IDENTITY = "agent-lanes[bot]"


def _comment(**changes: Any) -> dict[str, Any]:
    return {
        "issue_url": "https://api.github.com/repos/owner/repo/issues/40",
        "user": {"login": "owner-person", "type": "User"},
        "performed_via_github_app": None,
        "body": "**Decision recorded.** Approve the larger runner.",
        "node_id": "IC_7",
    } | changes


class CostDecision(unittest.TestCase):
    def decide(
        self,
        *,
        body: str = f"Closes #40\n\nCost decision: {LINK}\n",
        comment: dict[str, Any] | None = None,
        status: int = 200,
        permission: str = "admin",
        edited: Any = None,
        issue: int | None = 40,
    ) -> str | None:
        self.reads: list[str] = []

        def get(endpoint: str) -> tuple[int, Any]:
            self.reads.append(endpoint)
            return status, comment if comment is not None else _comment()

        graphql = mock.Mock(return_value={"node": {"lastEditedAt": edited}})
        with (
            mock.patch.object(policy, "_get", side_effect=get),
            mock.patch.object(policy, "_graphql", graphql),
        ):
            return policy.cost_decision(
                REPO,
                {"number": 99, "body": body},
                issue,
                permission=lambda login: permission,
                agent_identity=IDENTITY,
            )

    def test_an_owner_decision_on_the_closing_issue_clears(self) -> None:
        self.assertEqual(self.decide(), LINK)
        self.assertEqual(self.reads, ["repos/owner/repo/issues/comments/7"])

    def test_a_decision_on_the_pull_request_itself_clears(self) -> None:
        link = "https://github.com/owner/repo/pull/99#issuecomment-7"
        comment = _comment(
            issue_url="https://api.github.com/repos/owner/repo/issues/99"
        )
        self.assertEqual(self.decide(body=link, comment=comment), link)

    def test_a_decision_on_another_issue_does_not_cover_it(self) -> None:
        other = "https://github.com/owner/repo/issues/12#issuecomment-7"
        self.assertIsNone(self.decide(body=other))
        self.assertEqual(self.reads, [])

    def test_a_link_into_another_repository_is_ignored(self) -> None:
        self.assertIsNone(self.decide(body=LINK.replace("owner/repo", "evil/repo")))

    def test_a_comment_that_is_not_on_the_linked_issue_is_refused(self) -> None:
        moved = _comment(issue_url="https://api.github.com/repos/owner/repo/issues/41")
        self.assertIsNone(self.decide(comment=moved))

    def test_each_failing_condition_holds(self) -> None:
        cases = {
            "write, not admin": dict(permission="write"),
            "edited": dict(edited="2026-10-22T10:00:00Z"),
            "unreadable": dict(status=404),
            "no decision line": dict(comment=_comment(body="Sounds fine to me.")),
            "quoted decision": dict(
                comment=_comment(body="> **Decision recorded.** quoted")
            ),
            "posted through an App": dict(
                comment=_comment(performed_via_github_app={"slug": "cursor"})
            ),
            "a bot": dict(
                comment=_comment(user={"login": "agent-lanes[bot]", "type": "Bot"})
            ),
            "the agent identity": dict(
                comment=_comment(user={"login": "agent-lanes", "type": "User"})
            ),
            "no body link": dict(body="Closes #40"),
        }
        for name, change in cases.items():
            with self.subTest(name):
                self.assertIsNone(self.decide(**change))

    def test_a_failed_permission_read_clears_nothing(self) -> None:
        def refuse(login: str) -> str:
            raise policy.PolicyReadError("permission unreadable")

        with (
            mock.patch.object(policy, "_get", return_value=(200, _comment())),
            mock.patch.object(policy, "_graphql") as graphql,
        ):
            decision = policy.cost_decision(
                REPO,
                {"number": 99, "body": LINK},
                40,
                permission=refuse,
                agent_identity=IDENTITY,
            )
        self.assertIsNone(decision)
        graphql.assert_not_called()


if __name__ == "__main__":
    unittest.main()
