#!/usr/bin/env python3
"""Unit tests for ``lib/policy_cascade.py``."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

LIB_DIR = Path(__file__).resolve().parent
if str(LIB_DIR) not in sys.path:
    sys.path.insert(0, str(LIB_DIR))

import policy_cascade  # noqa: E402


class PolicyCascadeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()

    def test_baseline_snapshot_is_cached_and_immutable(self) -> None:
        policy_cascade.load_baseline_snapshot.cache_clear()
        first = policy_cascade.load_baseline_snapshot()
        second = policy_cascade.load_baseline_snapshot()
        self.assertIs(first, second)
        self.assertIsInstance(first.protected_exact_names, frozenset)
        self.assertIsInstance(first.protected_exact_names_casefolded, frozenset)
        self.assertIsInstance(first.protected_name_globs, tuple)
        self.assertIsInstance(first.disk_image_name_globs, tuple)
        info = policy_cascade.load_baseline_snapshot.cache_info()
        self.assertEqual(1, info.misses)
        self.assertGreaterEqual(info.hits, 1)

        p1 = policy_cascade.baseline_policy()
        p1["protected_exact_names"].append("MUTATED")
        p1["hints"].clear()
        p2 = policy_cascade.baseline_policy()
        self.assertNotIn("MUTATED", p2["protected_exact_names"])
        self.assertGreater(len(p2["hints"]), 0)

    def test_baseline_protected_names_does_not_reread_disk_after_first_load(self) -> None:
        policy_cascade.load_baseline_snapshot.cache_clear()
        _ = policy_cascade.baseline_protected_names()
        with mock.patch.object(
            policy_cascade, "load_json", side_effect=AssertionError("re-read disk")
        ):
            names = policy_cascade.baseline_protected_names()
            globs = policy_cascade.baseline_protected_name_globs()
            disk_globs = policy_cascade.baseline_disk_image_name_globs()
            snap_names = policy_cascade.snapshot_protected_exact_names(
                {"policy": {"protected_exact_names": ["CustomVault"]}}
            )
        self.assertIn("Documents", names)
        self.assertTrue(len(globs) > 0)
        self.assertTrue(len(disk_globs) > 0)
        self.assertIn("Documents", snap_names)
        self.assertIn("CustomVault", snap_names)

    def test_standing_cascade_and_repo_elevation_floor(self) -> None:
        home = self.base / "home"
        project = self.base / "project"
        (home / ".config" / "disk-hygiene").mkdir(parents=True)
        (project / "docs" / "conventions").mkdir(parents=True)
        user_file = home / ".config" / "disk-hygiene" / "policy.json"
        team_file = project / "docs" / "conventions" / "disk-hygiene.yaml"

        user_file.write_text(
            json.dumps({"version": 2, "elevation": "uac-prompt"}), encoding="utf-8"
        )
        team_file.write_text(
            'version: 2\nadditional_protected_path_globs:\n  - "keep/**"\n',
            encoding="utf-8",
        )
        with mock.patch.object(Path, "home", return_value=home):
            policy = policy_cascade.load_policy(None, project, str(user_file))
        self.assertEqual("uac-prompt", policy["elevation"])
        self.assertIn("keep/**", policy["additional_protected_path_globs"])
        self.assertEqual([], policy["policy_warnings"])

        team_file.write_text("version: 2\nelevation: uac-prompt\n", encoding="utf-8")
        with mock.patch.object(Path, "home", return_value=home):
            with self.assertRaises(policy_cascade.PolicyError):
                policy_cascade.load_policy(None, project, None)

    def test_team_layer_extends_inventory_bounded_stores_and_bad_entries_fail(
        self,
    ) -> None:
        project = self.base / "project"
        (project / "docs" / "conventions").mkdir(parents=True)
        team_file = project / "docs" / "conventions" / "disk-hygiene.yaml"
        team_file.write_text(
            "version: 1\nadditional_inventory_bounded_stores:\n"
            '  - glob: "vendor/blobs"\n    reason: "artifact mirror"\n',
            encoding="utf-8",
        )
        with mock.patch.object(Path, "home", return_value=self.base / "home"):
            policy = policy_cascade.load_policy(None, project, None)
        globs = [
            policy_cascade.protection_glob_pattern(e)
            for e in policy["inventory_bounded_stores"]
        ]
        self.assertIn(".npm", globs)
        self.assertEqual("vendor/blobs", globs[-1])
        team_file.write_text(
            "version: 1\nadditional_inventory_bounded_stores:\n  - glob: x\n    size: 1\n",
            encoding="utf-8",
        )
        with mock.patch.object(Path, "home", return_value=self.base / "home"):
            with self.assertRaisesRegex(
                policy_cascade.PolicyError, "inventory bounded store objects"
            ):
                policy_cascade.load_policy(None, project, None)

    def test_retired_claude_policy_files_are_not_read_and_warn(self) -> None:
        home = self.base / "home"
        project = self.base / "project"
        (home / ".claude").mkdir(parents=True)
        (project / ".claude").mkdir(parents=True)
        old_user = home / ".claude" / "disk-hygiene.json"
        old_project = project / ".claude" / "disk-hygiene.json"
        old_user.write_text(
            json.dumps({"version": 1, "additional_protected_path_globs": ["old-u/**"]}),
            encoding="utf-8",
        )
        old_project.write_text(
            json.dumps({"version": 1, "additional_protected_path_globs": ["old-p/**"]}),
            encoding="utf-8",
        )
        with mock.patch.object(Path, "home", return_value=home):
            policy = policy_cascade.load_policy(None, project, None)
        self.assertEqual(["baseline"], policy["policy_sources"])
        self.assertEqual([], policy["additional_protected_path_globs"])
        self.assertEqual(2, len(policy["policy_warnings"]))
        joined = "\n".join(policy["policy_warnings"])
        self.assertIn(str(old_user), joined)
        self.assertIn(str(old_project), joined)
        self.assertIn("is not read", joined)


if __name__ == "__main__":
    unittest.main()
