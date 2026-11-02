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

import json
import pathlib
import re
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
        # PR 60 closes nothing; its FAIL names issue 7, which PR 41 closes.
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
            return ve.build_legacy_fails(reader, self.CUTOVER, NOW)

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


def setUpModule() -> None:
    base.setUpModule()


def tearDownModule() -> None:
    base.tearDownModule()


if __name__ == "__main__":
    unittest.main()
