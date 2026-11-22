#!/usr/bin/env python3
# test-scope: plugins/disk-hygiene/*
"""Behavioral tests for the old-policy migration the setup skill runs."""

from __future__ import annotations

import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import policy_migration  # noqa: E402  (path set above)

hygiene = policy_migration.hygiene

HINT = {
    "id": "team-hint",
    "os": ["all"],
    "kind": "name_glob",
    "pattern": "*.team",
    "confidence_ceiling": "medium",
    "reason": 'a "quoted" reason',
}
TEAM_POLICY = {
    "version": 2,
    "disabled_hint_ids": [],
    "additional_hints": [HINT],
    "additional_protected_path_globs": ["keep/**", {"glob": "x/*", "reason": "r"}],
    "rules": [
        {"match": {"hint_id": "team-hint"}, "preselect": True, "min_age_days": 3},
        {"match": {"hint_ids": ["team-hint"]}, "preselect": False},
    ],
}


class PolicyMigrationTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        self.home = root / "home"
        self.project = root / "project"
        (self.home / ".claude").mkdir(parents=True)
        (self.project / ".claude").mkdir(parents=True)
        self.old_user = self.home / ".claude" / "disk-hygiene.json"
        self.old_team = self.project / ".claude" / "disk-hygiene.json"
        self.new_user = root / "policy.json"
        self.new_team = self.project / "docs" / "conventions" / "disk-hygiene.yaml"
        self.old_user.write_text(
            json.dumps({"version": 2, "elevation": "uac-prompt"}), encoding="utf-8"
        )
        self.old_team.write_text(json.dumps(TEAM_POLICY), encoding="utf-8")
        patcher = mock.patch.object(hygiene.Path, "home", return_value=self.home)
        patcher.start()
        self.addCleanup(patcher.stop)

    def run_step(self, *argv: str) -> tuple[int, dict]:
        out = io.StringIO()
        with redirect_stdout(out):
            code = policy_migration.main(
                [*argv, "--project-dir", str(self.project)]
            )
        return code, json.loads(out.getvalue())

    def test_check_names_each_old_file_and_writes_nothing(self) -> None:
        code, report = self.run_step("check", "--user-target", str(self.new_user))
        self.assertEqual(0, code)
        self.assertEqual(
            [
                ("userConfig", str(self.old_user), str(self.new_user), True),
                ("team", str(self.old_team), str(self.new_team), False),
            ],
            [
                (row["layer"], row["old"], row["new"], row["set_option"])
                for row in report["files"]
            ],
        )
        self.assertFalse(self.new_user.exists())
        self.assertFalse(self.new_team.exists())

    def test_move_and_finish_end_in_one_home(self) -> None:
        self.assertEqual(2, self.run_step("move")[0])
        code, _ = self.run_step("move", "--yes", "--user-target", str(self.new_user))
        self.assertEqual(0, code)
        self.assertEqual(TEAM_POLICY, hygiene.yaml_subset.load(str(self.new_team)))
        self.assertTrue(self.old_user.is_file())
        code, report = self.run_step(
            "finish", "--yes", "--user-target", str(self.new_user)
        )
        self.assertEqual(1, code)
        self.assertTrue(self.old_user.is_file())
        self.assertFalse(self.old_team.exists())
        self.assertIn("--user-policy", report["files"][0]["result"])
        code, _ = self.run_step("finish", "--yes", "--user-policy", str(self.new_user))
        self.assertEqual(0, code)
        self.assertFalse(self.old_user.exists())
        policy = hygiene.load_policy(None, self.project, str(self.new_user))
        self.assertEqual("uac-prompt", policy["elevation"])
        self.assertEqual([], policy["policy_warnings"])

    def test_an_option_naming_the_old_file_is_never_deleted(self) -> None:
        code, report = self.run_step(
            "finish", "--yes", "--user-policy", str(self.old_user)
        )
        self.assertEqual(1, code)
        self.assertEqual(["team"], [row["layer"] for row in report["files"]])
        self.assertTrue(self.old_user.is_file())

    def test_move_never_overwrites_and_finish_keeps_a_differing_old_file(
        self,
    ) -> None:
        self.new_team.parent.mkdir(parents=True)
        self.new_team.write_text("version: 1\n", encoding="utf-8")
        code, report = self.run_step("move", "--yes")
        self.assertEqual(1, code)
        team = [row for row in report["files"] if row["layer"] == "team"][0]
        self.assertIn("new file exists", team["result"])
        self.assertEqual("version: 1\n", self.new_team.read_text(encoding="utf-8"))
        self.run_step("finish", "--yes")
        self.assertTrue(self.old_team.is_file())


if __name__ == "__main__":
    unittest.main()
