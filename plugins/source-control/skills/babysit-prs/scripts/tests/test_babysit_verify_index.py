# test-scope: plugins/source-control/skills/babysit-prs/scripts/tests/test_babysit_verify_evidence.py
"""The verdict reader's index mode (`babysit_verify_evidence.Reader._targeted`).

Expected values come from the module docstring's FAIL rules and
write-verdict.mjs `failIndexNames`: a FAIL uploads one index artifact per tie
(`pr-verify-index-pr-<n>`, `-sha-<head>`, `-ref-<digest>`, `-issue-<i>`)
before the FAIL itself, the API's name filter returns every artifact of that
exact name across runs, and the legacy FAILs file holds every FAIL uploaded
before the index. A judgment then reads those names, never the whole listing,
and any read that fails or does not hold its count refuses.
"""

from __future__ import annotations

import contextlib
import io
import json
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest
from datetime import UTC, datetime
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_postmerge as postmerge
import babysit_verify_evidence as ve
import test_babysit_verify_evidence as base
from test_babysit_verify_evidence import (
    EARLIER,
    HEAD,
    NOW,
    PR,
    REPO,
    UNRELATED,
    artifact,
    named,
    pull,
    record,
    run,
)

DIGEST = ve.head_ref_digest("feat/x")


def index(tie: str, run_id: int, n: int) -> dict[str, Any]:
    """One index artifact of run `run_id`, its id unlike any verdict's."""
    item = artifact(f"{ve.INDEX_PREFIX}{tie}", run_id)
    item["id"] = run_id * 10 + n
    return item


def fail(number: int, sha: str, run_id: int, suffix: str = "") -> list[dict[str, Any]]:
    """A FAIL of pull request `number` at `sha` and the index its run
    uploads first (write-verdict.mjs failIndexNames)."""
    issues = (
        [f"issue-{i}" for i in suffix.removeprefix("-i").split(".")] if suffix else []
    )
    ties = [
        f"pr-{number}",
        f"sha-{sha}",
        f"ref-{DIGEST if number == PR else 'f' * 16}",
        *issues,
    ]
    return [
        artifact(named(sha, "fail", number) + suffix, run_id),
        *(index(tie, run_id, n) for n, tie in enumerate(ties, 1)),
    ]


class IndexGitHub(base.FakeGitHub):
    """The fake GitHub, answering exact-name reads page by page and each
    run's artifacts, and counting both."""

    def __init__(self, *args: Any, **kwargs: Any):
        super().__init__(*args, **kwargs)
        self.name_total: dict[str, int] = {}
        self.still_running: set[int] = set()
        # The verifier runs not completed, as the workflow's run list gives them.
        self.running: list[dict[str, Any]] = []

    def rest(self, args, ok, missing, kwargs):  # type: ignore[no-untyped-def]
        path = next(a for a in args if a.startswith("repos/"))
        if not any(k in path for k in self.fail):
            by_name = re.fullmatch(
                rf"repos/{REPO}/actions/artifacts\?name=([^&]+)&per_page=100&page=([0-9]+)",
                path,
            )
            if by_name:
                held = [a for a in self.artifacts if a.get("name") == by_name[1]]
                page = int(by_name[2])
                return ok(
                    {
                        "total_count": self.name_total.get(by_name[1], len(held)),
                        "artifacts": held[(page - 1) * 100 : page * 100],
                    }
                )
            of_run = re.fullmatch(
                rf"repos/{REPO}/actions/runs/([0-9]+)/artifacts\?per_page=100", path
            )
            if of_run:
                held = [
                    a
                    for a in self.artifacts
                    if a["workflow_run"]["id"] == int(of_run[1])
                ]
                return ok({"total_count": len(held), "artifacts": held})
            running = re.fullmatch(
                rf"repos/{REPO}/actions/workflows/pr-verify\.yml/runs\?status=([a-z_]+)&per_page=100",
                path,
            )
            if running:
                listed = [r for r in self.running if r["status"] == running[1]]
                return ok({"total_count": len(listed), "workflow_runs": listed})
            ran = re.fullmatch(rf"repos/{REPO}/actions/runs/([0-9]+)", path)
            if ran and int(ran[1]) in self.still_running:
                return ok(run(int(ran[1]), status="in_progress", conclusion=None))
        return super().rest(args, ok, missing, kwargs)

    def whole(self) -> int:
        """Reads of the whole listing or its count, which index mode never makes."""
        return (
            self.full_listings()
            + self.probes()
            + sum("actions/artifacts?per_page=" in " ".join(c) for c in self.calls)
        )


class IndexMode(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.legacy_file = pathlib.Path(self.tmp.name, ve.LEGACY_FAILS_FILE)
        self.legacy([])

    def legacy(self, entries: list[dict[str, Any]], **overrides: Any) -> None:
        self.legacy_file.write_text(
            json.dumps(
                {
                    "version": ve.LEGACY_FAILS_VERSION,
                    "repo": REPO,
                    "cutover": "2026-10-15T00:00:00+00:00",
                    "artifacts": entries,
                    **overrides,
                }
            )
        )

    def reader(self, **kwargs: Any) -> ve.Reader:
        return ve.Reader(
            REPO, "main", now=NOW, legacy_path=str(self.legacy_file), **kwargs
        )

    def judge(self, fake: IndexGitHub, **kwargs: Any) -> ve.Evidence:
        with (
            mock.patch.object(postmerge, "gh_capture", side_effect=fake),
            mock.patch.object(ve.merge_policy, "gh_capture", side_effect=fake),
        ):
            return self.reader(**kwargs).evidence(PR, HEAD, pull())

    def passing(
        self, *extra: dict[str, Any], runs: dict[int, Any] | None = None
    ) -> IndexGitHub:
        return IndexGitHub(
            [artifact(named(HEAD, "pass"), 1), *extra],
            {1: run(1), **(runs or {})},
            {named(HEAD, "pass"): record()},
        )

    def test_a_pass_allows_without_the_whole_listing(self) -> None:
        fake = self.passing()
        self.assertTrue(self.reader().index_mode())
        self.assertIsNone(self.judge(fake).refusal)
        self.assertEqual(fake.whole(), 0)

    def test_no_legacy_file_keeps_the_whole_listing(self) -> None:
        for text in (
            None,
            "{not json",
            json.dumps({"version": 1, "repo": "other/repo", "artifacts": []}),
        ):
            if text is None:
                self.legacy_file.unlink()
            else:
                self.legacy_file.write_text(text)
            self.assertFalse(self.reader().index_mode(), text)
        self.assertFalse(ve.Reader(REPO, "main", legacy_path=None).index_mode())

    def test_a_fail_at_the_head_under_another_number_refuses(self) -> None:
        # Found by the head's sha index alone: PR 90 is tied to nothing else.
        fake = self.passing(*fail(90, HEAD, 3), runs={3: run(3)})
        self.assertEqual(self.judge(fake).refusal, ve.FAIL)
        self.assertEqual(fake.whole(), 0)

    def test_a_fail_at_an_earlier_head_refuses(self) -> None:
        fake = self.passing(
            *fail(PR, EARLIER, 3), runs={3: run(3, created_at="2026-10-16T00:00:00Z")}
        )
        self.assertEqual(self.judge(fake).refusal, ve.EARLIER_FAIL)

    def test_a_fail_tied_by_head_branch_alone_refuses(self) -> None:
        # Another number and head; its run uploaded this branch's ref index,
        # and its verdict records the branch.
        items = [
            artifact(named(UNRELATED, "fail", 90), 3),
            index(f"ref-{DIGEST}", 3, 1),
        ]
        fake = self.passing(*items, runs={3: run(3, created_at="2026-10-16T00:00:00Z")})
        fake.records[named(UNRELATED, "fail", 90)] = record(
            90, UNRELATED, verdict="fail"
        )
        self.assertEqual(self.judge(fake).refusal, ve.EARLIER_FAIL)

    def test_a_fail_naming_a_live_issue_counts_toward_the_cap(self) -> None:
        # Pull request 60 closes nothing; its FAIL's name carries the issue
        # the judged pull request closes.
        own = fail(PR, HEAD, 3)
        other = fail(60, UNRELATED, 4, "-i7")
        fake = self.passing(*own, *other, runs={3: run(3), 4: run(4)})
        fake.pulls[60] = {
            "state": "open",
            "user": {"login": "maintainer", "type": "User"},
        }
        self.assertEqual(self.judge(fake, max_fails=2).refusal, ve.REPEATED_FAIL)

    def test_a_legacy_fail_counts_on_its_recorded_origin(self) -> None:
        old = artifact(named(EARLIER, "fail"), 5)
        self.legacy(
            [old | {"workflow_run": {"id": 5}, "origin": True, "head_ref": "feat/x"}]
        )
        # Its origin is the file's, read with no call.
        idle = IndexGitHub([], {})
        with mock.patch.object(postmerge, "gh_capture", side_effect=idle):
            reader = self.reader()
            self.assertTrue(reader.index_mode())
            self.assertEqual(reader._run_state(5, shared=True), ve.ORIGIN)
        self.assertEqual(idle.calls, [])
        # Its creation time is still read fresh, against the pass's.
        fake = self.passing(runs={5: run(5, created_at="2026-10-16T00:00:00Z")})
        self.assertEqual(self.judge(fake).refusal, ve.EARLIER_FAIL)

    def test_an_expired_legacy_fail_no_longer_counts(self) -> None:
        old = artifact(named(EARLIER, "fail"), 5) | {
            "expires_at": "2026-10-15T00:00:00Z"
        }
        self.legacy(
            [old | {"workflow_run": {"id": 5}, "origin": True, "head_ref": "feat/x"}]
        )
        self.assertIsNone(self.judge(self.passing()).refusal)

    def test_an_index_whose_run_still_uploads_refuses(self) -> None:
        fake = self.passing(index(f"pr-{PR}", 3, 1), runs={3: run(3)})
        fake.still_running.add(3)
        self.assertEqual(self.judge(fake).refusal, ve.UNREADABLE)
        # Once that run completes with no FAIL, its upload failed: none counts.
        fake.still_running.clear()
        self.assertIsNone(self.judge(fake).refusal)

    def test_a_name_read_that_fails_or_misses_its_count_refuses(self) -> None:
        fake = self.passing()
        fake.fail.add(f"name={ve.INDEX_PREFIX}sha-{HEAD}")
        self.assertEqual(self.judge(fake).refusal, ve.UNREADABLE)
        fake = self.passing()
        fake.name_total[f"{ve.INDEX_PREFIX}pr-{PR}"] = 1
        self.assertEqual(self.judge(fake).refusal, ve.UNREADABLE)

    def test_more_names_than_a_listing_costs_read_the_listing(self) -> None:
        fake = self.passing(
            *fail(PR, EARLIER, 3), runs={3: run(3, created_at="2026-10-16T00:00:00Z")}
        )
        fake.commits = [f"{n:040x}" for n in range(1, ve.INDEX_NAMES_CAP + 1)] + [HEAD]
        self.assertEqual(self.judge(fake).refusal, ve.EARLIER_FAIL)
        self.assertGreater(fake.whole(), 0)

    def test_too_many_index_runs_refuse(self) -> None:
        many = [index(f"pr-{PR}", 100 + n, 1) for n in range(ve.INDEX_RUNS_CAP + 1)]
        self.assertEqual(self.judge(self.passing(*many)).refusal, ve.UNREADABLE)

    def test_own_verdicts_reads_the_pull_request_and_head_names(self) -> None:
        fake = self.passing(
            *fail(PR, EARLIER, 3), *fail(90, UNRELATED, 4), runs={3: run(3), 4: run(4)}
        )
        with (
            mock.patch.object(postmerge, "gh_capture", side_effect=fake),
            mock.patch.object(ve.merge_policy, "gh_capture", side_effect=fake),
        ):
            names = {a["name"] for a in self.reader().own_verdicts(PR, HEAD)}
        self.assertEqual(names, {named(HEAD, "pass"), named(EARLIER, "fail")})
        self.assertEqual(fake.whole(), 0)


class LegacyFailsBuild(unittest.TestCase):
    CUTOVER = datetime(2026, 10, 15, tzinfo=UTC)

    def build(self, fake: IndexGitHub) -> dict[str, Any]:
        with (
            mock.patch.object(postmerge, "gh_capture", side_effect=fake),
            mock.patch.object(ve.merge_policy, "gh_capture", side_effect=fake),
        ):
            reader = ve.Reader(
                REPO,
                "main",
                now=NOW,
                legacy_path=None,
                listing_path=None,
                carry_path=None,
            )
            return ve.build_legacy_fails_from_listing(reader, self.CUTOVER, NOW)

    def fake(self) -> IndexGitHub:
        fake = IndexGitHub(
            [
                artifact(named(EARLIER, "fail"), 5),  # before the index
                *fail(PR, UNRELATED, 3),  # indexed: found by its names
                artifact(named(HEAD, "fail", 90), 6),  # another workflow's
                artifact(named(HEAD, "pass"), 1),
            ],
            {
                1: run(1),
                3: run(3),
                5: run(5),
                6: run(6, path=".github/workflows/other.yml"),
            },
            {named(EARLIER, "fail"): record(sha=EARLIER, verdict="fail")},
        )
        return fake

    def test_it_holds_each_unindexed_fail_of_verifier_origin_with_its_branch(
        self,
    ) -> None:
        built = self.build(self.fake())
        self.assertEqual(
            [
                (a["name"], a["workflow_run"], a["origin"], a["head_ref"])
                for a in built["artifacts"]
            ],
            [(named(EARLIER, "fail"), {"id": 5}, True, "feat/x")],
        )
        self.assertEqual(built["repo"], REPO)
        # What it writes, the reader takes.
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp, "legacy.json")
            path.write_text(json.dumps(built))
            self.assertTrue(ve.Reader(REPO, "main", legacy_path=str(path)).index_mode())

    def test_a_verifier_run_from_before_the_cutover_still_running_refuses(self) -> None:
        fake = self.fake()
        fake.running = [
            run(
                9,
                status="in_progress",
                conclusion=None,
                created_at="2026-10-14T23:00:00Z",
            )
        ]
        with self.assertRaisesRegex(ve._Unreadable, "before the cutover"):
            self.build(fake)
        fake.running = [
            run(
                9,
                status="in_progress",
                conclusion=None,
                created_at="2026-10-15T01:00:00Z",
            )
        ]
        self.build(fake)

    def test_an_unreadable_branch_refuses(self) -> None:
        fake = self.fake()
        fake.records.clear()
        with self.assertRaises(ve._Unreadable):
            self.build(fake)


class RunsGitHub:
    """GitHub as the per-run build reads it: the verifier's runs by
    `created` window, each run's artifacts, the rate limit, a compare of a
    run head against main, and a verdict archive by artifact id."""

    def __init__(self) -> None:
        self.runs = [
            run(5, created_at="2026-10-14T03:00:00Z"),  # FAIL before the index
            run(3, created_at="2026-10-15T01:00:00Z"),  # FAIL with its index
            run(1, created_at="2026-10-15T02:00:00Z"),  # a pass
            run(
                6, created_at="2026-10-15T03:00:00Z", path=".github/workflows/other.yml"
            ),
        ]
        self.artifacts = {
            5: [artifact(named(EARLIER, "fail"), 5)],
            3: fail(PR, UNRELATED, 3),
            1: [artifact(named(HEAD, "pass"), 1)],
            6: [artifact(named(HEAD, "fail", 90), 6)],
        }
        self.records = {named(EARLIER, "fail"): record(sha=EARLIER, verdict="fail")}
        self.window_total: int | None = None
        self.run_total: dict[int, int] = {}
        self.remaining = 4000
        self.limit_from: int | None = None  # the call that answers rate limited
        self.calls: list[str] = []

    def __call__(self, args: list[str], **kwargs: Any) -> subprocess.CompletedProcess:
        path = next(a for a in args if a.startswith("repos/") or a == "rate_limit")
        self.calls.append(path)

        def ok(payload: Any) -> subprocess.CompletedProcess:
            return subprocess.CompletedProcess(args, 0, json.dumps(payload), "")

        if self.limit_from is not None and len(self.calls) >= self.limit_from:
            return subprocess.CompletedProcess(
                args, 1, "", "gh: API rate limit exceeded (HTTP 403)"
            )
        if path == "rate_limit":
            reset = 4_000_000_000
            return ok(
                {"resources": {"core": {"remaining": self.remaining, "reset": reset}}}
            )
        window = re.fullmatch(
            rf"repos/{REPO}/actions/workflows/pr-verify\.yml/runs\?created=(\S+)\.\.(\S+)"
            r"&per_page=100&page=1",
            path,
        )
        if window:
            listed = [r for r in self.runs if window[1] <= r["created_at"] <= window[2]]
            total = len(listed) if self.window_total is None else self.window_total
            return ok({"total_count": total, "workflow_runs": listed})
        of_run = re.fullmatch(
            rf"repos/{REPO}/actions/runs/([0-9]+)/artifacts\?per_page=100", path
        )
        if of_run:
            held = self.artifacts.get(int(of_run[1]), [])
            total = self.run_total.get(int(of_run[1]), len(held))
            return ok({"total_count": total, "artifacts": held})
        if path.startswith(f"repos/{REPO}/compare/"):
            return ok({"status": "ahead"})
        zips = re.fullmatch(rf"repos/{REPO}/actions/artifacts/([0-9]+)/zip", path)
        if zips:
            name = next(
                a["name"]
                for held in self.artifacts.values()
                for a in held
                if a["id"] == int(zips[1])
            )
            return subprocess.CompletedProcess(
                args, 0, base.zipped(self.records[name]), ""
            )
        raise AssertionError(f"unexpected gh call: {args}")


class PerRunLegacyFails(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.out = pathlib.Path(self.tmp.name, "legacy.json")
        self.checkpoint = pathlib.Path(self.tmp.name, "checkpoint.json")

    def run_build(self, fake: RunsGitHub, *extra: str) -> tuple[int, str]:
        stderr = io.StringIO()
        with (
            mock.patch.object(postmerge, "gh_capture", side_effect=fake),
            contextlib.redirect_stderr(stderr),
        ):
            code = ve.main(
                [
                    "legacy-fails",
                    "--repo",
                    REPO,
                    "--since",
                    "2026-10-14T00:00:00Z",
                    "--cutover",
                    "2026-10-16T00:00:00Z",
                    "--out",
                    str(self.out),
                    "--checkpoint",
                    str(self.checkpoint),
                    "--calls-per-second",
                    "0",
                    *extra,
                ],
                now=NOW,
            )
        return code, stderr.getvalue()

    def test_it_holds_each_unindexed_fail_of_a_verifier_run(self) -> None:
        fake = RunsGitHub()
        code, err = self.run_build(fake)
        self.assertEqual(code, 0, err)
        built = json.loads(self.out.read_text())
        self.assertEqual(
            [(a["name"], a["head_ref"], a["origin"]) for a in built["artifacts"]],
            [(named(EARLIER, "fail"), "feat/x", True)],
        )
        self.assertEqual(built["runs"], 4)
        # One rate-limit read, two day windows, four runs, one compare, one download.
        self.assertEqual(len(fake.calls), 9)
        self.assertIn("calls=9 total=9", err)
        self.assertTrue(ve.Reader(REPO, "main", legacy_path=str(self.out)).index_mode())

    def test_a_window_that_misses_its_count_refuses_and_writes_nothing(self) -> None:
        fake = RunsGitHub()
        fake.window_total = 9
        code, err = self.run_build(fake)
        self.assertEqual(code, 1, err)
        self.assertIn("list 1 of [9]", err)
        self.assertFalse(self.out.exists())

    def test_a_run_whose_artifacts_miss_their_count_refuses(self) -> None:
        fake = RunsGitHub()
        fake.run_total[5] = 2
        code, err = self.run_build(fake)
        self.assertEqual(code, 1, err)
        self.assertIn("artifacts of run 5 do not hold their count", err)
        self.assertFalse(self.out.exists())

    def test_a_run_not_completed_refuses(self) -> None:
        fake = RunsGitHub()
        fake.runs[2] = run(1, created_at="2026-10-15T02:00:00Z", status="in_progress")
        code, err = self.run_build(fake)
        self.assertEqual(code, 1, err)
        self.assertIn("verifier run 1 is in_progress", err)

    def test_a_rate_limit_stops_and_the_checkpoint_resumes(self) -> None:
        fake = RunsGitHub()
        # Calls: rate limit, window 1, run 5, its compare and download, then
        # window 2, which answers rate limited.
        fake.limit_from = 6
        code, err = self.run_build(fake)
        self.assertEqual(code, 3, err)
        self.assertIn("stopped, resume from", err)
        self.assertFalse(self.out.exists())
        saved = json.loads(self.checkpoint.read_text())
        self.assertEqual(len(saved["windows"]), 1)
        self.assertEqual(sorted(saved["runs"]), ["5"])
        # Resumed: nothing read before is read again.
        resumed = RunsGitHub()
        code, err = self.run_build(resumed)
        self.assertEqual(code, 0, err)
        self.assertNotIn(
            f"repos/{REPO}/actions/runs/5/artifacts?per_page=100", resumed.calls
        )
        self.assertEqual(len(json.loads(self.out.read_text())["artifacts"]), 1)

    def test_a_rate_limit_inside_a_verdict_download_still_stops(self) -> None:
        # The download's reader wraps every error; the stop is kept anyway.
        fake = RunsGitHub()
        fake.limit_from = 5
        code, err = self.run_build(fake)
        self.assertEqual(code, 3, err)
        self.assertEqual(json.loads(self.checkpoint.read_text())["runs"], {})

    def test_calls_are_paced(self) -> None:
        with mock.patch.object(ve, "_listing_sleep") as slept:
            stderr = io.StringIO()
            with (
                mock.patch.object(postmerge, "gh_capture", side_effect=RunsGitHub()),
                contextlib.redirect_stderr(stderr),
            ):
                ve.main(
                    [
                        "legacy-fails",
                        "--repo",
                        REPO,
                        "--since",
                        "2026-10-14T00:00:00Z",
                        "--cutover",
                        "2026-10-16T00:00:00Z",
                        "--out",
                        str(self.out),
                        "--checkpoint",
                        str(self.checkpoint),
                    ],
                    now=NOW,
                )
        # The default 0.5 calls a second: about 2 s before each call after the first.
        self.assertEqual(slept.call_count, 8)
        self.assertTrue(all(1.9 < c.args[0] <= 2.0 for c in slept.call_args_list))

    def test_the_window_cap_stops(self) -> None:
        code, err = self.run_build(RunsGitHub(), "--window-cap", "4")
        self.assertEqual(code, 3, err)
        self.assertIn("4 calls in the window", err)

    def test_the_breaker_or_low_remaining_stops_before_any_read(self) -> None:
        breaker = pathlib.Path(self.tmp.name, "breaker.txt")
        breaker.write_text("tripped")
        fake = RunsGitHub()
        code, err = self.run_build(fake, "--breaker-file", str(breaker))
        self.assertEqual((code, fake.calls), (3, []), err)
        fake = RunsGitHub()
        fake.remaining = 1999
        code, err = self.run_build(fake)
        self.assertEqual((code, fake.calls), (3, ["rate_limit"]), err)
        self.assertIn("core remaining 1999 is under 2000", err)

    def test_a_checkpoint_for_another_range_refuses(self) -> None:
        self.checkpoint.write_text(
            json.dumps({"version": 1, "repo": REPO, "since": "x"})
        )
        code, err = self.run_build(RunsGitHub())
        self.assertEqual(code, 1, err)
        self.assertIn("another repository, range or cutover", err)


def setUpModule() -> None:
    base.setUpModule()


def tearDownModule() -> None:
    base.tearDownModule()


if __name__ == "__main__":
    unittest.main()
