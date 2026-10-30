"""A run listing past GitHub's search cap, read in `created` sub-ranges
(`babysit_postmerge._runs`).

Expected values come from the list-workflow-runs page cited at
babysit_gh.RUN_SEARCH_CAP: a filtered listing returns at most 1,000 runs, and
`created` takes a `>=` bound or an inclusive `A..B` range. Network is stubbed
at the `gh_capture` seam; no real gh process runs.
"""

from __future__ import annotations

import pathlib
import sys
import unittest
from datetime import UTC, datetime, timedelta
from typing import Any
from unittest import mock
from urllib.parse import unquote

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import babysit_postmerge as pm
from test_babysit_postmerge import REPO, canary_run, completed

CANARY = "post-merge-detect-silent-revert.yml"
SINCE = datetime(2026, 10, 21, 15, 40, 33, tzinfo=UTC)
STAMP = "%Y-%m-%dT%H:%M:%SZ"


def _parse(value: str) -> datetime:
    return datetime.strptime(value, STAMP).replace(tzinfo=UTC)


class CreatedFilteringGh:
    """Serves one workflow's run listing filtered by its `created` qualifier,
    at most 1,000 runs a search, with `total_count` the runs that matched."""

    def __init__(self, runs: list[dict[str, Any]]) -> None:
        self.runs = runs
        self.ranges: list[str] = []

    def __call__(self, args: list[str], **_: Any) -> Any:
        endpoint = next(a for a in args if a.startswith("repos/"))
        created = unquote(endpoint.split("created=")[1].split("&")[0])
        self.ranges.append(created)
        if created.startswith(">="):
            low, high = _parse(created[2:]), None
        else:
            start, end = created.split("..")
            low, high = _parse(start), _parse(end)
        matched = [
            r
            for r in self.runs
            if _parse(r["created_at"]) >= low
            and (high is None or _parse(r["created_at"]) <= high)
        ]
        page = {"total_count": len(matched), "workflow_runs": matched[:1000]}
        return completed([page])


def canary_runs(count: int, start: datetime, span: timedelta) -> list[dict[str, Any]]:
    """`count` canary push runs on main, evenly spread over `span`."""
    step = span / count
    return [
        canary_run(
            1000 + i,
            created_at=(start + step * i).strftime(STAMP),
            head_branch="main",
        )
        for i in range(count)
    ]


class RunWindowTest(unittest.TestCase):
    def runs(self, gh: CreatedFilteringGh, now: datetime) -> list[pm.Run]:
        owner, name = REPO.split("/")
        with mock.patch.object(pm, "gh_capture", gh):
            return pm._runs(owner, name, CANARY, "push", "main", SINCE, now=now)

    def test_a_listing_past_the_cap_is_read_whole_in_sub_ranges(self) -> None:
        # 1,183 canary runs over 8 days: the whole window answers 1,000 of
        # 1,183, so it is split until each range is under the cap.
        now = SINCE + timedelta(days=8)
        gh = CreatedFilteringGh(canary_runs(1183, SINCE, timedelta(days=7, hours=20)))
        runs = self.runs(gh, now)
        self.assertEqual(len(runs), 1183)
        self.assertEqual({r.id for r in runs}, {1000 + i for i in range(1183)})
        self.assertGreater(len(gh.ranges), 1)
        # The newest range stays open-ended, so a run created during the
        # read is not lost.
        self.assertTrue(gh.ranges[-1].startswith(">="), gh.ranges)

    def test_a_listing_under_the_cap_is_read_once(self) -> None:
        now = SINCE + timedelta(days=8)
        gh = CreatedFilteringGh(canary_runs(999, SINCE, timedelta(days=7)))
        self.assertEqual(len(self.runs(gh, now)), 999)
        self.assertEqual(len(gh.ranges), 1)

    def test_a_day_still_past_the_cap_fails_closed(self) -> None:
        # 1,200 runs in a two-hour burst: the range holding it reaches a day
        # still at the cap, and no shorter split is tried.
        now = SINCE + timedelta(days=3)
        gh = CreatedFilteringGh(
            canary_runs(1200, SINCE + timedelta(days=1), timedelta(hours=2))
        )
        with self.assertRaises(pm.PostMergeReadError) as raised:
            self.runs(gh, now)
        self.assertIn("search cap", str(raised.exception))


if __name__ == "__main__":
    unittest.main()
