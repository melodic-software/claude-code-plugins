"""A `--merge` run re-runs an AI review check that failed on the usage limit.

The re-run fires only for a `class=rate-limit` annotation, only five hours
after the failure, only on the pinned live head, and only on a run's first
attempt. Network is stubbed through `babysit_merge`'s gh seams.
"""

from __future__ import annotations

import contextlib
import io
import json
import pathlib
import sys
import unittest
from datetime import datetime
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_merge as merge
import test_babysit_merge as base
from repo_config_fake import RepoConfigFake

HEAD = base.HEAD
REPO = "owner/repo"
RUN_ID = 111
JOB_ID = 222
FAILED_AT = "2026-10-09T10:00:00Z"
CHECK = {
    "name": "pr-review / claude-review-status",
    "effective_state": "FAILURE",
    "details_url": f"https://github.com/{REPO}/actions/runs/{RUN_ID}/job/{JOB_ID}",
}
RATE_LIMITED = (
    "Claude review exited with: failure class=rate-limit -- an infrastructure "
    "failure, not a code-quality signal"
)


def _job(**overrides: Any) -> dict[str, Any]:
    job = {
        "run_id": RUN_ID,
        "head_sha": HEAD,
        "conclusion": "failure",
        "run_attempt": 1,
        "completed_at": FAILED_AT,
        "check_run_url": f"https://api.github.com/repos/{REPO}/check-runs/{JOB_ID}",
    }
    return {**job, **overrides}


class RerunRateLimitedReview(unittest.TestCase):
    def _run(
        self,
        *,
        job: dict[str, Any] | None = None,
        annotations: list[str] = (RATE_LIMITED,),  # type: ignore[assignment]
        now: str = "2026-10-09T15:00:00Z",
        check: dict[str, Any] = CHECK,
    ) -> tuple[dict[str, Any], list[list[str]]]:
        reads: list[list[str]] = []
        posts: list[list[str]] = []

        def gh_json(args: list[str]) -> Any:
            reads.append(args)
            if args[1] == f"repos/{REPO}/actions/jobs/{JOB_ID}":
                return job if job is not None else _job()
            if args[1].startswith(f"repos/{REPO}/check-runs/{JOB_ID}/annotations"):
                return [{"message": text} for text in annotations]
            raise AssertionError(f"unexpected gh_json call: {args}")

        def capture(cmd: list[str]) -> Any:
            posts.append(cmd)
            return mock.Mock(returncode=0, stdout="", stderr="")

        clock = datetime.fromisoformat(now.replace("Z", "+00:00"))
        with (
            mock.patch.object(merge, "gh_json", side_effect=gh_json),
            mock.patch.object(merge, "gh_capture", side_effect=capture),
            mock.patch.object(merge, "_now", return_value=clock),
        ):
            report = merge.rerun_rate_limited_review(REPO, HEAD, check)
        self.reads = reads
        return report, posts

    def test_rate_limit_past_the_reset_reruns_the_whole_run(self) -> None:
        report, posts = self._run()
        self.assertTrue(report["rerun"], report)
        self.assertEqual(
            posts, [["api", "-X", "POST", f"repos/{REPO}/actions/runs/{RUN_ID}/rerun"]]
        )

    def test_before_the_reset_waits_without_reading_annotations(self) -> None:
        report, posts = self._run(now="2026-10-09T14:59:00Z")
        self.assertFalse(report["rerun"])
        self.assertIn("2026-10-09T15:00:00Z", report["reason"])
        self.assertEqual(posts, [])
        self.assertEqual(len(self.reads), 1)

    def test_other_failure_class_is_never_rerun(self) -> None:
        for text in (
            "Claude review exited with: failure class=timeout",
            "Claude review exited with: failure class=other",
        ):
            report, posts = self._run(annotations=[text])
            self.assertFalse(report["rerun"])
            self.assertEqual(posts, [], text)

    def test_a_rerun_attempt_is_not_rerun_again(self) -> None:
        report, posts = self._run(job=_job(run_attempt=2))
        self.assertFalse(report["rerun"])
        self.assertEqual(posts, [])

    def test_a_job_on_another_head_is_left_alone(self) -> None:
        report, posts = self._run(job=_job(head_sha=base.STALE))
        self.assertFalse(report["rerun"])
        self.assertEqual(posts, [])

    def test_a_non_actions_check_is_left_alone(self) -> None:
        report, posts = self._run(check={**CHECK, "details_url": "https://example"})
        self.assertFalse(report["rerun"])
        self.assertEqual((posts, self.reads), ([], []))

    def test_a_failed_read_is_reported_not_raised(self) -> None:
        with mock.patch.object(merge, "gh_json", side_effect=RuntimeError("boom")):
            report = merge.rerun_rate_limited_review(REPO, HEAD, CHECK)
        self.assertFalse(report["rerun"])
        self.assertIn("boom", report["reason"])


class RerunScope(unittest.TestCase):
    RESULT = {
        "headRefOid": HEAD,
        "headMatches": True,
        "state": "OPEN",
        "isDraft": False,
        "aiReviewChecks": [
            CHECK,
            {
                **CHECK,
                "name": "pr-review-security / security-review",
                "effective_state": "SUCCESS",
            },
        ],
    }

    def _reruns(self, **overrides: Any) -> mock.Mock:
        with mock.patch.object(
            merge, "rerun_rate_limited_review", return_value={}
        ) as one:
            merge.rerun_rate_limited_reviews(REPO, {**self.RESULT, **overrides})
        return one

    def test_only_failed_checks_on_the_pinned_open_head_are_considered(self) -> None:
        one = self._reruns()
        one.assert_called_once_with(REPO, HEAD, CHECK)

    def test_unpinned_moved_draft_or_closed_heads_are_skipped(self) -> None:
        for overrides in (
            {"headMatches": None},
            {"headMatches": False},
            {"isDraft": True},
            {"state": "MERGED"},
        ):
            self._reruns(**overrides).assert_not_called()


class EvaluateReportsAiReviewChecks(unittest.TestCase):
    def setUp(self) -> None:
        RepoConfigFake().install(self)

    def test_ai_review_checks_carry_their_details_url(self) -> None:
        url = CHECK["details_url"]
        rollup = [
            base._check("ci-status", "SUCCESS"),
            {
                **base._check("pr-review / claude-review-status", "FAILURE"),
                "detailsUrl": url,
            },
            base._check("pr-review-security / security-review", "SUCCESS"),
        ]
        result = base.AutoMergeArming()._evaluate(rollup, mergeStateStatus="BLOCKED")
        self.assertEqual(
            [
                (c["name"], c["effective_state"], c["details_url"])
                for c in result["aiReviewChecks"]
            ],
            [
                ("pr-review / claude-review-status", "FAILURE", url),
                ("pr-review-security / security-review", "SUCCESS", ""),
            ],
        )
        self.assertFalse(result["autoMerge"]["ready"])


class MainRerunsOnlyUnderMerge(unittest.TestCase):
    def setUp(self) -> None:
        RepoConfigFake().install(self)

    def _main(self, *extra: str) -> mock.Mock:
        result = {
            "ready": False,
            "blockers": ["failing checks: pr-review / claude-review-status"],
            "headRefOid": HEAD,
            "autoMerge": {"ready": False, "blockers": []},
        }
        argv = ["babysit_merge.py", f"{REPO}#1", "--allowed-owners", "owner", *extra]
        with (
            mock.patch.object(sys, "argv", argv),
            mock.patch.object(merge, "evaluate", return_value=result),
            mock.patch.object(
                merge, "rerun_rate_limited_reviews", return_value=[{"rerun": True}]
            ) as reruns,
            mock.patch.object(merge, "gh_capture") as capture,
            contextlib.redirect_stdout(io.StringIO()) as out,
        ):
            self.code = merge.main()
        self.output = json.loads(out.getvalue())
        capture.assert_not_called()
        return reruns

    def test_check_only_never_reruns(self) -> None:
        self._main().assert_not_called()
        self.assertNotIn("aiReviewReruns", self.output)

    def test_held_merge_reruns_and_still_holds(self) -> None:
        reruns = self._main("--merge", "--expected-head", HEAD, "--auto")
        reruns.assert_called_once()
        self.assertEqual(self.code, 10)
        self.assertFalse(self.output["merged"])
        self.assertEqual(self.output["aiReviewReruns"], [{"rerun": True}])


if __name__ == "__main__":
    unittest.main()
