"""The attempt-jobs carry of the post-merge check (`babysit_postmerge`).

A completed attempt's job list cannot change, so `_Context.failing_checks`
saves its answer in the pr-merge run cache and
.github/scripts/pr-merge/carry-run-cache.mjs brings it to later runs. Job and
annotation shapes follow the jobs API as `test_babysit_postmerge` fakes it; the
expected checks are worked by hand from `failing_checks`' rule that a failed
job with no failure annotation counts as one check under its own name.
"""

from __future__ import annotations

import dataclasses
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
from datetime import timedelta
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import babysit_postmerge as pm
import babysit_run_cache as run_cache
from test_babysit_postmerge import (
    IDENTITY,
    LATER_SHA,
    REPO,
    CheckCase,
    by,
    canary_run,
    dispatch_run,
    failed_job,
    failure_annotation,
    schedule_run,
)

SCRIPTS = pathlib.Path(__file__).resolve().parent.parent
CARRY = (
    pathlib.Path(__file__).resolve().parents[6]
    / ".github/scripts/pr-merge/carry-run-cache.mjs"
)
OWNER, NAME = REPO.split("/")
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
NEW_PROCESS = """
import json, sys
sys.path.insert(0, sys.argv[1])
import babysit_postmerge as pm
def no_read(*args, **kwargs):
    raise AssertionError("the carried attempt was read from GitHub")
pm.gh_capture = no_read
run = pm.Run.from_api(json.loads(sys.argv[2]))
ctx = pm._Context(sys.argv[3], sys.argv[4], "identity", branch="main")
checks = ctx.failing_checks(run, 2)
print(json.dumps({
    "checks": sorted(checks),
    "unknown": sorted(ctx.unknown_checks[(run.id, 2)]),
    "passed": sorted(ctx.passed_jobs[(run.id, 2)]),
    "suite_job": ctx.check_jobs[(run.id, 2)]["Test Bash"]["id"],
}))
"""


def carry(source: pathlib.Path, target: pathlib.Path) -> None:
    subprocess.run(
        ["node", str(CARRY)],
        env={
            "PATH": os.environ["PATH"],
            "CARRY_FROM": str(source),
            "CARRY_TO": str(target),
            "GITHUB_REPOSITORY": REPO,
        },
        check=True,
        capture_output=True,
    )


class AttemptJobsCase(CheckCase):
    """Schedule run 31 on LATER_SHA, red again on its attempt 2."""

    def setUp(self) -> None:
        super().setUp()
        tmp = tempfile.TemporaryDirectory(prefix="attempt-jobs-")
        self.addCleanup(tmp.cleanup)
        self.dir = pathlib.Path(tmp.name)
        self.cache = self.dir / "run-cache.json"
        self.use_cache(self.cache)
        self.addCleanup(run_cache._memo.clear)
        self.payload = schedule_run(
            31,
            run_attempt=2,
            triggering_actor=by(IDENTITY),
            created_at="2026-10-12T10:30:00Z",
        )
        self.run_record = pm.Run.from_api(self.payload)
        self.gh.jobs[(31, 2)] = [FAILED, PASSED]

    def use_cache(self, path: pathlib.Path) -> None:
        patcher = mock.patch.dict(os.environ, {run_cache.ENV: str(path)})
        patcher.start()
        self.addCleanup(patcher.stop)
        run_cache._memo.clear()

    def listed_run(self) -> None:
        self.gh.add_runs("post-merge-detect-silent-revert.yml", "push", canary_run(21))
        self.gh.add_runs("pr-require-checks.yml", "schedule", self.payload)
        self.gh.attempts[(31, 1)] = schedule_run(31, created_at="2026-10-12T10:30:00Z")

    def context(self) -> pm._Context:
        return pm._Context(OWNER, NAME, IDENTITY, branch="main")

    def key(self, code: str | None = None) -> str:
        return f"{REPO}|31|2|{code or pm._attempt_jobs_code()}"

    def seed(self, value: Any, *, key: str | None = None, age_days: int = 0) -> None:
        at = run_cache.now() - timedelta(days=age_days)
        entry = {"at": at.isoformat(), "value": value}
        section = {key or self.key(): entry}
        self.cache.write_text(
            json.dumps({pm.CARRIED_ATTEMPT_JOBS_SECTION: section}), encoding="utf-8"
        )
        run_cache._memo.clear()

    def job_reads(self) -> int:
        return sum(
            1 for call in self.gh.calls if any("/jobs?per_page" in a for a in call)
        )

    def saved(self) -> dict[str, Any]:
        if not self.cache.exists():
            return {}
        data = json.loads(self.cache.read_text(encoding="utf-8"))
        return data.get(pm.ATTEMPT_JOBS_SECTION, {})


class ACarriedAttemptSendsNoRead(AttemptJobsCase):
    def test_a_carried_answer_restores_every_value_with_no_read(self) -> None:
        self.seed(ANSWER)
        ctx = self.context()
        self.assertEqual(ctx.failing_checks(self.run_record, 2), {"Test Bash"})
        self.assertEqual(self.job_reads(), 0)
        self.assertEqual(ctx.unknown_checks[(31, 2)], frozenset())
        self.assertEqual(ctx.passed_jobs[(31, 2)], {"Lint"})
        self.assertEqual(ctx.check_jobs[(31, 2)], ANSWER["jobs"])

    def test_a_live_read_saves_the_answer_the_carry_restores(self) -> None:
        self.context().failing_checks(self.run_record, 2)
        self.assertEqual(self.job_reads(), 1)
        self.assertEqual(self.saved()[self.key()]["value"], ANSWER)

    def test_a_check_on_the_carried_answer_survives_the_502_with_the_same_report(
        self,
    ) -> None:
        self.listed_run()
        live = self.check()
        self.assertEqual([f.signal for f in live.failures], ["schedule"])
        self.assertEqual(self.job_reads(), 1)
        self.gh.calls.clear()
        self.gh.fail_reads.add("/jobs?per_page")
        carried = self.check()
        self.assertEqual(self.job_reads(), 0)
        self.assertEqual(carried.report(), live.report())


class AnAttemptStillBeingWrittenIsReadLive(AttemptJobsCase):
    def test_an_in_progress_run_ignores_a_carried_answer_and_saves_nothing(
        self,
    ) -> None:
        self.seed({**ANSWER, "checks": ["Carried only"]})
        run = dataclasses.replace(self.run_record, status="in_progress")
        ctx = self.context()
        self.assertEqual(ctx.failing_checks(run, 2), {"Test Bash"})
        self.assertEqual(self.job_reads(), 1)
        self.assertEqual(self.saved(), {})

    def test_an_attempt_past_the_listed_one_is_read_live(self) -> None:
        self.seed({**ANSWER, "checks": ["Carried only"]})
        run = dataclasses.replace(self.run_record, attempt=1)
        self.assertEqual(self.context().failing_checks(run, 2), {"Test Bash"})
        self.assertEqual(self.job_reads(), 1)

    def test_a_listing_with_an_unfinished_job_is_not_saved(self) -> None:
        self.gh.jobs[(31, 2)] = [FAILED, {**PASSED, "status": "in_progress"}]
        self.context().failing_checks(self.run_record, 2)
        self.assertEqual(self.saved(), {})


class AnAnswerThatCouldChangeIsNotSaved(AttemptJobsCase):
    def test_a_job_with_unknown_steps_is_read_again_by_every_process(self) -> None:
        self.gh.jobs[(31, 2)] = [{**FAILED, "steps": []}]
        self.gh.annotations[312] = [failure_annotation("gate failed")]
        ctx = self.context()
        ctx.failing_checks(self.run_record, 2)
        self.assertEqual(ctx.unknown_checks[(31, 2)], {"Test Bash"})
        self.assertEqual(self.saved(), {})
        self.context().failing_checks(self.run_record, 2)
        self.assertEqual(self.job_reads(), 2)

    def test_a_failed_job_listing_no_failed_step_is_not_saved(self) -> None:
        self.gh.jobs[(31, 2)] = [{**FAILED, "steps": []}]
        self.context().failing_checks(self.run_record, 2)
        self.assertEqual(self.saved(), {})

    def test_an_annotation_read_the_token_may_not_make_is_not_saved(self) -> None:
        self.gh.annotations[312] = 403
        checks = self.context().failing_checks(self.run_record, 2)
        self.assertEqual(checks, {"Test Bash"})
        self.assertEqual(self.saved(), {})


class AnUnusableCarryFallsBackToTheLiveRead(AttemptJobsCase):
    UNUSABLE = {
        "no value": None,
        "a list": [ANSWER],
        "no failing check, which would read as a pass": {**ANSWER, "checks": []},
        "checks not a list": {**ANSWER, "checks": "Test Bash"},
        "a check of no shape": {**ANSWER, "checks": [1]},
        "passed jobs not a list": {**ANSWER, "passed": {"Lint": True}},
        "jobs not an object": {**ANSWER, "jobs": []},
        "a job with no id": {**ANSWER, "jobs": {"Test Bash": {"steps": []}}},
        "a job id that is a boolean": {
            **ANSWER,
            "jobs": {"Test Bash": {**ANSWER["jobs"]["Test Bash"], "id": True}},
        },
        "a job with no failed step": {
            **ANSWER,
            "jobs": {"Test Bash": {"id": 312, "steps": []}},
        },
        "a step that did not fail": {
            **ANSWER,
            "jobs": {
                "Test Bash": {
                    "id": 312,
                    "steps": [{"name": "Run", "conclusion": "success"}],
                }
            },
        },
        "another head SHA": {**ANSWER, "head_sha": "f" * 40},
    }

    def test_each_wrong_shape_reads_live_and_keeps_the_live_failure(self) -> None:
        for label, value in self.UNUSABLE.items():
            with self.subTest(label):
                self.gh.calls.clear()
                self.seed(value)
                checks = self.context().failing_checks(self.run_record, 2)
                self.assertEqual(checks, {"Test Bash"})
                self.assertEqual(self.job_reads(), 1)

    def test_a_corrupt_file_reads_live(self) -> None:
        self.cache.write_text("{not json", encoding="utf-8")
        run_cache._memo.clear()
        self.assertEqual(
            self.context().failing_checks(self.run_record, 2), {"Test Bash"}
        )
        self.assertEqual(self.job_reads(), 1)

    def test_an_answer_from_other_code_reads_live(self) -> None:
        self.seed(
            {**ANSWER, "checks": ["Carried only"]}, key=self.key("0123456789abcdef")
        )
        self.assertEqual(
            self.context().failing_checks(self.run_record, 2), {"Test Bash"}
        )
        self.assertEqual(self.job_reads(), 1)

    def test_an_answer_past_the_age_bound_reads_live(self) -> None:
        self.seed({**ANSWER, "checks": ["Carried only"]}, age_days=31)
        self.assertEqual(
            self.context().failing_checks(self.run_record, 2), {"Test Bash"}
        )
        self.assertEqual(self.job_reads(), 1)

    def test_a_wrong_shaped_carry_never_turns_a_red_run_into_a_pass(self) -> None:
        self.listed_run()
        self.seed({**ANSWER, "checks": []})
        verdict = self.check()
        self.assertEqual(self.job_reads(), 1)
        self.assertEqual([f.signal for f in verdict.failures], ["schedule"])


class AFailedReadStillRefuses(AttemptJobsCase):
    def refused(self) -> pm.PostMergeVerdict:
        self.listed_run()
        self.gh.fail_reads.add("/jobs?per_page")
        return self.check()

    def test_a_502_with_no_carry_is_unreadable(self) -> None:
        verdict = self.refused()
        self.assertFalse(verdict.ok)
        self.assertIn("unreadable", verdict.reason)
        self.assertIn("run 31 attempt 2 jobs", verdict.reason)

    def test_a_502_with_an_unusable_carry_is_unreadable(self) -> None:
        self.seed({**ANSWER, "checks": []})
        verdict = self.refused()
        self.assertFalse(verdict.ok)
        self.assertIn("unreadable", verdict.reason)


class TheCarrySurvivesIntoANewProcess(AttemptJobsCase):
    def test_a_new_interpreter_answers_from_the_file_the_carry_script_wrote(
        self,
    ) -> None:
        self.context().failing_checks(self.run_record, 2)
        carried = self.dir / "carried.json"
        next_run = self.dir / "next-run-cache.json"
        carry(self.cache, carried)
        carry(carried, next_run)
        proc = subprocess.run(
            [
                sys.executable,
                "-c",
                NEW_PROCESS,
                str(SCRIPTS),
                json.dumps(self.payload),
                OWNER,
                NAME,
            ],
            env={**os.environ, run_cache.ENV: str(next_run)},
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertEqual(
            json.loads(proc.stdout),
            {
                "checks": ["Test Bash"],
                "unknown": [],
                "passed": ["Lint"],
                "suite_job": 312,
            },
        )

    def test_the_carry_script_keeps_the_saved_answer_whole(self) -> None:
        self.context().failing_checks(self.run_record, 2)
        carried = self.dir / "carried.json"
        carry(self.cache, carried)
        data = json.loads(carried.read_text(encoding="utf-8"))
        self.assertEqual(
            data[pm.CARRIED_ATTEMPT_JOBS_SECTION][self.key()]["value"], ANSWER
        )


class DispatchedRunsUseTheSameKey(AttemptJobsCase):
    def test_a_completed_dispatch_run_is_saved_under_its_own_attempt(self) -> None:
        run = pm.Run.from_api(dispatch_run(11, "failure"))
        self.gh.jobs[(11, 1)] = [FAILED]
        self.context().failing_checks(run, 1)
        self.assertEqual(list(self.saved()), [f"{REPO}|11|1|{pm._attempt_jobs_code()}"])


if __name__ == "__main__":
    unittest.main()
