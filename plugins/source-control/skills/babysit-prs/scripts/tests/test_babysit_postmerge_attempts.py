# test-scope: plugins/source-control/lib/parse-concern-value.sh
"""The attempt carry of the post-merge check (`babysit_postmerge`).

A completed attempt of a workflow run never changes, so a check answers an
earlier attempt of a re-run full run from the file pr-merge.yml names in
`BABYSIT_POSTMERGE_ATTEMPTS` with no read, for the same run, attempt and head
SHA, and writes back the completed attempts it used. The reports are pins:
the check with no file (the code before the carry) is the source, and a
carried check must report the same. Request counts come from the
`babysit-gh-calls` counter (`babysit_gh._run_gh`), with gh stubbed at
`run_command` by the same fake as the check's tests; each run at attempt 2
costs one read of its attempt 1 (`_Context._outcome`: attempt 1 decides).
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
    OTHER_SHA,
    REPO,
    SINCE,
    FakeGh,
    by,
    canary_run,
    dispatch_run,
    human,
    schedule_run,
)

NOW = datetime(2026, 10, 12, 11, 0, tzinfo=UTC)
ATTEMPT_READS = "default GET repos/{}/{}/actions/runs/{}/attempts/{}"


class AttemptCase(unittest.TestCase):
    """Dispatch run 11 failed attempt 1 and passed its re-run (a flake), and
    schedule run 31 failed both attempts (a failure): two attempt-1 reads."""

    def setUp(self) -> None:
        self.gh = FakeGh()
        tmp = tempfile.TemporaryDirectory(prefix="attempts-")
        self.addCleanup(tmp.cleanup)
        self.path = pathlib.Path(tmp.name) / "attempts.json"

        def run_command(command: list[str], **kwargs: Any) -> Any:
            # The fake answers without headers, so the `-i` the guard adds is dropped.
            args = [a for i, a in enumerate(command[1:]) if (i, a) != (1, "-i")]
            return self.gh(args, timeout_seconds=kwargs.get("timeout_seconds"))

        patcher = mock.patch.object(gh, "run_command", side_effect=run_command)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.addCleanup(gh.reset_gh_call_counts)
        self.gh.add_runs("post-merge-detect-silent-revert.yml", "push", canary_run(21))
        self.gh.add_runs(
            "pr-require-checks.yml",
            "workflow_dispatch",
            dispatch_run(11, run_attempt=2, conclusion="success"),
        )
        self.gh.attempts[(11, 1)] = dispatch_run(11, conclusion="failure")
        after = "2026-10-12T10:02:00Z"
        self.gh.add_runs(
            "pr-require-checks.yml",
            "schedule",
            schedule_run(
                31, run_attempt=2, triggering_actor=by(IDENTITY), created_at=after
            ),
        )
        self.gh.attempts[(31, 1)] = schedule_run(31, created_at=after)

    def check(self, path: pathlib.Path | str | None = None) -> pm.PostMergeVerdict:
        """One check, with the attempts file at `path` (None: no file named,
        the check as it was before the carry)."""
        gh.reset_gh_call_counts()
        env = {pm.ATTEMPTS_ENV: "" if path is None else str(path)}
        with (
            mock.patch.dict("os.environ", env),
            contextlib.redirect_stderr(io.StringIO()) as self.stderr,
        ):
            return pm.check(
                REPO,
                agent_identity=IDENTITY,
                is_human=human,
                merged_since=SINCE,
                now=NOW,
                pinned_sha=lambda merge: None,
            )

    def reads(self) -> int:
        return gh.gh_call_counts().get(ATTEMPT_READS, 0)

    def written(self) -> dict[str, Any]:
        return json.loads(self.path.read_text(encoding="utf-8"))

    def baseline(self) -> dict[str, Any]:
        """The report of the check with no file: the pin's source."""
        report = self.check().report()
        self.assertEqual(self.reads(), 2)
        return report


class TheCarrySparesTheAttemptReads(AttemptCase):
    def test_a_carried_check_reports_as_one_with_no_file_in_two_fewer_reads(
        self,
    ) -> None:
        expected = self.baseline()
        self.assertEqual(
            [f.signal for f in self.check(self.path).failures], ["schedule"]
        )
        self.assertEqual(self.reads(), 2)
        self.assertEqual(set(self.written()["attempts"]), {"11:1", "31:1"})
        carried = self.check(self.path)
        self.assertEqual(self.reads(), 0)
        self.assertEqual(carried.report(), expected)
        # The flake and the failure stand on the carried attempt 1.
        self.assertEqual(
            carried.flakes, (f"https://github.com/{REPO}/actions/runs/11",)
        )
        self.assertEqual(
            carried.failures[0].run_url,
            f"https://github.com/{REPO}/actions/runs/31/attempts/2",
        )

    def test_a_carried_check_writes_the_same_attempts_back(self) -> None:
        self.check(self.path)
        first = self.written()
        self.check(self.path)
        self.assertEqual(self.written(), first)

    def test_with_no_file_named_every_attempt_is_read(self) -> None:
        self.check(self.path)
        self.check(None)
        self.assertEqual(self.reads(), 2)


class AnUnusableFileIsNoFile(AttemptCase):
    def carry(self) -> dict[str, Any]:
        self.check(self.path)
        return self.written()

    def assert_read_as_with_no_file(self, expected: dict[str, Any]) -> None:
        verdict = self.check(self.path)
        self.assertEqual(self.reads(), 2)
        self.assertEqual(verdict.report(), expected)

    def test_garbage_is_read_live(self) -> None:
        expected = self.baseline()
        self.path.write_text("{not json", encoding="utf-8")
        self.assert_read_as_with_no_file(expected)
        self.assertIn("attempts not used", self.stderr.getvalue())

    def test_another_repository_or_version_is_read_live(self) -> None:
        expected = self.baseline()
        for change in ({"repo": "other/repo"}, {"version": 2}):
            data = {**self.carry(), **change}
            self.path.write_text(json.dumps(data), encoding="utf-8")
            self.assert_read_as_with_no_file(expected)

    def test_an_in_progress_or_misfiled_entry_drops_the_whole_file(self) -> None:
        expected = self.baseline()
        for key, change in (
            ("11:1", {"status": "in_progress", "conclusion": None}),
            ("11:1", {"id": 12}),
            ("31:1", {"run_attempt": 2}),
            ("31:1", {"head_sha": "not-a-sha"}),
            ("31:1", {"extra": True}),
        ):
            data = self.carry()
            data["attempts"][key] = {**data["attempts"][key], **change}
            self.path.write_text(json.dumps(data), encoding="utf-8")
            self.assert_read_as_with_no_file(expected)

    def test_an_entry_for_another_head_sha_is_read_live(self) -> None:
        expected = self.baseline()
        data = self.carry()
        for entry in data["attempts"].values():
            entry["head_sha"] = OTHER_SHA
        self.path.write_text(json.dumps(data), encoding="utf-8")
        self.assert_read_as_with_no_file(expected)
        # The live reads replace the stale entries.
        self.assertNotIn(
            OTHER_SHA, {e["head_sha"] for e in self.written()["attempts"].values()}
        )


class OnlyCompletedAttemptsAreWritten(AttemptCase):
    def test_an_in_progress_attempt_is_not_written(self) -> None:
        self.gh.attempts[(11, 1)] = dispatch_run(
            11, status="in_progress", conclusion=None
        )
        self.check(self.path)
        self.assertEqual(set(self.written()["attempts"]), {"31:1"})

    def test_a_check_that_looks_up_no_attempt_leaves_the_file_as_it_was(
        self,
    ) -> None:
        self.check(self.path)
        before = self.path.read_text(encoding="utf-8")
        self.gh.runs.clear()
        self.gh.add_runs("post-merge-detect-silent-revert.yml", "push", canary_run(21))
        self.gh.add_runs("pr-require-checks.yml", "workflow_dispatch", dispatch_run(11))
        self.check(self.path)
        self.assertEqual(self.reads(), 0)
        self.assertEqual(self.path.read_text(encoding="utf-8"), before)


if __name__ == "__main__":
    unittest.main()
