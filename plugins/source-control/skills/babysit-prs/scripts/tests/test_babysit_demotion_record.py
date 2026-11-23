# test-scope: .github/scripts/post-merge-demotion-alert/demotion-record.vectors.json
"""The post-merge record grammar (`babysit_merge_policy.parse_record_marker`)
and the alert's failing checks (`babysit_postmerge._Context.failing_checks`)
agree with .github/scripts/post-merge-demotion-alert's demotion-record.mjs and
red-main.mjs failingChecks.

Expected values come from that directory's demotion-record.vectors.json, the
cases demotion-record.test.mjs and red-main.test.mjs also run. Network is
stubbed at the `_paginated` and `gh_capture` seams.
"""

from __future__ import annotations

import json
import os
import pathlib
import subprocess
import sys
import unittest
from datetime import UTC, datetime
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_merge_policy as policy
import babysit_postmerge as pm

VECTORS = json.loads(
    (
        pathlib.Path(__file__).resolve().parents[6]
        / ".github/scripts/post-merge-demotion-alert/demotion-record.vectors.json"
    ).read_text(encoding="utf-8")
)


class RecordMarker(unittest.TestCase):
    def test_each_record_vector_formats_to_its_line_and_parses_back(self) -> None:
        self.assertTrue(VECTORS["markers"])
        for v in VECTORS["markers"]:
            with self.subTest(v["name"]):
                self.assertEqual(
                    policy.record_marker(v["kind"], v["sha"], v["signal"]), v["line"]
                )
                self.assertEqual(
                    policy.parse_record_marker(v["line"]),
                    (v["kind"], v["sha"], v["signal"]),
                )

    def test_each_non_record_vector_parses_to_none(self) -> None:
        self.assertTrue(VECTORS["not_markers"])
        for v in VECTORS["not_markers"]:
            with self.subTest(v["name"]):
                self.assertIsNone(policy.parse_record_marker(v["line"]))

    def test_the_babysitter_writes_demotion_records_the_prefix_finds(self) -> None:
        for v in VECTORS["markers"]:
            with self.subTest(v["name"]):
                written = pm.demotion_marker(v["sha"], v["signal"])
                self.assertEqual(
                    policy.parse_record_marker(written),
                    ("babysit-merge-demotion", v["sha"], v["signal"]),
                )
                self.assertTrue(written.startswith(policy.DEMOTION_MARKER))
                self.assertEqual(
                    policy.DEMOTION_MARKER in v["line"],
                    v["kind"] == "babysit-merge-demotion",
                )

    def test_a_red_main_record_is_a_scheduled_or_dispatched_demotion(self) -> None:
        for v in VECTORS["markers"]:
            with self.subTest(v["name"]):
                red_main = v["kind"] == "babysit-merge-demotion" and v["signal"] in (
                    "schedule",
                    "dispatch",
                )
                self.assertEqual(
                    policy.red_main_record(v["line"]), v["sha"] if red_main else None
                )
        for v in VECTORS["not_markers"]:
            with self.subTest(v["name"]):
                self.assertIsNone(policy.red_main_record(v["line"]))

    def test_a_liftable_record_is_a_canary_revert_or_read_back_of_either_kind(
        self,
    ) -> None:
        for v in VECTORS["markers"]:
            with self.subTest(v["name"]):
                liftable = v["signal"] in ("canary", "revert", "read-back")
                self.assertEqual(
                    policy.liftable_record(v["line"]),
                    (v["sha"], v["signal"]) if liftable else None,
                )
        for v in VECTORS["not_markers"]:
            with self.subTest(v["name"]):
                self.assertIsNone(policy.liftable_record(v["line"]))


def judge(case: dict[str, Any]) -> tuple[frozenset[str], frozenset[str]]:
    """The vector's checks, live and as a baseline (`_baseline`'s subtraction)."""

    def gh(args: list[str], **_: Any) -> subprocess.CompletedProcess[str]:
        job = args[1].split("/check-runs/")[1].split("/")[0]
        return subprocess.CompletedProcess(
            args, 0, json.dumps(case["annotations"].get(job, [])), ""
        )

    run = pm.Run(
        id=1,
        attempt=1,
        status="completed",
        conclusion="failure",
        head_sha="a" * 40,
        head_branch="main",
        created_at=datetime(2026, 1, 5, tzinfo=UTC),
        url="",
        actor="github-actions[bot]",
        triggering_actor="github-actions[bot]",
    )
    with (
        mock.patch.dict(os.environ, {pm.ATTEMPTS_ENV: ""}),
        mock.patch.object(pm, "_paginated", return_value=case["jobs"]),
        mock.patch.object(pm, "gh_capture", gh),
    ):
        ctx = pm._Context("example-org", "example-repo", "", branch="main")
        checks = ctx.failing_checks(run, 1)
    return checks, checks - ctx.unknown_checks[(1, 1)]


class FailingChecks(unittest.TestCase):
    def test_each_failing_checks_vector(self) -> None:
        self.assertTrue(VECTORS["failing_checks"])
        for case in VECTORS["failing_checks"]:
            with self.subTest(case["name"]):
                checks, baseline = judge(case)
                self.assertEqual(sorted(checks), case["expect"])
                self.assertEqual(
                    sorted(baseline), case.get("expect_baseline", case["expect"])
                )


if __name__ == "__main__":
    unittest.main()
