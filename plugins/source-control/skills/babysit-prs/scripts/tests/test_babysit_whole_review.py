"""Whole-review requests: when one is wanted, the per-sweep limits, the
draft toggle and the recovery of a draft a toggle left behind."""

from __future__ import annotations

import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
from datetime import UTC, datetime
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_risk as risk
import babysit_whole_review as wr

HEAD = "a" * 40
MED = risk.Reason("findings:claude-review", risk.Risk.MED, "1 open")
HIGH = risk.Reason("security-finding", risk.Risk.HIGH, "1 open")
CLEARS = risk.LaneEvidence("claude-review", True, None, 1, True)
CLEAN = risk.LaneEvidence("claude-security-review", True, None, 0)


def result(*reasons: risk.Reason) -> risk.RiskResult:
    worst = max((r.severity for r in reasons), default=risk.Risk.LOW)
    return risk.RiskResult(risk.Risk(worst), reasons)


def done(stdout: Any = None, code: int = 0) -> subprocess.CompletedProcess[str]:
    text = stdout if isinstance(stdout, str) else json.dumps(stdout)
    return subprocess.CompletedProcess([], code, text, "boom" if code else "")


class Wanted(unittest.TestCase):
    def test_only_clearable_findings(self) -> None:
        self.assertTrue(wr.wanted(None, result(MED), (CLEARS, CLEAN)))

    def test_security_findings_count_too(self) -> None:
        lane = risk.LaneEvidence("claude-security-review", True, None, 1, True)
        self.assertTrue(wr.wanted(None, result(HIGH), (CLEAN, lane)))

    def test_another_gate_refusing(self) -> None:
        self.assertFalse(wr.wanted("checks-failing", result(MED), (CLEARS, CLEAN)))

    def test_another_risk_reason(self) -> None:
        other = risk.Reason("files-over", risk.Risk.MED, "9 > 8")
        self.assertFalse(wr.wanted(None, result(MED, other), (CLEARS, CLEAN)))

    def test_a_lane_whose_findings_a_whole_review_cannot_close(self) -> None:
        stuck = risk.LaneEvidence("claude-security-review", True, None, 1, False)
        self.assertFalse(wr.wanted(None, result(MED, HIGH), (CLEARS, stuck)))

    def test_low(self) -> None:
        self.assertFalse(wr.wanted(None, result(), (CLEAN,)))


class Record(unittest.TestCase):
    def test_round_trip_is_per_head(self) -> None:
        body = wr.with_record("reasons", HEAD)
        self.assertTrue(wr.recorded(body, HEAD))
        self.assertFalse(wr.recorded(body, "b" * 40))
        self.assertFalse(wr.recorded(None, HEAD))


class Limits(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.spent = os.path.join(tmp.name, "spent")
        self.lane_left = 5000
        self.job_left = 5000
        self.runs: list[dict[str, Any]] = [{"id": 1}, {"id": 2}]
        self.jobs = {1: ["in_progress", "completed"], 2: ["queued"]}
        self.calls: list[str] = []

    def _capture(self, args: list[str], env_overrides: Any = None) -> Any:
        endpoint = args[1]
        self.calls.append(endpoint)
        if endpoint == "rate_limit":
            left = self.job_left if env_overrides else self.lane_left
            return done(
                {
                    "resources": {
                        "core": {"remaining": left},
                        "graphql": {"remaining": 5000},
                    }
                }
            )
        if "/actions/runs?" in endpoint:
            return done({"workflow_runs": self.runs})
        run_id = int(endpoint.split("/runs/")[1].split("/")[0])
        return done({"jobs": [{"status": s} for s in self.jobs[run_id]]})

    def limits(self, env: dict[str, str] | None = None) -> str | None:
        env = (
            {wr.SPENT_ENV: self.spent, wr.JOB_TOKEN_ENV: "job"} if env is None else env
        )
        with (
            mock.patch.dict(os.environ, env, clear=False),
            mock.patch.object(wr, "gh_capture", side_effect=self._capture),
        ):
            return wr.limits("o/r")

    def test_allows_once_per_sweep(self) -> None:
        self.assertIsNone(self.limits())
        self.assertEqual(self.limits(), "sweep-limit")

    def test_exactly_the_minimum_remaining_is_allowed(self) -> None:
        self.lane_left = self.job_left = wr.MIN_REMAINING
        self.assertIsNone(self.limits())

    def test_a_refusal_also_spends_the_sweep(self) -> None:
        self.lane_left = 1499
        self.assertEqual(self.limits(), "rate-limit:lane:1499")
        self.assertEqual(self.limits(), "sweep-limit")

    def test_the_job_token_bucket(self) -> None:
        self.job_left = 100
        self.assertEqual(self.limits(), "rate-limit:job:100")

    def test_running_jobs_at_the_cap(self) -> None:
        self.jobs = {1: ["in_progress"] * 30, 2: ["queued"] * 5}
        self.assertEqual(self.limits(), "running-jobs:35")

    def test_a_full_page_of_runs_reads_no_jobs(self) -> None:
        self.runs = [{"id": n} for n in range(35)]
        self.assertEqual(self.limits(), "running-jobs:35")
        self.assertFalse(any("/jobs" in c for c in self.calls))

    def test_outside_pr_merge_nothing_is_requested(self) -> None:
        with mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop(wr.SPENT_ENV, None)
            self.assertEqual(wr.limits("o/r"), "not-pr-merge")

    def test_no_job_token(self) -> None:
        self.assertEqual(
            self.limits({wr.SPENT_ENV: self.spent, wr.JOB_TOKEN_ENV: ""}),
            "job-token-missing",
        )

    def test_an_unreadable_limit_refuses(self) -> None:
        with (
            mock.patch.dict(
                os.environ, {wr.SPENT_ENV: self.spent, wr.JOB_TOKEN_ENV: "j"}
            ),
            mock.patch.object(wr, "gh_capture", return_value=done(code=1)),
        ):
            self.assertTrue(str(wr.limits("o/r")).startswith("limits-unread"))


class Toggle(unittest.TestCase):
    def run_toggle(self, answers: list[int]) -> tuple[dict[str, Any], list[str]]:
        seen: list[str] = []

        def capture(args: list[str]) -> Any:
            seen.append("draft" if "convertPullRequestToDraft" in args[3] else "ready")
            return done({}, answers.pop(0))

        with mock.patch.object(wr, "gh_capture", side_effect=capture):
            return wr.toggle("PR_1", sleep=lambda s: None), seen

    def test_draft_then_ready(self) -> None:
        self.assertEqual(
            self.run_toggle([0, 0]), ({"toggled": True}, ["draft", "ready"])
        )

    def test_ready_is_retried(self) -> None:
        out, seen = self.run_toggle([0, 1, 0])
        self.assertEqual(out, {"toggled": True})
        self.assertEqual(seen, ["draft", "ready", "ready"])

    def test_a_failed_draft_stops(self) -> None:
        out, seen = self.run_toggle([1])
        self.assertFalse(out["toggled"])
        self.assertEqual(seen, ["draft"])

    def test_a_stranded_draft_is_reported(self) -> None:
        out, seen = self.run_toggle([0, 1, 1, 1])
        self.assertEqual(out["error"], "stranded-draft: mark-ready failed")
        self.assertEqual(seen.count("ready"), wr.READY_TRIES)


class Recover(unittest.TestCase):
    NOW = datetime(2026, 10, 20, 12, tzinfo=UTC)
    LANE = "lanes[bot]"

    def draft(self, **kw: Any) -> dict[str, Any]:
        return {
            "number": 7,
            "head": HEAD,
            "id": "PR_7",
            "labels": [],
            "updatedAt": "2026-10-20T11:00:00+00:00",
            **kw,
        }

    def comment(self, body: str, login: str = LANE, at: str = "T1") -> dict[str, Any]:
        return {"user": {"login": login}, "created_at": at, "body": body}

    def reasons(self, head: str = HEAD) -> str:
        return wr.with_record(f"{wr.RISK_MARKER}\nUnattended merge: risk MED", head)

    def recover(
        self,
        drafts: list[dict[str, Any]],
        comments: list[dict[str, Any]],
        converter: str | None = "lanes",
    ) -> tuple[list[dict[str, Any]], list[str]]:
        writes: list[str] = []
        actor = None if converter is None else {"login": converter}
        timeline = {"data": {"node": {"timelineItems": {"nodes": [{"actor": actor}]}}}}

        def capture(args: list[str]) -> Any:
            if wr.READY in args[3]:
                writes.append(args[-1])
                return done({})
            return done(timeline)

        with (
            mock.patch.object(wr, "fetch_paginated_api", return_value=comments),
            mock.patch.object(wr, "gh_capture", side_effect=capture),
        ):
            return wr.recover("o/r", self.LANE, drafts, now=self.NOW), writes

    def test_readies_a_draft_the_lane_converted(self) -> None:
        out, writes = self.recover([self.draft()], [self.comment(self.reasons())])
        self.assertEqual(out, [{"pr": 7, "head": HEAD, "ready": True}])
        self.assertEqual(writes, ["id=PR_7"])

    def test_a_human_conversion_after_the_record_stays_a_draft(self) -> None:
        out, writes = self.recover(
            [self.draft()], [self.comment(self.reasons())], converter="maintainer"
        )
        self.assertEqual((out, writes), ([], []))

    def test_a_head_moved_mid_toggle_still_recovers(self) -> None:
        moved = self.draft(head="b" * 40)
        out, writes = self.recover([moved], [self.comment(self.reasons(HEAD))])
        self.assertEqual(writes, ["id=PR_7"])

    def test_a_later_lane_comment_does_not_hide_the_record(self) -> None:
        comments = [
            self.comment(self.reasons(), at="T1"),
            self.comment("<!-- babysit-merge-pin -->\nother", at="T2"),
        ]
        out, writes = self.recover([self.draft()], comments)
        self.assertEqual(writes, ["id=PR_7"])

    def test_leaves_other_drafts(self) -> None:
        unmarked = wr.with_record("no marker line", HEAD)
        for drafts, comments, converter in (
            ([self.draft()], [self.comment(f"{wr.RISK_MARKER}\nno record")], "lanes"),
            ([self.draft()], [self.comment(unmarked)], "lanes"),
            ([self.draft()], [self.comment(self.reasons(), login="someone")], "lanes"),
            ([self.draft()], [self.comment(self.reasons())], None),
            (
                [self.draft(labels=["do-not-merge"])],
                [self.comment(self.reasons())],
                "lanes",
            ),
            (
                [self.draft(updatedAt="2026-10-18T00:00:00+00:00")],
                [self.comment(self.reasons())],
                "lanes",
            ),
        ):
            out, writes = self.recover(drafts, comments, converter)
            self.assertEqual((out, writes), ([], []), (drafts, comments, converter))


if __name__ == "__main__":
    unittest.main()
