"""Lease library: repo-scoped keying, snapshot pairing, steal-stale, reap.

Ports the lease and reap coverage onto `babysit_lease`. Uses a real temp
state dir; time-dependent staleness is driven with explicit `updated_at`
timestamps rather than sleeping.
"""

from __future__ import annotations

import pathlib
import sys
import tempfile
import unittest
from datetime import UTC, datetime, timedelta

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_lease as lease


class ScopeKeyingTests(unittest.TestCase):
    def test_lock_name_per_scope_shape(self) -> None:
        self.assertEqual(lease.queue_lock_name(()), "queue-run-lock.json")
        self.assertEqual(
            lease.queue_lock_name(("owner/repo",)),
            "queue-run-lock__owner__repo.json",
        )
        multi = lease.queue_lock_name(("owner/a", "owner/b"))
        self.assertTrue(multi.startswith("queue-run-lock__scope-"))

    def test_disjoint_single_repo_scopes_never_contend(self) -> None:
        self.assertNotEqual(
            lease.queue_lock_name(("owner/a",)),
            lease.queue_lock_name(("owner/b",)),
        )

    def test_normalize_scope_repos_sorts_dedups_and_validates(self) -> None:
        self.assertEqual(
            lease.normalize_scope_repos("Owner/B,owner/a,owner/a"),
            ("owner/a", "owner/b"),
        )

    def test_lease_path_rejects_mismatched_scope_arguments(self) -> None:
        with tempfile.TemporaryDirectory() as state_dir:
            with self.assertRaises(ValueError):
                lease.lease_path(state_dir, "queue", "owner/repo#1")
            with self.assertRaises(ValueError):
                lease.lease_path(state_dir, "worker", None)
            with self.assertRaises(ValueError):
                lease.lease_path(state_dir, "worker", "owner/repo#1",
                                 repos=("owner/repo",))

    def test_worker_lease_path_is_owner_and_pr_scoped(self) -> None:
        with tempfile.TemporaryDirectory() as state_dir:
            path = lease.lease_path(state_dir, "worker", "Owner/Repo#5")
            self.assertEqual(path.name, "owner__repo__pr-5.json")
            self.assertEqual(path.parent.name, "active-workers")


class SnapshotScopePairingTests(unittest.TestCase):
    def test_absent_lease_is_fine_without_a_token(self) -> None:
        with tempfile.TemporaryDirectory() as state_dir:
            lease.validate_snapshot_scope(state_dir, ("owner/repo",))

    def test_absent_lease_with_token_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as state_dir, \
                self.assertRaises(RuntimeError):
            lease.validate_snapshot_scope(state_dir, ("owner/repo",), token="tok")

    def test_matching_scope_passes(self) -> None:
        with tempfile.TemporaryDirectory() as state_dir:
            path = lease.lease_path(state_dir, "queue", None, repos=("owner/repo",))
            lease.acquire(path, "queue", "tok", "run", 3600, repos=("owner/repo",))
            lease.validate_snapshot_scope(state_dir, ("owner/repo",), token="tok")

    def test_scope_mismatch_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as state_dir:
            path = lease.lease_path(state_dir, "queue", None, repos=("owner/repo",))
            record = lease.acquire(path, "queue", "tok", "run", 3600,
                                   repos=("owner/repo",))
            record_lease = lease.load_lease(path)
            assert record_lease is not None
            record_lease["repos"] = ["owner/other"]
            lease.write_lease(path, record_lease)
            self.assertEqual(record["scope"], "queue")
            with self.assertRaises(RuntimeError):
                lease.validate_snapshot_scope(state_dir, ("owner/repo",))


class AcquireReleaseTests(unittest.TestCase):
    def test_acquire_heartbeat_release_round_trip(self) -> None:
        with tempfile.TemporaryDirectory() as state_dir:
            path = lease.lease_path(state_dir, "queue", None)
            acquired = lease.acquire(path, "queue", None, "run", 3600)
            token = acquired["token"]
            beat = lease.heartbeat(path, token, "run", 3600)
            self.assertTrue(beat["refreshed"])
            released = lease.release(path, token)
            self.assertTrue(released["released"])
            self.assertFalse(path.exists())

    def test_second_holder_is_rejected_while_lease_is_live(self) -> None:
        with tempfile.TemporaryDirectory() as state_dir:
            path = lease.lease_path(state_dir, "queue", None)
            lease.acquire(path, "queue", "tok-a", "run-a", 3600)
            with self.assertRaises(lease.LeaseHeldError):
                lease.acquire(path, "queue", "tok-b", "run-b", 3600)

    def test_generated_token_never_starts_with_dash(self) -> None:
        for _ in range(20):
            self.assertNotEqual(lease.generate_lease_token()[0], "-")


class StealStaleTests(unittest.TestCase):
    def _write_dead_lease(self, path: pathlib.Path, *, interval: int,
                          idle_seconds: int) -> None:
        now = datetime.now(UTC)
        lease.write_lease(path, {
            "version": 1, "scope": "queue", "repos": [], "token": "dead-token",
            "run_id": "dead", "started_at": (now - timedelta(hours=2)).isoformat(),
            "updated_at": (now - timedelta(seconds=idle_seconds)).isoformat(),
            "expires_at": (now + timedelta(seconds=600)).isoformat(),
            "heartbeat_interval_seconds": interval,
        })

    def test_steal_reclaims_dead_holder_and_fences_it(self) -> None:
        with tempfile.TemporaryDirectory() as state_dir:
            path = lease.lease_path(state_dir, "queue", None)
            self._write_dead_lease(path, interval=300, idle_seconds=1200)
            reclaimed = lease.acquire(path, "queue", None, "new", 3600,
                                      steal_stale=True, stale_after_seconds=900)
            self.assertTrue(reclaimed["reclaimed_stale"])
            self.assertNotEqual(reclaimed["token"], "dead-token")

    def test_steal_respects_holder_recorded_cadence(self) -> None:
        with tempfile.TemporaryDirectory() as state_dir:
            path = lease.lease_path(state_dir, "queue", None)
            self._write_dead_lease(path, interval=900, idle_seconds=1200)
            with self.assertRaises(lease.LeaseHeldError):
                lease.acquire(path, "queue", None, "new", 3600, steal_stale=True,
                              stale_after_seconds=900, heartbeat_interval_seconds=900)

    def test_stale_needs_parsable_updated_at(self) -> None:
        now = datetime.now(UTC)
        self.assertFalse(
            lease.lease_is_stale({"heartbeat_interval_seconds": 300}, now, 900)
        )


class ReapTests(unittest.TestCase):
    def _write_worker_lease(self, state_dir: str, expires_delta: int) -> pathlib.Path:
        path = lease.lease_path(state_dir, "worker", "owner/repo#9")
        now = datetime.now(UTC)
        lease.write_lease(path, {
            "version": 1, "scope": "worker", "token": "t", "run_id": "r",
            "expires_at": (now + timedelta(seconds=expires_delta)).isoformat(),
        })
        return path

    def test_dry_run_reports_without_deleting(self) -> None:
        with tempfile.TemporaryDirectory() as state_dir:
            path = self._write_worker_lease(state_dir, -10)
            results = lease.reap(state_dir)
            self.assertFalse(results[0]["reaped"])
            self.assertTrue(path.exists())

    def test_apply_deletes_expired_lease(self) -> None:
        with tempfile.TemporaryDirectory() as state_dir:
            path = self._write_worker_lease(state_dir, -10)
            results = lease.reap(state_dir, apply=True)
            self.assertTrue(results[0]["reaped"])
            self.assertFalse(path.exists())

    def test_apply_keeps_unexpired_lease(self) -> None:
        with tempfile.TemporaryDirectory() as state_dir:
            path = self._write_worker_lease(state_dir, 600)
            results = lease.reap(state_dir, apply=True)
            self.assertFalse(results[0]["reaped"])
            self.assertTrue(path.exists())

    def test_missing_active_workers_directory_is_ignored(self) -> None:
        with tempfile.TemporaryDirectory() as state_dir:
            self.assertEqual(lease.reap(state_dir), [])

    def test_malformed_expiry_is_left_for_a_human(self) -> None:
        with tempfile.TemporaryDirectory() as state_dir:
            path = lease.lease_path(state_dir, "worker", "owner/repo#9")
            lease.write_lease(path, {"version": 1, "scope": "worker",
                                     "expires_at": "not-a-timestamp"})
            results = lease.reap(state_dir, apply=True)
            self.assertFalse(results[0]["reaped"])
            self.assertEqual(results[0]["reason"], "invalid expires_at")
            self.assertTrue(path.exists())


if __name__ == "__main__":
    unittest.main()
