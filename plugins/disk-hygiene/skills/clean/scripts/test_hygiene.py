#!/usr/bin/env python3
"""Behavioral tests for the disk-hygiene safety engine and scoped guard."""

from __future__ import annotations

import importlib.util
import io
import json
import shutil
import subprocess
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

SCRIPT_DIR = Path(__file__).resolve().parent


def load_module(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPT_DIR / filename)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


hygiene = load_module("hygiene", "hygiene.py")
guard = load_module("destructive_guard", "destructive_guard.py")


def candidate(path: str, tier: str = "high") -> dict[str, object]:
    return {
        "path": path,
        "tier": tier,
        "reason": "fixture provenance identifies an abandoned atomic-write temporary",
        "evidence": ["name matches fixture convention", "owner process is absent"],
        "why_not_work_product": "fixture content is generated and has no durable consumer",
        "owner": "unmanaged",
    }


class HygieneTests(unittest.TestCase):
    def test_scan_is_read_only_and_hints_are_not_verdicts(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            root.mkdir()
            junk = root / "failed-write.tmp"
            keep = root / "notes.txt"
            junk.write_text("temporary", encoding="utf-8")
            keep.write_text("work product", encoding="utf-8")
            snapshot = hygiene.scan_tree(root.resolve(), hygiene.load_policy(None))
            entries = hygiene.entry_map(snapshot)
            self.assertTrue(entries["failed-write.tmp"]["hints"])
            self.assertFalse(entries["notes.txt"]["hints"])
            self.assertTrue(junk.exists())
            self.assertTrue(keep.exists())

    def test_policy_can_disable_hints_and_only_add_protection(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            policy_path = Path(temporary) / "policy.json"
            policy_path.write_text(
                json.dumps(
                    {
                        "version": 1,
                        "disabled_hint_ids": ["common-temp-file"],
                        "additional_hints": [],
                        "additional_protected_path_globs": ["deliverables/**"],
                    }
                ),
                encoding="utf-8",
            )
            policy = hygiene.load_policy(policy_path)
            self.assertNotIn(
                "common-temp-file", {hint["id"] for hint in policy["hints"]}
            )
            self.assertEqual(
                ["deliverables/**"], policy["additional_protected_path_globs"]
            )
            self.assertIn("NTUSER.DAT", policy["protected_exact_names"])

    def test_policy_rejects_non_array_boundary_input(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            policy_path = Path(temporary) / "policy.json"
            policy_path.write_text(
                json.dumps(
                    {
                        "version": 1,
                        "disabled_hint_ids": "common-temp-file",
                        "additional_hints": [],
                        "additional_protected_path_globs": [],
                    }
                ),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(hygiene.HygieneError, "must be arrays"):
                hygiene.load_policy(policy_path)

    def test_managed_candidate_rejects_non_text_native_command(self) -> None:
        managed = candidate("managed.tmp")
        managed["owner"] = "fixture-manager"
        managed["native_gc_evidence"] = {
            "command": ["fixture-manager", "prune", "--dry-run"],
            "result": "eligible",
        }
        plan = {"version": 1, "tier": "high", "candidates": [managed]}
        with self.assertRaisesRegex(hygiene.HygieneError, "native-GC"):
            hygiene.validate_plan(plan, {"managed.tmp": {}})

    def test_protected_shell_folder_blocks_descendant_inventory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            protected = root / "Documents"
            protected.mkdir(parents=True)
            (protected / "draft.tmp").write_text("work product", encoding="utf-8")

            snapshot = hygiene.scan_tree(root.resolve(), hygiene.load_policy(None))
            entries = hygiene.entry_map(snapshot)

            self.assertIn(
                "baseline-protected-name", entries["Documents"]["protected_reasons"]
            )
            self.assertNotIn("Documents/draft.tmp", entries)

    def test_linked_worktree_marker_is_discovered_as_repository_boundary(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            nested = root / "linked-worktree"
            nested.mkdir(parents=True)
            (nested / ".git").write_text("gitdir: ../metadata", encoding="utf-8")

            snapshot = hygiene.scan_tree(root.resolve(), hygiene.load_policy(None))

            self.assertIn(str(nested.resolve()), snapshot["repositories"])
            self.assertTrue(snapshot["repository_errors"])

    def test_missing_git_fails_closed_for_enclosing_repository_marker(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "repo"
            (root / ".git").mkdir(parents=True)
            with mock.patch.object(hygiene.shutil, "which", return_value=None):
                repositories, errors = hygiene.discover_enclosing_git(root.resolve())
            self.assertEqual([root.resolve()], repositories)
            self.assertEqual(["git-not-found"], errors)

    def test_generated_state_is_confined_to_plugin_data(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            data_root = base / "plugin-data"
            data_root.mkdir()
            with mock.patch.dict(
                "os.environ", {"CLAUDE_PLUGIN_DATA": str(data_root)}, clear=False
            ):
                self.assertEqual(
                    (data_root / "run" / "snapshot.json").resolve(),
                    hygiene.state_output_path(data_root / "run" / "snapshot.json"),
                )
                with self.assertRaisesRegex(hygiene.HygieneError, "must stay inside"):
                    hygiene.state_output_path(base / "target" / "snapshot.json")

    def test_protected_shell_folder_is_rejected_as_target(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            target = base / "Documents" / "scratch"
            data_root = base / "plugin-data"
            target.mkdir(parents=True)
            data_root.mkdir()
            output = io.StringIO()
            with (
                mock.patch.dict(
                    "os.environ", {"CLAUDE_PLUGIN_DATA": str(data_root)}, clear=False
                ),
                redirect_stdout(output),
            ):
                code = hygiene.main(
                    [
                        "scan",
                        "--target",
                        str(target),
                        "--output",
                        str(data_root / "snapshot.json"),
                    ]
                )
            self.assertEqual(2, code)
            self.assertIn("protected shell-folder", output.getvalue())
            self.assertFalse((data_root / "snapshot.json").exists())

    @unittest.skipUnless(
        shutil.which("git"), "git is required for the VCS regression fixture"
    )
    def test_preview_blocks_vcs_tracked_content(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "repo"
            root.mkdir()
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            tracked = root / "tracked.tmp"
            tracked.write_text("tracked", encoding="utf-8")
            subprocess.run(["git", "-C", str(root), "add", "tracked.tmp"], check=True)
            snapshot = hygiene.scan_tree(root.resolve(), hygiene.load_policy(None))
            plan = {
                "version": 1,
                "tier": "high",
                "candidates": [candidate("tracked.tmp")],
            }
            with mock.patch.object(
                hygiene, "handle_state", return_value=("clear", None)
            ):
                result = hygiene.preview(snapshot, plan)
            self.assertEqual("blocked", result["status"])
            self.assertIn("vcs-tracked", result["candidates"][0]["blockers"])

    def test_preview_blocks_changed_entries(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            root.mkdir()
            item = root / "orphan.tmp"
            item.write_text("before", encoding="utf-8")
            snapshot = hygiene.scan_tree(root.resolve(), hygiene.load_policy(None))
            item.write_text("after and changed", encoding="utf-8")
            plan = {
                "version": 1,
                "tier": "high",
                "candidates": [candidate("orphan.tmp")],
            }
            with mock.patch.object(
                hygiene, "handle_state", return_value=("clear", None)
            ):
                result = hygiene.preview(snapshot, plan)
            self.assertIn("changed-since-scan", result["candidates"][0]["blockers"])

    def test_preview_binds_one_tier_and_exact_snapshot_to_token(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            root.mkdir()
            (root / "orphan.tmp").write_text("temporary", encoding="utf-8")
            snapshot = hygiene.scan_tree(root.resolve(), hygiene.load_policy(None))
            plan = {
                "version": 1,
                "tier": "high",
                "candidates": [candidate("orphan.tmp")],
            }
            with (
                mock.patch.object(
                    hygiene, "handle_state", return_value=("clear", None)
                ),
                mock.patch.object(hygiene, "tracked_blocker", return_value=None),
            ):
                result = hygiene.preview(snapshot, plan)
            self.assertEqual("ready-for-explicit-approval", result["status"])
            self.assertRegex(result["approval_token"], r"^[0-9a-f]{24}$")
            altered = json.loads(json.dumps(plan))
            altered["candidates"][0]["reason"] = "different evidence"
            self.assertNotEqual(
                result["approval_token"], hygiene.approval_token(snapshot, altered)
            )

    def test_apply_without_execute_preserves_target(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            root = base / "target"
            root.mkdir()
            item = root / "orphan.tmp"
            item.write_text("temporary", encoding="utf-8")
            snapshot = hygiene.scan_tree(root.resolve(), hygiene.load_policy(None))
            plan = {
                "version": 1,
                "tier": "high",
                "candidates": [candidate("orphan.tmp")],
            }
            snapshot_path = base / "snapshot.json"
            plan_path = base / "plan.json"
            snapshot_path.write_text(json.dumps(snapshot), encoding="utf-8")
            plan_path.write_text(json.dumps(plan), encoding="utf-8")
            token = hygiene.approval_token(snapshot, plan)
            output = io.StringIO()
            with (
                mock.patch.object(
                    hygiene, "handle_state", return_value=("clear", None)
                ),
                mock.patch.object(hygiene, "tracked_blocker", return_value=None),
                redirect_stdout(output),
            ):
                code = hygiene.main(
                    [
                        "apply",
                        "--snapshot",
                        str(snapshot_path),
                        "--plan",
                        str(plan_path),
                        "--confirm-tier",
                        "high",
                        "--approval-token",
                        token,
                        "--report",
                        str(base / "report.json"),
                    ]
                )
            self.assertEqual(2, code)
            self.assertTrue(item.exists())
            self.assertIn("explicit --execute", output.getvalue())

    def test_invalid_report_path_is_rejected_before_apply(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            data_root = base / "plugin-data"
            data_root.mkdir()
            snapshot_path = base / "snapshot.json"
            plan_path = base / "plan.json"
            snapshot_path.write_text("{}", encoding="utf-8")
            plan_path.write_text('{"tier": "high"}', encoding="utf-8")
            output = io.StringIO()
            with (
                mock.patch.dict(
                    "os.environ", {"CLAUDE_PLUGIN_DATA": str(data_root)}, clear=False
                ),
                mock.patch.object(
                    hygiene,
                    "preview",
                    return_value={
                        "status": "ready-for-explicit-approval",
                        "approval_token": "a" * 24,
                    },
                ),
                mock.patch.object(hygiene, "apply_plan") as apply_plan,
                redirect_stdout(output),
            ):
                code = hygiene.main(
                    [
                        "apply",
                        "--execute",
                        "--snapshot",
                        str(snapshot_path),
                        "--plan",
                        str(plan_path),
                        "--confirm-tier",
                        "high",
                        "--approval-token",
                        "a" * 24,
                        "--report",
                        str(base / "outside" / "report.json"),
                    ]
                )
            self.assertEqual(2, code)
            apply_plan.assert_not_called()
            self.assertIn("must stay inside", output.getvalue())

    def test_apply_rechecks_vcs_protection_before_any_removal(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            root.mkdir()
            item = root / "orphan.tmp"
            item.write_text("temporary", encoding="utf-8")
            snapshot = hygiene.scan_tree(root.resolve(), hygiene.load_policy(None))
            plan = {
                "version": 1,
                "tier": "high",
                "candidates": [candidate("orphan.tmp")],
            }
            with mock.patch.object(
                hygiene, "tracked_blocker", return_value="vcs-tracked-content"
            ):
                report = hygiene.apply_plan(snapshot, plan)
            self.assertTrue(item.exists())
            self.assertEqual("completed-with-skips", report["status"])
            self.assertEqual("protected", report["skipped"][0]["outcome"])
            self.assertIn("vcs-tracked-content", report["skipped"][0]["detail"])


class GuardTests(unittest.TestCase):
    def run_guard(self, command: str) -> dict[str, object]:
        stdin = io.StringIO(json.dumps({"tool_input": {"command": command}}))
        stdout = io.StringIO()
        with (
            mock.patch("sys.stdin", stdin),
            redirect_stdout(stdout),
            mock.patch.dict(
                "os.environ", {"HOOK_DISK_HYGIENE_ENABLED": "true"}, clear=False
            ),
        ):
            self.assertEqual(0, guard.main())
        return json.loads(stdout.getvalue())

    def test_guard_denies_direct_recursive_delete(self) -> None:
        result = self.run_guard("rm -rf /tmp/example")
        self.assertEqual("deny", result["hookSpecificOutput"]["permissionDecision"])

    def test_guard_denies_direct_single_file_delete(self) -> None:
        result = self.run_guard("rm /tmp/example")
        self.assertEqual("deny", result["hookSpecificOutput"]["permissionDecision"])

    def test_guard_denies_unlink_command(self) -> None:
        result = self.run_guard("unlink /tmp/example")
        self.assertEqual("deny", result["hookSpecificOutput"]["permissionDecision"])

    def test_guard_denies_chained_delete_after_engine(self) -> None:
        script = SCRIPT_DIR / "hygiene.py"
        command = f'python "{script}" apply --execute --snapshot s --plan p --confirm-tier high --approval-token {"a" * 24} --report r; rm -rf x'
        result = self.run_guard(command)
        self.assertEqual("deny", result["hookSpecificOutput"]["permissionDecision"])

    def test_guard_denies_single_shell_operator_after_engine(self) -> None:
        script = SCRIPT_DIR / "hygiene.py"
        command = f'python "{script}" apply --execute --snapshot s --plan p --confirm-tier high --approval-token {"a" * 24} --report r | tee report'
        result = self.run_guard(command)
        self.assertEqual("deny", result["hookSpecificOutput"]["permissionDecision"])

    def test_guard_forces_final_prompt_for_exact_engine_apply(self) -> None:
        script = SCRIPT_DIR / "hygiene.py"
        command = f'python "{script}" apply --execute --snapshot s --plan p --confirm-tier high --approval-token {"a" * 24} --report r'
        result = self.run_guard(command)
        self.assertEqual("ask", result["hookSpecificOutput"]["permissionDecision"])

    def test_guard_denies_apply_through_another_engine_path(self) -> None:
        command = f"python C:/tmp/hygiene.py apply --execute --snapshot s --plan p --confirm-tier high --approval-token {'a' * 24} --report r"
        result = self.run_guard(command)
        self.assertEqual("deny", result["hookSpecificOutput"]["permissionDecision"])


if __name__ == "__main__":
    unittest.main()
