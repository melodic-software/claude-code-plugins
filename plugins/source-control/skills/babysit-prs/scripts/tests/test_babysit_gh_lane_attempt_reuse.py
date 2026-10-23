"""`collect_lane_runs` uses the fresh run read as the run's latest attempt.

The fixture is a recorded live pair: `GET actions/runs/{id}` and
`GET actions/runs/{id}/attempts/{run_attempt}` for one completed
pr-review-hosted run, with the actor, commit and repository objects (equal in
both) left out. Those two responses differ only in `jobs_url` and `logs_url`.
"""

from __future__ import annotations

import json
import pathlib
import sys
import unittest
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_gh as gh

FIXTURE = (
    pathlib.Path(__file__).resolve().parent
    / "fixtures"
    / "lane_runs"
    / "run_and_latest_attempt.json"
)
# Every attempt field babysit_review_evidence.bind() reads.
BIND_FIELDS = ("id", "run_attempt", "status", "conclusion", "head_sha")


class LaneAttemptReuseTests(unittest.TestCase):
    REPO = "melodic-software/claude-code-plugins"
    LANES = [(".github/workflows/pr-review-hosted.yml", "claude-review-status")]

    def setUp(self) -> None:
        recorded = json.loads(FIXTURE.read_text(encoding="utf-8"))
        self.run_record = recorded["run"]
        self.attempt = recorded["latest_attempt"]

    def test_the_recorded_pair_differs_only_in_unread_urls(self) -> None:
        differing = {
            key
            for key in self.run_record.keys() | self.attempt.keys()
            if self.run_record.get(key) != self.attempt.get(key)
        }
        self.assertEqual(differing, {"jobs_url", "logs_url"})

    def collect(self, run: dict[str, Any], earlier: dict[int, Any]) -> Any:
        run_id = run["id"]
        base = f"repos/{self.REPO}/actions/runs/{run_id}"
        listing = (
            f"repos/{self.REPO}/actions/workflows/pr-review-hosted.yml/runs"
            f"?branch={run['head_branch'].replace('/', '%2F')}"
            "&event=pull_request&per_page=100"
        )
        number = run["pull_requests"][0]["number"]
        answers: dict[str, Any] = {listing: [{"workflow_runs": [run]}], base: run}
        for n in range(1, run["run_attempt"] + 1):
            answers[f"{base}/attempts/{n}/jobs?per_page=100"] = [{"jobs": []}]
        for n, attempt in earlier.items():
            answers[f"{base}/attempts/{n}"] = attempt
        self.reads: list[str] = []

        def fake(args: list[str]) -> Any:
            self.reads.append(args[1])
            if args[1] not in answers:
                raise RuntimeError(f"gh: Not Found (HTTP 404) {args[1]}")
            return answers[args[1]]

        with mock.patch.object(gh, "gh_json", side_effect=fake):
            return gh.collect_lane_runs(
                self.REPO, number, run["head_branch"], self.LANES
            )

    def test_the_latest_attempt_is_the_run_read_and_is_not_requested(self) -> None:
        runs = self.collect(self.run_record, {})
        latest = runs[0]["attempts"][-1]
        self.assertEqual(
            {field: latest[field] for field in BIND_FIELDS},
            {field: self.attempt[field] for field in BIND_FIELDS},
        )
        self.assertNotIn(
            f"repos/{self.REPO}/actions/runs/{self.run_record['id']}/attempts/1",
            self.reads,
        )

    def test_earlier_attempts_are_still_read(self) -> None:
        rerun = {**self.run_record, "run_attempt": 2}
        first = {**self.attempt, "conclusion": "failure"}
        runs = self.collect(rerun, {1: first})
        attempts = runs[0]["attempts"]
        self.assertEqual(
            [(a["run_attempt"], a["conclusion"]) for a in attempts],
            [(1, "failure"), (2, "success")],
        )
        base = f"repos/{self.REPO}/actions/runs/{self.run_record['id']}"
        self.assertIn(f"{base}/attempts/1", self.reads)
        self.assertNotIn(f"{base}/attempts/2", self.reads)


if __name__ == "__main__":
    unittest.main()
