# test-scope: plugins/source-control/skills/babysit-prs/scripts/tests/fixtures/review_evidence/*
"""A `--merge` run re-runs an AI review check that failed on the usage limit
or on its runner install.

The re-run fires only for a failure annotation the review evidence accepts a
re-run after and the gate re-runs (`class=rate-limit` or this lane's publish
failure on GitHub's API rate limit, five hours after the failure; this lane's
`install-failed` failure at once), only on the pinned live head, and only on a
run's first attempt. Network is stubbed through `babysit_merge`'s gh seams.
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
import babysit_merge_skip as skip
import test_babysit_merge as base
import test_babysit_review_evidence as evidence_tests
from repo_config_fake import RepoConfigFake

HEAD = base.HEAD
REPO = "owner/repo"
RUN_ID = 111
JOB_ID = 222
FAILED_AT = "2026-10-09T10:00:00Z"
STARTED_AT = "2026-10-09T09:50:00Z"
# Shapes follow live payloads (2026-10-09): `gh pr view --json
# statusCheckRollup` gives a CheckRun no id, and an Actions job's `id`, its
# `check_run_url` tail and its check run's id are one number.
CHECK = {
    "name": "pr-review / claude-review-status",
    "id": "",
    "workflow_name": "pr-review-hosted",
    "effective_state": "FAILURE",
    "details_url": f"https://github.com/{REPO}/actions/runs/{RUN_ID}/job/{JOB_ID}",
}
RATE_LIMITED = (
    "Claude review exited with: failure class=rate-limit -- an infrastructure "
    "failure, not a code-quality signal"
)
INSTALL_FAILED = evidence_tests.INSTALL_FAILURE["message"]
SECURITY_CHECK = {
    **CHECK,
    "name": "pr-review-security / security-review",
    "workflow_name": "pr-review-security-hosted",
}


def _job(**overrides: Any) -> dict[str, Any]:
    job = {
        "id": JOB_ID,
        "run_id": RUN_ID,
        "name": "pr-review / claude-review-status",
        "workflow_name": "pr-review-hosted",
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
        annotations: list[str | dict[str, Any]] = (RATE_LIMITED,),  # type: ignore[assignment]
        now: str = "2026-10-09T15:00:00Z",
        check: dict[str, Any] = CHECK,
        attempt_conclusion: str = "failure",
        comments: list[dict[str, Any]] = (),  # type: ignore[assignment]
        number: int | None = 7,
    ) -> tuple[dict[str, Any], list[list[str]]]:
        reads: list[list[str]] = []
        posts: list[list[str]] = []
        self.comment_reads: list[str] = []

        def pages(endpoint: str, label: str) -> list[dict[str, Any]]:
            self.comment_reads.append(endpoint)
            return list(comments)

        def gh_json(args: list[str]) -> Any:
            reads.append(args)
            if args[1] == f"repos/{REPO}/actions/jobs/{JOB_ID}":
                return job if job is not None else _job()
            if args[1].startswith(f"repos/{REPO}/check-runs/{JOB_ID}/annotations"):
                # The check-runs annotations payload carries each level.
                return [
                    a
                    if isinstance(a, dict)
                    else {"annotation_level": "failure", "message": a}
                    for a in annotations
                ]
            if args[1] == f"repos/{REPO}/actions/runs/{RUN_ID}/attempts/1":
                return {
                    "run_attempt": 1,
                    "conclusion": attempt_conclusion,
                    "run_started_at": STARTED_AT,
                }
            raise AssertionError(f"unexpected gh_json call: {args}")

        def capture(cmd: list[str]) -> Any:
            posts.append(cmd)
            return mock.Mock(returncode=0, stdout="", stderr="")

        clock = datetime.fromisoformat(now.replace("Z", "+00:00"))
        with (
            mock.patch.object(merge, "gh_json", side_effect=gh_json),
            mock.patch.object(merge, "gh_capture", side_effect=capture),
            mock.patch.object(merge, "fetch_paginated_api", side_effect=pages),
            mock.patch.object(merge, "_now", return_value=clock),
        ):
            report = merge.rerun_rate_limited_review(REPO, HEAD, check, number=number)
        self.reads = reads
        return report, posts

    def test_rate_limit_past_the_reset_reruns_the_whole_run(self) -> None:
        report, posts = self._run()
        self.assertTrue(report["rerun"], report)
        self.assertEqual(
            posts, [["api", "-X", "POST", f"repos/{REPO}/actions/runs/{RUN_ID}/rerun"]]
        )

    def test_a_failed_job_in_an_attempt_that_did_not_fail_is_not_rerun(self) -> None:
        # The binding (review_evidence.rerun_binds) takes attempt 2 only
        # after an attempt 1 that concluded failure, so a re-run of any other
        # attempt would spend the one allowed attempt on a hold.
        for conclusion in ("cancelled", "success"):
            with self.subTest(conclusion):
                report, posts = self._run(attempt_conclusion=conclusion)
                self.assertFalse(report["rerun"])
                self.assertIn(conclusion, report["reason"])
                self.assertEqual(posts, [])

    def test_an_attempt_still_running_is_read_again_by_the_next_gate(self) -> None:
        # A sibling job can keep attempt 1 open after the lane job failed; a
        # stable reason here would freeze the skip before the run concludes.
        report, posts = self._run(attempt_conclusion=None)  # type: ignore[arg-type]
        self.assertFalse(report["rerun"])
        self.assertEqual(posts, [])
        self.assertFalse(report["reason"].startswith(skip.STABLE_RERUNS), report)

    def test_before_the_reset_a_rate_limit_waits(self) -> None:
        report, posts = self._run(now="2026-10-09T14:59:00Z")
        self.assertFalse(report["rerun"])
        self.assertIn("2026-10-09T15:00:00Z", report["reason"])
        self.assertEqual(posts, [])
        # The job and its annotations, not the attempt.
        self.assertEqual(len(self.reads), 2)

    def test_other_failure_class_is_never_rerun(self) -> None:
        for text in (
            "Claude review exited with: failure class=timeout",
            "Claude review exited with: failure class=other",
            # Classes the evidence binds a re-run after, but the gate leaves
            # to a person.
            evidence_tests.AUTH_FAILURE["message"],
        ):
            report, posts = self._run(annotations=[text])
            self.assertFalse(report["rerun"])
            self.assertTrue(
                report["reason"].startswith("failure class is not "), report
            )
            self.assertEqual(posts, [], text)

    def test_an_install_failure_reruns_at_once(self) -> None:
        security = INSTALL_FAILED.replace("claude-review:", "claude-security-review:", 1)
        for check, text in ((CHECK, INSTALL_FAILED), (SECURITY_CHECK, security)):
            with self.subTest(check["name"]):
                report, posts = self._run(
                    job=_job(name=check["name"], workflow_name=check["workflow_name"]),
                    annotations=[text],
                    check=check,
                    # A minute after the failure: no wait.
                    now="2026-10-09T10:01:00Z",
                )
                self.assertTrue(report["rerun"], report)
                self.assertEqual(
                    posts,
                    [["api", "-X", "POST", f"repos/{REPO}/actions/runs/{RUN_ID}/rerun"]],
                )

    def test_an_install_failure_is_rerun_once(self) -> None:
        report, posts = self._run(
            job=_job(run_attempt=2), annotations=[INSTALL_FAILED]
        )
        self.assertFalse(report["rerun"])
        self.assertIn("re-run at most once", report["reason"])
        self.assertEqual(posts, [])

    def test_an_install_failure_beside_a_rate_limit_waits(self) -> None:
        report, posts = self._run(
            annotations=[INSTALL_FAILED, RATE_LIMITED], now="2026-10-09T10:01:00Z"
        )
        self.assertFalse(report["rerun"])
        self.assertIn("2026-10-09T15:00:00Z", report["reason"])
        self.assertEqual(posts, [])

    def test_a_credential_failure_beside_an_install_failure_is_never_rerun(
        self,
    ) -> None:
        report, posts = self._run(
            annotations=[INSTALL_FAILED, evidence_tests.AUTH_FAILURE["message"]],
            now="2026-10-09T10:01:00Z",
        )
        self.assertFalse(report["rerun"])
        self.assertTrue(report["reason"].startswith("failure class is not "), report)
        self.assertEqual(posts, [])

    def test_an_install_failure_lookalike_is_never_rerun(self) -> None:
        for text in (
            # Another lane's line.
            INSTALL_FAILED.replace("claude-review:", "claude-security-review:", 1),
            # Not at the message start.
            f"quoted: {INSTALL_FAILED}",
            # Another class sharing the prefix.
            "claude-review: failure-class=install-failed-x: something else",
        ):
            with self.subTest(text[:50]):
                report, posts = self._run(
                    annotations=[text], now="2026-10-09T10:01:00Z"
                )
                self.assertFalse(report["rerun"])
                self.assertEqual(posts, [])

    def test_the_gate_reruns_only_classes_whose_rerun_binds(self) -> None:
        # A re-run the evidence would not bind spends the one allowed attempt
        # for nothing.
        # `LOST` is a conclusion, not an annotation; LostReviewRerun covers it.
        self.assertLessEqual(
            merge.review_evidence.GATE_RERUN_CLASSES,
            {*merge.review_evidence.RERUN_CLASSES, merge.review_evidence.LOST},
        )
        self.assertLessEqual(
            merge.NO_WAIT_RERUN_CLASSES, merge.review_evidence.GATE_RERUN_CLASSES
        )

    def test_a_rate_limit_notice_is_not_a_failure_class(self) -> None:
        report, posts = self._run(
            annotations=[{"annotation_level": "notice", "message": RATE_LIMITED}]
        )
        self.assertFalse(report["rerun"])
        self.assertEqual(posts, [])

    def _publish_check(self, check: dict[str, Any]) -> dict[str, Any]:
        return _job(name=check["name"], workflow_name=check["workflow_name"])

    def test_a_publish_rate_limit_reruns_its_lane(self) -> None:
        # The texts the review evidence binds attempt 2 after.
        primary = evidence_tests.PUBLISH_RATE_LIMIT["message"]
        secondary = evidence_tests.publish_failed(
            "You have exceeded a secondary rate limit. Please wait a few minutes"
        )["message"]
        security = primary.replace("claude-review:", "claude-security-review:", 1)
        for check, text in (
            (CHECK, primary),
            (CHECK, secondary),
            (SECURITY_CHECK, security),
        ):
            report, posts = self._run(
                job=self._publish_check(check), annotations=[text], check=check
            )
            self.assertTrue(report["rerun"], (check["name"], text, report))
            self.assertEqual(len(posts), 1)

    def test_a_publish_failure_the_evidence_refuses_is_never_rerun(self) -> None:
        primary = evidence_tests.PUBLISH_RATE_LIMIT["message"]
        for check, text in (
            # Another lane's publish line.
            (SECURITY_CHECK, primary),
            # A publish failure that is not GitHub's rate limit.
            (
                CHECK,
                evidence_tests.publish_failed("Resource not accessible by integration")[
                    "message"
                ],
            ),
            # The publish line not at the message start.
            (CHECK, f"quoted: {primary}"),
        ):
            report, posts = self._run(
                job=self._publish_check(check), annotations=[text], check=check
            )
            self.assertFalse(report["rerun"], (check["name"], text))
            self.assertEqual(posts, [], text)

    def test_a_rerun_attempt_is_not_rerun_again(self) -> None:
        report, posts = self._run(job=_job(run_attempt=2))
        self.assertFalse(report["rerun"])
        self.assertEqual(posts, [])

    def test_a_job_on_another_head_is_left_alone(self) -> None:
        report, posts = self._run(job=_job(head_sha=base.STALE))
        self.assertFalse(report["rerun"])
        self.assertEqual(posts, [])

    def test_a_rollup_check_id_matching_the_job_reruns(self) -> None:
        report, _ = self._run(check={**CHECK, "id": str(JOB_ID)})
        self.assertTrue(report["rerun"], report)

    def test_a_job_that_did_not_emit_the_check_is_left_alone(self) -> None:
        other_run = f"https://api.github.com/repos/{REPO}/check-runs/999"
        for job, check in (
            (_job(id=999), CHECK),
            (_job(check_run_url=other_run), CHECK),
            (_job(name="other / claude-review-status"), CHECK),
            (_job(workflow_name="other-workflow"), CHECK),
            (_job(), {**CHECK, "id": "999"}),
        ):
            report, posts = self._run(job=job, check=check)
            self.assertFalse(report["rerun"], (job, check))
            self.assertIn("did not emit this check", report["reason"])
            self.assertEqual((posts, len(self.reads)), ([], 1))

    def test_a_non_actions_check_is_left_alone(self) -> None:
        report, posts = self._run(check={**CHECK, "details_url": "https://example"})
        self.assertFalse(report["rerun"])
        self.assertEqual((posts, self.reads), ([], []))

    def test_a_failed_read_is_reported_not_raised(self) -> None:
        with mock.patch.object(merge, "gh_json", side_effect=RuntimeError("boom")):
            report = merge.rerun_rate_limited_review(REPO, HEAD, CHECK)
        self.assertFalse(report["rerun"])
        self.assertIn("boom", report["reason"])

    def test_a_plain_failure_is_never_rerun(self) -> None:
        # A failure outside the listed classes, with no annotation at all:
        # the lane judged the head, so a re-run could trade its verdict away.
        report, posts = self._run(annotations=[])
        self.assertFalse(report["rerun"])
        self.assertTrue(report["reason"].startswith("failure class is not "), report)
        self.assertEqual((posts, self.comment_reads), ([], []))


def _marker(
    lane: str = "claude-review",
    sha: str = HEAD,
    at: str = "2026-10-09T09:55:00Z",
    edited: str | None = None,
) -> dict[str, Any]:
    """A REST issue comment, whose `updated_at` equals `created_at` until an
    edit."""
    return {
        "id": 1,
        "user": {"login": "github-actions[bot]", "type": "Bot"},
        "created_at": at,
        "updated_at": edited or at,
        "body": f"<!-- claude-lane-reviewed-head lane={lane} sha={sha} -->\nreviewed",
    }


class LostReviewRerun(unittest.TestCase):
    """A review run an outage lost (cancelled, timed out) is re-run at once,
    once, only while nothing shows its lane posted on the head."""

    _run = RerunRateLimitedReview._run

    def _lost(self, conclusion: str = "cancelled", **kwargs: Any) -> Any:
        kwargs.setdefault("annotations", [])
        kwargs.setdefault("now", "2026-10-09T10:01:00Z")
        kwargs.setdefault("attempt_conclusion", conclusion)
        return self._run(job=kwargs.pop("job", _job(conclusion=conclusion)), **kwargs)

    def test_a_lost_run_is_rerun_at_once(self) -> None:
        for conclusion in ("cancelled", "timed_out"):
            with self.subTest(conclusion):
                report, posts = self._lost(conclusion)
                self.assertTrue(report["rerun"], report)
                self.assertEqual(
                    posts,
                    [["api", "-X", "POST", f"repos/{REPO}/actions/runs/{RUN_ID}/rerun"]],
                )
                self.assertEqual(
                    self.comment_reads, [f"repos/{REPO}/issues/7/comments?per_page=100"]
                )

    def test_a_lost_security_run_is_rerun(self) -> None:
        report, _ = self._lost(
            job=_job(
                conclusion="cancelled",
                name=SECURITY_CHECK["name"],
                workflow_name=SECURITY_CHECK["workflow_name"],
            ),
            check=SECURITY_CHECK,
        )
        self.assertTrue(report["rerun"], report)

    def test_a_lost_run_that_recorded_a_review_is_left_to_a_person(self) -> None:
        done = evidence_tests.record(
            "claude-review", HEAD, "findings=0 inline=0 scope=whole"
        )
        report, posts = self._lost(annotations=[done])
        self.assertFalse(report["rerun"])
        self.assertTrue(report["reason"].startswith(merge.LEFT_TO_A_PERSON), report)
        self.assertEqual(posts, [])

    def test_a_lost_run_whose_lane_posted_is_left_to_a_person(self) -> None:
        summary = {
            "id": 2,
            "user": {"login": "github-actions[bot]", "type": "Bot"},
            "created_at": "2026-10-09T09:58:00Z",
            "body": "Review summary\n\n`claude-lane: claude-review`",
        }
        for comments in ([_marker()], [summary]):
            with self.subTest(comments[0]["body"][:30]):
                report, posts = self._lost(comments=comments)
                self.assertFalse(report["rerun"])
                self.assertTrue(
                    report["reason"].startswith(merge.LEFT_TO_A_PERSON), report
                )
                self.assertEqual(posts, [])

    def test_a_lost_run_whose_lane_rewrote_its_marker_is_left_to_a_person(
        self,
    ) -> None:
        # The producer edits one marker in place: created by an earlier run,
        # rewritten since this one started, or with no readable edit time.
        rewritten = _marker(at="2026-10-09T09:00:00Z", edited="2026-10-09T09:55:00Z")
        unreadable = _marker(at="2026-10-09T09:00:00Z")
        del unreadable["updated_at"]
        for comment in (rewritten, unreadable):
            with self.subTest(updated=comment.get("updated_at")):
                report, posts = self._lost(comments=[comment])
                self.assertFalse(report["rerun"])
                self.assertTrue(
                    report["reason"].startswith(merge.LEFT_TO_A_PERSON), report
                )
                self.assertEqual(posts, [])

    def test_what_the_lane_posted_elsewhere_does_not_hold_the_rerun(self) -> None:
        for comments in (
            # Before the run started: an earlier run's review.
            [_marker(at="2026-10-09T09:00:00Z")],
            [_marker(at="2026-10-09T08:00:00Z", edited="2026-10-09T09:00:00Z")],
            # Another head, or the other lane.
            [_marker(sha=base.STALE)],
            [_marker(lane="claude-security-review")],
        ):
            with self.subTest(comments[0]["body"][:60]):
                report, _ = self._lost(comments=comments)
                self.assertTrue(report["rerun"], report)

    def test_a_lost_rerun_is_not_rerun_again(self) -> None:
        report, posts = self._lost(job=_job(conclusion="cancelled", run_attempt=2))
        self.assertFalse(report["rerun"])
        self.assertIn("re-run at most once", report["reason"])
        self.assertEqual(posts, [])

    def test_a_lost_job_in_a_failed_attempt_is_not_rerun(self) -> None:
        # The binding reads attempt 1's conclusion: a failure there goes the
        # failure-class way and binds no lost re-run.
        report, posts = self._lost(attempt_conclusion="failure")
        self.assertFalse(report["rerun"])
        self.assertIn("'failure'", report["reason"])
        self.assertEqual(posts, [])

    def test_a_lost_run_with_no_pull_request_number_is_not_rerun(self) -> None:
        report, posts = self._lost(number=None)
        self.assertFalse(report["rerun"])
        self.assertEqual((posts, self.comment_reads), ([], []))


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
        one.assert_called_once_with(REPO, HEAD, CHECK, number=None)

    def test_lost_checks_are_considered_with_the_pr_number(self) -> None:
        for state in ("CANCELLED", "TIMED_OUT", "STARTUP_FAILURE"):
            with self.subTest(state):
                lost = {**CHECK, "effective_state": state}
                one = self._reruns(pr=f"{REPO}#7", aiReviewChecks=[lost])
                one.assert_called_once_with(REPO, HEAD, lost, number=7)

    def test_other_states_are_not_considered(self) -> None:
        for state in ("SUCCESS", "SKIPPED", "NEUTRAL", "PENDING", "ACTION_REQUIRED"):
            with self.subTest(state):
                checks = [{**CHECK, "effective_state": state}]
                self._reruns(aiReviewChecks=checks).assert_not_called()

    def test_unpinned_moved_draft_or_closed_heads_are_skipped(self) -> None:
        for overrides in (
            {"headMatches": None},
            {"headMatches": False},
            {"isDraft": True},
            {"state": "MERGED"},
        ):
            self._reruns(**overrides).assert_not_called()

    def test_a_lower_stack_layer_failed_check_is_considered(self) -> None:
        layer_head = base.STALE
        layer = {
            **self.RESULT,
            "pr": f"{REPO}#2",
            "headRefOid": layer_head,
        }
        top = {
            **self.RESULT,
            "aiReviewChecks": [],
            "stack": {"layers": [layer, {**layer, "isDraft": True}]},
        }
        with mock.patch.object(
            merge, "rerun_rate_limited_review", return_value={"rerun": True}
        ) as one:
            reruns = merge.rerun_rate_limited_reviews(REPO, top)
        one.assert_called_once_with(REPO, layer_head, CHECK, number=2)
        self.assertEqual(reruns, [{"pr": f"{REPO}#2", "rerun": True}])


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
        self.enterContext(
            mock.patch.object(
                merge.merge_policy,
                "resolve",
                return_value=merge.merge_policy.UnattendedPolicy(
                    reason="authority-unconfigured"
                ),
            )
        )

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
