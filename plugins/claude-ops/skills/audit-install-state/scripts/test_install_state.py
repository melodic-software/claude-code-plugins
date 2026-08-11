#!/usr/bin/env python3
"""Contract tests for the install-state engine.

Every test builds its own synthetic tree. Nothing here reads the author's real
`~/.claude`, so the suite is portable and its results do not depend on which
machine it runs on.
"""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import install_state as engine  # noqa: E402


def build_tree(root: Path) -> None:
    """A miniature `~/.claude` carrying one instance of each trap."""
    (root / "sessions").mkdir(parents=True)
    (root / "sessions" / "5052.json").write_text("{}", encoding="utf-8")

    (root / "ide").mkdir()
    # Body deliberately carries an authToken so a test can prove it is not read.
    (root / "ide" / "22580.lock").write_text(
        '{"pid": 32324, "authToken": "SHOULD-NEVER-BE-READ"}', encoding="utf-8"
    )

    (root / "rate-limit-guard").mkdir()
    (root / "rate-limit-guard" / "stop-events.jsonl.tmp.2541395").write_text("x", encoding="utf-8")

    (root / "shell-snapshots").mkdir()
    (root / "shell-snapshots" / "snapshot-bash-1786398511670-a1b2c3.sh").write_text(
        "#", encoding="utf-8"
    )

    (root / "paste-cache").mkdir()
    (root / "paste-cache" / "deadbeefdeadbeef").write_text("p", encoding="utf-8")

    (root / "session-env" / "0be285ac-e025-47df-bac9-ee6a03806c3d").mkdir(parents=True)
    (root / "session-env" / "0be285ac-e025-47df-bac9-ee6a03806c3d" / "env.json").write_text(
        "{}", encoding="utf-8"
    )

    (root / "projects" / "D--repo").mkdir(parents=True)
    (root / "projects" / "D--repo" / "e2a52749-8ff6-4355-bd13-cbef81921701.jsonl").write_text(
        "{}", encoding="utf-8"
    )

    (root / "settings.json").write_text(json.dumps({"cleanupPeriodDays": 14}), encoding="utf-8")
    (root / ".credentials.json").write_text("SECRET", encoding="utf-8")
    (root / "history.jsonl").write_text("{}", encoding="utf-8")

    (root / "some-plugin-state").mkdir()
    (root / "some-plugin-state" / "notes.jsonl").write_text("{}", encoding="utf-8")


class TestNameSchemes(unittest.TestCase):
    """A number in a filename is not reliably a PID."""

    def test_known_schemes_resolve_to_their_real_meanings(self) -> None:
        cases = {
            "sessions/5052.json": engine.PID,
            "ide/22580.lock": engine.TCP_PORT,
            "rate-limit-guard/stop-events.jsonl.tmp.2541395": engine.MSYS_SHELL_PID,
            "shell-snapshots/snapshot-bash-1786398511670-a1b2c3.sh": engine.EPOCH_MS,
            "backups/.claude.json.backup.1786398511670": engine.EPOCH_MS,
            "paste-cache/deadbeefdeadbeef": engine.CONTENT_HASH,
            "session-env/0be285ac-e025-47df-bac9-ee6a03806c3d/env.json": engine.SESSION_UUID,
            "projects/D--repo/e2a52749-8ff6-4355-bd13-cbef81921701.jsonl": engine.SESSION_UUID,
        }
        for rel, expected in cases.items():
            with self.subTest(rel=rel):
                self.assertEqual(engine.classify_name(rel)[0], expected)

    def test_unrecognised_numeric_name_is_unknown_not_a_guess(self) -> None:
        meaning, _ = engine.classify_name("third-party-plugin/state.99999")
        self.assertEqual(meaning, engine.UNKNOWN_MEANING)

    def test_name_without_digits_is_none(self) -> None:
        self.assertEqual(engine.classify_name("hooks/guard.py")[0], engine.NO_NUMBER)


class TestLivenessGate(unittest.TestCase):
    """The probe must never run against a number that is not a PID.

    This is the check the whole engine exists to get right: a process lookup
    against a TCP port or a shell `$$` returns a meaningless miss that reads as
    "dead" and authorises a wrong deletion.
    """

    def setUp(self) -> None:
        self.calls: list[int] = []

    def spy(self, pid: int) -> tuple[str, str]:
        self.calls.append(pid)
        return engine.DEAD, "spy says dead"

    def test_probe_is_never_called_for_a_non_pid_name(self) -> None:
        non_pids = [
            "ide/22580.lock",
            "rate-limit-guard/stop-events.jsonl.tmp.2541395",
            "shell-snapshots/snapshot-bash-1786398511670-a1b2c3.sh",
            "paste-cache/deadbeefdeadbeef",
            "third-party-plugin/state.99999",
        ]
        for rel in non_pids:
            verdict = engine.verdict_for(rel, probe=self.spy)
            with self.subTest(rel=rel):
                self.assertEqual(verdict.liveness, engine.NOT_APPLICABLE)
        self.assertEqual(self.calls, [], "the liveness probe ran against a non-PID number")

    def test_probe_is_called_only_for_a_genuine_pid_name(self) -> None:
        verdict = engine.verdict_for("sessions/5052.json", probe=self.spy)
        self.assertEqual(self.calls, [5052])
        self.assertEqual(verdict.number_meaning, engine.PID)
        self.assertEqual(verdict.liveness, engine.DEAD)

    def test_an_unusable_probe_yields_unverified_never_dead(self) -> None:
        def broken(_pid: int) -> tuple[str, str]:
            return engine.UNVERIFIED, "no probe available"

        verdict = engine.verdict_for("sessions/5052.json", probe=broken)
        self.assertEqual(verdict.liveness, engine.UNVERIFIED)
        self.assertNotEqual(verdict.liveness, engine.DEAD)

    def test_probe_rejects_a_nonsensical_pid_without_claiming_death(self) -> None:
        self.assertEqual(engine.probe_pid(0)[0], engine.UNVERIFIED)
        self.assertEqual(engine.probe_pid(-1)[0], engine.UNVERIFIED)


class TestSecretHandling(unittest.TestCase):
    def test_never_read_list_covers_the_documented_secrets(self) -> None:
        for rel in (".credentials.json", "daemon/control.key", "daemon/pipe.key", "ide/22580.lock"):
            with self.subTest(rel=rel):
                self.assertTrue(engine.is_never_read(rel))

    def test_reader_refuses_a_secret_even_when_asked_directly(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            build_tree(root)
            for rel in (".credentials.json", "ide/22580.lock"):
                with self.subTest(rel=rel):
                    with self.assertRaises(engine.SecretReadRefused):
                        engine.read_text_guarded(root, rel)

    def test_reader_refuses_anything_outside_the_content_allowlist(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            build_tree(root)
            with self.assertRaises(engine.SecretReadRefused):
                engine.read_text_guarded(root, "history.jsonl")
            self.assertEqual(engine.read_text_guarded(root, "settings.json").strip()[0], "{")


class TestDenyListCaseSensitivity(unittest.TestCase):
    """Three deny paths differing only by case are three paths, not one.

    Recorded because the single operation a prior audit labelled mechanically
    provable was wrong for exactly this reason: a case-insensitive comparer
    collapsed three distinct deny rules into one and dropped two protections.
    """

    def test_case_distinct_deny_roots_all_survive(self) -> None:
        records = [
            {"deny_root": "plugins/data/Experiment"},
            {"deny_root": "plugins/data/experiment"},
            {"deny_root": "plugins/data/EXPERIMENT"},
        ]
        self.assertEqual(len(engine.deny_roots(records)), 3)

    def test_exact_duplicates_still_collapse(self) -> None:
        records = [{"deny_root": "plugins/data/x"}, {"deny_root": "plugins/data/x"}]
        self.assertEqual(engine.deny_roots(records), ["plugins/data/x"])

    def test_deny_matching_is_prefix_bounded_at_a_path_segment(self) -> None:
        denied = ["plugins/data/exp"]
        self.assertTrue(engine.under_deny("plugins/data/exp", denied))
        self.assertTrue(engine.under_deny("plugins/data/exp/RESTORE.md", denied))
        self.assertFalse(engine.under_deny("plugins/data/experiment2/x", denied))

    def test_surface_classification_is_case_sensitive(self) -> None:
        self.assertEqual(engine.classify_entry("projects/x")[0], engine.SWEPT)
        self.assertEqual(engine.classify_entry("Projects/x")[0], engine.UNCLASSIFIED)


class TestDeliberateState(unittest.TestCase):
    def test_a_restore_ledger_deny_lists_its_subtree(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            build_tree(root)
            exp = root / "plugins" / "data" / "an-experiment"
            exp.mkdir(parents=True)
            (exp / "RESTORE.md").write_text("all keys set false", encoding="utf-8")
            (exp / "settings.json.baseline").write_text("{}", encoding="utf-8")

            report = engine.scan(root, samples=1, interval=0, authored_threshold=1000, recent_hours=24)
            self.assertTrue(report["deliberate_state"], "the revert ledger was not found")
            self.assertIn("plugins/data/an-experiment", report["deny_roots"])
            plugins_entry = next(e for e in report["entries"] if e["entry"] == "plugins")
            self.assertTrue(plugins_entry["deny_listed"])
            self.assertEqual(plugins_entry["reading"]["verdict"], "deny-listed")

    def test_hotspot_is_swept_even_though_the_full_tree_is_too(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "plugins" / "data" / "e").mkdir(parents=True)
            (root / "plugins" / "data" / "e" / "manifest.json").write_text("{}", encoding="utf-8")
            found = engine.find_deliberate_state(root)
            self.assertEqual(len(found), 1)
            self.assertTrue(found[0]["found_via"].startswith("hotspot:"))


class TestRetention(unittest.TestCase):
    def test_user_setting_wins_over_the_documented_default(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            build_tree(root)
            retention = engine.read_retention(root)
            self.assertEqual(retention["effective_days"], 14)
            self.assertEqual(retention["effective_evidence"], engine.MEASURED)

    def test_absent_setting_reports_the_default_as_a_documented_default(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "settings.json").write_text("{}", encoding="utf-8")
            retention = engine.read_retention(root)
            self.assertEqual(retention["effective_days"], 30)
            self.assertEqual(retention["effective_evidence"], engine.DOCUMENTED_DEFAULT)

    def test_unparsable_settings_raises_the_sweep_paused_finding(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "settings.json").write_text("{ not json", encoding="utf-8")
            retention = engine.read_retention(root)
            ids = [f["id"] for f in retention["findings"]]
            self.assertIn("settings-unparsable-pauses-sweep", ids)


class TestReadings(unittest.TestCase):
    def test_a_swept_path_inside_the_window_is_product_managed_healthy(self) -> None:
        entry = {
            "entry": "plans",
            "surface": engine.SWEPT,
            "older_than_retention": 0,
            "deny_listed": False,
        }
        self.assertEqual(
            engine.staleness_reading(entry, 30)["verdict"], "product-managed-healthy"
        )

    def test_an_mtime_overage_is_reported_as_an_inference_not_a_measurement(self) -> None:
        entry = {"entry": "file-history", "surface": engine.SWEPT, "older_than_retention": 4, "deny_listed": False}
        reading = engine.staleness_reading(entry, 30)
        self.assertEqual(reading["verdict"], "age-exceeds-window")
        self.assertEqual(reading["evidence"], engine.INFERRED)
        self.assertIn("4 file(s)", reading["measured"])
        self.assertIn("checkpoint", reading["why"])

    def test_an_unclassified_path_is_never_called_disposable(self) -> None:
        entry = {"entry": "some-plugin", "surface": engine.UNCLASSIFIED, "older_than_retention": 99, "deny_listed": False}
        reading = engine.staleness_reading(entry, 30)
        self.assertEqual(reading["verdict"], "unclassified-report-only")
        self.assertEqual(reading["evidence"], "no-upstream-row")

    def test_session_scoped_state_is_keep_not_stale(self) -> None:
        entry = {"entry": "sessions", "surface": engine.SESSION_SCOPED, "older_than_retention": 7, "deny_listed": False}
        self.assertEqual(engine.staleness_reading(entry, 30)["verdict"], "keep")


class TestSampledCounts(unittest.TestCase):
    """A time-varying quantity is reported as a range with its sample count."""

    def test_a_count_is_never_emitted_as_a_bare_scalar(self) -> None:
        sampled = engine.Sampled([7, 9, 8])
        out = sampled.as_dict(volatile=True)
        self.assertEqual({out["min"], out["max"]}, {7, 9})
        self.assertEqual(out["n"], 3)
        self.assertNotIn("mean", out)
        self.assertNotIn("value", out)

    def test_unanimous_small_n_on_a_volatile_path_is_flagged_not_confirmed(self) -> None:
        out = engine.Sampled([5, 5]).as_dict(volatile=True)
        self.assertEqual(out["flag"], "unanimous_small_n_on_volatile_path")

    def test_a_stable_path_is_not_flagged(self) -> None:
        self.assertNotIn("flag", engine.Sampled([5, 5]).as_dict(volatile=False))

    def test_three_samples_clear_the_flag(self) -> None:
        self.assertNotIn("flag", engine.Sampled([5, 5, 5]).as_dict(volatile=True))


class TestScanShape(unittest.TestCase):
    def test_every_entry_carries_a_surface_a_reading_and_a_sampled_count(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            build_tree(root)
            report = engine.scan(root, samples=1, interval=0, authored_threshold=1000, recent_hours=24)
            self.assertTrue(report["entries"])
            for entry in report["entries"]:
                with self.subTest(entry=entry["entry"]):
                    self.assertIn("surface", entry)
                    self.assertIn("evidence", entry["reading"])
                    self.assertIn("n", entry["file_count_sampled"])

    def test_unlisted_plugin_state_lands_in_the_unclassified_bucket(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            build_tree(root)
            report = engine.scan(root, samples=1, interval=0, authored_threshold=1000, recent_hours=24)
            entry = next(e for e in report["entries"] if e["entry"] == "some-plugin-state")
            self.assertEqual(entry["surface"], engine.UNCLASSIFIED)
            self.assertEqual(entry["reading"]["verdict"], "unclassified-report-only")

    def test_the_run_excludes_its_own_output_from_its_scan_set(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            build_tree(root)
            (root / "plugins" / "data" / "claude-ops").mkdir(parents=True)
            out = root / "plugins" / "data" / "claude-ops" / "listing.csv"
            out.write_text("placeholder", encoding="utf-8")
            exclude = engine.self_excluded(root, [str(out)])
            self.assertIn("plugins/data/claude-ops/listing.csv", exclude)
            report = engine.scan(
                root,
                samples=1,
                interval=0,
                authored_threshold=1000,
                recent_hours=24,
                exclude=exclude,
            )
            listed = {m["relpath"] for e in report["entries"] for m in e.get("members", [])}
            self.assertNotIn("plugins/data/claude-ops/listing.csv", listed)

    def test_the_report_never_claims_a_quiesced_tree(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            build_tree(root)
            report = engine.scan(root, samples=1, interval=0, authored_threshold=1000, recent_hours=24)
            self.assertFalse(report["quiesced"])


class TestRootResolution(unittest.TestCase):
    def test_explicit_root_wins(self) -> None:
        self.assertEqual(engine.resolve_root("/tmp/x"), Path("/tmp/x"))


if __name__ == "__main__":
    unittest.main()
