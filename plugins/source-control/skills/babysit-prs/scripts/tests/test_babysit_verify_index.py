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

import base64
import contextlib
import io
import json
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest
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
    IN_PR,
    NOW,
    PR,
    REPO,
    UNRELATED,
    WORKFLOW,
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
        # Answers to a run's artifact reads in turn, before its artifacts.
        self.run_reads: dict[int, list[list[dict[str, Any]]]] = {}
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
            if of_run and self.run_reads.get(int(of_run[1])):
                held = self.run_reads[int(of_run[1])].pop(0)
                return ok({"total_count": len(held), "artifacts": held})
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
        # Nor is it a finding of the pull request's own FAILs.
        fake = self.passing()
        with (
            mock.patch.object(postmerge, "gh_capture", side_effect=fake),
            mock.patch.object(ve.merge_policy, "gh_capture", side_effect=fake),
        ):
            self.assertEqual(self.reader().fail_findings(PR), [])

    def test_an_index_whose_run_still_uploads_refuses(self) -> None:
        fake = self.passing(index(f"pr-{PR}", 3, 1), runs={3: run(3)})
        fake.still_running.add(3)
        self.assertEqual(self.judge(fake).refusal, ve.UNREADABLE)
        # Once that run completes with no FAIL, its upload failed: none counts.
        fake.still_running.clear()
        self.assertIsNone(self.judge(fake).refusal)

    def test_a_fail_uploaded_while_its_run_completes_still_counts(self) -> None:
        # The first read of run 3 holds only its index; by the time the run is
        # seen completed its FAIL has uploaded.
        items = fail(90, HEAD, 3)
        fake = self.passing(*items, runs={3: run(3)})
        fake.run_reads[3] = [items[1:]]
        self.assertEqual(self.judge(fake).refusal, ve.FAIL)

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


MERGE_SHA = "9" * 40
MERGED_AT = "2026-10-15T20:00:00Z"  # its cutover, with the margin: 21:00
SINCE = "2026-10-14T00:00:00Z"  # the build's `--since`


def uploaded(items: list[dict[str, Any]], at: str) -> list[dict[str, Any]]:
    """`items`, each uploaded at `at`."""
    return [{**item, "created_at": at} for item in items]


class RunsGitHub:
    """GitHub as the per-run build reads it: the merge commit and its
    pr-verify.yml, the verifier's runs by `created` window and by id, each
    run's artifacts, one whole artifact listing, the rate limit, a compare of
    a commit against main, and a verdict archive by artifact id."""

    def __init__(self) -> None:
        self.runs = [
            run(5, created_at="2026-10-14T03:00:00Z"),  # FAIL before the index
            run(3, created_at="2026-10-15T01:00:00Z"),  # FAIL with its index
            run(1, created_at="2026-10-15T02:00:00Z"),  # a pass
            run(
                6, created_at="2026-10-15T03:00:00Z", path=".github/workflows/other.yml"
            ),
        ]
        # Each uploaded within its run's hour.
        self.artifacts = {
            5: uploaded([artifact(named(EARLIER, "fail"), 5)], "2026-10-14T03:30:00Z"),
            3: uploaded(fail(PR, UNRELATED, 3), "2026-10-15T01:30:00Z"),
            1: uploaded([artifact(named(HEAD, "pass"), 1)], "2026-10-15T02:30:00Z"),
            6: uploaded([artifact(named(HEAD, "fail", 90), 6)], "2026-10-15T03:30:00Z"),
        }
        # Runs outside every window, read only by id.
        self.other_runs: dict[int, dict[str, Any]] = {}
        # Listed artifacts no run's own read holds.
        self.listed_only: list[dict[str, Any]] = []
        self.records = {named(EARLIER, "fail"): record(sha=EARLIER, verdict="fail")}
        self.workflow = 'env:\n  FAIL_INDEX: "1"\n'
        # A window's stated count, by its start, where it is not its runs'.
        self.window_total: dict[str, int] = {}
        self.run_total: dict[int, int] = {}
        self.remaining = 4000
        self.limit_from: int | None = None  # the call that answers rate limited
        self.limit_text = "gh: API rate limit exceeded (HTTP 403)"
        self.calls: list[str] = []
        # Verifier runs not completed, by the workflow's status filter.
        self.running: list[dict[str, Any]] = []

    def __call__(self, args: list[str], **kwargs: Any) -> subprocess.CompletedProcess:
        path = next(a for a in args if a.startswith("repos/") or a == "rate_limit")
        self.calls.append(path)

        def ok(payload: Any) -> subprocess.CompletedProcess:
            return subprocess.CompletedProcess(args, 0, json.dumps(payload), "")

        if self.limit_from is not None and len(self.calls) >= self.limit_from:
            return subprocess.CompletedProcess(args, 1, "", self.limit_text)
        if path == "rate_limit":
            reset = 4_000_000_000
            return ok(
                {"resources": {"core": {"remaining": self.remaining, "reset": reset}}}
            )
        if path == f"repos/{REPO}/commits/{MERGE_SHA}":
            return ok({"sha": MERGE_SHA, "commit": {"committer": {"date": MERGED_AT}}})
        if path == f"repos/{REPO}/contents/{WORKFLOW}?ref={MERGE_SHA}":
            content = base64.b64encode(self.workflow.encode()).decode()
            return ok({"content": content, "encoding": "base64"})
        status = re.fullmatch(
            rf"repos/{REPO}/actions/workflows/pr-verify\.yml/runs\?status=([a-z_]+)&per_page=100",
            path,
        )
        if status:
            listed = [r for r in self.running if r["status"] == status[1]]
            return ok({"total_count": len(listed), "workflow_runs": listed})
        window = re.fullmatch(
            rf"repos/{REPO}/actions/workflows/pr-verify\.yml/runs\?created=(\S+)\.\.(\S+)"
            r"&per_page=100&page=([0-9]+)",
            path,
        )
        if window:
            listed = [r for r in self.runs if window[1] <= r["created_at"] <= window[2]]
            total = self.window_total.get(window[1], len(listed))
            first = (int(window[3]) - 1) * 100
            return ok({"total_count": total, "workflow_runs": listed[first : first + 100]})
        of_run = re.fullmatch(
            rf"repos/{REPO}/actions/runs/([0-9]+)/artifacts\?per_page=100", path
        )
        if of_run:
            held = self.artifacts.get(int(of_run[1]), [])
            total = self.run_total.get(int(of_run[1]), len(held))
            return ok({"total_count": total, "artifacts": held})
        by_id = re.fullmatch(rf"repos/{REPO}/actions/runs/([0-9]+)", path)
        if by_id:
            return ok(self.other_runs[int(by_id[1])])
        if path == f"repos/{REPO}/actions/artifacts?per_page=100&page=1":
            items = [a for held in self.artifacts.values() for a in held]
            items += self.listed_only
            return ok({"total_count": len(items), "artifacts": items})
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


# Calls of a whole build: rate limit, merge commit, its compare, its
# pr-verify.yml (4); the five running statuses (9); 31 lookback windows (40);
# window 1, run 5, its compare and download (44); window 2, runs 3, 1 and 6
# (48); the running statuses (53), the listing page (54), and the running
# statuses again (59).
BUILD_CALLS = 59


class PerRunLegacyFails(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.out = pathlib.Path(self.tmp.name, "legacy.json")
        self.checkpoint = pathlib.Path(self.tmp.name, "checkpoint.json")

    def run_build(
        self, fake: RunsGitHub, *extra: str, pace: bool = False
    ) -> tuple[int, str]:
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
                    SINCE,
                    "--merge-sha",
                    MERGE_SHA,
                    "--cutover",
                    "2026-10-16T00:00:00Z",
                    "--out",
                    str(self.out),
                    "--checkpoint",
                    str(self.checkpoint),
                    *([] if pace else ["--calls-per-second", "0"]),
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
        self.assertEqual((built["runs"], built["addedFromListing"]), (4, []))
        self.assertEqual(len(fake.calls), BUILD_CALLS)
        self.assertIn(f"calls={BUILD_CALLS} total={BUILD_CALLS}", err)
        self.assertTrue(ve.Reader(REPO, "main", legacy_path=str(self.out)).index_mode())

    def test_the_last_window_reads_the_cutovers_own_second(self) -> None:
        fake = RunsGitHub()
        self.run_build(fake)
        self.assertIn(
            f"repos/{REPO}/actions/workflows/pr-verify.yml/runs"
            "?created=2026-10-15T00:00:00Z..2026-10-16T00:00:00Z&per_page=100&page=1",
            fake.calls,
        )

    def test_a_fail_of_a_run_from_before_since_is_added_through_the_listing(
        self,
    ) -> None:
        # A re-run keeps its creation time, so no window holds run 8; its
        # FAIL uploaded after `--since`, so the listing adds it.
        fake = RunsGitHub()
        fake.other_runs[8] = run(8, created_at="2026-10-13T23:00:00Z")
        fake.artifacts[8] = uploaded(
            [artifact(named(IN_PR, "fail"), 8)], "2026-10-14T01:00:00Z"
        )
        fake.records[named(IN_PR, "fail")] = record(sha=IN_PR, verdict="fail")
        code, err = self.run_build(fake)
        self.assertEqual(code, 0, err)
        built = json.loads(self.out.read_text())
        self.assertEqual(built["addedFromListing"], [8])
        self.assertEqual(
            sorted(a["name"] for a in built["artifacts"]),
            sorted([named(EARLIER, "fail"), named(IN_PR, "fail")]),
        )

    def test_a_listed_fail_uploaded_before_since_refuses_naming_the_earliest(
        self,
    ) -> None:
        # Runs 8 and 9 sit outside every window and their FAILs predate
        # `--since`: `--since` is too late, so nothing is written.
        fake = RunsGitHub()
        for run_id, at in ((8, "2026-10-13T22:00:00Z"), (9, "2026-10-13T20:00:00Z")):
            fake.other_runs[run_id] = run(run_id, created_at="2026-10-13T19:00:00Z")
            fake.artifacts[run_id] = uploaded(
                [artifact(named(IN_PR, "fail", 40 + run_id), run_id)], at
            )
        code, err = self.run_build(fake)
        self.assertEqual(code, 1, err)
        self.assertIn(
            "2 listed FAIL(s) uploaded before --since 2026-10-14T00:00:00Z, the "
            "earliest artifact 90 of run 9 at 2026-10-13T20:00:00Z: lower --since "
            "to at most 2026-10-13T20:00:00Z, remove the checkpoint file and run "
            "again",
            err,
        )
        self.assertFalse(self.out.exists())
        # Nothing outside the windows was read for them.
        self.assertNotIn(f"repos/{REPO}/actions/runs/9", fake.calls)

    def test_a_listed_fail_with_no_creation_time_refuses(self) -> None:
        fake = RunsGitHub()
        fake.artifacts[5] = uploaded(fake.artifacts[5], None)  # type: ignore[arg-type]
        code, err = self.run_build(fake)
        self.assertEqual(code, 1, err)
        self.assertIn("listed FAIL 50 of run 5 has no creation time", err)

    def test_a_checkpoint_listing_without_upload_times_is_listed_again(self) -> None:
        # A checkpoint from before the listing kept `created_at`.
        fake = RunsGitHub()
        self.assertEqual(self.run_build(fake)[0], 0)
        saved = json.loads(self.checkpoint.read_text())
        saved["listed"] = [
            {k: v for k, v in item.items() if k != "created_at"}
            for item in saved["listed"]
        ]
        self.checkpoint.write_text(json.dumps(saved))
        resumed = RunsGitHub()
        resumed.artifacts[5] = uploaded(resumed.artifacts[5], "2026-10-13T12:00:00Z")
        code, err = self.run_build(resumed)
        self.assertEqual(code, 1, err)
        self.assertIn("the earliest artifact 50 of run 5", err)
        self.assertIn(
            f"repos/{REPO}/actions/artifacts?per_page=100&page=1", resumed.calls
        )

    def test_a_run_created_before_since_and_updated_after_it_is_read(self) -> None:
        # Run 9 was re-run after `--since`; run 7 was not, so it is not read.
        fake = RunsGitHub()
        fake.runs += [
            run(
                9, created_at="2026-10-01T00:00:00Z", updated_at="2026-10-14T05:00:00Z"
            ),
            run(
                7, created_at="2026-10-02T00:00:00Z", updated_at="2026-10-02T01:00:00Z"
            ),
        ]
        fake.artifacts[9] = uploaded(
            [artifact(named(IN_PR, "fail"), 9)], "2026-10-14T05:00:00Z"
        )
        fake.records[named(IN_PR, "fail")] = record(sha=IN_PR, verdict="fail")
        code, err = self.run_build(fake)
        self.assertEqual(code, 0, err)
        built = json.loads(self.out.read_text())
        # Read through its window, not added by the listing.
        self.assertEqual(built["addedFromListing"], [])
        self.assertIn(named(IN_PR, "fail"), [a["name"] for a in built["artifacts"]])
        self.assertNotIn(
            f"repos/{REPO}/actions/runs/7/artifacts?per_page=100", fake.calls
        )

    def test_a_lookback_window_that_misses_its_count_refuses(self) -> None:
        fake = RunsGitHub()
        fake.window_total["2026-10-01T00:00:00Z"] = 1
        code, err = self.run_build(fake)
        self.assertEqual(code, 1, err)
        self.assertIn("list 0 of [1]", err)

    def test_a_verifier_run_from_before_the_cutover_still_running_refuses(self) -> None:
        fake = RunsGitHub()
        fake.running = [
            run(
                9,
                status="in_progress",
                conclusion=None,
                created_at="2026-10-15T23:00:00Z",
            )
        ]
        code, err = self.run_build(fake)
        self.assertEqual(code, 1, err)
        self.assertIn("verifier run 9 from before the cutover is in_progress", err)
        self.assertFalse(self.out.exists())
        # One created after the cutover is the index's, and holds nothing up.
        fake = RunsGitHub()
        fake.running = [
            run(9, status="queued", conclusion=None, created_at="2026-10-16T00:00:01Z")
        ]
        self.assertEqual(self.run_build(fake)[0], 0)

    def test_a_listed_fail_no_run_read_holds_refuses(self) -> None:
        fake = RunsGitHub()
        (ghost,) = uploaded([artifact(named(IN_PR, "fail"), 5)], "2026-10-14T04:00:00Z")
        ghost["id"] = 51
        fake.listed_only.append(ghost)
        code, err = self.run_build(fake)
        self.assertEqual(code, 1, err)
        self.assertIn("the listing holds FAILs no run read holds, in runs [5]", err)
        self.assertFalse(self.out.exists())

    def test_a_cutover_before_the_merge_commit_refuses(self) -> None:
        code, err = self.run_build(RunsGitHub(), "--cutover", "2026-10-15T20:30:00Z")
        self.assertEqual(code, 1, err)
        self.assertIn("when FAIL_INDEX reached main", err)
        self.assertFalse(self.out.exists())

    def test_a_merge_commit_without_fail_index_refuses(self) -> None:
        fake = RunsGitHub()
        fake.workflow = "env: {}\n"
        code, err = self.run_build(fake)
        self.assertEqual(code, 1, err)
        self.assertIn("sets no FAIL_INDEX", err)

    def test_a_window_that_misses_its_count_refuses_and_writes_nothing(self) -> None:
        fake = RunsGitHub()
        fake.window_total["2026-10-14T00:00:00Z"] = 9
        code, err = self.run_build(fake)
        self.assertEqual(code, 1, err)
        self.assertIn("list 1 of [9]", err)
        self.assertFalse(self.out.exists())

    def window_below_its_runs(self, size: int, total: int) -> None:
        """A window of `size` runs whose pages claim `total`: pages are read
        while full, never stopped at the claimed count, so the build refuses."""
        fake = RunsGitHub()
        fake.runs += [
            run(1000 + n, created_at=f"2026-10-14T04:{n // 60:02d}:{n % 60:02d}Z")
            for n in range(size - 1)
        ]
        fake.window_total["2026-10-14T00:00:00Z"] = total
        code, err = self.run_build(fake)
        self.assertEqual(code, 1, err)
        self.assertIn(f"list {size} of [{total}]", err)
        self.assertFalse(self.out.exists())

    def test_a_window_count_on_a_page_boundary_below_its_runs_refuses(self) -> None:
        self.window_below_its_runs(200, 100)

    def test_a_window_count_off_a_page_boundary_below_its_runs_refuses(self) -> None:
        self.window_below_its_runs(150, 120)

    def test_a_window_at_the_search_cap_splits_down_to_a_minute_then_refuses(
        self,
    ) -> None:
        # Each left half keeps the day's start, so it stays at the cap until
        # it spans a minute (`split_created_window`), and the build refuses.
        fake = RunsGitHub()
        fake.window_total["2026-10-14T00:00:00Z"] = 1000
        code, err = self.run_build(fake)
        self.assertEqual(code, 1, err)
        self.assertIn("1000 verifier runs created 2026-10-14T00:00:00Z..", err)
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
        fake.limit_from = 45  # window 2
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

    def test_a_run_unfinished_at_the_first_build_is_listed_again_on_resume(
        self,
    ) -> None:
        fake = RunsGitHub()
        fake.runs[2] = run(1, created_at="2026-10-15T02:00:00Z", status="in_progress")
        code, err = self.run_build(fake)
        self.assertEqual(code, 1, err)
        # Run 1 completed since: the resume reads its window afresh.
        code, err = self.run_build(RunsGitHub())
        self.assertEqual(code, 0, err)

    def test_a_resume_inside_the_same_reset_window_keeps_its_cap(self) -> None:
        code, err = self.run_build(RunsGitHub(), "--window-cap", "4")
        self.assertEqual(code, 3, err)
        resumed = RunsGitHub()
        code, err = self.run_build(resumed, "--window-cap", "4")
        self.assertEqual(code, 3, err)
        self.assertEqual(resumed.calls, ["rate_limit"])
        self.assertIn("calls in the window", err)

    def test_a_rate_limit_inside_a_verdict_download_still_stops(self) -> None:
        # The download's reader wraps every error; the stop is kept anyway.
        fake = RunsGitHub()
        fake.limit_from = 44  # run 5's download
        code, err = self.run_build(fake)
        self.assertEqual(code, 3, err)
        self.assertEqual(json.loads(self.checkpoint.read_text())["runs"], {})

    def test_a_permission_403_refuses_and_does_not_wait(self) -> None:
        fake = RunsGitHub()
        fake.limit_from = 42  # run 5's artifacts
        fake.limit_text = "gh: Resource not accessible by integration (HTTP 403)"
        code, err = self.run_build(fake)
        self.assertEqual(code, 1, err)
        self.assertIn("refused, nothing written", err)

    def test_calls_are_paced(self) -> None:
        with mock.patch.object(ve, "_listing_sleep") as slept:
            self.run_build(RunsGitHub(), pace=True)
        # The default 0.5 calls a second: about 2 s before each call after the first.
        self.assertEqual(slept.call_count, BUILD_CALLS - 1)
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
            json.dumps({"version": 2, "repo": REPO, "since": "x"})
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
