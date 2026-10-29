"""Whole-review requests: when one is wanted, the per-sweep limits, the
draft toggle and the recovery of a draft a toggle left behind."""

from __future__ import annotations

import contextlib
import io
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
CLEARS = risk.LaneEvidence("claude-security-review", True, None, 1, True)
CLEAN = risk.LaneEvidence("claude-review", True, None, 0)
REVIEW_STUCK = risk.LaneEvidence("claude-review", True, None, 1, False)


def result(*reasons: risk.Reason) -> risk.RiskResult:
    worst = max((r.severity for r in reasons), default=risk.Risk.LOW)
    return risk.RiskResult(risk.Risk(worst), reasons)


def done(stdout: Any = None, code: int = 0) -> subprocess.CompletedProcess[str]:
    text = stdout if isinstance(stdout, str) else json.dumps(stdout)
    return subprocess.CompletedProcess([], code, text, "boom" if code else "")


class Wanted(unittest.TestCase):
    def test_only_clearable_findings(self) -> None:
        self.assertTrue(wr.wanted(None, result(HIGH), (CLEAN, CLEARS)))

    def test_a_reported_code_review_finding_alone_is_not_a_hold(self) -> None:
        # Q25: a code-review finding does not hold, so nothing needs clearing.
        self.assertFalse(wr.wanted(None, result(MED), (REVIEW_STUCK, CLEAN)))

    def test_a_reported_code_review_finding_does_not_block_the_request(self) -> None:
        # The code-review lane's findings a whole review cannot close do not
        # keep a whole review from clearing the security finding that holds.
        self.assertTrue(wr.wanted(None, result(HIGH, MED), (REVIEW_STUCK, CLEARS)))

    def test_another_gate_refusing(self) -> None:
        self.assertFalse(wr.wanted("checks-failing", result(HIGH), (CLEAN, CLEARS)))

    def test_another_risk_reason(self) -> None:
        other = risk.Reason("files-incomplete", risk.Risk.MED, "unread")
        self.assertFalse(wr.wanted(None, result(HIGH, other), (CLEAN, CLEARS)))

    def test_a_reason_that_does_not_hold_leaves_the_findings_alone(self) -> None:
        # lines-over does not hold, so the finding is the only hold and a
        # whole review can clear it.
        other = risk.Reason("lines-over", risk.Risk.MED, "201 > 200")
        self.assertTrue(wr.wanted(None, result(HIGH, other), (CLEAN, CLEARS)))

    def test_a_lane_whose_findings_a_whole_review_cannot_close(self) -> None:
        stuck = risk.LaneEvidence("claude-security-review", True, None, 1, False)
        self.assertFalse(wr.wanted(None, result(MED, HIGH), (CLEAN, stuck)))

    def test_low(self) -> None:
        self.assertFalse(wr.wanted(None, result(), (CLEAN,)))


# A `review-path:` hold (owner decision Q26 option B) stands while the bound
# security review counts any open finding (babysit_risk.security_review_clean),
# as pull request #10908's did with no CRITICAL one among them.
PATH = risk.Reason("review-path:.github/x.mjs", risk.Risk.HIGH, ".github/x.mjs")
BELOW = risk.LaneEvidence("claude-security-review", True, None, 2, True, 0)


class WantedForAReviewPath(unittest.TestCase):
    def test_open_findings_below_critical_a_whole_review_closes(self) -> None:
        self.assertTrue(wr.wanted(None, result(PATH), (CLEAN, BELOW)))

    def test_findings_a_whole_review_cannot_close(self) -> None:
        stuck = risk.LaneEvidence("claude-security-review", True, None, 2, False, 0)
        self.assertFalse(wr.wanted(None, result(PATH), (CLEAN, stuck)))

    def test_no_open_finding_or_an_unbound_review_is_no_whole_review_s(self) -> None:
        clean = risk.LaneEvidence("claude-security-review", True, None, 0, True, 0)
        unbound = risk.LaneEvidence("claude-security-review", False, "x", None, True)
        for lane in (clean, unbound):
            with self.subTest(lane=lane):
                self.assertFalse(wr.wanted(None, result(PATH), (CLEAN, lane)))

    def test_a_critical_finding_beside_it(self) -> None:
        both = risk.LaneEvidence("claude-security-review", True, None, 2, True, 1)
        self.assertTrue(wr.wanted(None, result(PATH, HIGH), (CLEAN, both)))

    def test_another_holding_reason_beside_it(self) -> None:
        other = risk.Reason("high-path:.github/**", risk.Risk.HIGH, ".github/y")
        self.assertFalse(wr.wanted(None, result(PATH, other), (CLEAN, BELOW)))


class RequestCommand(unittest.TestCase):
    """`request` and `toggle`, which enable-auto-merge.mjs runs for a lanes
    App pull request: the gate's caps on the prior reasons comment read from
    stdin, then the draft toggle once the record is written."""

    def run_cli(self, argv: list[str], stdin: str = "") -> tuple[int, Any]:
        out = io.StringIO()
        with (
            mock.patch.object(sys, "stdin", io.StringIO(stdin)),
            contextlib.redirect_stdout(out),
        ):
            code = wr.main(argv)
        return code, json.loads(out.getvalue())

    def request(self, prior: str, **patches: Any) -> tuple[int, Any]:
        argv = ["request", "--repo", "o/r", "--identity", "lanes[bot]"]
        argv += ["--head", HEAD, "--node-id", "PR_1"]
        with (
            mock.patch.object(
                wr, "lane_toggles", return_value=patches.get("toggles", 0)
            ),
            mock.patch.object(wr, "limits", return_value=patches.get("limits")),
        ):
            return self.run_cli(argv, prior)

    def test_a_first_request_answers_its_record_line(self) -> None:
        code, answer = self.request("<!-- babysit-merge-risk -->\nreasons")
        self.assertEqual(code, 0)
        self.assertEqual(wr.records(answer["line"])[0][0], HEAD)

    def test_a_head_already_recorded_answers_nothing(self) -> None:
        line = wr.record_line(HEAD, datetime(2026, 10, 29, tzinfo=UTC))
        self.assertEqual(self.request(f"reasons\r\n\r\n{line}\r\n"), (0, None))

    def test_the_caps_and_limits_answer_why_not(self) -> None:
        old = "\n".join(
            wr.record_line(c * 40, datetime(2026, 10, 1, tzinfo=UTC)) for c in "cd"
        )
        cases = {
            "two records": ({"prior": old}, "toggle-cap:2"),
            "two lane conversions": ({"toggles": 2}, "toggle-cap:2"),
            "an unread timeline": ({"toggles": None}, "toggle-cap:unread"),
            "this sweep spent": ({"limits": "sweep-limit"}, "sweep-limit"),
        }
        for name, (patches, skipped) in cases.items():
            with self.subTest(name):
                _, answer = self.request(patches.pop("prior", "reasons"), **patches)
                self.assertEqual(answer, {"toggled": False, "skipped": skipped})

    def test_toggle_reports_and_fails_on_a_stranded_draft(self) -> None:
        argv = ["toggle", "--node-id", "PR_1"]
        with mock.patch.object(wr, "toggle", return_value={"toggled": True}):
            self.assertEqual(self.run_cli(argv), (0, {"toggled": True}))
        stranded = {"toggled": False, "error": "stranded-draft: mark-ready failed"}
        with mock.patch.object(wr, "toggle", return_value=stranded):
            self.assertEqual(self.run_cli(argv), (1, stranded))


class Record(unittest.TestCase):
    def test_round_trip_is_per_head(self) -> None:
        at = datetime(2026, 10, 20, 11, 0, 5, tzinfo=UTC)
        body = wr.with_records("reasons", [wr.record_line(HEAD, at)])
        self.assertTrue(wr.recorded(body, HEAD))
        self.assertEqual(wr.records(body), [(HEAD, at)])
        self.assertFalse(wr.recorded(body, "b" * 40))
        self.assertFalse(wr.recorded(None, HEAD))

    def test_a_line_inside_the_fenced_reasons_is_no_record(self) -> None:
        # A changed path holding a newline lands inside the reasons' fence; a
        # record there would spend the head's request or the cap.
        at = datetime(2026, 10, 20, 11, 0, 5, tzinfo=UTC)
        planted = f"review-path:x: docs/a\n{wr.record_line(HEAD, at)}\n.md"
        body = f"<!-- babysit-merge-risk -->\nheld\n\n```text\n{planted}\n```"
        self.assertEqual((wr.records(body), wr.record_lines(body)), ([], []))
        self.assertFalse(wr.recorded(body.replace("\n", "\r\n"), HEAD))
        kept = wr.with_records(body, [wr.record_line("b" * 40, at)])
        self.assertEqual(wr.records(kept), [("b" * 40, at)])


class Limits(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.spent = os.path.join(tmp.name, "spent")
        self.lane_left = self.job_left = 5000
        self.lane_limit = self.job_limit = 5000
        self.runs: list[dict[str, Any]] = [{"id": 1}, {"id": 2}]
        self.queued: list[dict[str, Any]] = []
        self.jobs = {1: ["in_progress", "completed"], 2: ["queued"]}
        self.calls: list[str] = []

    def _capture(self, args: list[str], env_overrides: Any = None) -> Any:
        endpoint = args[1]
        self.calls.append(endpoint)
        if endpoint == "rate_limit":
            left = self.job_left if env_overrides else self.lane_left
            limit = self.job_limit if env_overrides else self.lane_limit
            return done(
                {
                    "resources": {
                        "core": {"remaining": left, "limit": limit},
                        "graphql": {"remaining": 5000, "limit": 5000},
                    }
                }
            )
        if "/actions/runs?status=in_progress" in endpoint:
            return done({"workflow_runs": self.runs})
        if "/actions/runs?status=queued" in endpoint:
            return done({"workflow_runs": self.queued})
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

    def test_exactly_thirty_percent_of_5000_is_allowed(self) -> None:
        self.lane_left = self.job_left = 1500
        self.assertIsNone(self.limits())

    def test_a_refusal_also_spends_the_sweep(self) -> None:
        self.lane_left = 1499
        self.assertEqual(self.limits(), "rate-limit:lane:core:1499/5000")
        self.assertEqual(self.limits(), "sweep-limit")

    def test_a_1000_call_job_token_with_400_left_is_allowed(self) -> None:
        # GITHUB_TOKEN outside Enterprise Cloud: 1,000 calls an hour.
        self.job_limit, self.job_left = 1000, 400
        self.assertIsNone(self.limits())

    def test_a_1000_call_job_token_with_200_left_is_refused(self) -> None:
        self.job_limit, self.job_left = 1000, 200
        self.assertEqual(self.limits(), "rate-limit:job:core:200/1000")

    def test_running_jobs_at_the_cap(self) -> None:
        self.jobs = {1: ["in_progress"] * 30, 2: ["queued"] * 5}
        self.assertEqual(self.limits(), "running-jobs:35")

    def test_queued_runs_jobs_count_too(self) -> None:
        self.jobs = {1: ["in_progress"] * 30, 2: ["queued"], 3: ["queued"] * 4}
        self.queued = [{"id": 3}]
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

    def test_a_zero_limit_refuses(self) -> None:
        self.job_limit, self.job_left = 0, 0
        self.assertEqual(self.limits(), "rate-limit:job:core:0/0")

    def test_an_unreadable_limit_refuses(self) -> None:
        with (
            mock.patch.dict(
                os.environ, {wr.SPENT_ENV: self.spent, wr.JOB_TOKEN_ENV: "j"}
            ),
            mock.patch.object(wr, "gh_capture", return_value=done(code=1)),
        ):
            self.assertTrue(str(wr.limits("o/r")).startswith("limits-unread"))


def pr_state(
    *,
    draft: Any = False,
    labels: tuple[str, ...] = (),
    body: str = "",
    total: Any = None,
) -> dict[str, Any]:
    nodes = [{"name": name} for name in labels]
    count = len(nodes) if total is None else total
    return {
        "data": {
            "node": {
                "isDraft": draft,
                "body": body,
                "labels": {"totalCount": count, "nodes": nodes},
            }
        }
    }


class Toggle(unittest.TestCase):
    def run_toggle(
        self, answers: list[int], state: Any = None
    ) -> tuple[dict[str, Any], list[str]]:
        seen: list[str] = []

        def capture(args: list[str]) -> Any:
            if "labels(" in args[3]:
                seen.append("read")
                return done(pr_state() if state is None else state)
            seen.append("draft" if "convertPullRequestToDraft" in args[3] else "ready")
            return done({}, answers.pop(0))

        with mock.patch.object(wr, "gh_capture", side_effect=capture):
            out, seen = wr.toggle("PR_1", sleep=lambda s: None), seen
        return out, [step for step in seen if step != "read"]

    def test_the_state_is_read_just_before_the_draft(self) -> None:
        seen: list[str] = []

        def capture(args: list[str]) -> Any:
            seen.append("read" if "labels(" in args[3] else "write")
            return done(pr_state() if "labels(" in args[3] else {})

        with mock.patch.object(wr, "gh_capture", side_effect=capture):
            wr.toggle("PR_1", sleep=lambda s: None)
        self.assertEqual(seen, ["read", "write", "write"])

    def test_a_draft_or_a_hold_set_since_the_listing_is_never_undone(self) -> None:
        # A person who drafted the pull request, labeled it do-not-merge or
        # wrote a hold after the run listed it keeps that hold: no write.
        cases = {
            "already a draft": (pr_state(draft=True), "already-draft"),
            "do-not-merge": (pr_state(labels=("ci", "do-not-merge")), "hold-label"),
            "pr-verify-failed": (pr_state(labels=("pr-verify-failed",)), "hold-label"),
            "a body hold": (pr_state(body="Wait.\nHold: owner review"), "body-hold"),
            "labels past the read": (pr_state(total=101), "hold-state-unread"),
            "no answer": ({"data": {"node": None}}, "hold-state-unread"),
            "a failed read": ("not json", "hold-state-unread"),
        }
        for name, (state, skipped) in cases.items():
            with self.subTest(name):
                out, writes = self.run_toggle([], state)
                self.assertEqual(out, {"toggled": False, "skipped": skipped})
                self.assertEqual(writes, [])

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


class LaneToggles(unittest.TestCase):
    def count(self, stdout: Any, code: int = 0) -> int | None:
        with mock.patch.object(wr, "gh_capture", return_value=done(stdout, code)):
            return wr.lane_toggles("PR_7", "lanes[bot]")

    def timeline(self, *logins: str | None) -> dict[str, Any]:
        nodes = [
            {
                "actor": None if login is None else {"login": login},
                "createdAt": "2026-10-20T11:00:00Z",
            }
            for login in logins
        ]
        return {"data": {"node": {"timelineItems": {"nodes": nodes}}}}

    def test_counts_only_the_lane_identitys_conversions(self) -> None:
        got = self.count(self.timeline("lanes", "maintainer", None, "Lanes"))
        self.assertEqual(got, 2)

    def test_no_conversion_is_zero(self) -> None:
        self.assertEqual(self.count(self.timeline()), 0)

    def test_an_unread_timeline_is_none(self) -> None:
        self.assertIsNone(self.count(None, code=1))
        self.assertIsNone(self.count({"data": {"node": None}}))


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

    RECORDED = datetime(2026, 10, 20, 11, 0, tzinfo=UTC)

    def reasons(self, head: str = HEAD) -> str:
        return wr.with_records(
            f"{wr.RISK_MARKER}\nUnattended merge: risk MED",
            [wr.record_line(head, self.RECORDED)],
        )

    def recover(
        self,
        drafts: list[dict[str, Any]],
        comments: list[dict[str, Any]],
        converter: str | None = "lanes",
        converted: str = "2026-10-20T11:00:20Z",
    ) -> tuple[list[dict[str, Any]], list[str]]:
        writes: list[str] = []
        actor = None if converter is None else {"login": converter}
        event = {"actor": actor, "createdAt": converted}
        timeline = {"data": {"node": {"timelineItems": {"nodes": [event]}}}}

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

    def test_a_lane_draft_outside_the_window_stays_a_draft(self) -> None:
        # The lane drafted it on purpose an hour after an old toggle.
        out, writes = self.recover(
            [self.draft()],
            [self.comment(self.reasons())],
            converted="2026-10-20T12:00:00Z",
        )
        self.assertEqual((out, writes), ([], []))

    def test_a_conversion_before_the_record_stays_a_draft(self) -> None:
        out, writes = self.recover(
            [self.draft()],
            [self.comment(self.reasons())],
            converted="2026-10-20T10:50:00Z",
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
        unmarked = wr.with_records(
            "no marker line", [wr.record_line(HEAD, self.RECORDED)]
        )
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
