#!/usr/bin/env python3
"""Behavioral tests for the disk-hygiene safety engine and scoped guard."""

from __future__ import annotations

import importlib.util
import io
import json
import os
import shutil
import subprocess
import tempfile
import types
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


def refuse_call(name: str):
    """Patch a hygiene function to fail the test if it is ever called.

    Used to prove an already-blocked, unvisited candidate short-circuits
    before reaching a live, unbounded filesystem/VCS/process check.
    """
    return mock.patch.object(
        hygiene,
        name,
        side_effect=AssertionError(
            f"an already-blocked, unvisited candidate must not trigger {name}, "
            "an unbounded live check its blocker makes moot"
        ),
    )


class HygieneTests(unittest.TestCase):
    def setUp(self) -> None:
        # Keep every load_policy(None) call independent of the developer
        # machine's real standing policy files.
        patcher = mock.patch.object(
            hygiene, "standing_policy_paths", return_value=[]
        )
        self.addCleanup(patcher.stop)
        patcher.start()

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

    def test_python_311_reparse_attribute_is_linkish(self) -> None:
        info = types.SimpleNamespace(
            st_mode=0o100644,
            st_file_attributes=hygiene.FILE_ATTRIBUTE_REPARSE_POINT,
        )
        with mock.patch.object(Path, "lstat", return_value=info):
            self.assertTrue(hygiene.is_linkish(Path("fixture")))

    def test_reparse_in_any_target_component_is_rejected(self) -> None:
        target = Path("root") / "junction" / "child"
        with mock.patch.object(
            hygiene,
            "is_linkish",
            side_effect=lambda path: path.name == "junction",
        ):
            self.assertTrue(hygiene.has_linkish_component(target))

    def test_windows_system_folders_are_protected_on_every_drive(self) -> None:
        roots = {
            str(path).replace("\\", "/").casefold()
            for path in hygiene.system_roots(
                platform_key="windows", windows_roots=[Path("C:/"), Path("D:/")]
            )
        }
        self.assertIn("c:/system volume information", roots)
        self.assertIn("d:/system volume information", roots)
        self.assertIn("d:/$recycle.bin", roots)

    @unittest.skipUnless(
        hygiene.os_key() == "linux", "real mountinfo is available only on Linux"
    )
    def test_linux_mountinfo_scans_current_namespace(self) -> None:
        points, error = hygiene.linux_mount_points()
        self.assertIsNone(error)
        self.assertIn(Path("/"), points)
        self.assertTrue(all(path.is_absolute() for path in points))

    def test_linux_mountinfo_detects_same_device_bind_mount_target(self) -> None:
        target = Path("/srv/bound")
        with (
            mock.patch.object(hygiene, "os_key", return_value="linux"),
            mock.patch.object(
                hygiene,
                "linux_mount_points",
                return_value=({target.absolute()}, None),
            ),
        ):
            self.assertEqual((True, None), hygiene.mount_state(target))

    def test_preview_rejects_target_that_became_mount_point(self) -> None:
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
            with mock.patch.object(hygiene, "mount_state", return_value=(True, None)):
                with self.assertRaisesRegex(hygiene.HygieneError, "mount point"):
                    hygiene.preview(snapshot, plan)

    def test_preview_blocks_nested_linux_bind_mount(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            bound = root / "bound"
            bound.mkdir(parents=True)
            snapshot = hygiene.scan_tree(root.resolve(), hygiene.load_policy(None))
            plan = {
                "version": 1,
                "tier": "high",
                "candidates": [candidate("bound")],
            }
            mount_points = {bound.resolve()}
            with (
                mock.patch.object(hygiene, "os_key", return_value="linux"),
                mock.patch.object(
                    hygiene,
                    "linux_mount_points",
                    return_value=(mount_points, None),
                ),
                mock.patch.object(
                    hygiene, "handle_state", return_value=("clear", None)
                ),
                mock.patch.object(hygiene, "tracked_blocker", return_value=None),
                mock.patch.object(hygiene, "execution_blockers", return_value=[]),
            ):
                result = hygiene.preview(snapshot, plan)
            self.assertIn("nested-mount-point", result["candidates"][0]["blockers"])

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
            self.assertEqual(["Documents"], snapshot["truncated_paths"])

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
            self.assertIn("vcs-tracked-content", result["candidates"][0]["blockers"])

    @unittest.skipUnless(
        shutil.which("git"), "git is required for the VCS regression fixture"
    )
    def test_forged_snapshot_cannot_hide_fresh_vcs_state(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "repo"
            root.mkdir()
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            tracked = root / "tracked.tmp"
            tracked.write_text("tracked", encoding="utf-8")
            snapshot = hygiene.scan_tree(root.resolve(), hygiene.load_policy(None))
            subprocess.run(["git", "-C", str(root), "add", "tracked.tmp"], check=True)
            snapshot["repositories"] = []
            snapshot["repository_errors"] = []
            for entry in snapshot["entries"]:
                entry["protected_reasons"] = []
            plan = {
                "version": 1,
                "tier": "high",
                "candidates": [candidate("tracked.tmp")],
            }
            with mock.patch.object(
                hygiene, "handle_state", return_value=("clear", None)
            ):
                result = hygiene.preview(snapshot, plan)
            self.assertIn("vcs-tracked-content", result["candidates"][0]["blockers"])

    def test_annotate_tracked_scopes_git_query_to_inventoried_paths(self) -> None:
        target = Path("/audit/root/profile")
        repo = Path("/audit/root")
        entries = [{"path": "keep.txt", "protected_reasons": []}]
        captured: dict[str, list[str]] = {}

        class FakeCompletedProcess:
            returncode = 0
            stdout = b""

        def fake_run(cmd, **kwargs):
            captured["cmd"] = cmd
            return FakeCompletedProcess()

        with (
            mock.patch.object(hygiene.shutil, "which", return_value="git"),
            mock.patch.object(hygiene.subprocess, "run", side_effect=fake_run),
        ):
            hygiene.annotate_tracked(entries, target, [repo], ["huge-vendored-dep"], [])

        pathspecs = captured["cmd"][captured["cmd"].index("--") + 1 :]
        self.assertEqual("profile", pathspecs[0])
        self.assertIn(":(exclude)profile/huge-vendored-dep", pathspecs)

    def test_forged_snapshot_cannot_hide_fresh_protected_name(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            protected = root / "Documents"
            protected.mkdir(parents=True)
            snapshot = hygiene.scan_tree(root.resolve(), hygiene.load_policy(None))
            for entry in snapshot["entries"]:
                entry["protected_reasons"] = []
            plan = {
                "version": 1,
                "tier": "high",
                "candidates": [candidate("Documents")],
            }
            with (
                mock.patch.object(
                    hygiene, "handle_state", return_value=("clear", None)
                ),
                mock.patch.object(hygiene, "execution_blockers", return_value=[]),
            ):
                result = hygiene.preview(snapshot, plan)
            self.assertIn(
                "baseline-protected-name", result["candidates"][0]["blockers"]
            )

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
                mock.patch.object(hygiene, "execution_blockers", return_value=[]),
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
            root_info = root.lstat()
            with (
                mock.patch.object(
                    hygiene,
                    "tracked_blocker",
                    side_effect=[None, "vcs-tracked-content"],
                ),
                mock.patch.object(hygiene, "execution_blockers", return_value=[]),
                mock.patch.object(
                    hygiene,
                    "preview",
                    return_value={
                        "status": "ready-for-explicit-approval",
                        "candidates": [],
                    },
                ),
                mock.patch.object(hygiene, "hard_protection", return_value=[]),
                mock.patch.object(
                    hygiene, "linux_mount_points", return_value=(set(), None)
                ),
                mock.patch.object(hygiene.os, "open", return_value=100),
                mock.patch.object(hygiene.os, "fstat", return_value=root_info),
                mock.patch.object(hygiene.os, "close"),
                mock.patch.object(hygiene.os, "O_DIRECTORY", 0x10000, create=True),
                mock.patch.object(hygiene.os, "O_NOFOLLOW", 0x20000, create=True),
                mock.patch.object(
                    hygiene, "handle_state", return_value=("clear", None)
                ),
                mock.patch.object(hygiene, "anchored_remove") as remove,
            ):
                report = hygiene.apply_plan(snapshot, plan)
            remove.assert_not_called()
            self.assertTrue(item.exists())
            self.assertEqual("completed-with-skips", report["status"])
            self.assertEqual("protected", report["skipped"][0]["outcome"])
            self.assertIn("vcs-tracked-content", report["skipped"][0]["detail"])

    def test_managed_candidate_is_always_report_only(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            root.mkdir()
            (root / "managed.tmp").write_text("state", encoding="utf-8")
            snapshot = hygiene.scan_tree(root.resolve(), hygiene.load_policy(None))
            managed = candidate("managed.tmp")
            managed["owner"] = "fixture-manager"
            managed["native_gc_evidence"] = {
                "command": "fixture-manager prune --dry-run",
                "result": "eligible",
            }
            plan = {"version": 1, "tier": "high", "candidates": [managed]}
            with (
                mock.patch.object(
                    hygiene, "handle_state", return_value=("clear", None)
                ),
                mock.patch.object(hygiene, "tracked_blocker", return_value=None),
                mock.patch.object(hygiene, "execution_blockers", return_value=[]),
            ):
                result = hygiene.preview(snapshot, plan)
            self.assertIn(
                "native-managed-report-only", result["candidates"][0]["blockers"]
            )

    def test_unsupported_platform_never_reaches_removal(self) -> None:
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
            with (
                mock.patch.object(
                    hygiene,
                    "execution_blockers",
                    return_value=["execution-platform-unsupported"],
                ),
                mock.patch.object(hygiene, "anchored_remove") as remove,
            ):
                report = hygiene.apply_plan(snapshot, plan)
            remove.assert_not_called()
            self.assertTrue(item.exists())
            self.assertIn(
                "execution-platform-unsupported", report["skipped"][0]["detail"]
            )

    def test_dirfd_walk_rejects_swapped_parent_identity(self) -> None:
        entry = {
            "kind": "directory",
            "stat_size": 0,
            "mtime_ns": 1,
            "device": 1,
            "inode": 1,
            "mode": 0o040000,
        }
        changed = types.SimpleNamespace(
            st_mode=0o040000,
            st_size=0,
            st_mtime_ns=2,
            st_dev=1,
            st_ino=2,
        )
        with (
            mock.patch.object(hygiene.os, "dup", return_value=100),
            mock.patch.object(hygiene.os, "open", return_value=101) as opened,
            mock.patch.object(hygiene.os, "fstat", return_value=changed),
            mock.patch.object(hygiene.os, "close"),
            mock.patch.object(hygiene.os, "O_DIRECTORY", 0x10000, create=True),
            mock.patch.object(hygiene.os, "O_NOFOLLOW", 0x20000, create=True),
        ):
            with self.assertRaisesRegex(hygiene.HygieneError, "parent changed"):
                hygiene.open_anchored_parent(99, "parent/orphan.tmp", {"parent": entry})
        self.assertTrue(opened.call_args.kwargs["dir_fd"] == 100)
        self.assertTrue(opened.call_args.args[1] & 0x20000)

    @unittest.skipUnless(
        hygiene.os_key() == "linux", "descriptor-relative removal is Linux-only"
    )
    def test_nested_directory_candidate_removes_only_snapshotted_fixture(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            nested = root / "candidate" / "nested"
            nested.mkdir(parents=True)
            payload = nested / "captured.tmp"
            payload.write_text("temporary fixture", encoding="utf-8")
            untouched = root / "keep.txt"
            untouched.write_text("work product", encoding="utf-8")
            snapshot = hygiene.scan_tree(root.resolve(), hygiene.load_policy(None))
            plan = {
                "version": 1,
                "tier": "high",
                "candidates": [candidate("candidate")],
            }
            with (
                mock.patch.object(hygiene, "execution_blockers", return_value=[]),
                mock.patch.object(hygiene, "hard_protection", return_value=[]),
                mock.patch.object(hygiene, "tracked_blocker", return_value=None),
                mock.patch.object(
                    hygiene, "linux_mount_points", return_value=(set(), None)
                ),
                mock.patch.object(
                    hygiene, "handle_state", return_value=("clear", None)
                ),
            ):
                report = hygiene.apply_plan(snapshot, plan)
            self.assertEqual("completed", report["status"])
            self.assertEqual(
                {"candidate/nested/captured.tmp", "candidate/nested", "candidate"},
                {item["path"] for item in report["removed"]},
            )
            self.assertFalse((root / "candidate").exists())
            self.assertEqual("work product", untouched.read_text(encoding="utf-8"))


    def test_scan_max_depth_truncates_and_preview_blocks_planning(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            (root / "deep" / "sub").mkdir(parents=True)
            (root / "loose.tmp").write_text("x", encoding="utf-8")
            (root / "deep" / "sub" / "leaf.txt").write_text("y", encoding="utf-8")
            snapshot = hygiene.scan_tree(
                root.resolve(), hygiene.load_policy(None), max_depth=1
            )
            entries = hygiene.entry_map(snapshot)
            self.assertIn("loose.tmp", entries)
            self.assertIn("deep", entries)
            self.assertNotIn("deep/sub", entries)
            self.assertEqual(["deep"], snapshot["truncated_paths"])
            plan = {
                "version": 1,
                "tier": "high",
                "candidates": [candidate("deep")],
            }
            with mock.patch.object(
                hygiene, "handle_state", return_value=("clear", None)
            ):
                result = hygiene.preview(snapshot, plan)
            self.assertIn(
                "truncated-not-inventoried", result["candidates"][0]["blockers"]
            )

    def test_preview_skips_live_recursive_checks_for_truncated_candidate(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            (root / "deep" / "sub").mkdir(parents=True)
            (root / "deep" / "sub" / "leaf.txt").write_text("y", encoding="utf-8")
            snapshot = hygiene.scan_tree(
                root.resolve(), hygiene.load_policy(None), max_depth=1
            )
            plan = {
                "version": 1,
                "tier": "high",
                "candidates": [candidate("deep")],
            }
            with (
                refuse_call("current_descendants"),
                refuse_call("tracked_blocker"),
                refuse_call("candidate_handle_state"),
            ):
                result = hygiene.preview(snapshot, plan)
            candidate_result = result["candidates"][0]
            blockers = candidate_result["blockers"]
            self.assertIn("truncated-not-inventoried", blockers)
            self.assertNotIn("changed-since-scan", blockers)
            self.assertEqual("unverified", candidate_result["handle_state"])
            self.assertEqual(
                "truncated-not-inventoried", candidate_result["handle_detail"]
            )

    def test_preview_skips_live_recursive_checks_for_unvisited_protected_candidate(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            protected = root / "Documents"
            protected.mkdir(parents=True)
            (protected / "draft.tmp").write_text("work product", encoding="utf-8")
            snapshot = hygiene.scan_tree(root.resolve(), hygiene.load_policy(None))
            self.assertEqual(["Documents"], snapshot["truncated_paths"])
            plan = {
                "version": 1,
                "tier": "high",
                "candidates": [candidate("Documents")],
            }
            with (
                refuse_call("current_descendants"),
                refuse_call("tracked_blocker"),
                refuse_call("candidate_handle_state"),
            ):
                result = hygiene.preview(snapshot, plan)
            blockers = result["candidates"][0]["blockers"]
            self.assertIn("truncated-not-inventoried", blockers)
            self.assertNotIn("changed-since-scan", blockers)

    def test_entry_cap_allows_exactly_the_configured_maximum(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            root.mkdir()
            (root / "one.txt").write_text("x", encoding="utf-8")
            (root / "two.txt").write_text("x", encoding="utf-8")
            with mock.patch.object(hygiene, "MAX_SNAPSHOT_ENTRIES", 2):
                snapshot = hygiene.scan_tree(root.resolve(), hygiene.load_policy(None))
            self.assertEqual(2, len(snapshot["entries"]))

    def test_entry_cap_rejects_one_more_than_the_configured_maximum(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            root.mkdir()
            (root / "one.txt").write_text("x", encoding="utf-8")
            (root / "two.txt").write_text("x", encoding="utf-8")
            (root / "three.txt").write_text("x", encoding="utf-8")
            with (
                mock.patch.object(hygiene, "MAX_SNAPSHOT_ENTRIES", 2),
                self.assertRaisesRegex(hygiene.HygieneError, "exceeds 2 entries"),
            ):
                hygiene.scan_tree(root.resolve(), hygiene.load_policy(None))

    def test_scan_data_root_flag_substitutes_for_environment(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            root = base / "target"
            root.mkdir()
            (root / "junk.tmp").write_text("x", encoding="utf-8")
            data_root = base / "plugin-data"
            data_root.mkdir()
            output = data_root / "run" / "snapshot.json"
            environment = {
                key: value
                for key, value in os.environ.items()
                if key != "CLAUDE_PLUGIN_DATA"
            }
            stdout_io = io.StringIO()
            with (
                mock.patch.dict("os.environ", environment, clear=True),
                redirect_stdout(stdout_io),
            ):
                code = hygiene.main(
                    [
                        "scan",
                        "--target",
                        str(root),
                        "--output",
                        str(output),
                        "--data-root",
                        str(data_root),
                    ]
                )
            self.assertEqual(0, code)
            self.assertTrue(output.exists())
            payload = json.loads(stdout_io.getvalue())
            self.assertEqual("scan-complete", payload["status"])
            self.assertEqual([], payload["truncated_paths"])

    def test_capped_scan_reports_advisory_and_bounded_rerun_guidance(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            root = base / "target"
            root.mkdir()
            for index in range(3):
                (root / f"file-{index}.txt").write_text("x", encoding="utf-8")
            data_root = base / "plugin-data"
            data_root.mkdir()
            stdout_io = io.StringIO()
            with (
                mock.patch.object(hygiene, "MAX_SNAPSHOT_ENTRIES", 1),
                mock.patch.dict(
                    "os.environ", {"CLAUDE_PLUGIN_DATA": str(data_root)}, clear=False
                ),
                redirect_stdout(stdout_io),
            ):
                code = hygiene.main(
                    [
                        "scan",
                        "--target",
                        str(root),
                        "--output",
                        str(data_root / "snapshot.json"),
                    ]
                )
            self.assertEqual(2, code)
            payload = json.loads(stdout_io.getvalue())
            self.assertEqual("invalid-or-blocked", payload["status"])
            self.assertIn("--max-depth", payload["error"])
            self.assertIn("os_autoclean", payload)


class StandingPolicyTests(unittest.TestCase):
    @staticmethod
    def write_policy(root: Path, body: dict[str, object]) -> Path:
        path = root / ".claude" / "disk-hygiene.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"version": 1, **body}), encoding="utf-8")
        return path

    @staticmethod
    def hint(hint_id: str, pattern: str) -> dict[str, object]:
        return {
            "id": hint_id,
            "os": ["all"],
            "kind": "name_glob",
            "pattern": pattern,
            "confidence_ceiling": "medium",
            "reason": "fixture standing-policy hint",
        }

    def test_standing_layers_apply_user_global_then_project(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary) / "home"
            project = Path(temporary) / "project"
            user_path = self.write_policy(
                home,
                {
                    "additional_hints": [self.hint("user-hint", "user-*")],
                    "additional_protected_path_globs": ["user-keep/**"],
                },
            )
            project_path = self.write_policy(
                project,
                {
                    "additional_hints": [self.hint("project-hint", "proj-*")],
                    "additional_protected_path_globs": ["proj-keep/**"],
                },
            )
            with mock.patch.object(hygiene.Path, "home", return_value=home):
                policy = hygiene.load_policy(None, project)
            ids = {hint["id"] for hint in policy["hints"]}
            self.assertIn("user-hint", ids)
            self.assertIn("project-hint", ids)
            self.assertEqual(
                ["user-keep/**", "proj-keep/**"],
                policy["additional_protected_path_globs"],
            )
            self.assertEqual(
                ["baseline", str(user_path), str(project_path)],
                policy["policy_sources"],
            )

    def test_explicit_policy_replaces_standing_layers(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary) / "home"
            self.write_policy(
                home, {"additional_hints": [self.hint("user-hint", "user-*")]}
            )
            explicit = Path(temporary) / "explicit.json"
            explicit.write_text(
                json.dumps(
                    {
                        "version": 1,
                        "additional_hints": [self.hint("explicit-hint", "exp-*")],
                    }
                ),
                encoding="utf-8",
            )
            with mock.patch.object(hygiene.Path, "home", return_value=home):
                policy = hygiene.load_policy(explicit, Path(temporary) / "project")
            ids = {hint["id"] for hint in policy["hints"]}
            self.assertIn("explicit-hint", ids)
            self.assertNotIn("user-hint", ids)
            self.assertEqual(["baseline", str(explicit)], policy["policy_sources"])

    def test_cross_layer_duplicate_hint_id_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary) / "home"
            project = Path(temporary) / "project"
            self.write_policy(
                home, {"additional_hints": [self.hint("shared-id", "user-*")]}
            )
            self.write_policy(
                project, {"additional_hints": [self.hint("shared-id", "proj-*")]}
            )
            with mock.patch.object(hygiene.Path, "home", return_value=home):
                with self.assertRaisesRegex(
                    hygiene.HygieneError, "already exists"
                ):
                    hygiene.load_policy(None, project)

    def test_standing_layers_cannot_weaken_protections(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary) / "home"
            self.write_policy(
                home, {"additional_protected_path_globs": ["extra-keep/**"]}
            )
            with mock.patch.object(hygiene.Path, "home", return_value=home):
                policy = hygiene.load_policy(None, None)
            self.assertIn("NTUSER.DAT", policy["protected_exact_names"])
            self.assertIn("extra-keep/**", policy["additional_protected_path_globs"])

    def test_validation_names_never_read_standing_policy(self) -> None:
        def explode(_project_dir):
            raise AssertionError("validation must not touch standing policy")

        with mock.patch.object(
            hygiene, "standing_policy_paths", side_effect=explode
        ):
            names = hygiene.baseline_protected_names()
        self.assertIn("NTUSER.DAT", names)

    def test_baseline_ships_agent_leak_signatures(self) -> None:
        with mock.patch.object(
            hygiene, "standing_policy_paths", return_value=[]
        ):
            policy = hygiene.load_policy(None)
        matched = {
            name: [
                hint["id"]
                for hint in hygiene.matching_hints(name, name, policy)
            ]
            for name in (
                ".claude.json.tmp.25020.a926d229fa70",
                "temp_git_clone_1234",
                ".pulumi-write-test-42",
            )
        }
        self.assertIn(
            "claude-json-failed-atomic-write",
            matched[".claude.json.tmp.25020.a926d229fa70"],
        )
        self.assertIn("agent-temp-git-scratch", matched["temp_git_clone_1234"])
        self.assertIn(
            "pulumi-writability-probe", matched[".pulumi-write-test-42"]
        )


class OsAutocleanAdvisoryTests(unittest.TestCase):
    def test_zone_outside_temp_has_no_advisory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            unrelated = Path(temporary) / "unrelated"
            unrelated.mkdir()
            with mock.patch.object(
                hygiene.tempfile,
                "gettempdir",
                return_value=os.fspath(Path(temporary) / "temp-root"),
            ):
                (Path(temporary) / "temp-root").mkdir()
                self.assertIsNone(hygiene.os_autoclean_advisory(unrelated))

    def test_temp_zone_reports_platform_mechanism(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            temp_root = Path(temporary) / "temp-root"
            temp_root.mkdir()
            with mock.patch.object(
                hygiene.tempfile, "gettempdir", return_value=os.fspath(temp_root)
            ):
                advisory = hygiene.os_autoclean_advisory(temp_root)
        self.assertIsNotNone(advisory)
        assert advisory is not None
        expected = {
            "win32": "windows-storage-sense",
            "linux": "systemd-tmpfiles",
        }.get(
            "win32"
            if hygiene.sys.platform == "win32"
            else ("linux" if hygiene.sys.platform.startswith("linux") else "other"),
            "not-detected",
        )
        self.assertEqual(expected, advisory["mechanism"])


class GuardTests(unittest.TestCase):
    @staticmethod
    def python_command() -> str:
        return guard._display_python()

    def run_guard(self, command: str) -> dict[str, object]:
        stdin = io.StringIO(json.dumps({"tool_input": {"command": command}}))
        stdout = io.StringIO()
        with (
            mock.patch("sys.stdin", stdin),
            redirect_stdout(stdout),
            mock.patch.dict(
                "os.environ", {"CLAUDE_PLUGIN_OPTION_DISK_HYGIENE_ENABLED": "true"}, clear=False
            ),
        ):
            self.assertEqual(0, guard.main())
        return json.loads(stdout.getvalue())

    def run_guard_disabled(self, command: str) -> dict[str, object]:
        stdin = io.StringIO(json.dumps({"tool_input": {"command": command}}))
        stdout = io.StringIO()
        with (
            mock.patch("sys.stdin", stdin),
            redirect_stdout(stdout),
            mock.patch.dict(
                "os.environ", {"CLAUDE_PLUGIN_OPTION_DISK_HYGIENE_ENABLED": "false"}, clear=False
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
        command = f'"{self.python_command()}" "{script}" apply --execute --snapshot s --plan p --confirm-tier high --approval-token {"a" * 24} --report r; rm -rf x'
        result = self.run_guard(command)
        self.assertEqual("deny", result["hookSpecificOutput"]["permissionDecision"])

    def test_guard_denies_single_shell_operator_after_engine(self) -> None:
        script = SCRIPT_DIR / "hygiene.py"
        command = f'"{self.python_command()}" "{script}" apply --execute --snapshot s --plan p --confirm-tier high --approval-token {"a" * 24} --report r | tee report'
        result = self.run_guard(command)
        self.assertEqual("deny", result["hookSpecificOutput"]["permissionDecision"])

    def test_guard_forces_final_prompt_for_exact_engine_apply(self) -> None:
        script = SCRIPT_DIR / "hygiene.py"
        command = f'"{self.python_command()}" "{script}" apply --execute --snapshot s --plan p --confirm-tier high --approval-token {"a" * 24} --report r'
        result = self.run_guard(command)
        self.assertEqual("ask", result["hookSpecificOutput"]["permissionDecision"])

    def test_disabled_guard_denies_exact_apply(self) -> None:
        script = SCRIPT_DIR / "hygiene.py"
        command = f'"{self.python_command()}" "{script}" apply --execute --snapshot s --plan p --confirm-tier high --approval-token {"a" * 24} --report r'
        result = self.run_guard_disabled(command)
        self.assertEqual("deny", result["hookSpecificOutput"]["permissionDecision"])

    def test_guard_denies_apply_through_another_engine_path(self) -> None:
        command = f'"{self.python_command()}" C:/tmp/hygiene.py apply --execute --snapshot s --plan p --confirm-tier high --approval-token {"a" * 24} --report r'
        result = self.run_guard(command)
        self.assertEqual("deny", result["hookSpecificOutput"]["permissionDecision"])

    def test_guard_denies_bare_python_even_when_it_resolves_to_hook_runtime(self) -> None:
        script = SCRIPT_DIR / "hygiene.py"
        command = f'python "{script}" scan --target t --output s'
        result = self.run_guard(command)
        self.assertEqual("deny", result["hookSpecificOutput"]["permissionDecision"])
        self.assertIn(
            self.python_command(),
            result["hookSpecificOutput"]["permissionDecisionReason"],
        )

    @unittest.skipUnless(os.name == "posix", "exported Bash functions are POSIX-only")
    def test_absolute_python_bypasses_exported_same_name_function(self) -> None:
        completed = subprocess.run(
            [
                "bash",
                "-c",
                'python() { printf hijacked; }; export -f python; "$1" -c '
                "'import sys; print(sys.executable)'",
                "bash",
                self.python_command(),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertNotIn("hijacked", completed.stdout)
        self.assertTrue(Path(completed.stdout.strip()).is_absolute())

    def test_guard_denies_unknown_and_mutation_capable_bypass_forms(self) -> None:
        commands = [
            "busybox rm -rf /tmp/example",
            "python -c \"import os; os.unlink('example')\"",
            "powershell -Command Remove-Item example",
            "cmd /c del example",
            "find . -print0 | xargs -0 rm",
            "truncate -s 0 important.txt",
            "dd if=/dev/null of=important.txt",
            "mv important.txt /tmp/hidden",
            "echo erased > important.txt",
            "rm${IFS}-rf${IFS}/tmp/example",
            "true",
        ]
        for command in commands:
            with self.subTest(command=command):
                result = self.run_guard(command)
                self.assertEqual(
                    "deny", result["hookSpecificOutput"]["permissionDecision"]
                )

    def test_guard_denies_every_shell_expansion_family(self) -> None:
        script = SCRIPT_DIR / "hygiene.py"
        template = f'"{self.python_command()}" "{script}" scan --target {{payload}} --output snapshot.json'
        payloads = [
            "target{one,two}",
            "$TARGET",
            '"$TARGET"',
            "target*",
            "target?",
            "target[12]",
            "~/target",
            "$(printf target)",
            "`printf target`",
            "$((1 + 1))",
            "<(printf target)",
            "target\\ value",
            "target\tvalue",
        ]
        for payload in payloads:
            with self.subTest(payload=payload):
                result = self.run_guard(template.format(payload=payload))
                self.assertEqual(
                    "deny", result["hookSpecificOutput"]["permissionDecision"]
                )

    @unittest.skipUnless(os.name == "posix", "POSIX path case is tested on POSIX")
    def test_script_path_key_preserves_posix_case(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            upper = Path(temporary) / "HYGIENE.py"
            lower = Path(temporary) / "hygiene.py"
            upper.touch()
            lower.touch()
            self.assertNotEqual(
                guard._script_path_key(os.fspath(upper)),
                guard._script_path_key(os.fspath(lower)),
            )

    def test_guard_allows_only_exact_read_only_engine_shapes(self) -> None:
        script = SCRIPT_DIR / "hygiene.py"
        scan = f'"{self.python_command()}" "{script}" scan --target t --output s'
        preview = f'"{self.python_command()}" "{script}" preview --snapshot s --plan p'
        malformed = f'"{self.python_command()}" "{script}" preview --plan p --snapshot s'
        self.assertEqual(
            "allow",
            self.run_guard(scan)["hookSpecificOutput"]["permissionDecision"],
        )
        self.assertEqual(
            "allow",
            self.run_guard(preview)["hookSpecificOutput"]["permissionDecision"],
        )
        self.assertEqual(
            "deny",
            self.run_guard(malformed)["hookSpecificOutput"]["permissionDecision"],
        )

    def test_guard_scan_accepts_optional_policy_and_project_dir(self) -> None:
        script = SCRIPT_DIR / "hygiene.py"
        base = f'"{self.python_command()}" "{script}" scan --target t --output s'
        allowed = (
            f"{base} --policy p",
            f"{base} --project-dir d",
            f"{base} --policy p --project-dir d",
            f"{base} --project-dir d --policy p",
        )
        denied = (
            f"{base} --policy p --policy q",
            f"{base} --project-dir d --project-dir e",
            f"{base} --unknown v",
            f"{base} --policy",
            f"{base} --policy p --project-dir",
        )
        for command in allowed:
            self.assertEqual(
                "allow",
                self.run_guard(command)["hookSpecificOutput"]["permissionDecision"],
                command,
            )
        for command in denied:
            self.assertEqual(
                "deny",
                self.run_guard(command)["hookSpecificOutput"]["permissionDecision"],
                command,
            )

    def run_guard_powershell(self, command: str) -> dict[str, object] | None:
        stdin = io.StringIO(
            json.dumps({"tool_name": "PowerShell", "tool_input": {"command": command}})
        )
        stdout = io.StringIO()
        with (
            mock.patch("sys.stdin", stdin),
            redirect_stdout(stdout),
            mock.patch.dict(
                "os.environ", {"CLAUDE_PLUGIN_OPTION_DISK_HYGIENE_ENABLED": "true"}, clear=False
            ),
        ):
            self.assertEqual(0, guard.main())
        value = stdout.getvalue()
        return json.loads(value) if value.strip() else None

    def test_guard_scan_accepts_only_hook_authorized_data_root(self) -> None:
        script = SCRIPT_DIR / "hygiene.py"
        with tempfile.TemporaryDirectory() as temporary:
            # resolve() yields the long-form path: the guard rejects the "~" in
            # Windows 8.3 short names as a shell-expansion character.
            authorized = str(Path(temporary).resolve() / "plugin-data")
            other = str(Path(temporary).resolve() / "elsewhere")
            base = f'"{self.python_command()}" "{script}" scan --target t --output s'
            with mock.patch.dict(
                "os.environ", {"CLAUDE_PLUGIN_DATA": authorized}, clear=False
            ):
                self.assertEqual(
                    "allow",
                    self.run_guard(f'{base} --data-root "{authorized}"')[
                        "hookSpecificOutput"
                    ]["permissionDecision"],
                )
                self.assertEqual(
                    "deny",
                    self.run_guard(f'{base} --data-root "{other}"')[
                        "hookSpecificOutput"
                    ]["permissionDecision"],
                )

    def test_guard_denies_data_root_without_hook_authority(self) -> None:
        script = SCRIPT_DIR / "hygiene.py"
        with tempfile.TemporaryDirectory() as temporary:
            command = (
                f'"{self.python_command()}" "{script}" scan --target t --output s '
                f'--data-root "{Path(temporary).resolve()}"'
            )
            environment = {
                key: value
                for key, value in os.environ.items()
                if key != "CLAUDE_PLUGIN_DATA"
            }
            environment["CLAUDE_PLUGIN_OPTION_DISK_HYGIENE_ENABLED"] = "true"
            stdin = io.StringIO(json.dumps({"tool_input": {"command": command}}))
            stdout = io.StringIO()
            with (
                mock.patch("sys.stdin", stdin),
                redirect_stdout(stdout),
                mock.patch.dict("os.environ", environment, clear=True),
            ):
                self.assertEqual(0, guard.main())
            result = json.loads(stdout.getvalue())
            self.assertEqual(
                "deny", result["hookSpecificOutput"]["permissionDecision"]
            )

    def run_guard_hook_argv(
        self, command: str, authorized: str | None
    ) -> dict[str, object]:
        """Drive the guard with the data root supplied via hook argv, not the env.

        Mirrors the skill-frontmatter hook, which substitutes
        ``--authorized-data-root ${CLAUDE_PLUGIN_DATA}`` into the guard's own argv
        while CLAUDE_PLUGIN_DATA is absent from the hook process environment.
        """
        argv = [str(SCRIPT_DIR / "destructive_guard.py")]
        if authorized is not None:
            argv += ["--authorized-data-root", authorized]
        environment = {
            key: value
            for key, value in os.environ.items()
            if key != "CLAUDE_PLUGIN_DATA"
        }
        environment["CLAUDE_PLUGIN_OPTION_DISK_HYGIENE_ENABLED"] = "true"
        stdin = io.StringIO(json.dumps({"tool_input": {"command": command}}))
        stdout = io.StringIO()
        with (
            mock.patch("sys.stdin", stdin),
            redirect_stdout(stdout),
            mock.patch.object(guard.sys, "argv", argv),
            mock.patch.dict("os.environ", environment, clear=True),
        ):
            self.assertEqual(0, guard.main())
        return json.loads(stdout.getvalue())

    def test_guard_authorizes_data_root_from_hook_argv_without_env(self) -> None:
        script = SCRIPT_DIR / "hygiene.py"
        with tempfile.TemporaryDirectory() as temporary:
            authorized = str(Path(temporary).resolve() / "plugin-data")
            other = str(Path(temporary).resolve() / "elsewhere")
            base = f'"{self.python_command()}" "{script}" scan --target t --output s'
            self.assertEqual(
                "allow",
                self.run_guard_hook_argv(
                    f'{base} --data-root "{authorized}"', authorized
                )["hookSpecificOutput"]["permissionDecision"],
            )
            self.assertEqual(
                "deny",
                self.run_guard_hook_argv(f'{base} --data-root "{other}"', authorized)[
                    "hookSpecificOutput"
                ]["permissionDecision"],
            )

    def test_guard_denies_data_root_when_argv_and_env_both_absent(self) -> None:
        script = SCRIPT_DIR / "hygiene.py"
        with tempfile.TemporaryDirectory() as temporary:
            target = str(Path(temporary).resolve())
            base = f'"{self.python_command()}" "{script}" scan --target t --output s'
            result = self.run_guard_hook_argv(
                f'{base} --data-root "{target}"', None
            )
            self.assertEqual(
                "deny", result["hookSpecificOutput"]["permissionDecision"]
            )
            self.assertIn(
                "--authorized-data-root",
                result["hookSpecificOutput"]["permissionDecisionReason"],
            )

    def test_argv_authorized_data_root_parses_both_arg_spellings(self) -> None:
        self.assertEqual(
            "/data", guard._argv_authorized_data_root(["--authorized-data-root", "/data"])
        )
        self.assertEqual(
            "/data", guard._argv_authorized_data_root(["--authorized-data-root=/data"])
        )
        self.assertIsNone(guard._argv_authorized_data_root(["--other", "/data"]))
        self.assertIsNone(guard._argv_authorized_data_root(["--authorized-data-root"]))

    def test_resolve_authorized_data_root_precedence(self) -> None:
        script = str(SCRIPT_DIR / "destructive_guard.py")
        with mock.patch.dict(
            "os.environ", {"CLAUDE_PLUGIN_DATA": "/from-env"}, clear=False
        ):
            with mock.patch.object(
                guard.sys, "argv", [script, "--authorized-data-root", "/from-argv"]
            ):
                self.assertEqual("/from-argv", guard.resolve_authorized_data_root())
            with mock.patch.object(guard.sys, "argv", [script]):
                self.assertEqual("/from-env", guard.resolve_authorized_data_root())
            with mock.patch.object(
                guard.sys,
                "argv",
                [script, "--authorized-data-root", "${CLAUDE_PLUGIN_DATA}"],
            ):
                self.assertEqual(
                    "/from-env",
                    guard.resolve_authorized_data_root(),
                    "an unsubstituted placeholder must fall back to the environment",
                )

    def test_skill_hook_passes_authorized_data_root_flag_matching_constant(
        self,
    ) -> None:
        """Lock the config<->code seam the fix depends on.

        The frontmatter hook must pass the exact flag literal the guard parses,
        immediately followed by the ${CLAUDE_PLUGIN_DATA} placeholder. If either
        side is renamed without the other, the guard silently loses its authority
        and the engine lane fails closed — the regression this test guards.
        """
        skill = SCRIPT_DIR.parent / "SKILL.md"
        text = skill.read_text(encoding="utf-8")
        args_line = next(
            (
                line
                for line in text.splitlines()
                if "destructive_guard.py" in line and "args:" in line
            ),
            None,
        )
        self.assertIsNotNone(args_line, "frontmatter hook args line not found")
        assert args_line is not None
        array_text = args_line[args_line.index("[") : args_line.rindex("]") + 1]
        args = json.loads(array_text)
        self.assertTrue(args[0].endswith("destructive_guard.py"), args)
        self.assertIn(guard._AUTHORIZED_DATA_ROOT_FLAG, args)
        flag_index = args.index(guard._AUTHORIZED_DATA_ROOT_FLAG)
        self.assertEqual("${CLAUDE_PLUGIN_DATA}", args[flag_index + 1])

    def test_guard_scan_max_depth_accepts_only_positive_integer_literal(self) -> None:
        script = SCRIPT_DIR / "hygiene.py"
        base = f'"{self.python_command()}" "{script}" scan --target t --output s'
        self.assertEqual(
            "allow",
            self.run_guard(f"{base} --max-depth 3")["hookSpecificOutput"][
                "permissionDecision"
            ],
        )
        for value in ("0", "007", "3x", "-1"):
            self.assertEqual(
                "deny",
                self.run_guard(f"{base} --max-depth {value}")["hookSpecificOutput"][
                    "permissionDecision"
                ],
                value,
            )

    def test_guard_preview_accepts_optional_authorized_data_root(self) -> None:
        script = SCRIPT_DIR / "hygiene.py"
        with tempfile.TemporaryDirectory() as temporary:
            authorized = str(Path(temporary).resolve() / "plugin-data")
            command = (
                f'"{self.python_command()}" "{script}" preview --snapshot s --plan p '
                f'--data-root "{authorized}"'
            )
            with mock.patch.dict(
                "os.environ", {"CLAUDE_PLUGIN_DATA": authorized}, clear=False
            ):
                self.assertEqual(
                    "allow",
                    self.run_guard(command)["hookSpecificOutput"][
                        "permissionDecision"
                    ],
                )

    def test_guard_apply_accepts_optional_authorized_data_root(self) -> None:
        script = SCRIPT_DIR / "hygiene.py"
        with tempfile.TemporaryDirectory() as temporary:
            authorized = str(Path(temporary).resolve() / "plugin-data")
            command = (
                f'"{self.python_command()}" "{script}" apply --execute --snapshot s '
                f'--plan p --confirm-tier high --approval-token {"a" * 24} --report r '
                f'--data-root "{authorized}"'
            )
            with mock.patch.dict(
                "os.environ", {"CLAUDE_PLUGIN_DATA": authorized}, clear=False
            ):
                self.assertEqual(
                    "ask",
                    self.run_guard(command)["hookSpecificOutput"][
                        "permissionDecision"
                    ],
                )

    def test_powershell_engine_invocation_is_denied(self) -> None:
        script = SCRIPT_DIR / "hygiene.py"
        result = self.run_guard_powershell(
            f'& "{self.python_command()}" "{script}" scan --target t --output s'
        )
        assert result is not None
        self.assertEqual("deny", result["hookSpecificOutput"]["permissionDecision"])

    def test_powershell_deletion_spellings_force_final_prompt(self) -> None:
        for command in (
            "Remove-Item -Recurse -Force C:/tmp/example",
            "rm C:/tmp/example",
            "del C:/tmp/example",
            "[IO.File]::Delete('C:/tmp/example')",
            "[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile('x', 'OnlyErrorDialogs', 'SendToRecycleBin')",
        ):
            result = self.run_guard_powershell(command)
            assert result is not None, command
            self.assertEqual(
                "ask",
                result["hookSpecificOutput"]["permissionDecision"],
                command,
            )

    def test_powershell_read_only_support_work_defers(self) -> None:
        for command in (
            "git status --short",
            "gh pr list --repo owner/repo",
            "Get-ChildItem -Force C:/tmp",
            "Get-Item C:/tmp/example | Select-Object Length",
        ):
            self.assertIsNone(self.run_guard_powershell(command), command)


if __name__ == "__main__":
    unittest.main()
