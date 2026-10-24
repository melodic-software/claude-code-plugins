"""A report-only run reads the pending merge records and never writes them.

`merge.report-only` makes an unattended `--merge` run a check that writes
nothing, so a merged queue entry it reads must stay recorded for the live run
that dispatches the post-merge full run. A live run still clears it. The state
directory is a real temporary one; the GitHub reads are the harness fakes of
`test_babysit_merge_unattended`.
"""

from __future__ import annotations

import dataclasses
import json
import pathlib
import sys
import tempfile
import unittest
from typing import Any
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_merge as merge
import babysit_merge_policy as policy
import test_babysit_merge as fixtures
import test_babysit_merge_unattended as harness

HEAD = harness.HEAD
PR = harness.PR
KEY = f"owner/repo#{PR}"
QUEUED = {
    "queued": True,
    "head": HEAD,
    "mergeAction": "merge_queue",
    "requestedAt": "2026-10-12T10:00:00Z",
}

_role_label = fixtures.role_label_stub()


def setUpModule() -> None:
    _role_label.start()


def tearDownModule() -> None:
    _role_label.stop()


def _seed(state: str, entry: dict[str, Any]) -> pathlib.Path:
    path = pathlib.Path(state) / merge.PENDING_MERGES_FILE
    path.write_text(
        json.dumps({"schema_version": 1, "requests": {KEY: entry}}), encoding="utf-8"
    )
    return path


class MergedQueueEntryUnderTheLane(harness.Unattended):
    """`--authority pr-merge` reading back a queue entry that has merged."""

    def setUp(self) -> None:
        super().setUp()
        self.config = policy.PipelineConfig(
            harness.BASE, "C2", "pr-merge", harness.IDENTITY, 200, (".github/**",),
            "c2-mechanical", require_verifier_verdict=True,
        )  # fmt: skip
        passing = merge.verify_evidence.Evidence(
            refusal=None, head=HEAD, verdicts=(), ignored=0
        )
        for patcher in (
            mock.patch.object(
                merge.verify_evidence.Reader, "evidence", return_value=passing
            ),
            mock.patch.object(
                merge,
                "pull_request_landed",
                return_value={"merged": True, "head": HEAD},
            ),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)
        self.opt_in_recheck = "not-lane-authored-or-opted-in"
        self.kill = []
        self.flight = policy.InFlight(False, f"unverified-auto-merge:#{PR}")
        self.pr_view = fixtures._pr(state="MERGED")
        self.queue = {**fixtures._queue_read(required=True), "merged": True}

    def lane(self, state: str) -> tuple[int, dict[str, Any]]:
        return self.run_main(
            "--authority", "pr-merge", "--lane-kill-switch", "proceed",
            "--lane-rung-cap", "", "--state-dir", state,
        )  # fmt: skip

    def test_report_only_leaves_the_state_file_byte_for_byte(self) -> None:
        self.config = dataclasses.replace(self.config, report_only=True)
        with tempfile.TemporaryDirectory() as state:
            path = _seed(state, QUEUED)
            before = path.read_bytes()
            _, out = self.lane(state)
            after = path.read_bytes()
        self.assertIs(out["unattended"]["reportOnly"], True)
        self.assertEqual(out["pendingMergeRequest"]["status"], "merged")
        self.assertEqual(after, before)
        self.dispatch.assert_not_called()

    def test_a_live_run_clears_the_record_and_dispatches(self) -> None:
        with tempfile.TemporaryDirectory() as state:
            path = _seed(state, QUEUED)
            _, out = self.lane(state)
            requests = json.loads(path.read_text(encoding="utf-8"))["requests"]
        self.assertIs(out["merged"], True)
        self.assertNotIn(KEY, requests)
        self.dispatch.assert_called_once_with("owner/repo", ref="main")


class EveryRecordWriteIsGated(unittest.TestCase):
    """Each record `check_pending_request` would rewrite, read with write off."""

    def check(self, entry: dict[str, Any], *, write: bool) -> tuple[bytes, bytes]:
        with tempfile.TemporaryDirectory() as state:
            path = _seed(state, entry)
            before = path.read_bytes()
            merge.check_pending_request("owner/repo", PR, path, write=write)
            return before, path.read_bytes()

    def test_an_unconfirmed_entry_still_unseen(self) -> None:
        unconfirmed = {**QUEUED, "unconfirmed": True, "unseenReads": 0}
        with mock.patch.object(
            merge, "read_merge_queue", return_value=fixtures._queue_read()
        ):
            before, after = self.check(unconfirmed, write=False)
            self.assertEqual(after, before)
            _, live = self.check(unconfirmed, write=True)
        self.assertEqual(json.loads(live)["requests"][KEY]["unseenReads"], 1)

    def test_an_unconfirmed_entry_now_queued(self) -> None:
        unconfirmed = {**QUEUED, "unconfirmed": True, "unseenReads": 0}
        with mock.patch.object(
            merge, "read_merge_queue", return_value=fixtures._queue_read(in_queue=True)
        ):
            before, after = self.check(unconfirmed, write=False)
            self.assertEqual(after, before)
            _, live = self.check(unconfirmed, write=True)
        self.assertNotIn("unconfirmed", json.loads(live)["requests"][KEY])

    def test_a_dequeued_entry(self) -> None:
        with mock.patch.object(
            merge, "read_merge_queue", return_value=fixtures._queue_read()
        ):
            before, after = self.check(QUEUED, write=False)
            self.assertEqual(after, before)
            _, live = self.check(QUEUED, write=True)
        self.assertEqual(json.loads(live)["requests"], {})

    def test_a_failed_async_request(self) -> None:
        request = {"uuid": "req-1", "head": HEAD, "mergeAction": "merge"}
        failed = {"status": "failed", "message": "", "expired": False}
        with mock.patch.object(merge, "read_async_merge", return_value=failed):
            before, after = self.check(request, write=False)
            self.assertEqual(after, before)
            _, live = self.check(request, write=True)
        self.assertEqual(json.loads(live)["requests"], {})


if __name__ == "__main__":
    unittest.main()
