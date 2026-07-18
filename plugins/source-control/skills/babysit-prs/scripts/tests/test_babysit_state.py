"""Durable queue-state storage.

Ports the state-persistence coverage onto `babysit_state`: the scope-aware
`save_state` (scoped-run clobber fix and non-livelock staleness guard), the
schema-version stamp/refusal, corrupt-JSON quarantine, persisted sweep
counters, the error quarantine, and the resolve helpers. Snapshot PR records
are produced by the real `classify_pr` so their shape matches
`persisted_pr_state` exactly.
"""

from __future__ import annotations

import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_delta as delta
import babysit_state as state

CONFIG = delta.ClassifyConfig(allowed_owners=frozenset({"owner"}))


def snapshot_pr(repo: str, number: int,
                comments: list[dict[str, object]] | None = None) -> dict[str, object]:
    pr = {
        "repo": repo, "number": number, "url": "u", "title": "t", "state": "OPEN",
        "author": {"login": "someone", "__typename": "User"},
        "headRefName": "f", "headRefOid": "a" * 40, "baseRefName": "main",
        "baseRefOid": "b" * 40, "headRepository": {"nameWithOwner": repo},
        "headRepositoryOwner": {"login": repo.split("/")[0]}, "isCrossRepository": False,
        "isDraft": False, "maintainerCanModify": True, "baseRepositoryArchived": False,
        "mergeStateStatus": "CLEAN", "mergeable": "MERGEABLE", "reviewDecision": "",
        "reviews": [], "latestReviews": [], "comments": comments or [],
        "statusCheckRollup": [], "updatedAt": "2026-07-09T00:00:00Z",
    }
    return delta.classify_pr(pr, None, None, "2026-07-10T00:00:00Z", config=CONFIG)


def make_snapshot(prs: list[dict[str, object]], *, mode: str = "queue",
                  errors: list[str] | None = None,
                  generated_at: str = "2026-07-10T00:00:00Z") -> dict[str, object]:
    return {"mode": mode, "generated_at": generated_at, "errors": errors or [],
            "prs": prs}


def save(path: pathlib.Path, snapshot: dict[str, object], **kw: object) -> None:
    state.save_state(path, snapshot, recommend_cadence=delta.recommend_cadence, **kw)


class ResolveStateDirTests(unittest.TestCase):
    def test_empty_or_missing_is_rejected(self) -> None:
        for value in (None, "", "   "):
            with self.subTest(value=value), self.assertRaises(ValueError):
                state.resolve_state_dir(value)

    def test_filesystem_root_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            state.resolve_state_dir("/")

    def test_ordinary_path_resolves(self) -> None:
        self.assertTrue(str(state.resolve_state_dir("./sub")).endswith("sub"))


class SchemaAndCorruptionTests(unittest.TestCase):
    def test_missing_file_cold_starts(self) -> None:
        with tempfile.TemporaryDirectory() as state_dir:
            path = state.state_path_for(state_dir)
            self.assertEqual(state.load_state(path),
                             {"schema_version": 1, "prs": {}})

    def test_foreign_schema_version_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as state_dir:
            path = state.state_path_for(state_dir)
            path.write_text('{"schema_version": 999, "prs": {}}', encoding="utf-8")
            with self.assertRaises(RuntimeError):
                state.load_state(path)

    def test_corrupt_json_is_quarantined_and_cold_starts(self) -> None:
        with tempfile.TemporaryDirectory() as state_dir:
            path = state.state_path_for(state_dir)
            path.write_text("{ not valid json", encoding="utf-8")
            result = state.load_state(path)
            self.assertEqual(result, {"schema_version": 1, "prs": {}})
            siblings = [p.name for p in path.parent.iterdir()
                        if p.name.endswith(".corrupt")]
            self.assertEqual(len(siblings), 1)

    def test_every_write_stamps_the_schema_version(self) -> None:
        with tempfile.TemporaryDirectory() as state_dir:
            path = state.state_path_for(state_dir)
            save(path, make_snapshot([snapshot_pr("owner/a", 1)]))
            self.assertEqual(state.load_state(path)["schema_version"], 1)


class ScopedClobberTests(unittest.TestCase):
    def test_scoped_complete_run_clears_only_in_scope_repo_keys(self) -> None:
        with tempfile.TemporaryDirectory() as state_dir:
            path = state.state_path_for(state_dir)
            save(path, make_snapshot([
                snapshot_pr("owner/a", 1), snapshot_pr("owner/a", 2),
                snapshot_pr("owner/b", 3)]))
            self.assertEqual(sorted(state.load_state(path)["prs"]),
                             ["owner/a#1", "owner/a#2", "owner/b#3"])

            save(path, make_snapshot([snapshot_pr("owner/a", 1)],
                                     generated_at="2026-07-10T01:00:00Z"),
                 scope_repos=["owner/a"])
            keys = sorted(state.load_state(path)["prs"])
            self.assertEqual(keys, ["owner/a#1", "owner/b#3"])

    def test_unscoped_complete_run_replaces_the_whole_map(self) -> None:
        with tempfile.TemporaryDirectory() as state_dir:
            path = state.state_path_for(state_dir)
            save(path, make_snapshot([snapshot_pr("owner/a", 1),
                                      snapshot_pr("owner/b", 2)]))
            save(path, make_snapshot([snapshot_pr("owner/a", 1)],
                                     generated_at="2026-07-10T01:00:00Z"))
            self.assertEqual(sorted(state.load_state(path)["prs"]), ["owner/a#1"])


class StalenessGuardTests(unittest.TestCase):
    def _seed(self, path: pathlib.Path, prs: dict[str, object],
              updated_at: str) -> None:
        state.write_state(path, {"schema_version": 1, "updated_at": updated_at,
                                 "prs": prs, "mutation_ledger": {}, "pr_errors": {}})

    def test_disjoint_scopes_do_not_livelock(self) -> None:
        with tempfile.TemporaryDirectory() as state_dir:
            path = state.state_path_for(state_dir)
            self._seed(path, {
                "owner/a#1": {"recorded_at": "2026-07-10T00:00:00Z"},
                "owner/b#2": {"recorded_at": "2026-07-10T02:00:00Z"},
            }, updated_at="2026-07-10T02:00:00Z")
            # Global updated_at (02:00) is newer than this scoped run's
            # generated_at (01:00); a non-scope-aware guard would raise here.
            save(path, make_snapshot([], generated_at="2026-07-10T01:00:00Z"),
                 scope_repos=["owner/a"])
            self.assertIn("owner/b#2", state.load_state(path)["prs"])

    def test_newer_in_scope_record_blocks_the_write(self) -> None:
        with tempfile.TemporaryDirectory() as state_dir:
            path = state.state_path_for(state_dir)
            self._seed(path, {"owner/a#1": {"recorded_at": "2026-07-10T05:00:00Z"}},
                       updated_at="2026-07-10T05:00:00Z")
            with self.assertRaises(RuntimeError):
                save(path, make_snapshot([], generated_at="2026-07-10T01:00:00Z"),
                     scope_repos=["owner/a"])


class SweepCounterTests(unittest.TestCase):
    def test_full_sweep_resets_counters_and_partial_runs_advance_them(self) -> None:
        with tempfile.TemporaryDirectory() as state_dir:
            path = state.state_path_for(state_dir)
            save(path, make_snapshot([snapshot_pr("owner/a", 1)]))
            full = state.load_state(path)
            self.assertEqual(full["cycles_since_full_sweep"], 0)
            self.assertEqual(full["last_full_sweep_generated_at"],
                             "2026-07-10T00:00:00Z")

            save(path, make_snapshot([], generated_at="2026-07-10T01:00:00Z"),
                 scope_repos=["owner/b"])
            partial = state.load_state(path)
            self.assertEqual(partial["cycles_since_full_sweep"], 1)
            self.assertEqual(partial["last_full_sweep_generated_at"],
                             "2026-07-10T00:00:00Z")


class ErrorQuarantineTests(unittest.TestCase):
    def test_streak_below_threshold_is_not_quarantined(self) -> None:
        records, quarantined = state.update_error_quarantine(
            {}, ["owner/a#1"], "2026-07-10T00:00:00Z")
        self.assertEqual(quarantined, set())
        self.assertEqual(records["owner/a#1"]["consecutive_errors"], 1)

    def test_threshold_streak_is_quarantined(self) -> None:
        errors = {}
        for cycle in range(state.ERROR_QUARANTINE_THRESHOLD):
            errors, quarantined = state.update_error_quarantine(
                errors, ["owner/a#1"], f"2026-07-10T0{cycle}:00:00Z")
        self.assertIn("owner/a#1", quarantined)
        self.assertIn("quarantined_until", errors["owner/a#1"])

    def test_clean_cycle_breaks_the_streak(self) -> None:
        errors, _ = state.update_error_quarantine(
            {}, ["owner/a#1"], "2026-07-10T00:00:00Z")
        errors, quarantined = state.update_error_quarantine(
            errors, [], "2026-07-10T01:00:00Z")
        self.assertEqual(errors, {})
        self.assertEqual(quarantined, set())


class ExpectedHeadShaTests(unittest.TestCase):
    def test_exact_and_prefix_resolve_to_stored(self) -> None:
        stored = "a" * 40
        self.assertEqual(state.resolve_expected_head_sha(stored, stored), stored)
        self.assertEqual(state.resolve_expected_head_sha(stored, "a" * 12), stored)

    def test_short_prefix_is_rejected(self) -> None:
        with self.assertRaises(RuntimeError):
            state.resolve_expected_head_sha("a" * 40, "a" * 8)

    def test_non_matching_pin_is_rejected(self) -> None:
        with self.assertRaises(RuntimeError):
            state.resolve_expected_head_sha("a" * 40, "b" * 40)


class MutationLedgerTests(unittest.TestCase):
    def test_merge_unions_histories_and_seen_human_ids(self) -> None:
        existing = {"review_request_history": {"h1": {"comment_id": "1"}},
                    "seen_human_feedback_ids": ["a"]}
        observed = {"review_request_history": {"h2": {"comment_id": "2"}},
                    "seen_human_feedback_ids": ["b"]}
        merged = state.merge_mutation_ledger_entry(existing, observed)
        self.assertEqual(set(merged["review_request_history"]), {"h1", "h2"})
        self.assertEqual(merged["seen_human_feedback_ids"], ["a", "b"])


class LedgerTombstoneTests(unittest.TestCase):
    def test_complete_queue_prunes_live_prs_but_keeps_ledger(self) -> None:
        with tempfile.TemporaryDirectory() as state_dir:
            path = state.state_path_for(state_dir)
            # A human comment gives the PR real mutation-ledger content, so the
            # tombstone survives when the complete queue run prunes the live PR.
            human = [{"id": 1, "author": {"login": "person", "__typename": "User"},
                      "body": "a passing note"}]
            save(path, make_snapshot([snapshot_pr("owner/a", 1, human)]))
            save(path, make_snapshot([], generated_at="2026-07-10T01:00:00Z"))
            loaded = state.load_state(path)
            self.assertEqual(loaded["prs"], {})
            self.assertIn("owner/a#1", loaded.get("mutation_ledger", {}))


if __name__ == "__main__":
    unittest.main()
