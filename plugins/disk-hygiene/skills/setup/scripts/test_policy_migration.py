#!/usr/bin/env python3
# test-scope: plugins/disk-hygiene/*

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

    def run_step(self, *argv: str, project: Path | None = None) -> tuple[int, dict]:
        out = io.StringIO()
        with redirect_stdout(out):
            code = policy_migration.main(
                [*argv, "--project-dir", str(project or self.project)]
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

    def engine(self, *argv: str) -> dict:
        data = self.home.parent / "data"
        data.mkdir(exist_ok=True)
        out = io.StringIO()
        with redirect_stdout(out):
            hygiene.main([*argv, "--data-root", str(data)])
        return json.loads(out.getvalue())

    def remove(self, row: dict, token: str | None = None) -> dict:
        data = self.home.parent / "data"
        snapshot = str(data / "snapshot.json")
        target, path = row["remove"]["target"], row["remove"]["path"]
        self.engine(
            "scan", "--target", target, "--max-depth", "1", "--output", snapshot
        )
        preview = self.engine(
            "preview", "--snapshot", snapshot, "--tier", "high", "--path", path
        )
        self.assertEqual("ready-for-explicit-approval", preview["status"])
        return self.engine(
            "apply",
            "--execute",
            "--snapshot",
            snapshot,
            "--plan",
            str(data / "plan-high.json"),
            "--confirm-tier",
            "high",
            "--approval-token",
            token or preview["approval_token"],
            "--report",
            str(data / "report-high.json"),
        )

    def test_move_and_verify_end_in_one_home_through_the_engine(self) -> None:
        self.assertEqual(2, self.run_step("move")[0])
        code, _ = self.run_step("move", "--yes", "--user-target", str(self.new_user))
        self.assertEqual(0, code)
        self.assertEqual(TEAM_POLICY, hygiene.yaml_subset.load(str(self.new_team)))
        code, report = self.run_step("verify", "--user-target", str(self.new_user))
        self.assertEqual(1, code)
        self.assertIn("--user-policy", report["files"][0]["result"])
        code, report = self.run_step("verify", "--user-policy", str(self.new_user))
        self.assertEqual(0, code)
        self.assertEqual(["verified"] * 2, [row["result"] for row in report["files"]])
        self.assertTrue(self.old_user.is_file())
        self.assertTrue(self.old_team.is_file())
        for row in report["files"]:
            self.assertEqual("completed", self.remove(row)["status"])
        self.assertFalse(self.old_user.exists())
        self.assertFalse(self.old_team.exists())
        self.assertEqual([], self.run_step("check")[1]["files"])
        policy = hygiene.load_policy(None, self.project, str(self.new_user))
        self.assertEqual("uac-prompt", policy["elevation"])
        self.assertEqual([], policy["policy_warnings"])

    def test_the_engine_keeps_an_old_file_without_the_previews_token(self) -> None:
        self.run_step("move", "--yes", "--user-target", str(self.new_user))
        report = self.run_step("verify", "--user-policy", str(self.new_user))[1]
        team = [row for row in report["files"] if row["layer"] == "team"][0]
        result = self.remove(team, token="0" * 24)
        self.assertEqual("invalid-or-blocked", result["status"])
        self.assertIn("approval token", result["error"])
        self.assertTrue(self.old_team.is_file())

    def test_an_option_naming_the_old_file_is_never_deleted(self) -> None:
        code, report = self.run_step("verify", "--user-policy", str(self.old_user))
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
        code, report = self.run_step("verify")
        team = [row for row in report["files"] if row["layer"] == "team"][0]
        self.assertEqual("refused: the new file resolves differently", team["result"])
        self.assertNotIn("remove", team)

    def test_a_home_project_dir_moves_only_the_user_file(self) -> None:
        self.old_user.write_text(json.dumps(TEAM_POLICY), encoding="utf-8")
        code, report = self.run_step(
            "move", "--yes", "--user-target", str(self.new_user), project=self.home
        )
        self.assertEqual(0, code)
        self.assertEqual(["userConfig"], [row["layer"] for row in report["files"]])
        self.assertFalse((self.home / "docs").exists())
        code, report = self.run_step(
            "verify", "--user-policy", str(self.new_user), project=self.home
        )
        self.assertEqual(0, code)
        self.assertEqual(["verified"], [row["result"] for row in report["files"]])

    def test_a_team_row_through_a_symlink_is_refused(self) -> None:
        outside = self.project.parent / "outside"
        outside.mkdir()
        (self.project / "docs").mkdir()
        (self.project / "docs" / "conventions").symlink_to(outside)
        code, report = self.run_step("move", "--yes")
        self.assertEqual(1, code)
        team = [row for row in report["files"] if row["layer"] == "team"][0]
        self.assertIn("outside", team["result"])
        self.assertEqual([], list(outside.iterdir()))
        (self.project / "docs" / "conventions").unlink()
        source = outside / "source.json"
        source.write_text(json.dumps(TEAM_POLICY), encoding="utf-8")
        self.old_team.unlink()
        self.old_team.symlink_to(source)
        for step in ("move", "verify"):
            code, report = self.run_step(step, "--yes")
            team = [row for row in report["files"] if row["layer"] == "team"][0]
            self.assertIn("is a symlink", team["result"])
        self.assertFalse(self.new_team.exists())
        self.assertTrue(self.old_team.is_symlink())


if __name__ == "__main__":
    unittest.main()
