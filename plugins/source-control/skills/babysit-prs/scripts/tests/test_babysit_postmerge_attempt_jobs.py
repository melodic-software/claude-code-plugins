"""The attempt answers the post-merge check carries in its attempts file.

A completed attempt's job list cannot change, so `_Context.failing_checks`
keeps its answer in the file pr-merge.yml names in `BABYSIT_POSTMERGE_ATTEMPTS`
and dispatch-post-merge-runs hands from run to run. Job and annotation shapes
follow the jobs API as `test_babysit_postmerge` fakes it; the expected checks
are worked by hand from `failing_checks`' rule that a failed job with no failure
annotation counts as one check under its own name.
"""

from __future__ import annotations

import contextlib
import dataclasses
import io
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from datetime import UTC, datetime, timedelta
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import babysit_postmerge as pm
from test_babysit_postmerge import (
    HEAD_SHA,
    IDENTITY,
    LATER_SHA,
    REPO,
    SINCE,
    CheckCase,
    FakeGh,
    by,
    canary_run,
    dispatch_run,
    failed_job,
    failure_annotation,
    human,
    schedule_run,
)

TESTS = pathlib.Path(__file__).resolve().parent
WORKFLOW = (
    pathlib.Path(__file__).resolve().parents[6] / ".github/workflows/pr-merge.yml"
)
OWNER, NAME = REPO.split("/")
KEY = "31:2"
JOBS_READ = "/jobs?per_page"
CHECKED_AT = datetime(2026, 10, 12, 11, 0, tzinfo=UTC)
CREATED = "2026-10-12T10:30:00Z"
FAILED = {**failed_job(312, "Test Bash", "Run the bash tests"), "status": "completed"}
PASSED = {
    "id": 313,
    "name": "Lint",
    "status": "completed",
    "conclusion": "success",
    "steps": [{"name": "Lint", "conclusion": "success"}],
}
ANSWER = {
    "head_sha": LATER_SHA,
    "checks": ["Test Bash"],
    "passed": ["Lint"],
    "jobs": {
        "Test Bash": {
            "id": 312,
            "steps": [{"name": "Run the bash tests", "conclusion": "failure"}],
        }
    },
}


def red_run() -> dict[str, Any]:
    return schedule_run(
        31, run_attempt=2, triggering_actor=by(IDENTITY), created_at=CREATED
    )


def list_red_run(fake: FakeGh) -> None:
    fake.add_runs("post-merge-detect-silent-revert.yml", "push", canary_run(21))
    fake.add_runs("pr-require-checks.yml", "schedule", red_run())
    fake.attempts[(31, 1)] = schedule_run(31, created_at=CREATED)
    fake.jobs[(31, 2)] = [FAILED, PASSED]


def job_reads(fake: FakeGh) -> int:
    return sum(1 for call in fake.calls if any(JOBS_READ in a for a in call))


def next_run_report() -> dict[str, Any]:
    """The next run's check in this interpreter, every jobs read answering 502."""
    fake = FakeGh()
    list_red_run(fake)
    fake.fail_reads.add(JOBS_READ)
    pm.gh_capture = fake
    pm.policy.gh_capture = fake
    verdict = pm.check(
        REPO,
        agent_identity=IDENTITY,
        is_human=human,
        merged_since=SINCE,
        now=CHECKED_AT,
        pinned_sha=lambda merge: HEAD_SHA,
    )
    return {"jobReads": job_reads(fake), "report": verdict.report()}


def entry(**overrides: Any) -> dict[str, Any]:
    return {
        "at": datetime.now(UTC).isoformat(),
        "code": pm._attempt_jobs_code(),
        **ANSWER,
        **overrides,
    }


class AttemptJobsCase(CheckCase):
    """Schedule run 31 on LATER_SHA, red again on its attempt 2."""

    def setUp(self) -> None:
        super().setUp()
        tmp = tempfile.TemporaryDirectory(prefix="attempt-jobs-")
        self.addCleanup(tmp.cleanup)
        self.dir = pathlib.Path(tmp.name)
        self.path = self.dir / "post-merge-attempts.json"
        patcher = mock.patch.dict(os.environ, {pm.ATTEMPTS_ENV: str(self.path)})
        patcher.start()
        self.addCleanup(patcher.stop)
        self.run_record = pm.Run.from_api(red_run())
        self.gh.jobs[(31, 2)] = [FAILED, PASSED]

    def context(self) -> pm._Context:
        return pm._Context(OWNER, NAME, IDENTITY, branch="main")

    def seed(self, jobs: Any, **fields: Any) -> None:
        data = {
            "version": pm.ATTEMPTS_VERSION,
            "repo": REPO,
            "attempts": {},
            "jobs": jobs,
            **fields,
        }
        self.path.write_text(json.dumps(data), encoding="utf-8")

    def answer(self, run: pm.Run | None = None) -> frozenset[str]:
        ctx = self.context()
        checks = ctx.failing_checks(run or self.run_record, 2)
        ctx.save_attempts()
        return checks

    def written(self) -> dict[str, Any]:
        return json.loads(self.path.read_text(encoding="utf-8"))

    def reads(self) -> int:
        return job_reads(self.gh)


class ACarriedAttemptSendsNoRead(AttemptJobsCase):
    def test_a_carried_answer_restores_every_value_with_no_read(self) -> None:
        self.seed({KEY: entry()})
        ctx = self.context()
        self.assertEqual(ctx.failing_checks(self.run_record, 2), {"Test Bash"})
        self.assertEqual(self.reads(), 0)
        self.assertEqual(ctx.unknown_checks[(31, 2)], frozenset())
        self.assertEqual(ctx.passed_jobs[(31, 2)], {"Lint"})
        self.assertEqual(ctx.check_jobs[(31, 2)], ANSWER["jobs"])

    def test_a_live_read_keeps_the_answer_the_carry_restores(self) -> None:
        self.answer()
        self.assertEqual(self.reads(), 1)
        kept = self.written()["jobs"][KEY]
        self.assertEqual({k: kept[k] for k in ANSWER}, ANSWER)
        self.assertEqual(kept["code"], pm._attempt_jobs_code())

    def test_with_no_file_named_nothing_is_kept_or_restored(self) -> None:
        self.seed({KEY: entry(checks=["Carried only"])})
        with mock.patch.dict(os.environ, {pm.ATTEMPTS_ENV: ""}):
            ctx = self.context()
            self.assertEqual(ctx.failing_checks(self.run_record, 2), {"Test Bash"})
        self.assertEqual(ctx.attempt_jobs_new, {})


class TheNextRunsCheckSendsNoJobsRead(AttemptJobsCase):
    def dispatch_job(self) -> str:
        text = WORKFLOW.read_text(encoding="utf-8")
        return text.split("\n  dispatch-post-merge-runs:\n")[1].split("\n  merge:\n")[0]

    def shell_line(self, block: str, fragment: str) -> str:
        return next(ln.strip() for ln in block.splitlines() if fragment in ln)

    def test_the_answer_crosses_the_workflows_hand_over_into_a_new_process(
        self,
    ) -> None:
        block = self.dispatch_job()
        self.assertIn(
            "BABYSIT_POSTMERGE_ATTEMPTS: ${{ runner.temp }}/post-merge-attempts.json",
            block,
        )
        list_red_run(self.gh)
        first = self.check()
        self.assertEqual(self.reads(), 1)
        self.assertEqual([f.signal for f in first.failures], ["schedule"])

        kept = self.dir / "post-merge-report"
        kept.mkdir()
        subprocess.run(
            [
                "bash",
                "-c",
                self.shell_line(block, 'cp "$RUNNER_TEMP/post-merge-attempts.json"'),
            ],
            env={**os.environ, "RUNNER_TEMP": str(self.dir), "kept": str(kept)},
            check=True,
        )
        next_temp = self.dir / "next-run"
        next_temp.mkdir()
        last = next_temp / "post-merge-last"
        shutil.copytree(kept, last)
        subprocess.run(
            [
                "bash",
                "-c",
                self.shell_line(block, 'cp "$last/attempts.json"'),
            ],
            env={**os.environ, "RUNNER_TEMP": str(next_temp), "last": str(last)},
            check=True,
        )

        program = (
            "import json, sys\n"
            f"sys.path.insert(0, {str(TESTS)!r})\n"
            "import test_babysit_postmerge_attempt_jobs as t\n"
            "print(json.dumps(t.next_run_report()))\n"
        )
        env = {
            **os.environ,
            pm.ATTEMPTS_ENV: str(next_temp / "post-merge-attempts.json"),
        }
        proc = subprocess.run(
            [sys.executable, "-c", program],
            env=env,
            check=True,
            capture_output=True,
            text=True,
        )
        result = json.loads(proc.stdout.splitlines()[-1])
        self.assertEqual(result["jobReads"], 0)
        self.assertEqual(
            result["report"], json.loads(json.dumps(first.report(), default=str))
        )


class AnAttemptStillBeingWrittenIsReadLive(AttemptJobsCase):
    def test_an_in_progress_run_ignores_a_carried_answer_and_keeps_nothing(
        self,
    ) -> None:
        self.seed({KEY: entry(checks=["Carried only"])})
        run = dataclasses.replace(self.run_record, status="in_progress")
        ctx = self.context()
        self.assertEqual(ctx.failing_checks(run, 2), {"Test Bash"})
        self.assertEqual(self.reads(), 1)
        self.assertEqual(ctx.attempt_jobs_new, {})

    def test_an_attempt_past_the_listed_one_is_read_live(self) -> None:
        self.seed({KEY: entry(checks=["Carried only"])})
        run = dataclasses.replace(self.run_record, attempt=1)
        self.assertEqual(self.answer(run), {"Test Bash"})
        self.assertEqual(self.reads(), 1)

    def test_a_listing_with_an_unfinished_job_is_not_kept(self) -> None:
        self.gh.jobs[(31, 2)] = [FAILED, {**PASSED, "status": "in_progress"}]
        ctx = self.context()
        ctx.failing_checks(self.run_record, 2)
        self.assertEqual(ctx.attempt_jobs_new, {})


class AnAnswerThatCouldChangeIsNotKept(AttemptJobsCase):
    def test_a_job_with_unknown_steps_is_read_again_by_every_process(self) -> None:
        self.gh.jobs[(31, 2)] = [{**FAILED, "steps": []}]
        self.gh.annotations[312] = [failure_annotation("gate failed")]
        ctx = self.context()
        ctx.failing_checks(self.run_record, 2)
        self.assertEqual(ctx.unknown_checks[(31, 2)], {"Test Bash"})
        self.assertEqual(ctx.attempt_jobs_new, {})
        self.answer()
        self.answer()
        self.assertEqual(self.reads(), 3)

    def test_a_failed_job_listing_no_failed_step_is_not_kept(self) -> None:
        self.gh.jobs[(31, 2)] = [{**FAILED, "steps": []}]
        ctx = self.context()
        ctx.failing_checks(self.run_record, 2)
        self.assertEqual(ctx.attempt_jobs_new, {})

    def test_an_annotation_read_the_token_may_not_make_is_not_kept(self) -> None:
        for status in (403, 404):
            with self.subTest(status):
                self.gh.annotations[312] = status
                ctx = self.context()
                self.assertEqual(ctx.failing_checks(self.run_record, 2), {"Test Bash"})
                self.assertEqual(ctx.attempt_jobs_new, {})


class AnUnusableCarryFallsBackToTheLiveRead(AttemptJobsCase):
    UNUSABLE = {
        "no value": None,
        "a list": [ANSWER],
        "no failing check, which would read as a pass": {"checks": []},
        "checks not a list": {"checks": "Test Bash"},
        "a check of no shape": {"checks": [1]},
        "passed jobs not a list": {"passed": {"Lint": True}},
        "jobs not an object": {"jobs": []},
        "a job with no id": {"jobs": {"Test Bash": {"steps": []}}},
        "a job id that is a boolean": {
            "jobs": {"Test Bash": {**ANSWER["jobs"]["Test Bash"], "id": True}}
        },
        "a job with no failed step": {"jobs": {"Test Bash": {"id": 312, "steps": []}}},
        "a step that did not fail": {
            "jobs": {
                "Test Bash": {
                    "id": 312,
                    "steps": [{"name": "Run", "conclusion": "success"}],
                }
            }
        },
        "another head SHA": {"head_sha": "f" * 40},
        "a head SHA of no shape": {"head_sha": "main"},
        "other code": {"code": "0123456789abcdef"},
        "no date": {"at": None},
        "a date with no zone": {"at": "2026-10-12T10:00:00"},
        "dated in the future": {
            "at": (datetime.now(UTC) + timedelta(days=1)).isoformat()
        },
        "past the age bound": {
            "at": (datetime.now(UTC) - timedelta(days=31)).isoformat()
        },
        "past the size bound": {"passed": ["x" * pm.ATTEMPT_JOBS_BYTES]},
    }

    def assert_read_live(self) -> None:
        self.gh.calls.clear()
        self.assertEqual(self.answer(), {"Test Bash"})
        self.assertEqual(self.reads(), 1)

    def test_each_unusable_entry_reads_live_and_keeps_the_live_failure(self) -> None:
        for label, change in self.UNUSABLE.items():
            with self.subTest(label):
                value = entry(**change) if isinstance(change, dict) else change
                self.seed({KEY: value})
                self.assert_read_live()

    def test_a_corrupt_file_reads_live(self) -> None:
        self.path.write_text("{not json", encoding="utf-8")
        with contextlib.redirect_stderr(io.StringIO()):
            self.assert_read_live()

    def test_another_repository_or_version_reads_live(self) -> None:
        for fields in ({"repo": "other/repo"}, {"version": 99}):
            with self.subTest(fields), contextlib.redirect_stderr(io.StringIO()):
                self.seed({KEY: entry(checks=["Carried only"])}, **fields)
                self.assert_read_live()

    def test_a_wrong_shaped_carry_never_turns_a_red_run_into_a_pass(self) -> None:
        list_red_run(self.gh)
        self.seed({KEY: entry(checks=[])})
        verdict = self.check()
        self.assertEqual(self.reads(), 1)
        self.assertEqual([f.signal for f in verdict.failures], ["schedule"])


class AFailedReadStillRefuses(AttemptJobsCase):
    def refused(self) -> pm.PostMergeVerdict:
        list_red_run(self.gh)
        self.gh.fail_reads.add(JOBS_READ)
        return self.check()

    def test_a_502_with_no_carry_is_unreadable(self) -> None:
        verdict = self.refused()
        self.assertFalse(verdict.ok)
        self.assertIn("unreadable", verdict.reason)
        self.assertIn("run 31 attempt 2 jobs", verdict.reason)

    def test_a_502_with_an_unusable_carry_is_unreadable(self) -> None:
        self.seed({KEY: entry(checks=[])})
        verdict = self.refused()
        self.assertFalse(verdict.ok)
        self.assertIn("unreadable", verdict.reason)


class TheFileStaysBounded(AttemptJobsCase):
    def test_a_new_answer_keeps_the_other_usable_answers(self) -> None:
        self.seed({"11:1": entry()})
        self.answer()
        self.assertEqual(set(self.written()["jobs"]), {"11:1", KEY})

    def test_an_answer_past_a_bound_is_dropped_when_the_file_is_written(self) -> None:
        old = (datetime.now(UTC) - timedelta(days=31)).isoformat()
        self.seed({"11:1": entry(at=old), "12:1": entry(code="0123456789abcdef")})
        self.answer()
        self.assertEqual(set(self.written()["jobs"]), {KEY})

    def test_an_entry_of_no_shape_is_dropped_when_the_file_is_written(self) -> None:
        self.seed({"31:2:extra": entry(), "11:1": entry(head_sha="main")})
        self.answer()
        self.assertEqual(set(self.written()["jobs"]), {KEY})

    def test_the_file_holds_the_400_newest_answers(self) -> None:
        start = datetime.now(UTC) - timedelta(hours=1)
        many = {
            f"{1000 + i}:1": entry(at=(start - timedelta(seconds=i)).isoformat())
            for i in range(450)
        }
        self.seed(many)
        self.answer()
        kept = set(self.written()["jobs"])
        self.assertEqual(len(kept), 400)
        self.assertIn(KEY, kept)
        self.assertIn("1000:1", kept)
        self.assertNotIn("1399:1", kept)

    def test_an_answer_past_the_size_bound_is_not_kept(self) -> None:
        self.gh.jobs[(31, 2)] = [
            FAILED,
            {**PASSED, "name": "x" * pm.ATTEMPT_JOBS_BYTES},
        ]
        ctx = self.context()
        ctx.failing_checks(self.run_record, 2)
        self.assertEqual(ctx.attempt_jobs_new, {})

    def test_a_check_that_looks_up_no_attempt_keeps_the_files_attempts(self) -> None:
        attempt = pm._attempt_fields(schedule_run(31, created_at=CREATED))
        self.seed({}, attempts={"31:1": attempt})
        self.answer()
        self.assertEqual(self.written()["attempts"], {"31:1": attempt})

    def test_a_check_with_no_new_answer_leaves_the_file_as_it_was(self) -> None:
        self.seed({KEY: entry()})
        before = json.dumps(self.written(), indent=1)
        self.path.write_text(before, encoding="utf-8")
        self.answer()
        self.assertEqual(self.path.read_text(encoding="utf-8"), before)


class DispatchedRunsUseTheirOwnKey(AttemptJobsCase):
    def test_a_completed_dispatch_run_is_kept_under_its_own_attempt(self) -> None:
        run = pm.Run.from_api(dispatch_run(11, "failure"))
        self.gh.jobs[(11, 1)] = [FAILED]
        ctx = self.context()
        ctx.failing_checks(run, 1)
        self.assertEqual(list(ctx.attempt_jobs_new), ["11:1"])


if __name__ == "__main__":
    unittest.main()
