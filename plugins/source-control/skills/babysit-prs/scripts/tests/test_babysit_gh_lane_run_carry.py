"""`collect_lane_runs` takes a completed lane run's attempts from the run cache.

A read saved in one pr-merge run is carried to the next by
.github/scripts/pr-merge/carry-run-cache.mjs; these tests carry it the same
way, then check that the warm read asks GitHub only for the listing and that
`babysit_review_evidence.bind()` decides exactly as on a cold read.
"""

from __future__ import annotations

import contextlib
import copy
import functools
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
import babysit_risk

HERE = pathlib.Path(__file__).resolve().parent
FIXTURE = HERE / "fixtures" / "lane_runs" / "run_and_latest_attempt.json"
CARRY = (
    pathlib.Path(__file__).resolve().parents[6]
    / ".github/scripts/pr-merge/carry-run-cache.mjs"
)
REPO = "melodic-software/claude-code-plugins"
LANES = [(".github/workflows/pr-review-hosted.yml", ("pr-review / claude-review-status",))]
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


def index(sha: str) -> str:
    """The read of the code lane's index check runs on `sha`."""
    return (
        f"repos/{REPO}/commits/{sha}/check-runs"
        "?check_name=PR%20Review%20Hosted%20Lane&filter=all&per_page=100"
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
                "head_sha": sha,
                "run_id": run_id,
                "run_attempt": 1,
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
            index(run["head_sha"]): {"total_count": 0, "check_runs": []},
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
            floor=babysit_risk.floor_for(),
        )

    def warm(self) -> pathlib.Path:
        """The run cache a next run starts from, after a cold read."""
        first = self.dir / "first.json"
        self.collect(first)
        carried = self.dir / "carried.json"
        carry(first, carried)
        return carried

    def test_a_warm_carry_reads_only_the_listing_and_the_lane_run_index(self) -> None:
        _, cold = self.collect(self.dir / "cold.json")
        self.assertEqual(len(cold), 5)
        _, warm = self.collect(self.warm())
        self.assertEqual(len(warm), 2)
        self.assertIn("/actions/workflows/", warm[0])
        self.assertEqual(warm[1], index(self.run["head_sha"]))

    def test_warm_and_cold_reads_decide_alike(self) -> None:
        cold, _ = self.collect(None)
        warm, reads = self.collect(self.warm())
        self.assertEqual(len(reads), 2)
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
                    self.assertEqual(len(reads), 5)
                    self.assertEqual(self.decide(runs, sha), self.decide(cold, sha))

    def saved(self, section: str, value: Any) -> pathlib.Path:
        key = gh.lane_run_key(REPO, self.run["id"], 1, "claude-review-status")
        path = self.dir / f"{section}.json"
        entry = {"at": "2026-10-28T00:00:00+00:00", "value": value}
        path.write_text(json.dumps({section: {key: entry}}), encoding="utf-8")
        return path

    def test_a_forged_passing_lane_in_the_uncarried_section_never_binds(self) -> None:
        # Only carry-run-cache.mjs's checked carried-lane-run is served: a
        # lane-run section handed to a gate as it starts is read past.
        self.annotations = []
        cold, _ = self.collect(None)
        sha = self.run["head_sha"]
        self.assertFalse(self.decide(cold, sha)[0].bound)
        forged = copy.deepcopy(gh.lane_run_value(self.run, cold[0]["attempts"]))
        forged["attempts"][0]["jobs"][1]["annotations"] = [
            {
                "annotation_level": "notice",
                "title": "claude-lane-review-complete",
                "message": (
                    f"claude-lane-review-complete lane=claude-review sha={sha} "
                    "findings=0 inline=0 scope=whole"
                ),
            }
        ]
        runs, reads = self.collect(self.saved(gh.LANE_RUN_SECTION, forged))
        self.assertEqual(len(reads), 5)
        self.assertFalse(self.decide(runs, sha)[0].bound)

    def test_a_saved_job_the_listed_run_disagrees_with_is_read_fresh(self) -> None:
        cold, _ = self.collect(None)
        sha = self.run["head_sha"]
        good = gh.lane_run_value(self.run, cold[0]["attempts"])
        for field, wrong in (
            ("head_sha", "0" * 40),
            ("run_id", 1),
            ("run_attempt", 2),
        ):
            for job in (0, 1):
                with self.subTest(field=field, job=job):
                    forged = copy.deepcopy(good)
                    forged["attempts"][0]["jobs"][job][field] = wrong
                    path = self.saved(gh.CARRIED_LANE_RUN_SECTION, forged)
                    runs, reads = self.collect(path)
                    self.assertEqual(len(reads), 5)
                    self.assertEqual(self.decide(runs, sha), self.decide(cold, sha))


class HeldLegAnnotationTests(unittest.TestCase):
    """`collect_lane_runs` reads a held leg's annotations, which
    `babysit_review_evidence._rate_held` binds a re-run on."""

    def setUp(self) -> None:
        import test_babysit_review_evidence as suite

        self.carry = LaneRunCarryTests("test_a_warm_carry_reads_only_the_listing_and_the_lane_run_index")
        self.carry.setUp()
        self.addCleanup(self.carry.doCleanups)
        run = self.carry.run
        sha = run["head_sha"]
        self.carry.annotations = [
            {
                "annotation_level": "notice",
                "title": "",
                "message": f"held: claude-review did not review {sha}: the compare"
                " read of the merge base failed. A later run of this workflow reviews it.",
            }
        ]
        self.leg_notes = [
            {"annotation_level": "warning", "title": "", "message": m}
            for m in (suite.LEG_HOLD, *suite.LEG_REFUSALS)
        ]

    def with_leg(self, review: str) -> str:
        """Adds the Review Subscription leg, its `Claude review` step ended
        `review`, and answers its annotations read; returns that read's path."""
        run = self.carry.run
        self.carry.jobs.append(
            {
                "id": 23,
                "name": "pr-review / Review Subscription",
                "conclusion": "success",
                "head_sha": run["head_sha"],
                "run_id": run["id"],
                "run_attempt": 1,
                "steps": [{"name": "Claude review", "conclusion": review}],
            }
        )
        path = f"repos/{REPO}/check-runs/23/annotations?per_page=100"
        answers = self.carry.answers
        self.carry.answers = lambda r: {**answers(r), path: [self.leg_notes]}
        return path

    def first_attempt(self, runs: list[dict[str, Any]]) -> dict[str, Any]:
        return next(a for a in runs[0]["attempts"] if a["run_attempt"] == 1)

    def leg(self, runs: list[dict[str, Any]]) -> dict[str, Any]:
        return next(j for j in self.first_attempt(runs)["jobs"] if j["id"] == 23)

    def test_a_held_leg_s_annotations_are_read_and_bind_its_rerun(self) -> None:
        path = self.with_leg("skipped")
        runs, reads = self.carry.collect(None)
        self.assertIn(path, reads, "the held leg's annotations are read")
        self.assertEqual(
            [a["message"] for a in self.leg(runs)["annotations"]],
            [a["message"] for a in self.leg_notes],
        )
        self.assertTrue(
            review_evidence._rate_held(
                "claude-review", self.carry.run["id"], self.first_attempt(runs)
            ),
            "_rate_held reads the leg annotations collect_lane_runs attached",
        )

    def test_a_leg_whose_review_ran_is_not_read(self) -> None:
        path = self.with_leg("success")
        runs, reads = self.carry.collect(None)
        self.assertNotIn(path, reads)
        self.assertNotIn("annotations", self.leg(runs))

    def test_a_warm_carry_keeps_the_held_leg_s_annotations(self) -> None:
        self.with_leg("skipped")
        runs, reads = self.carry.collect(self.carry.warm())
        self.assertEqual(len(reads), 2, "the carried v2 record is served: only the listing and the lane-run index are read")
        self.assertEqual(
            [a["message"] for a in self.leg(runs)["annotations"]],
            [a["message"] for a in self.leg_notes],
        )
        self.assertTrue(
            review_evidence._rate_held(
                "claude-review", self.carry.run["id"], self.first_attempt(runs)
            )
        )


@functools.cache
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


MAIN_TIP = "9" * 40


class LaneRunGateTests(unittest.TestCase):
    """The merge gate binds a lane's review from the caller's workflow_run lane
    run: found through the index check run on the head, collected only when
    its own record binds it to this pull request at that head, and read as a
    run on that head. The head's pull_request run only started it, so it has
    no status job."""

    def setUp(self) -> None:
        self.carry = LaneRunCarryTests(
            "test_a_warm_carry_reads_only_the_listing_and_the_lane_run_index"
        )
        self.carry.setUp()
        self.addCleanup(self.carry.doCleanups)
        self.trigger = self.carry.run
        self.sha = self.trigger["head_sha"]
        self.pr = self.trigger["pull_requests"][0]["number"]
        self.lane_id = self.trigger["id"] + 1

    def lane_run(self, change: Mapping[str, Any]) -> dict[str, Any]:
        return {
            "id": self.lane_id,
            "path": ".github/workflows/pr-review-hosted-lane.yml",
            "event": "workflow_run",
            "head_branch": "main",
            "head_sha": MAIN_TIP,
            "head_commit": {"id": MAIN_TIP, "tree_id": "8" * 40},
            "status": "completed",
            "conclusion": "success",
            "run_attempt": 1,
            "created_at": "2026-10-23T05:00:00Z",
            "updated_at": "2026-10-23T05:01:39Z",
            "run_started_at": "2026-10-23T05:00:00Z",
            "repository": {"full_name": REPO},
            "head_repository": {"full_name": REPO},
            "display_title": f"PR Review Hosted Lane #{self.pr} {self.sha}",
            **change,
        }

    def collect(self, change: Mapping[str, Any]) -> tuple[list[dict[str, Any]], list[str]]:
        trigger, lane = self.trigger, self.lane_run(change)
        kill = {**self.carry.jobs[0]}
        lane_jobs = [
            {**job, "id": job["id"] + 10, "head_sha": MAIN_TIP, "run_id": self.lane_id}
            for job in self.carry.jobs
        ]
        listing = (
            f"repos/{REPO}/actions/workflows/pr-review-hosted.yml/runs"
            f"?branch={trigger['head_branch'].replace('/', '%2F')}"
            "&event=pull_request&per_page=100"
        )
        answers: dict[str, Any] = {
            listing: [{"workflow_runs": [trigger]}],
            f"repos/{REPO}/actions/runs/{trigger['id']}": trigger,
            f"repos/{REPO}/actions/runs/{trigger['id']}/attempts/1/jobs?per_page=100": [{"jobs": [kill]}],
            f"repos/{REPO}/check-runs/21/annotations?per_page=100": [[]],
            index(self.sha): {"total_count": 1, "check_runs": [{"external_id": str(self.lane_id)}]},
            f"repos/{REPO}/actions/runs/{self.lane_id}": lane,
            f"repos/{REPO}/actions/runs/{self.lane_id}/attempts/1/jobs?per_page=100": [{"jobs": lane_jobs}],
            f"repos/{REPO}/check-runs/32/annotations?per_page=100": [self.carry.annotations],
            f"repos/{REPO}/git/commits/{self.sha}": {"sha": self.sha, "tree": {"sha": TREE}},
        }
        reads: list[str] = []

        def fake(args: list[str]) -> Any:
            reads.append(args[1])
            if args[1] not in answers:
                raise RuntimeError(f"gh: Not Found (HTTP 404) {args[1]}")
            return copy.deepcopy(answers[args[1]])

        with mock.patch.object(gh, "gh_json", side_effect=fake):
            os.environ.pop("BABYSIT_RUN_CACHE", None)
            runs = gh.collect_lane_runs(REPO, self.pr, trigger["head_branch"], LANES)
        return runs, reads

    def test_a_bound_lane_run_binds_the_lane_on_the_head_it_names(self) -> None:
        runs, reads = self.collect({})
        lane = next(run for run in runs if run["id"] == self.lane_id)
        self.assertEqual(lane["head_sha"], self.sha, "the lane run stands on the head its run-name names")
        self.assertEqual(lane["head_commit"]["tree_id"], TREE, "with that head's tree, not main's")
        self.assertEqual(
            {job["head_sha"] for attempt in lane["attempts"] for job in attempt["jobs"]},
            {self.sha},
        )
        self.assertIn(index(self.sha), reads)
        evidence = self.carry.decide(runs, self.sha)[0]
        self.assertTrue(evidence.bound, evidence)

    def test_a_lane_run_bound_elsewhere_is_never_collected(self) -> None:
        for label, change in {
            "another pull request": {"display_title": f"PR Review Hosted Lane #{self.pr + 1} {self.sha}"},
            "another head": {"display_title": f"PR Review Hosted Lane #{self.pr} {'0' * 40}"},
            "another branch": {"head_branch": self.trigger["head_branch"]},
            "another event": {"event": "pull_request"},
            "another path": {"path": ".github/workflows/pr-review-hosted.yml"},
            "another repository": {"head_repository": {"full_name": "fork/claude-code-plugins"}},
        }.items():
            with self.subTest(label):
                runs, _ = self.collect(change)
                self.assertEqual([run["id"] for run in runs], [self.trigger["id"]])
                evidence = self.carry.decide(runs, self.sha)[0]
                self.assertEqual((evidence.bound, evidence.unbound_reason), (False, "no-lane-job"))

    def test_an_index_that_does_not_read_whole_fails_the_collection(self) -> None:
        with mock.patch.object(
            gh.lane_binding, "lane_runs_at", side_effect=RuntimeError("did not read whole")
        ), self.assertRaises(RuntimeError):
            self.collect({})
