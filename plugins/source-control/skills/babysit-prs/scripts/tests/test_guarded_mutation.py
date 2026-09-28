"""Refusal paths through the shared guarded-mutation preamble.

The three CLIs used to carry this opening themselves. These rows call the
helper directly so a future edit cannot widen what a mutating run is allowed
to do without failing here. Existing CLI suites still assert the same
refusals at the entry points; nothing in those assertions changes.
"""

from __future__ import annotations

import argparse
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_state as state
import guarded_mutation
from babysit_lease import LeaseHeldError

HEAD = "a" * 40


def _args(
    *, apply: bool, token: str | None = None, pin: str = HEAD
) -> argparse.Namespace:
    return argparse.Namespace(
        pr="owner/repo#1",
        apply=apply,
        lease_token=token,
        expected_head_sha=pin,
    )


def _write_snapshot(state_dir: pathlib.Path, head: str = HEAD) -> pathlib.Path:
    path = state.state_path_for(state_dir)
    state.write_state(
        path,
        {
            "schema_version": state.STATE_SCHEMA_VERSION,
            "prs": {
                "owner/repo#1": {"head_sha": head},
            },
        },
    )
    return path


class GuardedMutationRefusalTest(unittest.TestCase):
    def test_missing_snapshot_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state_dir = pathlib.Path(tmp)
            with self.assertRaises(RuntimeError) as caught:
                guarded_mutation.begin_guarded_mutation(
                    _args(apply=False),
                    state_dir,
                    state.state_path_for(state_dir),
                )
        self.assertIn("missing snapshot state", str(caught.exception))

    def test_head_pin_mismatch_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state_dir = pathlib.Path(tmp)
            path = _write_snapshot(state_dir)
            with self.assertRaises(RuntimeError) as caught:
                guarded_mutation.begin_guarded_mutation(
                    _args(apply=False, pin="b" * 40),
                    state_dir,
                    path,
                )
        self.assertIn("does not match --expected-head-sha", str(caught.exception))

    def test_apply_without_a_lease_token_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state_dir = pathlib.Path(tmp)
            path = _write_snapshot(state_dir)
            with self.assertRaises(ValueError) as caught:
                guarded_mutation.begin_guarded_mutation(
                    _args(apply=True, token=None),
                    state_dir,
                    path,
                )
        self.assertIn("lease token is required", str(caught.exception))

    def test_apply_with_the_wrong_lease_token_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state_dir = pathlib.Path(tmp)
            path = _write_snapshot(state_dir)
            acquired = guarded_mutation.leases.acquire(
                guarded_mutation.leases.lease_path(state_dir, "worker", "owner/repo#1"),
                "worker",
                "owner-token",
                None,
                guarded_mutation.leases.DEFAULT_WORKER_TTL_SECONDS,
            )
            self.assertEqual(acquired["token"], "owner-token")
            with self.assertRaises(LeaseHeldError):
                guarded_mutation.begin_guarded_mutation(
                    _args(apply=True, token="other-token"),
                    state_dir,
                    path,
                )

    def test_dry_run_returns_the_live_snapshot_record(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state_dir = pathlib.Path(tmp)
            path = _write_snapshot(state_dir)
            opened = guarded_mutation.begin_guarded_mutation(
                _args(apply=False, pin="a" * 12),
                state_dir,
                path,
            )
        self.assertEqual(opened.head_sha, HEAD)
        self.assertIs(opened.pr_state, opened.state["prs"]["owner/repo#1"])


if __name__ == "__main__":
    unittest.main()
