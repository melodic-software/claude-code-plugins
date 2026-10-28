"""`collect_lane_runs` takes a completed lane run's attempts from the run cache.

A read saved in one pr-merge run is carried to the next by
.github/scripts/pr-merge/carry-run-cache.mjs; these tests carry it the same
way, then check that the warm read asks GitHub only for the listing and that
`babysit_review_evidence.bind()` decides exactly as on a cold read.
"""

from __future__ import annotations

import contextlib
import copy
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
from collections.abc import Iterator, Mapping
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import babysit_gh as gh
import babysit_review_evidence as review_evidence

HERE = pathlib.Path(__file__).resolve().parent
FIXTURE = HERE / "fixtures" / "lane_runs" / "run_and_latest_attempt.json"
CARRY = (
    pathlib.Path(__file__).resolve().parents[6]
    / ".github/scripts/pr-merge/carry-run-cache.mjs"
)
REPO = "melodic-software/claude-code-plugins"
LANES = [(".github/workflows/pr-review-hosted.yml", "claude-review-status")]
TREE = "7ee1" * 10


def carry(source: pathlib.Path, target: pathlib.Path) -> None:
    """Carry `source`'s kept reads into `target`, as pr-merge.yml does
    between runs."""
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


class LaneRunCarryTests(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = pathlib.Path(tmp.name)
        recorded = json.loads(FIXTURE.read_text(encoding="utf-8"))
        self.run = {**recorded["run"], "head_commit": {"tree_id": TREE}}
        sha = self.run["head_sha"]
        run_id = self.run["id"]
        self.jobs = [
            {
                "id": 21,
                "name": "kill-switch",
                "conclusion": "success",
                "steps": [{"name": "Set up job"}],
            },
            {
                "id": 22,
                "name": "pr-review / claude-review-status",
                "status": "completed",
                "conclusion": "success",
                "head_sha": sha,
                "run_id": run_id,
                "run_attempt": 1,
                "started_at": "2026-10-23T04:58:10Z",
                "completed_at": "2026-10-23T04:59:30Z",
                "steps": [{"name": "Review"}],
            },
        ]
        self.annotations = [
            {
                "path": ".github",
                "annotation_level": "notice",
                "title": "claude-lane-review-complete",
                "message": (
                    f"claude-lane-review-complete lane=claude-review sha={sha} "
                    "findings=0 inline=0 scope=whole"
                ),
                "start_line": 1,
            }
        ]

    def answers(self, run: dict[str, Any]) -> dict[str, Any]:
        base = f"repos/{REPO}/actions/runs/{run['id']}"
        listing = (
            f"repos/{REPO}/actions/workflows/pr-review-hosted.yml/runs"
            f"?branch={run['head_branch'].replace('/', '%2F')}"
            "&event=pull_request&per_page=100"
        )
        return {
            listing: [{"workflow_runs": [run]}],
            base: run,
            f"{base}/attempts/1/jobs?per_page=100": [{"jobs": self.jobs}],
            f"repos/{REPO}/check-runs/22/annotations?per_page=100": [self.annotations],
        }

    def collect(
        self,
        cache: pathlib.Path | None,
        run: dict[str, Any] | None = None,
        reads: list[str] | None = None,
    ) -> tuple[list[dict[str, Any]], list[str]]:
        run = run or self.run
        answers = self.answers(run)
        reads = [] if reads is None else reads

        def fake(args: list[str]) -> Any:
            reads.append(args[1])
            if args[1] not in answers:
                raise RuntimeError(f"gh: Not Found (HTTP 404) {args[1]}")
            return copy.deepcopy(answers[args[1]])

        env = {"BABYSIT_RUN_CACHE": str(cache)} if cache else {}
        with (
            mock.patch.dict("os.environ", env),
            mock.patch.object(gh, "gh_json", side_effect=fake),
        ):
            if not cache:
                os.environ.pop("BABYSIT_RUN_CACHE", None)
            runs = gh.collect_lane_runs(
                REPO, run["pull_requests"][0]["number"], run["head_branch"], LANES
            )
        return runs, reads

    @staticmethod
    def decide(runs: list[dict[str, Any]], sha: str) -> Any:
        import test_babysit_review_evidence as suite

        return review_evidence.bind(
            sha,
            runs,
            [suite.marker("claude-review", sha)],
            [],
            is_human=lambda actor: False,
            changed_paths=[],
        )

    def warm(self) -> pathlib.Path:
        """The run cache a next run starts from, after a cold read."""
        first = self.dir / "first.json"
        self.collect(first)
        carried = self.dir / "carried.json"
        carry(first, carried)
        return carried

    def test_a_warm_carry_reads_only_the_listing(self) -> None:
        _, cold = self.collect(self.dir / "cold.json")
        self.assertEqual(len(cold), 4)
        _, warm = self.collect(self.warm())
        self.assertEqual(len(warm), 1)
        self.assertIn("/actions/workflows/", warm[0])

    def test_warm_and_cold_reads_decide_alike(self) -> None:
        cold, _ = self.collect(None)
        warm, reads = self.collect(self.warm())
        self.assertEqual(len(reads), 1)
        sha = self.run["head_sha"]
        self.assertEqual(self.decide(warm, sha), self.decide(cold, sha))
        self.assertTrue(self.decide(cold, sha)[0].bound)

    def test_a_listing_that_moved_on_reads_the_run_again(self) -> None:
        carried = self.warm()
        moved = {
            "in progress": {"status": "in_progress", "conclusion": None},
            "re-run": {"run_attempt": 2},
            "updated": {"updated_at": "2026-10-24T00:00:00Z"},
            "other head": {"head_sha": "0" * 40},
            "restarted": {"run_started_at": "2026-10-24T00:00:00Z"},
        }
        for label, change in moved.items():
            with self.subTest(label):
                run = {**self.run, **change}
                reads: list[str] = []
                # A re-run's attempt 1 has no answer here, so its read raises.
                with contextlib.suppress(RuntimeError):
                    self.collect(carried, run, reads)
                self.assertIn(f"repos/{REPO}/actions/runs/{run['id']}", reads)

    def test_an_unreadable_or_forged_carry_is_read_fresh(self) -> None:
        cold, _ = self.collect(None)
        sha = self.run["head_sha"]
        key = gh.lane_run_key(REPO, self.run["id"], 1, "claude-review-status")
        good = gh.lane_run_value(self.run, cold[0]["attempts"])
        at = "2026-10-28T00:00:00+00:00"
        broken = {
            "not json": "{",
            "not an object": "[]",
            "attempts missing": {"updated_at": self.run["updated_at"]},
            "attempt of another run": {
                **good,
                "attempts": [{**good["attempts"][0], "id": 1}],
            },
            "jobs not a list": {
                **good,
                "attempts": [{**good["attempts"][0], "jobs": {}}],
            },
            "two attempts for one": {
                **good,
                "attempts": good["attempts"] * 2,
            },
        }
        for label, value in broken.items():
            for section in (gh.LANE_RUN_SECTION, gh.CARRIED_LANE_RUN_SECTION):
                with self.subTest(label, section=section):
                    path = self.dir / "forged.json"
                    if isinstance(value, str):
                        path.write_text(value, encoding="utf-8")
                    else:
                        entry = {"at": at, "value": value}
                        path.write_text(json.dumps({section: {key: entry}}))
                    runs, reads = self.collect(path)
                    self.assertEqual(len(reads), 4)
                    self.assertEqual(self.decide(runs, sha), self.decide(cold, sha))


def bind_corpus() -> list[tuple[tuple[Any, ...], dict[str, Any]]]:
    """Every `bind()` call the review-evidence suite makes, with its runs as
    they were passed."""
    import test_babysit_review_evidence as suite

    calls: list[tuple[tuple[Any, ...], dict[str, Any]]] = []
    real = review_evidence.bind

    def record(*args: Any, **kwargs: Any) -> Any:
        calls.append((copy.deepcopy(args[:2]) + args[2:], kwargs))
        return real(*args, **kwargs)

    tests = unittest.defaultTestLoader.loadTestsFromModule(suite)
    with mock.patch.object(review_evidence, "bind", side_effect=record):
        unittest.TextTestRunner(stream=open(os.devnull, "w")).run(tests)  # noqa: SIM115
    return calls


class EveryRecordedBindDecidesAlikeWarm(unittest.TestCase):
    """For each run of every bind() call in the review-evidence suite, read as
    GitHub would answer (the listing record is the run record), a saved read
    carried through JSON decides as the cold one."""

    def test_the_corpus(self) -> None:
        calls = bind_corpus()
        self.assertGreater(len(calls), 200)
        warmed = 0
        for index, (args, kwargs) in enumerate(calls):
            head, runs, *rest = args
            if not isinstance(runs, list) or not all(
                isinstance(item, dict) and isinstance(item.get("attempts"), list)
                for item in runs
            ):
                continue
            cold, warm = [], []
            for item in runs:
                attempts = item["attempts"]
                latest = attempts[-1] if attempts else {}
                if (
                    not isinstance(latest, dict)
                    or latest.get("status") != "completed"
                    or not all(
                        isinstance(a, dict)
                        and isinstance(a.get("jobs"), list)
                        and all(isinstance(j, dict) for j in a["jobs"])
                        for a in attempts
                    )
                ):
                    cold.append(item)
                    warm.append(item)
                    continue
                record = {k: v for k, v in item.items() if k != "attempts"}
                record.update({k: v for k, v in latest.items() if k != "jobs"})
                record["updated_at"] = "2026-01-02T00:00:00Z"
                value = json.loads(json.dumps(gh.lane_run_value(record, attempts)))
                saved = gh.carried_lane_attempts(record, value)
                cold.append({**record, "attempts": attempts})
                if saved is None:
                    warm.append({**record, "attempts": attempts})
                else:
                    warmed += 1
                    warm.append({**record, "attempts": saved})
            with self.subTest(index):
                self.assertEqual(
                    review_evidence.bind(head, warm, *rest, **kwargs),
                    review_evidence.bind(head, cold, *rest, **kwargs),
                )
        self.assertGreater(warmed, 200)


class Recorded(Mapping[str, Any]):
    """A record that notes each key read from it into `read`."""

    def __init__(self, data: dict[str, Any], read: set[str]) -> None:
        self.data = data
        self.read = read

    def __getitem__(self, key: str) -> Any:
        self.read.add(key)
        return self.data[key]

    def __contains__(self, key: object) -> bool:
        self.read.add(str(key))
        return key in self.data

    def __iter__(self) -> Iterator[str]:
        self.read.add("<every key>")
        return iter(self.data)

    def __len__(self) -> int:
        return len(self.data)


class BindReadsOnlyTheSavedFields(unittest.TestCase):
    """A saved attempt keeps only the fields bind() reads: over the
    review-evidence suite's bind() calls, it reads no other key of an
    attempt, a job or an annotation."""

    def test_the_corpus(self) -> None:
        read: dict[str, set[str]] = {
            "attempt": set(),
            "job": set(),
            "annotation": set(),
        }

        def job(value: Any) -> Any:
            if not isinstance(value, dict):
                return value
            out = dict(value)
            if isinstance(value.get("annotations"), list):
                out["annotations"] = [
                    Recorded(a, read["annotation"]) if isinstance(a, dict) else a
                    for a in value["annotations"]
                ]
            return Recorded(out, read["job"])

        def attempt(value: Any) -> Any:
            if not isinstance(value, dict):
                return value
            out = dict(value)
            if isinstance(value.get("jobs"), list):
                out["jobs"] = [job(j) for j in value["jobs"]]
            return Recorded(out, read["attempt"])

        for args, kwargs in bind_corpus():
            head, runs, *rest = args
            if isinstance(runs, list):
                runs = [
                    {**item, "attempts": [attempt(a) for a in item["attempts"]]}
                    if isinstance(item, dict) and isinstance(item.get("attempts"), list)
                    else item
                    for item in runs
                ]
            review_evidence.bind(head, runs, *rest, **kwargs)
        self.assertLessEqual(read["attempt"], {*gh.LANE_ATTEMPT_FIELDS, "jobs"})
        self.assertLessEqual(read["job"], {*gh.LANE_JOB_FIELDS, "annotations"})
        self.assertLessEqual(read["annotation"], set(gh.LANE_ANNOTATION_FIELDS))
        self.assertTrue(read["attempt"] and read["job"] and read["annotation"])


if __name__ == "__main__":
    unittest.main()
