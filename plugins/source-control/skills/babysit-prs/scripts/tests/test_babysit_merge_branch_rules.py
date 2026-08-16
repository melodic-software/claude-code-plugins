"""Ruleset composition in `babysit_merge.branch_rules`.

`repos/{repo}/rules/branches/{branch}` returns one rule of a given type PER
RULESET governing the branch, not one rule overall -- the shape classic branch
protection never produced. These tests pin the fold: every ruleset's contexts
survive, a context required by two rulesets is reported once, and a rule
carrying an empty context list cannot erase the contexts an earlier rule
established (which would flip `baseUnprotected` and silently drop the
unprotected-base hold on a non-self-authored PR). `pull_request` rules compose
the same way, folded max/OR so the summary can only ever over-report.

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
PR_NUMBER = 2157
CI_GATE = ["pr-title / pr-title", "do-not-merge / do-not-merge", "ci-status"]
SECURITY_GATE = ["security-review / security-review"]


def _status_checks_rule(contexts: list[str]) -> dict[str, Any]:
    return {
        "type": "required_status_checks",
        "parameters": {
            "required_status_checks": [{"context": c} for c in contexts]
        },
    }


# A base whose `pull_request` rule requires zero approving reviews, as this
# repository's does: `baseUnprotected` then hangs entirely on the context union.
NO_REQUIRED_REVIEWS = {
    "type": "pull_request",
    "parameters": {"required_approving_review_count": 0},
}


def _rules(*rules: dict[str, Any]) -> list[dict[str, Any]]:
    return list(rules)


def _branch_rules(rules: list[dict[str, Any]]) -> dict[str, object]:
    """`branch_rules` folded over `rules`, with the single gh read stubbed."""
    with mock.patch.object(merge, "gh_json", return_value=rules):
        return merge.branch_rules("owner/repo", "main")


def _pr(**overrides: Any) -> dict[str, Any]:
    pr: dict[str, Any] = {
        "state": "OPEN",
        "isDraft": False,
        "mergeable": "MERGEABLE",
        "mergeStateStatus": "CLEAN",
        "reviewDecision": "APPROVED",
        "headRefOid": HEAD,
        "baseRefName": "main",
        "author": {"login": "someone-else"},
        "url": "https://example/pr",
        "title": "t",
        "labels": [],
        "statusCheckRollup": [],
        "closingIssuesReferences": [],
    }
    pr.update(overrides)
    return pr


class BranchRulesUnionsEveryRulesetsContexts(unittest.TestCase):
    def test_contexts_from_every_ruleset_survive(self) -> None:
        summary = _branch_rules(
            _rules(
                NO_REQUIRED_REVIEWS,
                _status_checks_rule(CI_GATE),
                _status_checks_rule(SECURITY_GATE),
            )
        )
        self.assertEqual(
            summary["requiredContexts"], sorted(CI_GATE + SECURITY_GATE)
        )

    def test_a_context_required_by_two_rulesets_is_reported_once(self) -> None:
        summary = _branch_rules(
            _rules(
                _status_checks_rule(["ci-status", "pr-title / pr-title"]),
                _status_checks_rule(["ci-status"]),
            )
        )
        self.assertEqual(
            summary["requiredContexts"], ["ci-status", "pr-title / pr-title"]
        )

    def test_a_context_less_entry_is_dropped(self) -> None:
        summary = _branch_rules(
            _rules(
                {
                    "type": "required_status_checks",
                    "parameters": {
                        "required_status_checks": [{"integration_id": 1}]
                    },
                }
            )
        )
        self.assertEqual(summary["requiredContexts"], [])


class PullRequestRulesFoldFailClosed(unittest.TestCase):
    """`pull_request` composes too; max/OR can only ever hold more, never less."""

    def test_the_strictest_approval_count_wins(self) -> None:
        summary = _branch_rules(
            _rules(
                {
                    "type": "pull_request",
                    "parameters": {"required_approving_review_count": 2},
                },
                NO_REQUIRED_REVIEWS,
            )
        )
        self.assertEqual(summary["requiredApprovingReviews"], 2)

    def test_thread_resolution_required_by_any_ruleset_survives(self) -> None:
        summary = _branch_rules(
            _rules(
                {
                    "type": "pull_request",
                    "parameters": {"required_review_thread_resolution": True},
                },
                NO_REQUIRED_REVIEWS,
            )
        )
        self.assertTrue(summary["requireThreadResolution"])

    def test_an_unreadable_count_counts_as_one_not_zero(self) -> None:
        """Every FALSY non-int too -- the shape that keeps re-opening this hole.

        `None` is the realistic one: a ruleset payload carrying the key with a
        null value. A truthiness test reads all of these as zero, which is the
        fail-open this fold exists to prevent.
        """
        for raw in (None, "", 0.0, [], {}, "two", object()):
            with self.subTest(raw=raw):
                summary = _branch_rules(
                    _rules(
                        {
                            "type": "pull_request",
                            "parameters": {
                                "required_approving_review_count": raw
                            },
                        }
                    )
                )
                self.assertEqual(summary["requiredApprovingReviews"], 1)

    def test_an_absent_count_is_zero_not_one(self) -> None:
        """Absence is readable: the rule states no review requirement."""
        summary = _branch_rules(
            _rules({"type": "pull_request", "parameters": {}})
        )
        self.assertEqual(summary["requiredApprovingReviews"], 0)

    def test_a_readable_count_is_reported_as_an_int(self) -> None:
        """`bool` is an `int` subclass; it must not leak into the summary."""
        summary = _branch_rules(
            _rules(
                {
                    "type": "pull_request",
                    "parameters": {"required_approving_review_count": True},
                }
            )
        )
        self.assertIs(type(summary["requiredApprovingReviews"]), int)
        self.assertEqual(summary["requiredApprovingReviews"], 1)


class AnEmptyLaterRuleCannotUnprotectTheBase(unittest.TestCase):
    """The union keeps `baseUnprotected` honest, and with it the merge hold.

    Only the first case regresses. `test_no_context_anywhere_...` passes against
    the unfixed code too, by design: it is the over-correction guard, pinning
    that a genuinely context-less base still reports unprotected. Do not count
    it among the regression tests.
    """

    def _evaluate(self, rules: list[dict[str, Any]]) -> dict[str, Any]:
        def gh_json(args: list[str]) -> Any:
            if args[:2] == ["pr", "view"]:
                return _pr()
            if args[0] == "api" and "/rules/branches/" in args[1]:
                return rules
            if args[0] == "api":  # repository metadata (default-branch read)
                return {"name": "main"}
            raise AssertionError(f"unexpected gh_json call: {args}")

        with (
            mock.patch.object(merge, "gh_json", side_effect=gh_json),
            mock.patch.object(merge, "fetch_review_threads", return_value=[]),
        ):
            return merge.evaluate(
                "owner/repo", PR_NUMBER, None, {"owner"}, frozenset(), False, False,
            )

    def test_empty_trailing_rule_leaves_the_base_protected(self) -> None:
        result = self._evaluate(
            _rules(
                NO_REQUIRED_REVIEWS,
                _status_checks_rule(["ci-status"]),
                _status_checks_rule([]),
            )
        )
        self.assertFalse(result["baseUnprotected"])
        self.assertEqual(
            [b for b in result["blockers"] if "unprotected" in b], []
        )

    def test_no_context_anywhere_still_reports_an_unprotected_base(self) -> None:
        result = self._evaluate(_rules(NO_REQUIRED_REVIEWS, _status_checks_rule([])))
        self.assertTrue(result["baseUnprotected"])
        self.assertTrue([b for b in result["blockers"] if "unprotected" in b])


if __name__ == "__main__":
    unittest.main()
