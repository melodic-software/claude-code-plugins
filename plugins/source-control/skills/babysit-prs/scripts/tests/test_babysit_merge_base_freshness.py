"""The merge gate's hold on a head behind its base (#5955).

Under loose required status checks GitHub reports a behind head `CLEAN`, so
`mergeStateStatus` alone lets the gate merge it, and a squash of a behind head
can drop base commits. The gate compares the head against the live base once
the PR is otherwise ready, unless the base requires up-to-date branches
(GitHub then reports BEHIND itself) or a merge queue (which tests the merged
result itself).

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
PR_NUMBER = 5955
UP_TO_DATE = {"status": "ahead", "ahead_by": 1, "behind_by": 0}
BEHIND = {"status": "diverged", "ahead_by": 1, "behind_by": 3}


def _status_checks(*, strict: bool) -> dict[str, Any]:
    return {
        "type": "required_status_checks",
        "parameters": {
            "required_status_checks": [{"context": "ci-status"}],
            "strict_required_status_checks_policy": strict,
        },
    }


LOOSE = [_status_checks(strict=False)]
STRICT = [_status_checks(strict=True)]
QUEUE = [_status_checks(strict=False), {"type": "merge_queue", "parameters": {}}]


def _check(name: str, conclusion: str | None) -> dict[str, Any]:
    return {
        "__typename": "CheckRun",
        "name": name,
        "status": "COMPLETED" if conclusion else "IN_PROGRESS",
        "conclusion": conclusion or "",
    }


def _pr(**overrides: Any) -> dict[str, Any]:
    pr: dict[str, Any] = {
        "state": "OPEN",
        "isDraft": False,
        "mergeable": "MERGEABLE",
        "mergeStateStatus": "CLEAN",
        "reviewDecision": "",
        "headRefOid": HEAD,
        "baseRefName": "main",
        "author": {"login": "someone-else"},
        "url": "https://example/pr",
        "title": "t",
        "labels": [],
        "statusCheckRollup": [_check("ci-status", "SUCCESS")],
        "closingIssuesReferences": [],
    }
    pr.update(overrides)
    return pr


class BaseFreshnessHarness(unittest.TestCase):
    def _evaluate(
        self,
        rules: list[dict[str, Any]],
        compare: Any = UP_TO_DATE,
        **pr_overrides: Any,
    ) -> dict[str, Any]:
        self.compare_calls: list[list[str]] = []

        def gh_json(args: list[str]) -> Any:
            if args[:2] == ["pr", "view"]:
                return _pr(**pr_overrides)
            if args[0] == "api" and "/compare/" in args[1]:
                self.compare_calls.append(args)
                if isinstance(compare, Exception):
                    raise compare
                return compare
            if args[0] == "api" and "/rules/branches/" in args[1]:
                return rules
            if args[0] == "api" and args[1] == "repos/owner/repo":
                return {"name": "main"}
            raise AssertionError(f"unexpected gh_json call: {args}")

        with (
            mock.patch.object(merge, "gh_json", side_effect=gh_json),
            mock.patch.object(merge, "fetch_review_threads", return_value=[]),
        ):
            return merge.evaluate(
                "owner/repo", PR_NUMBER, HEAD, {"owner"}, frozenset(), False, False,
            )

    def _freshness_blockers(self, result: dict[str, Any]) -> list[str]:
        return [b for b in result["blockers"] if "base 'main'" in b]


class LooseBaseHoldsABehindCleanHead(BaseFreshnessHarness):
    def test_clean_head_behind_a_loose_base_is_held(self) -> None:
        result = self._evaluate(LOOSE, BEHIND)
        self.assertFalse(result["ready"])
        self.assertEqual(
            self._freshness_blockers(result),
            [
                "head is 3 commit(s) behind base 'main', which does not require "
                "up-to-date branches -- refresh the branch before merging"
            ],
        )
        self.assertTrue(result["baseFreshness"]["behind"])
        self.assertEqual(
            self.compare_calls, [["api", f"repos/owner/repo/compare/main...{HEAD}"]]
        )

    def test_has_hooks_head_behind_a_loose_base_is_held(self) -> None:
        result = self._evaluate(LOOSE, BEHIND, mergeStateStatus="HAS_HOOKS")
        self.assertFalse(result["ready"])
        self.assertTrue(self._freshness_blockers(result))

    def test_clean_head_up_to_date_with_a_loose_base_is_ready(self) -> None:
        result = self._evaluate(LOOSE, UP_TO_DATE)
        self.assertTrue(result["ready"], result["blockers"])
        self.assertEqual(
            result["baseFreshness"],
            {"checked": True, "compare": UP_TO_DATE, "behind": False},
        )
        self.assertEqual(len(self.compare_calls), 1)

    def test_an_unreadable_compare_holds(self) -> None:
        result = self._evaluate(LOOSE, RuntimeError("gh: Server Error (HTTP 502)"))
        self.assertFalse(result["ready"])
        self.assertTrue(
            any("freshness is UNPROVEN" in b for b in result["blockers"]),
            result["blockers"],
        )

    def test_auto_merge_is_not_armed_over_a_behind_head(self) -> None:
        # Only a running required check holds the merge, which `--auto` may arm
        # over; on a loose base GitHub would then merge the behind head itself.
        result = self._evaluate(
            LOOSE,
            BEHIND,
            mergeStateStatus="BLOCKED",
            statusCheckRollup=[
                _check("ci-status", None),
                _check("claude-review-status", "SUCCESS"),
                _check("claude-security-review-status", "SUCCESS"),
            ],
        )
        self.assertFalse(result["autoMerge"]["ready"])
        self.assertTrue(
            any("behind base" in b for b in result["autoMerge"]["blockers"]),
            result["autoMerge"],
        )


class BasesThatProveFreshnessThemselvesMakeNoCompare(BaseFreshnessHarness):
    def test_a_merge_queue_base_is_unchanged(self) -> None:
        result = self._evaluate(QUEUE, BEHIND)
        self.assertTrue(result["ready"], result["blockers"])
        self.assertEqual(result["mergeAction"], "merge_queue")
        self.assertEqual(self.compare_calls, [])
        self.assertFalse(result["baseFreshness"]["checked"])

    def test_a_strict_base_makes_no_compare(self) -> None:
        result = self._evaluate(STRICT, BEHIND)
        self.assertTrue(result["ready"], result["blockers"])
        self.assertEqual(self.compare_calls, [])

    def test_a_pr_already_held_pays_no_compare(self) -> None:
        result = self._evaluate(LOOSE, BEHIND, isDraft=True)
        self.assertFalse(result["ready"])
        self.assertEqual(self.compare_calls, [])


class StrictRequiredChecksFold(unittest.TestCase):
    def test_one_strict_ruleset_marks_the_base_up_to_date_required(self) -> None:
        with mock.patch.object(merge, "gh_json", return_value=[*LOOSE, *STRICT]):
            summary = merge.branch_rules("owner/repo", "main")
        self.assertTrue(summary["requireUpToDate"])

    def test_loose_rulesets_do_not(self) -> None:
        with mock.patch.object(merge, "gh_json", return_value=LOOSE):
            summary = merge.branch_rules("owner/repo", "main")
        self.assertFalse(summary["requireUpToDate"])


if __name__ == "__main__":
    unittest.main()
