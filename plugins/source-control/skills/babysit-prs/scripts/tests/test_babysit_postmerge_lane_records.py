"""The lane-record carry of the post-merge check (`babysit_postmerge`).

Expected values come from the carry's rules: a `pr-merge-dispatched-<id>` or
`pr-merge-rerun-<id>-attempt-2` record a check proved (one name-filtered
artifact listing and one read of the uploading run, per record) is answered
from the file pr-merge.yml names in `BABYSIT_POSTMERGE_LANE_RECORDS` with
neither read, decides as the reads would, and is written back only when it is
final: the uploading run completed and the artifact listed unexpired. Any
failure to read or parse the file means the reads of today, and the written
set keeps only records at or after the floor and not yet expired. Request
counts come from the `babysit-gh-calls` counter (`babysit_gh._run_gh`), with
gh itself stubbed at `run_command` by the same fake as the check's tests.
"""

from __future__ import annotations

import contextlib
import io
import json
import pathlib
import sys
import tempfile
import unittest
from datetime import UTC, datetime
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import babysit_gh as gh
import babysit_postmerge as pm
from test_babysit_postmerge import (
    IDENTITY,
    LATER_SHA,
    OTHER_SHA,
    REPO,
    SINCE,
    FakeGh,
    by,
    canary_run,
    dispatch_run,
    human,
)

NOW = datetime(2026, 10, 12, 11, 0, tzinfo=UTC)
EXPIRES = "2027-01-10T10:05:00Z"
BOT = by("github-actions[bot]")
SENDER = 500
RERUNNER = 600
ARTIFACTS = "default GET repos/{}/{}/actions/artifacts"
RUN_READS = "default GET repos/{}/{}/actions/runs/{}"


def sender_record(run_id: int, **changes: Any) -> dict[str, Any]:
    record = {
        "id": run_id,
        "path": ".github/workflows/pr-merge.yml",
        "event": "schedule",
        "status": "completed",
        "head_branch": "main",
        "head_sha": LATER_SHA,
        "repository": {"full_name": REPO},
        "head_repository": {"full_name": REPO},
    }
    record.update(changes)
    return record


class LaneRecordCase(unittest.TestCase):
    """A merge covered by `count` green full runs pr-merge.yml dispatched,
    each with its record, and a green canary run; gh is reached through
    `babysit_gh.run_command`, so every call is counted."""

    def setUp(self) -> None:
        self.gh = FakeGh()
        tmp = tempfile.TemporaryDirectory(prefix="lane-records-")
        self.addCleanup(tmp.cleanup)
        self.path = pathlib.Path(tmp.name) / "lane-records.json"

        def run_command(command: list[str], **kwargs: Any) -> Any:
            return self.gh(command[1:], timeout_seconds=kwargs.get("timeout_seconds"))

        for patcher in (
            mock.patch.object(gh, "run_command", side_effect=run_command),
            mock.patch.dict("os.environ", {pm.LANE_RECORDS_ENV: str(self.path)}),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)
        gh.reset_gh_call_counts()
        self.addCleanup(gh.reset_gh_call_counts)

    def lane_runs(self, count: int, *, first: int = 11) -> None:
        self.gh.add_runs("post-merge-detect-silent-revert.yml", "push", canary_run(21))
        for n in range(first, first + count):
            self.gh.add_runs(
                "pr-require-checks.yml",
                "workflow_dispatch",
                dispatch_run(n, actor=BOT, triggering_actor=BOT),
            )
            name = f"pr-merge-dispatched-{n}"
            self.gh.artifacts[name] = [
                {
                    "id": 9000 + n,
                    "name": name,
                    "expired": False,
                    "expires_at": EXPIRES,
                    "workflow_run": {"id": SENDER},
                }
            ]
        self.gh.run_records[SENDER] = sender_record(SENDER)

    def check(
        self, now: datetime = NOW, since: datetime = SINCE
    ) -> pm.PostMergeVerdict:
        gh.reset_gh_call_counts()
        return pm.check(
            REPO,
            agent_identity=IDENTITY,
            is_human=human,
            merged_since=since,
            now=now,
            pinned_sha=lambda merge: None,
        )

    def counts(self) -> dict[str, int]:
        return gh.gh_call_counts()

    def written(self) -> dict[str, Any]:
        return json.loads(self.path.read_text(encoding="utf-8"))

    def carried(self) -> set[str]:
        return set(self.written()["records"])


class TheCarrySparesTheRecordReads(LaneRecordCase):
    def test_104_carried_records_are_read_in_208_fewer_requests(self) -> None:
        # The run 39972998315 window: 104 lane-dispatched full runs, each one
        # name-filtered listing and one read of the run that uploaded it.
        self.lane_runs(104)
        fresh = self.check()
        before = self.counts()
        self.assertEqual(before[ARTIFACTS], 104)
        self.assertEqual(before[RUN_READS], 104)
        carried = self.check()
        after = self.counts()
        self.assertNotIn(ARTIFACTS, after)
        self.assertNotIn(RUN_READS, after)
        self.assertEqual(sum(before.values()) - sum(after.values()), 208)
        self.assertEqual(carried.report(), fresh.report())
        self.assertTrue(carried.merges[0].verified)

    def test_a_carried_record_answers_after_its_artifact_is_gone(self) -> None:
        self.lane_runs(1)
        self.check()
        self.gh.artifacts.clear()
        self.gh.run_records.clear()
        verdict = self.check()
        self.assertTrue(verdict.merges[0].verified)
        self.assertNotIn(ARTIFACTS, self.counts())

    def test_a_carried_rerun_record_answers_with_no_read(self) -> None:
        name = "pr-merge-rerun-11-attempt-2"
        fresh = lane_rerun(self)
        self.assertEqual(fresh.flakes, (f"https://github.com/{REPO}/actions/runs/11",))
        self.assertEqual(self.carried(), {"pr-merge-dispatched-11", name})
        self.gh.artifacts.clear()
        self.assertEqual(self.check().report(), fresh.report())
        self.assertNotIn(ARTIFACTS, self.counts())


def lane_rerun(case: LaneRecordCase) -> pm.PostMergeVerdict:
    """Run 11, lane-dispatched, red on attempt 1 and green on the lane's
    recorded attempt 2; the first check, which proves both records."""
    case.lane_runs(1)
    case.gh.runs[("pr-require-checks.yml", "workflow_dispatch")] = [
        dispatch_run(11, run_attempt=2, actor=BOT, triggering_actor=BOT)
    ]
    case.gh.attempts[(11, 1)] = dispatch_run(
        11, "failure", actor=BOT, triggering_actor=BOT
    )
    name = "pr-merge-rerun-11-attempt-2"
    case.gh.artifacts[name] = [
        {
            "id": 7001,
            "name": name,
            "expired": False,
            "expires_at": EXPIRES,
            "workflow_run": {"id": RERUNNER},
        }
    ]
    case.gh.run_records[RERUNNER] = sender_record(RERUNNER)
    return case.check()


class OnlyFinalAnswersCarry(LaneRecordCase):
    def test_a_record_whose_uploading_run_is_running_is_not_carried(self) -> None:
        self.lane_runs(2)
        self.gh.artifacts["pr-merge-dispatched-12"][0]["workflow_run"]["id"] = 501
        self.gh.run_records[501] = sender_record(501, status="in_progress")
        self.assertTrue(self.check().merges[0].verified)
        self.assertEqual(self.carried(), {"pr-merge-dispatched-11"})

    def test_an_expired_or_undated_artifact_is_not_carried(self) -> None:
        self.lane_runs(3)
        self.gh.artifacts["pr-merge-dispatched-12"][0]["expired"] = True
        del self.gh.artifacts["pr-merge-dispatched-13"][0]["expires_at"]
        self.check()
        self.assertEqual(self.carried(), {"pr-merge-dispatched-11"})

    def test_an_absent_or_untrusted_record_is_not_carried(self) -> None:
        self.lane_runs(3)
        self.gh.artifacts["pr-merge-dispatched-12"] = []
        self.gh.artifacts["pr-merge-dispatched-13"][0]["workflow_run"]["id"] = 502
        self.gh.run_records[502] = sender_record(502, event="pull_request_target")
        self.check()
        self.assertEqual(self.carried(), {"pr-merge-dispatched-11"})

    def test_no_file_is_written_without_the_variable(self) -> None:
        self.lane_runs(1)
        with mock.patch.dict("os.environ", {pm.LANE_RECORDS_ENV: ""}):
            self.check()
        self.assertFalse(self.path.exists())


class AnUnusableCarryReadsAsToday(LaneRecordCase):
    def carry(self, mutate: Any) -> None:
        self.lane_runs(2)
        self.check()
        data = self.written()
        mutate(data)
        self.path.write_text(
            data if isinstance(data, str) else json.dumps(data), encoding="utf-8"
        )

    def test_a_malformed_carry_is_dropped_whole(self) -> None:
        entry = "pr-merge-dispatched-11"
        cases = {
            "another version": lambda d: d.update(version=2),
            "another repository": lambda d: d.update(repo="example-org/other"),
            "another record name": lambda d: d["records"].update(
                {"pr-merge-summary": d["records"][entry]}
            ),
            "no expiry": lambda d: d["records"][entry].pop("expires_at"),
            "no artifact id": lambda d: d["records"][entry].update(artifact="9"),
            "no sender": lambda d: d["records"][entry].update(sender=None),
            "a running sender": lambda d: d["records"][entry]["sender"].update(
                status="in_progress"
            ),
            "records not a map": lambda d: d.update(records=[]),
        }
        for label, mutate in cases.items():
            with self.subTest(label):
                self.gh = FakeGh()
                self.carry(mutate)
                err = io.StringIO()
                with contextlib.redirect_stderr(err):
                    verdict = self.check()
                self.assertTrue(verdict.merges[0].verified)
                self.assertEqual(self.counts()[ARTIFACTS], 2)
                self.assertIn("lane records", err.getvalue())

    def test_a_carry_that_is_not_json_reads_as_today(self) -> None:
        self.lane_runs(2)
        self.path.write_text("{", encoding="utf-8")
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertTrue(self.check().merges[0].verified)
        self.assertEqual(self.counts()[ARTIFACTS], 2)
        self.assertEqual(self.carried(), {f"pr-merge-dispatched-{n}" for n in (11, 12)})

    def test_a_carried_sender_that_is_no_longer_trusted_is_read_again(self) -> None:
        self.carry(
            lambda d: d["records"]["pr-merge-dispatched-11"]["sender"].update(
                event="pull_request_target"
            )
        )
        self.gh.artifacts["pr-merge-dispatched-11"] = []
        verdict = self.check()
        self.assertEqual(self.counts()[ARTIFACTS], 2)
        self.assertEqual(self.carried(), {"pr-merge-dispatched-12"})
        self.assertTrue(verdict.merges[0].verified)

    def test_a_carried_sender_off_the_branch_is_read_again(self) -> None:
        for label, change in {
            "head commit off main": {"head_sha": OTHER_SHA},
            "a fork's head repository": {
                "head_repository": {"full_name": "outsider/example-repo"}
            },
        }.items():
            with self.subTest(label):
                self.gh = FakeGh()
                self.carry(
                    lambda d, change=change: d["records"]["pr-merge-dispatched-11"][
                        "sender"
                    ].update(change)
                )
                self.gh.artifacts["pr-merge-dispatched-11"] = []
                self.assertTrue(self.check().merges[0].verified)
                # Record 11 read again, empty twice; record 12 carried.
                self.assertEqual(self.counts()[ARTIFACTS], 2)
                self.assertEqual(self.carried(), {"pr-merge-dispatched-12"})

    def test_a_carried_rerun_record_from_a_push_run_is_read_again(self) -> None:
        # A push run writes dispatch records only, never a re-run record.
        name = "pr-merge-rerun-11-attempt-2"
        lane_rerun(self)
        data = self.written()
        data["records"][name]["sender"]["event"] = "push"
        self.path.write_text(json.dumps(data), encoding="utf-8")
        self.gh.artifacts[name] = []
        verdict = self.check()
        self.assertEqual([f.signal for f in verdict.failures], ["dispatch"])
        self.assertEqual(self.counts()[ARTIFACTS], 1)
        self.assertEqual(self.carried(), {"pr-merge-dispatched-11"})

    def test_a_sender_with_another_field_drops_the_file(self) -> None:
        self.carry(
            lambda d: d["records"]["pr-merge-dispatched-11"]["sender"].update(
                conclusion="success"
            )
        )
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertTrue(self.check().merges[0].verified)
        self.assertEqual(self.counts()[ARTIFACTS], 2)

    def test_an_expired_carried_record_is_read_again(self) -> None:
        self.carry(
            lambda d: d["records"]["pr-merge-dispatched-11"].update(
                expires_at="2026-10-12T10:59:59Z"
            )
        )
        self.check()
        self.assertEqual(self.counts()[ARTIFACTS], 1)


class TheCarryIsBoundToTheWindow(LaneRecordCase):
    def test_records_before_the_floor_or_expired_are_dropped(self) -> None:
        self.lane_runs(1)
        self.check()
        data = self.written()
        old = dict(
            data["records"]["pr-merge-dispatched-11"], created_at="2026-10-11T23:59:59Z"
        )
        gone = dict(
            data["records"]["pr-merge-dispatched-11"], expires_at="2026-10-12T10:00:00Z"
        )
        data["records"]["pr-merge-dispatched-9"] = old
        data["records"]["pr-merge-dispatched-10"] = gone
        self.path.write_text(json.dumps(data), encoding="utf-8")
        self.check()
        self.assertEqual(self.carried(), {"pr-merge-dispatched-11"})

    def test_a_later_check_under_a_higher_floor_keeps_the_earlier_records(
        self,
    ) -> None:
        # The run's first check proves record 11 (created 10:05) under the
        # merge gate's floor; a later check in the same run under a floor past
        # it must not drop it.
        self.lane_runs(1)
        self.check()
        self.check(since=datetime(2026, 10, 12, 10, 30, tzinfo=UTC))
        self.assertEqual(self.carried(), {"pr-merge-dispatched-11"})
        self.gh.artifacts.clear()
        self.check()
        self.assertNotIn(ARTIFACTS, self.counts())

    def test_records_another_process_wrote_since_the_load_are_kept(self) -> None:
        # A gate process loads the file, the next one proves record 12 and
        # writes it, then the first saves: record 12 stays.
        self.lane_runs(2)
        self.check()
        both = self.written()
        only_11 = dict(
            both,
            records={
                "pr-merge-dispatched-11": both["records"]["pr-merge-dispatched-11"]
            },
        )
        self.path.write_text(json.dumps(only_11), encoding="utf-8")
        ctx = pm._Context(
            "example-org", "example-repo", IDENTITY, branch="main", now=NOW
        )
        self.assertEqual(set(ctx._carried_records()), {"pr-merge-dispatched-11"})
        self.path.write_text(json.dumps(both), encoding="utf-8")
        ctx.save_lane_records(SINCE)
        self.assertEqual(
            self.carried(), {"pr-merge-dispatched-11", "pr-merge-dispatched-12"}
        )


class AFileThatCannotParse(LaneRecordCase):
    def test_a_nesting_too_deep_to_parse_reads_as_today(self) -> None:
        self.lane_runs(2)
        self.path.write_text("[" * 200_000, encoding="utf-8")
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            verdict = self.check()
        self.assertTrue(verdict.readable, verdict.reason)
        self.assertTrue(verdict.merges[0].verified)
        self.assertEqual(self.counts()[ARTIFACTS], 2)
        self.assertIn("lane records not used", err.getvalue())

    def test_a_record_name_cannot_start_a_workflow_command(self) -> None:
        self.lane_runs(1)
        self.check()
        data = self.written()
        data["records"]["x\n::error::forged"] = data["records"][
            "pr-merge-dispatched-11"
        ]
        self.path.write_text(json.dumps(data), encoding="utf-8")
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            self.check()
        self.assertIn("lane records not used", err.getvalue())
        self.assertNotIn("\n::error::", err.getvalue())


if __name__ == "__main__":
    unittest.main()
