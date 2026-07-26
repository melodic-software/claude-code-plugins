#!/usr/bin/env python3
"""Behavioral tests for the disk-hygiene safety engine and scoped guard."""

from __future__ import annotations

import importlib.util
import io
import json
import math
import os
import re
import shutil
import subprocess
import tempfile
import types
import unittest
from contextlib import (
    ExitStack,
    chdir as chdir_context,
    redirect_stderr,
    redirect_stdout,
)
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

    def test_os_drive_markers_exclude_per_volume_metadata(self) -> None:
        markers = {
            str(path).replace("\\", "/").casefold()
            for path in hygiene.os_drive_markers(
                platform_key="windows", windows_roots=[Path("C:/"), Path("D:/")]
            )
        }
        # OS-install markers stay; the per-volume metadata every Windows volume
        # carries — a provisioned non-OS Dev Drive included — must NOT count as
        # an OS-drive signal, or every drive root would classify OS-managed.
        self.assertIn("d:/windows", markers)
        self.assertIn("d:/programdata", markers)
        self.assertNotIn("d:/system volume information", markers)
        self.assertNotIn("d:/$recycle.bin", markers)

    def test_os_managed_target_flags_drive_holding_os_install(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            drive = Path(temporary) / "drive"
            (drive / "Windows").mkdir(parents=True)
            self.assertTrue(
                hygiene.is_os_managed_target(
                    drive, roots=[], markers=[drive / "Windows"]
                )
            )

    def test_os_managed_target_ignores_per_volume_metadata_only(self) -> None:
        # The Dev Drive case: a volume root whose only system-looking folders
        # are the per-volume metadata every volume carries is NOT OS-managed —
        # the synthesized OS-install marker does not exist on it.
        with tempfile.TemporaryDirectory() as temporary:
            drive = Path(temporary) / "dev-drive"
            (drive / "System Volume Information").mkdir(parents=True)
            (drive / "$Recycle.Bin").mkdir()
            self.assertFalse(
                hygiene.is_os_managed_target(
                    drive,
                    roots=[],
                    markers=[drive / name for name in ("Windows", "ProgramData")],
                )
            )

    def test_os_managed_target_flags_path_within_a_system_root(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "sysroot"
            inside = root / "sub"
            inside.mkdir(parents=True)
            self.assertTrue(
                hygiene.is_os_managed_target(inside, roots=[root], markers=[])
            )

    def test_hard_protection_names_the_target_root(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / "target"
            target.mkdir()
            self.assertIn(
                "target-root", hygiene.hard_protection(target, target, set())
            )

    def test_hard_protection_reasons_about_volume_root_purpose(self) -> None:
        # The cited hard_protection branch is now reasoned, not structural: a
        # volume-root path is flagged os-managed only when reasoned OS-managed.
        # No live call path reaches it with a root-shaped entry, so exercise it
        # directly to lock the intent.
        path, target = Path("X:/"), Path("Y:/")
        with (
            mock.patch.object(hygiene, "is_volume_root", return_value=True),
            mock.patch.object(hygiene, "is_os_managed_target", return_value=True),
        ):
            self.assertIn(
                "os-managed-root", hygiene.hard_protection(path, target, set())
            )
        with (
            mock.patch.object(hygiene, "is_volume_root", return_value=True),
            mock.patch.object(hygiene, "is_os_managed_target", return_value=False),
        ):
            self.assertNotIn(
                "os-managed-root", hygiene.hard_protection(path, target, set())
            )

    def test_hard_protection_exempts_admitted_volume_root_from_mount_reason(
        self,
    ) -> None:
        # Regression: a descendant of an admitted non-OS volume-root target must
        # not inherit target-is-mount-point from the ancestor walk reaching the
        # (mounted) volume root — that blanket-protected every entry and defeated
        # the admitted scan. A nested mount below the target stays blocked.
        target, child, nested = Path("X:/"), Path("X:/scratch"), Path("X:/mnt")
        with (
            mock.patch.object(
                hygiene, "is_volume_root", side_effect=lambda p: p == target
            ),
            mock.patch.object(hygiene, "is_linkish", return_value=False),
        ):
            with mock.patch.object(
                hygiene, "mount_state", side_effect=lambda p, *a: (p == target, None)
            ):
                child_reasons = hygiene.hard_protection(child, target, set())
            self.assertNotIn("target-is-mount-point", child_reasons)
            self.assertNotIn("nested-mount-point", child_reasons)

            with mock.patch.object(
                hygiene,
                "mount_state",
                side_effect=lambda p, *a: (p in {target, nested}, None),
            ):
                nested_reasons = hygiene.hard_protection(nested, target, set())
            self.assertIn("nested-mount-point", nested_reasons)
            self.assertNotIn("target-is-mount-point", nested_reasons)

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

    def _scan_target(
        self,
        target: Path,
        data_root: Path,
        patches: list[object],
        extra_args: list[str] | None = None,
    ) -> tuple[int, dict[str, object]]:
        output = io.StringIO()
        with (
            mock.patch.dict(
                "os.environ", {"CLAUDE_PLUGIN_DATA": str(data_root)}, clear=False
            ),
            redirect_stdout(output),
        ):
            for patch in patches:
                self.enterContext(patch)
            code = hygiene.main(
                [
                    "scan",
                    "--target",
                    str(target),
                    "--output",
                    str(data_root / "snapshot.json"),
                    *(extra_args or []),
                ]
            )
        return code, json.loads(output.getvalue())

    def _non_os_volume_root_patches(self) -> list[object]:
        # A drive-letter root is always os.path.ismount True; it holds no
        # OS-managed content (a Windows Dev Drive), so it is a valid non-OS
        # volume root rather than a rejected OS root.
        return [
            mock.patch.object(hygiene, "is_volume_root", return_value=True),
            mock.patch.object(hygiene, "is_os_managed_target", return_value=False),
            mock.patch.object(hygiene, "mount_state", return_value=(True, None)),
        ]

    def test_non_os_volume_root_without_bound_requires_large_confirmation(self) -> None:
        # A non-OS volume root is no longer blanket-rejected, but an unbounded
        # whole-volume walk is gated the same way a home target is (#985's
        # large-target gate) rather than silently proceeding.
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            target = base / "dev-drive"
            data_root = base / "plugin-data"
            target.mkdir()
            (target / "scratch.tmp").write_text("x", encoding="utf-8")
            data_root.mkdir()
            code, payload = self._scan_target(
                target, data_root, self._non_os_volume_root_patches()
            )
            self.assertEqual(5, code)
            self.assertEqual("large-target-confirmation-required", payload["status"])
            self.assertIn("non-os-volume-root", payload["large_target_reasons"])
            self.assertFalse((data_root / "snapshot.json").exists())

    def test_non_os_volume_root_with_confirmed_flag_scans(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            target = base / "dev-drive"
            data_root = base / "plugin-data"
            target.mkdir()
            (target / "scratch.tmp").write_text("x", encoding="utf-8")
            data_root.mkdir()
            code, payload = self._scan_target(
                target,
                data_root,
                self._non_os_volume_root_patches(),
                extra_args=["--confirmed-large-scan"],
            )
            self.assertEqual(0, code)
            self.assertEqual("scan-complete", payload["status"])
            self.assertTrue((data_root / "snapshot.json").exists())

    def test_large_scan_reasons_flags_non_os_volume_root(self) -> None:
        with (
            mock.patch.object(hygiene, "is_volume_root", return_value=True),
            mock.patch.object(hygiene, "is_os_managed_target", return_value=False),
        ):
            self.assertEqual(
                ["non-os-volume-root"], hygiene.large_scan_reasons(Path("X:/"))
            )
        # An OS-managed volume root never reaches the gate (denied upstream), and
        # even called directly it is not named a large target here.
        with (
            mock.patch.object(hygiene, "is_volume_root", return_value=True),
            mock.patch.object(hygiene, "is_os_managed_target", return_value=True),
        ):
            self.assertEqual([], hygiene.large_scan_reasons(Path("X:/")))

    def test_scan_denies_os_managed_root(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            target = base / "os-root"
            data_root = base / "plugin-data"
            target.mkdir()
            data_root.mkdir()
            code, payload = self._scan_target(
                target,
                data_root,
                [mock.patch.object(hygiene, "is_os_managed_target", return_value=True)],
            )
            self.assertEqual(2, code)
            self.assertIn("OS-managed roots", payload["error"])
            self.assertFalse((data_root / "snapshot.json").exists())

    def test_scan_rejects_non_root_mount_point(self) -> None:
        # A mount point that is not a volume root (a nested or bind mount as the
        # target) stays hard-blocked — the real cross-boundary danger, unchanged.
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            target = base / "mounted"
            data_root = base / "plugin-data"
            target.mkdir()
            data_root.mkdir()
            code, payload = self._scan_target(
                target,
                data_root,
                [
                    mock.patch.object(
                        hygiene, "is_os_managed_target", return_value=False
                    ),
                    mock.patch.object(hygiene, "is_volume_root", return_value=False),
                    mock.patch.object(
                        hygiene, "mount_state", return_value=(True, None)
                    ),
                ],
            )
            self.assertEqual(2, code)
            self.assertIn("mount points are not valid audit targets", payload["error"])
            self.assertFalse((data_root / "snapshot.json").exists())

    def test_preview_denies_os_managed_root_snapshot(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            root.mkdir()
            (root / "orphan.tmp").write_text("x", encoding="utf-8")
            snapshot = hygiene.scan_tree(root.resolve(), hygiene.load_policy(None))
            plan = {
                "version": 1,
                "tier": "high",
                "candidates": [candidate("orphan.tmp")],
            }
            with mock.patch.object(hygiene, "is_os_managed_target", return_value=True):
                with self.assertRaisesRegex(hygiene.HygieneError, "OS-managed root"):
                    hygiene.preview(snapshot, plan)

    def test_preview_allows_non_os_volume_root_snapshot(self) -> None:
        # Symmetry with scan: a non-OS volume-root snapshot reaches candidate
        # evaluation instead of a target-level root/mount veto (the confirmation
        # gate lived at scan; preview must not re-reject the same root).
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            root.mkdir()
            (root / "orphan.tmp").write_text("x", encoding="utf-8")
            snapshot = hygiene.scan_tree(root.resolve(), hygiene.load_policy(None))
            plan = {
                "version": 1,
                "tier": "high",
                "candidates": [candidate("orphan.tmp")],
            }
            with (
                mock.patch.object(hygiene, "is_volume_root", return_value=True),
                mock.patch.object(hygiene, "is_os_managed_target", return_value=False),
                mock.patch.object(hygiene, "mount_state", return_value=(True, None)),
            ):
                result = hygiene.preview(snapshot, plan)
            self.assertEqual("high", result["tier"])
            self.assertEqual(
                ["orphan.tmp"], [item["path"] for item in result["candidates"]]
            )

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

    def _home_target_fixture(self) -> tuple[Path, Path, Path]:
        """A directory tree standing in for the user home target."""
        base = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, base, ignore_errors=True)
        root = base / "home"
        root.mkdir()
        (root / "loose.tmp").write_text("x", encoding="utf-8")
        (root / "nested").mkdir()
        (root / "nested" / "leaf.txt").write_text("y", encoding="utf-8")
        data_root = base / "plugin-data"
        data_root.mkdir()
        return root, data_root, data_root / "run" / "snapshot.json"

    def _run_home_scan(
        self, extra_args: list[str]
    ) -> tuple[int, dict[str, object], Path]:
        root, data_root, output = self._home_target_fixture()
        stdout_io = io.StringIO()
        with (
            mock.patch.object(hygiene.Path, "home", return_value=root.resolve()),
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
                    *extra_args,
                ]
            )
        return code, json.loads(stdout_io.getvalue()), output

    def test_home_target_without_bound_requires_confirmation_and_never_walks(
        self,
    ) -> None:
        root, data_root, output = self._home_target_fixture()
        stdout_io = io.StringIO()
        with (
            mock.patch.object(hygiene.Path, "home", return_value=root.resolve()),
            refuse_call("scan_tree"),
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
        payload = json.loads(stdout_io.getvalue())
        self.assertEqual(5, code)
        self.assertEqual("large-target-confirmation-required", payload["status"])
        self.assertEqual(["user-home"], payload["large_target_reasons"])
        self.assertEqual(2, payload["immediate_entries"])
        self.assertIn("os_autoclean", payload)
        self.assertFalse(output.exists())

    def test_home_target_with_max_depth_proceeds(self) -> None:
        code, payload, output = self._run_home_scan(["--max-depth", "1"])
        self.assertEqual(0, code)
        self.assertEqual("scan-complete", payload["status"])
        self.assertTrue(output.exists())

    def test_home_target_with_confirmed_flag_proceeds(self) -> None:
        code, payload, output = self._run_home_scan(["--confirmed-large-scan"])
        self.assertEqual(0, code)
        self.assertEqual("scan-complete", payload["status"])
        self.assertTrue(output.exists())

    def test_ordinary_subdirectory_is_not_gated(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            root = base / "target"
            root.mkdir()
            (root / "junk.tmp").write_text("x", encoding="utf-8")
            home = base / "home"
            home.mkdir()
            data_root = base / "plugin-data"
            data_root.mkdir()
            output = data_root / "run" / "snapshot.json"
            stdout_io = io.StringIO()
            with (
                # Home is a different real directory, so identity does not match.
                mock.patch.object(hygiene.Path, "home", return_value=home.resolve()),
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
            payload = json.loads(stdout_io.getvalue())
            self.assertEqual(0, code)
            self.assertEqual("scan-complete", payload["status"])

    def test_home_match_is_by_filesystem_identity_not_case_folded_string(
        self,
    ) -> None:
        # A case-variant spelling resolves to the same directory on a
        # case-insensitive macOS volume, but os.path.normcase folds case only on
        # Windows — a string compare would let it bypass the gate. The match is
        # by filesystem identity, simulated here (CI is case-sensitive Linux) by
        # having samefile report the two distinct spellings as one file.
        target = Path("/users/alice")
        home = Path("/Users/alice")
        self.assertNotEqual(os.fspath(target), os.fspath(home))
        with (
            mock.patch.object(hygiene, "user_home", return_value=home),
            mock.patch("os.path.samefile", return_value=True) as samefile,
        ):
            reasons = hygiene.large_scan_reasons(target)
        self.assertEqual(["user-home"], reasons)
        samefile.assert_called_once_with(target, home)

    def test_home_match_treats_unstattable_home_as_no_match(self) -> None:
        # samefile raises when a path is missing; a home that cannot be stat'd
        # must be no match, never a crash.
        with (
            mock.patch.object(
                hygiene, "user_home", return_value=Path("/home/missing")
            ),
            mock.patch("os.path.samefile", side_effect=FileNotFoundError),
        ):
            self.assertEqual([], hygiene.large_scan_reasons(Path("/home/target")))


class VersionFloorTests(unittest.TestCase):
    """The Python floor has one origin: hygiene.MIN_PYTHON."""

    def test_min_python_line_keeps_its_greppable_shape(self) -> None:
        # setup check and the .test.sh wrappers derive the floor by parsing
        # this exact line shape out of hygiene.py.
        source = (SCRIPT_DIR / "hygiene.py").read_text(encoding="utf-8")
        matches = re.findall(
            r"^MIN_PYTHON = \((\d+), (\d+)\)$", source, flags=re.MULTILINE
        )
        self.assertEqual(1, len(matches))
        self.assertEqual(tuple(map(int, matches[0])), hygiene.MIN_PYTHON)

    def test_engine_enforces_the_constant_and_names_it_in_the_error(self) -> None:
        below = (hygiene.MIN_PYTHON[0], hygiene.MIN_PYTHON[1] - 1, 0)
        with (
            mock.patch.object(hygiene.sys, "version_info", below),
            redirect_stdout(io.StringIO()),
        ):
            code = hygiene.main(
                ["scan", "--target", "irrelevant", "--output", "irrelevant"]
            )
        self.assertNotEqual(0, code)

    def test_error_message_derives_from_the_constant(self) -> None:
        floor = ".".join(str(part) for part in hygiene.MIN_PYTHON)
        below = (hygiene.MIN_PYTHON[0], hygiene.MIN_PYTHON[1] - 1, 0)
        stdout = io.StringIO()
        with (
            mock.patch.object(hygiene.sys, "version_info", below),
            redirect_stdout(stdout),
        ):
            hygiene.main(
                ["scan", "--target", "irrelevant", "--output", "irrelevant"]
            )
        payload = json.loads(stdout.getvalue())
        self.assertIn(floor, payload["error"])


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


class LeastObservableEnginePathTests(unittest.TestCase):
    """Direct coverage for the engine paths a consumer can least verify live (F8).

    Each test mocks the OS surface (Win32 handle probe, lsof, the registry,
    /proc/self/mountinfo encoding, VCS markers) so both CI lanes exercise the
    same branch regardless of host platform.
    """

    @staticmethod
    def fake_windows_ctypes(create_result: int, error_code: int = 0):
        dll = types.SimpleNamespace(
            CreateFileW=mock.Mock(return_value=create_result),
            CloseHandle=mock.Mock(),
        )
        fake = types.SimpleNamespace(
            WinDLL=mock.Mock(return_value=dll),
            c_wchar_p=object(),
            c_uint32=object(),
            c_void_p=lambda value=None: types.SimpleNamespace(value=value),
            get_last_error=mock.Mock(return_value=error_code),
        )
        return fake, dll

    def windows_handle_probe(
        self, probe: Path, create_result: int, error_code: int = 0
    ):
        fake, dll = self.fake_windows_ctypes(create_result, error_code)
        with mock.patch.object(hygiene, "ctypes", fake):
            return hygiene.windows_handle_state(probe), dll

    def test_windows_handle_sharing_violation_codes_map_to_open(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            probe = Path(temporary) / "probe.tmp"
            probe.write_text("busy", encoding="utf-8")
            for code in (32, 33):  # ERROR_SHARING_VIOLATION / ERROR_LOCK_VIOLATION
                state, dll = self.windows_handle_probe(probe, -1, code)
                self.assertEqual(("open", f"win32-error-{code}"), state)
                dll.CloseHandle.assert_not_called()

    def test_windows_handle_access_denied_codes_map_to_needs_elevation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            probe = Path(temporary) / "probe.tmp"
            probe.write_text("guarded", encoding="utf-8")
            for code in (5, 1314):  # ERROR_ACCESS_DENIED / ERROR_PRIVILEGE_NOT_HELD
                state, _ = self.windows_handle_probe(probe, -1, code)
                self.assertEqual(("needs_elevation", f"win32-error-{code}"), state)

    def test_windows_handle_unknown_error_fails_closed_as_unverified(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            probe = Path(temporary) / "probe.tmp"
            probe.write_text("gone", encoding="utf-8")
            state, _ = self.windows_handle_probe(probe, -1, 2)
            self.assertEqual(("unverified", "win32-error-2"), state)

    def test_windows_handle_success_reports_clear_and_closes_handle(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            probe = Path(temporary) / "probe.tmp"
            probe.write_text("idle", encoding="utf-8")
            state, dll = self.windows_handle_probe(probe, 42)
            self.assertEqual(("clear", None), state)
            dll.CloseHandle.assert_called_once()

    def test_windows_handle_directory_probe_uses_backup_semantics(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / "held-dir"
            directory.mkdir()
            probe = directory / "probe.tmp"
            probe.write_text("file", encoding="utf-8")
            _, directory_dll = self.windows_handle_probe(directory, 42)
            _, file_dll = self.windows_handle_probe(probe, 42)
        directory_flags = directory_dll.CreateFileW.call_args.args[5]
        file_flags = file_dll.CreateFileW.call_args.args[5]
        self.assertEqual(0x02000000, directory_flags)  # FILE_FLAG_BACKUP_SEMANTICS
        self.assertEqual(0x00000080, file_flags)  # FILE_ATTRIBUTE_NORMAL

    @staticmethod
    def lsof_result(returncode: int, stdout: str = "", stderr: str = ""):
        return types.SimpleNamespace(
            returncode=returncode, stdout=stdout, stderr=stderr
        )

    def posix_handle_probe(self, path: Path, result=None, side_effect=None):
        captured: dict[str, list[str]] = {}

        def fake_run(command, **kwargs):
            captured["command"] = command
            if side_effect is not None:
                raise side_effect
            return result

        with (
            mock.patch.object(hygiene.shutil, "which", return_value="/usr/bin/lsof"),
            mock.patch.object(hygiene.subprocess, "run", side_effect=fake_run),
        ):
            return hygiene.posix_handle_state(path), captured

    def test_posix_handle_without_lsof_fails_closed(self) -> None:
        with mock.patch.object(hygiene.shutil, "which", return_value=None):
            self.assertEqual(
                ("unverified", "lsof-not-found"),
                hygiene.posix_handle_state(Path("/anywhere")),
            )

    def test_posix_handle_open_file_reported_by_lsof(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            probe = Path(temporary) / "probe.tmp"
            probe.write_text("busy", encoding="utf-8")
            state, captured = self.posix_handle_probe(
                probe, self.lsof_result(0, stdout=f"n{probe}\n")
            )
        self.assertEqual(("open", "lsof-reported-open-file"), state)
        self.assertEqual(["--", str(probe)], captured["command"][-2:])

    def test_posix_handle_directory_probe_walks_descendants(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / "held-dir"
            directory.mkdir()
            state, captured = self.posix_handle_probe(
                directory, self.lsof_result(1)
            )
        self.assertEqual(("clear", None), state)
        self.assertEqual(["+D", str(directory)], captured["command"][-2:])

    def test_posix_handle_clear_when_lsof_finds_nothing(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            probe = Path(temporary) / "probe.tmp"
            probe.write_text("idle", encoding="utf-8")
            state, _ = self.posix_handle_probe(probe, self.lsof_result(1))
        self.assertEqual(("clear", None), state)

    def test_posix_handle_diagnostics_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            probe = Path(temporary) / "probe.tmp"
            probe.write_text("busy", encoding="utf-8")
            state, _ = self.posix_handle_probe(
                probe,
                self.lsof_result(
                    0, stdout=f"n{probe}\n", stderr="lsof: WARNING: unreadable dir"
                ),
            )
        self.assertEqual("unverified", state[0])
        self.assertTrue(state[1] and state[1].startswith("lsof-diagnostic:"))

    def test_posix_handle_unexpected_exit_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            probe = Path(temporary) / "probe.tmp"
            probe.write_text("odd", encoding="utf-8")
            state, _ = self.posix_handle_probe(probe, self.lsof_result(3))
        self.assertEqual(("unverified", "lsof-exit-3"), state)

    def test_posix_handle_timeout_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            probe = Path(temporary) / "probe.tmp"
            probe.write_text("slow", encoding="utf-8")
            state, _ = self.posix_handle_probe(
                probe, side_effect=subprocess.TimeoutExpired("lsof", 20)
            )
        self.assertEqual(("unverified", "lsof-timeout"), state)

    @staticmethod
    def fake_winreg(values=None, open_error=None):
        class FakeKey:
            def __enter__(self):
                return self

            def __exit__(self, *exc_info):
                return False

        def open_key(root, key_path):
            if open_error is not None:
                raise open_error
            return FakeKey()

        def query_value_ex(key, name):
            if values is not None and name in values:
                return values[name], 4  # REG_DWORD
            raise OSError(2, "value not found")

        # `import winreg` returns whatever object sys.modules holds; a plain
        # namespace stands in for the real module on every platform.
        return types.SimpleNamespace(
            HKEY_CURRENT_USER=object(),
            OpenKey=open_key,
            QueryValueEx=query_value_ex,
        )

    def test_storage_sense_reads_policy_values(self) -> None:
        fake = self.fake_winreg({"01": 1, "04": 1, "2048": 7})
        with mock.patch.dict("sys.modules", {"winreg": fake}):
            state = hygiene.windows_storage_sense_state()
        self.assertEqual(
            {"enabled": True, "temporary_files_cleanup": True, "cadence_days": 7},
            state,
        )

    def test_storage_sense_zero_values_read_as_disabled(self) -> None:
        fake = self.fake_winreg({"01": 0, "04": 0, "2048": 0})
        with mock.patch.dict("sys.modules", {"winreg": fake}):
            state = hygiene.windows_storage_sense_state()
        self.assertEqual(
            {"enabled": False, "temporary_files_cleanup": False, "cadence_days": 0},
            state,
        )

    def test_storage_sense_missing_values_stay_unknown(self) -> None:
        fake = self.fake_winreg({})
        with mock.patch.dict("sys.modules", {"winreg": fake}):
            state = hygiene.windows_storage_sense_state()
        self.assertEqual(
            {"enabled": None, "temporary_files_cleanup": None, "cadence_days": None},
            state,
        )

    def test_storage_sense_missing_key_reports_unknown_state(self) -> None:
        fake = self.fake_winreg(open_error=OSError(2, "key not found"))
        with mock.patch.dict("sys.modules", {"winreg": fake}):
            state = hygiene.windows_storage_sense_state()
        self.assertEqual(
            {"enabled": None, "temporary_files_cleanup": None, "cadence_days": None},
            state,
        )

    def test_mountinfo_decoder_decodes_octal_escapes(self) -> None:
        self.assertEqual(
            "/mnt/data disk", hygiene._decode_mountinfo_path("/mnt/data\\040disk")
        )
        self.assertEqual("/mnt/a\tb", hygiene._decode_mountinfo_path("/mnt/a\\011b"))
        self.assertEqual(
            "/mnt/back\\slash", hygiene._decode_mountinfo_path("/mnt/back\\134slash")
        )
        self.assertEqual(
            "/mnt/two  spaces",
            hygiene._decode_mountinfo_path("/mnt/two\\040\\040spaces"),
        )

    def test_mountinfo_decoder_leaves_non_octal_sequences_verbatim(self) -> None:
        self.assertEqual("/plain/path", hygiene._decode_mountinfo_path("/plain/path"))
        # "8" is not an octal digit, so the sequence is not an escape.
        self.assertEqual("/mnt/x\\81a", hygiene._decode_mountinfo_path("/mnt/x\\81a"))
        # Truncated escape at end of string stays verbatim.
        self.assertEqual("/mnt/x\\04", hygiene._decode_mountinfo_path("/mnt/x\\04"))

    def test_nested_non_git_vcs_marker_is_flagged_and_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            target = (Path(temporary) / "target").resolve()
            nested = target / "vendored"
            (nested / ".hg").mkdir(parents=True)
            repositories, errors = hygiene.discover_current_repositories(
                target, target
            )
            self.assertIn(nested, repositories)
            self.assertIn(
                f"{nested}: non-Git VCS state is not independently verified", errors
            )
            self.assertEqual(
                "vcs-state-unverified", hygiene.tracked_blocker(target, target)
            )

    def test_enclosing_non_git_vcs_marker_is_flagged(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = (Path(temporary) / "checkout").resolve()
            inner = root / "inner"
            (root / ".svn").mkdir(parents=True)
            inner.mkdir()
            _, errors = hygiene.discover_current_repositories(root, inner)
            self.assertIn(
                f"{root}: non-Git VCS state is not independently verified", errors
            )

    def test_casefolded_non_git_marker_is_still_flagged(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            target = (Path(temporary) / "target").resolve()
            nested = target / "vendored"
            (nested / ".SVN").mkdir(parents=True)
            repositories, errors = hygiene.discover_current_repositories(
                target, target
            )
            self.assertIn(nested, repositories)
            self.assertIn(
                f"{nested}: non-Git VCS state is not independently verified", errors
            )


class TargetRootIdentityTests(unittest.TestCase):
    """The anchored target root is object identity, not stat identity (#384)."""

    def setUp(self) -> None:
        patcher = mock.patch.object(hygiene, "standing_policy_paths", return_value=[])
        self.addCleanup(patcher.stop)
        patcher.start()

    @staticmethod
    def churned_root_stat(identity: dict[str, object]):
        """The live root after an unrelated write: same object, new mtime/size."""
        return types.SimpleNamespace(
            st_mode=0o040000,
            st_size=int(identity["stat_size"]) + 4096,
            st_mtime_ns=int(identity["mtime_ns"]) + 1_000_000,
            st_dev=identity["device"],
            st_ino=identity["inode"],
        )

    def test_preview_survives_benign_root_churn_between_scan_and_approval(self) -> None:
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
            # An unrelated write into the live target during the approval
            # window flips the root's own mtime and size.
            (root / "unrelated.log").write_text("later work", encoding="utf-8")
            with (
                mock.patch.object(
                    hygiene, "handle_state", return_value=("clear", None)
                ),
                mock.patch.object(hygiene, "tracked_blocker", return_value=None),
                mock.patch.object(hygiene, "execution_blockers", return_value=[]),
            ):
                result = hygiene.preview(snapshot, plan)
            self.assertEqual("ready-for-explicit-approval", result["status"])

    def test_preview_still_refuses_a_replaced_root(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            root.mkdir()
            (root / "orphan.tmp").write_text("temporary", encoding="utf-8")
            snapshot = hygiene.scan_tree(root.resolve(), hygiene.load_policy(None))
            snapshot["target_identity"]["inode"] += 1
            plan = {
                "version": 1,
                "tier": "high",
                "candidates": [candidate("orphan.tmp")],
            }
            with self.assertRaisesRegex(hygiene.HygieneError, "replaced"):
                hygiene.preview(snapshot, plan)

    @staticmethod
    def enter_apply_patches(stack: ExitStack, root_stat) -> None:
        patches = (
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
            mock.patch.object(hygiene, "tracked_blocker", return_value=None),
            mock.patch.object(
                hygiene, "linux_mount_points", return_value=(set(), None)
            ),
            mock.patch.object(hygiene, "handle_state", return_value=("clear", None)),
            mock.patch.object(hygiene.os, "open", return_value=100),
            mock.patch.object(hygiene.os, "fstat", return_value=root_stat),
            mock.patch.object(hygiene.os, "close"),
            mock.patch.object(hygiene.os, "O_DIRECTORY", 0x10000, create=True),
            mock.patch.object(hygiene.os, "O_NOFOLLOW", 0x20000, create=True),
        )
        for patch in patches:
            stack.enter_context(patch)

    def test_apply_survives_benign_root_churn_between_scan_and_approval(self) -> None:
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
            churned = self.churned_root_stat(snapshot["target_identity"])
            with ExitStack() as stack:
                self.enter_apply_patches(stack, churned)
                remove = stack.enter_context(
                    mock.patch.object(hygiene, "anchored_remove")
                )
                report = hygiene.apply_plan(snapshot, plan)
            remove.assert_called_once()
            self.assertEqual("completed", report["status"])
            self.assertEqual(
                ["orphan.tmp"], [item["path"] for item in report["removed"]]
            )

    def test_apply_still_refuses_a_replaced_root(self) -> None:
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
            replaced = self.churned_root_stat(snapshot["target_identity"])
            replaced.st_ino = snapshot["target_identity"]["inode"] + 1
            with ExitStack() as stack:
                self.enter_apply_patches(stack, replaced)
                remove = stack.enter_context(
                    mock.patch.object(hygiene, "anchored_remove")
                )
                with self.assertRaisesRegex(hygiene.HygieneError, "replaced"):
                    hygiene.apply_plan(snapshot, plan)
            remove.assert_not_called()


class HandoffVerifyTests(unittest.TestCase):
    """handoff-verify: read-only manual-lane revalidation (#1109)."""

    def setUp(self) -> None:
        patcher = mock.patch.object(hygiene, "standing_policy_paths", return_value=[])
        self.addCleanup(patcher.stop)
        patcher.start()

    @staticmethod
    def clear_probe_mocks():
        return (
            mock.patch.object(hygiene, "handle_state", return_value=("clear", None)),
            mock.patch.object(hygiene, "tracked_blocker", return_value=None),
        )

    def test_clear_verdict_is_read_only_and_ignores_platform_blockers(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            root.mkdir()
            junk = root / "junk.tmp"
            junk.write_text("stale", encoding="utf-8")
            snapshot = hygiene.scan_tree(root.resolve(), hygiene.load_policy(None))
            handle, vcs = self.clear_probe_mocks()
            with handle, vcs:
                result = hygiene.handoff_verify(snapshot, ["junk.tmp"])
            self.assertEqual("handoff-verify-complete", result["status"])
            self.assertEqual(1, result["clear"])
            self.assertEqual(0, result["not_clear"])
            verdict = result["verdicts"][0]
            self.assertEqual(
                {"path": "junk.tmp", "verdict": "clear", "reasons": []}, verdict
            )
            # Read-only: the path survives, and the platform execution gate
            # (which blocks apply on Windows/macOS) must not appear here.
            self.assertTrue(junk.exists())
            self.assertNotIn("execution-platform-unsupported", verdict["reasons"])

    def test_gone_verdict_for_removed_path(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            root.mkdir()
            junk = root / "junk.tmp"
            junk.write_text("stale", encoding="utf-8")
            snapshot = hygiene.scan_tree(root.resolve(), hygiene.load_policy(None))
            junk.unlink()
            handle, vcs = self.clear_probe_mocks()
            with handle, vcs:
                result = hygiene.handoff_verify(snapshot, ["junk.tmp"])
            self.assertEqual(
                {"path": "junk.tmp", "verdict": "gone", "reasons": ["no-longer-present"]},
                result["verdicts"][0],
            )
            self.assertEqual(1, result["not_clear"])

    def test_drifted_verdict_for_changed_since_approval_content(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            root.mkdir()
            junk = root / "junk.tmp"
            junk.write_text("stale", encoding="utf-8")
            snapshot = hygiene.scan_tree(root.resolve(), hygiene.load_policy(None))
            junk.write_text("rewritten after approval", encoding="utf-8")
            handle, vcs = self.clear_probe_mocks()
            with handle, vcs:
                result = hygiene.handoff_verify(snapshot, ["junk.tmp"])
            verdict = result["verdicts"][0]
            self.assertEqual("drifted", verdict["verdict"])
            self.assertIn("changed-since-scan", verdict["reasons"])

    def test_drifted_verdict_for_new_descendant(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            stale = root / "stale-cache"
            stale.mkdir(parents=True)
            (stale / "old.tmp").write_text("old", encoding="utf-8")
            snapshot = hygiene.scan_tree(root.resolve(), hygiene.load_policy(None))
            (stale / "arrived-later.txt").write_text("new", encoding="utf-8")
            handle, vcs = self.clear_probe_mocks()
            with handle, vcs:
                result = hygiene.handoff_verify(snapshot, ["stale-cache"])
            verdict = result["verdicts"][0]
            self.assertEqual("drifted", verdict["verdict"])
            self.assertIn("changed-since-scan", verdict["reasons"])

    def test_contested_verdict_for_live_handle(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            root.mkdir()
            (root / "busy.tmp").write_text("held", encoding="utf-8")
            snapshot = hygiene.scan_tree(root.resolve(), hygiene.load_policy(None))
            with (
                mock.patch.object(
                    hygiene, "handle_state", return_value=("open", "win32-error-32")
                ),
                mock.patch.object(hygiene, "tracked_blocker", return_value=None),
            ):
                result = hygiene.handoff_verify(snapshot, ["busy.tmp"])
            verdict = result["verdicts"][0]
            self.assertEqual("contested", verdict["verdict"])
            # candidate_handle_state prefixes the relative path on Windows.
            reason = next(
                value
                for value in verdict["reasons"]
                if value.startswith("live-handle")
            )
            self.assertIn("win32-error-32", reason)

    def test_contested_verdict_for_vcs_state(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            root.mkdir()
            (root / "tracked.tmp").write_text("tracked", encoding="utf-8")
            snapshot = hygiene.scan_tree(root.resolve(), hygiene.load_policy(None))
            with (
                mock.patch.object(
                    hygiene, "handle_state", return_value=("clear", None)
                ),
                mock.patch.object(
                    hygiene, "tracked_blocker", return_value="vcs-tracked-content"
                ),
            ):
                result = hygiene.handoff_verify(snapshot, ["tracked.tmp"])
            verdict = result["verdicts"][0]
            self.assertEqual("contested", verdict["verdict"])
            self.assertIn("vcs-tracked-content", verdict["reasons"])

    def test_unverified_handle_fails_closed_as_contested(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            root.mkdir()
            (root / "murky.tmp").write_text("murky", encoding="utf-8")
            snapshot = hygiene.scan_tree(root.resolve(), hygiene.load_policy(None))
            with (
                mock.patch.object(
                    hygiene,
                    "handle_state",
                    return_value=("unverified", "lsof-not-found"),
                ),
                mock.patch.object(hygiene, "tracked_blocker", return_value=None),
            ):
                result = hygiene.handoff_verify(snapshot, ["murky.tmp"])
            verdict = result["verdicts"][0]
            self.assertEqual("contested", verdict["verdict"])
            reason = next(
                value
                for value in verdict["reasons"]
                if value.startswith("handle-state-unverified")
            )
            self.assertIn("lsof-not-found", reason)

    def test_root_metadata_churn_from_prior_deletion_does_not_refuse(self) -> None:
        # The motivating scenario for the tolerant root check: deleting one
        # approved root-level item changes the root's own mtime; the next
        # item's re-verify must still run and verdict cleanly.
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            root.mkdir()
            first = root / "first.tmp"
            second = root / "second.tmp"
            first.write_text("stale", encoding="utf-8")
            second.write_text("stale", encoding="utf-8")
            snapshot = hygiene.scan_tree(root.resolve(), hygiene.load_policy(None))
            first.unlink()  # manual-lane deletion of the prior approved item
            handle, vcs = self.clear_probe_mocks()
            with handle, vcs:
                result = hygiene.handoff_verify(snapshot, ["second.tmp"])
            self.assertEqual(
                {"path": "second.tmp", "verdict": "clear", "reasons": []},
                result["verdicts"][0],
            )

    def test_replaced_root_still_refuses(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            root.mkdir()
            (root / "junk.tmp").write_text("stale", encoding="utf-8")
            snapshot = hygiene.scan_tree(root.resolve(), hygiene.load_policy(None))
            with mock.patch.object(
                hygiene, "same_object_identity", return_value=False
            ):
                with self.assertRaisesRegex(hygiene.HygieneError, "replaced"):
                    hygiene.handoff_verify(snapshot, ["junk.tmp"])

    def test_unstatable_path_maps_permission_to_needs_elevation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            root.mkdir()
            guarded = root / "guarded.tmp"
            guarded.write_text("held", encoding="utf-8")
            snapshot = hygiene.scan_tree(root.resolve(), hygiene.load_policy(None))
            real_lstat = Path.lstat

            def selective_lstat(self: Path):
                if self.name == "guarded.tmp":
                    raise PermissionError(13, "access denied")
                return real_lstat(self)

            handle, vcs = self.clear_probe_mocks()
            with handle, vcs, mock.patch.object(Path, "lstat", selective_lstat):
                result = hygiene.handoff_verify(snapshot, ["guarded.tmp"])
            self.assertEqual(
                {
                    "path": "guarded.tmp",
                    "verdict": "contested",
                    "reasons": ["needs-elevation"],
                },
                result["verdicts"][0],
            )

    def test_unreadable_descendants_are_contested_not_drifted(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            stale = root / "stale-cache"
            stale.mkdir(parents=True)
            (stale / "old.tmp").write_text("old", encoding="utf-8")
            snapshot = hygiene.scan_tree(root.resolve(), hygiene.load_policy(None))
            handle, vcs = self.clear_probe_mocks()
            with (
                handle,
                vcs,
                mock.patch.object(
                    hygiene,
                    "current_descendants",
                    side_effect=PermissionError(13, "access denied"),
                ),
            ):
                result = hygiene.handoff_verify(snapshot, ["stale-cache"])
            verdict = result["verdicts"][0]
            self.assertEqual("contested", verdict["verdict"])
            self.assertIn("needs-elevation", verdict["reasons"])
            self.assertNotIn("changed-since-scan", verdict["reasons"])

    def test_truncated_path_can_never_be_clear(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            deep = root / "outer" / "inner"
            deep.mkdir(parents=True)
            (deep / "leaf.tmp").write_text("deep", encoding="utf-8")
            snapshot = hygiene.scan_tree(
                root.resolve(), hygiene.load_policy(None), 1
            )
            self.assertIn("outer", snapshot["truncated_paths"])
            handle, vcs = self.clear_probe_mocks()
            with handle, vcs:
                result = hygiene.handoff_verify(snapshot, ["outer"])
            verdict = result["verdicts"][0]
            self.assertNotEqual("clear", verdict["verdict"])
            self.assertIn("truncated-not-inventoried", verdict["reasons"])

    def test_vcs_probe_timeout_degrades_to_contested_not_abort(self) -> None:
        # A hung git must not abort the run with zero verdicts: every
        # approved path still gets its verdict, the timed-out one contested.
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            root.mkdir()
            (root / "first.tmp").write_text("stale", encoding="utf-8")
            (root / "second.tmp").write_text("stale", encoding="utf-8")
            snapshot = hygiene.scan_tree(root.resolve(), hygiene.load_policy(None))
            with (
                mock.patch.object(
                    hygiene, "handle_state", return_value=("clear", None)
                ),
                mock.patch.object(
                    hygiene,
                    "tracked_blocker",
                    side_effect=subprocess.TimeoutExpired("git", 20),
                ),
            ):
                result = hygiene.handoff_verify(snapshot, ["first.tmp", "second.tmp"])
            self.assertEqual(2, len(result["verdicts"]))
            for verdict in result["verdicts"]:
                self.assertEqual("contested", verdict["verdict"])
                self.assertIn("vcs-state-unverified", verdict["reasons"])

    def test_denied_descendant_stat_is_contested_not_drifted(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            stale = root / "stale-cache"
            stale.mkdir(parents=True)
            (stale / "sealed.tmp").write_text("sealed", encoding="utf-8")
            snapshot = hygiene.scan_tree(root.resolve(), hygiene.load_policy(None))
            real_lstat = Path.lstat

            def selective_lstat(self: Path):
                if self.name == "sealed.tmp":
                    raise PermissionError(13, "access denied")
                return real_lstat(self)

            handle, vcs = self.clear_probe_mocks()
            with (
                handle,
                vcs,
                mock.patch.object(
                    hygiene,
                    "current_descendants",
                    return_value={"stale-cache", "stale-cache/sealed.tmp"},
                ),
                mock.patch.object(Path, "lstat", selective_lstat),
            ):
                result = hygiene.handoff_verify(snapshot, ["stale-cache"])
            verdict = result["verdicts"][0]
            self.assertEqual("contested", verdict["verdict"])
            self.assertIn("needs-elevation", verdict["reasons"])
            self.assertNotIn("changed-since-scan", verdict["reasons"])

    def test_handle_probe_launch_failure_degrades_to_contested(self) -> None:
        # lsof vanishing between which() and run() (or a ctypes load error)
        # must contest this path, not abort the run with zero verdicts.
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            root.mkdir()
            (root / "first.tmp").write_text("stale", encoding="utf-8")
            (root / "second.tmp").write_text("stale", encoding="utf-8")
            snapshot = hygiene.scan_tree(root.resolve(), hygiene.load_policy(None))
            with (
                mock.patch.object(
                    hygiene,
                    "handle_state",
                    side_effect=FileNotFoundError(2, "lsof vanished"),
                ),
                mock.patch.object(hygiene, "tracked_blocker", return_value=None),
            ):
                result = hygiene.handoff_verify(snapshot, ["first.tmp", "second.tmp"])
            self.assertEqual(2, len(result["verdicts"]))
            for verdict in result["verdicts"]:
                self.assertEqual("contested", verdict["verdict"])
                self.assertIn(
                    "handle-state-unverified: handle-probe-failed",
                    verdict["reasons"],
                )

    def test_validate_handoff_paths_rejects_malformed_input(self) -> None:
        entries = {"keep/junk.tmp": {}, "keep": {}}
        cases = [
            ({"version": 2, "paths": ["keep"]}, "version"),
            ({"version": 1, "paths": []}, "non-empty"),
            ({"version": 1, "paths": ["/absolute"]}, "outside or absent"),
            ({"version": 1, "paths": ["../escape"]}, "outside or absent"),
            ({"version": 1, "paths": ["not-in-snapshot"]}, "outside or absent"),
            ({"version": 1, "paths": ["keep", "keep/junk.tmp"]}, "overlap"),
            ({"version": 1, "paths": ["."]}, "non-root"),
        ]
        for payload, message in cases:
            with self.subTest(payload=payload):
                with self.assertRaisesRegex(hygiene.HygieneError, message):
                    hygiene.validate_handoff_paths(payload, entries)

    def test_handoff_verify_subcommand_exit_codes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "target"
            root.mkdir()
            junk = root / "junk.tmp"
            junk.write_text("stale", encoding="utf-8")
            snapshot = hygiene.scan_tree(root.resolve(), hygiene.load_policy(None))
            snapshot_path = Path(temporary) / "snapshot.json"
            snapshot_path.write_text(json.dumps(snapshot), encoding="utf-8")
            paths_path = Path(temporary) / "handoff-paths.json"
            paths_path.write_text(
                json.dumps({"version": 1, "paths": ["junk.tmp"]}), encoding="utf-8"
            )
            argv = [
                "handoff-verify",
                "--snapshot",
                str(snapshot_path),
                "--paths",
                str(paths_path),
            ]
            handle, vcs = self.clear_probe_mocks()
            output = io.StringIO()
            with handle, vcs, redirect_stdout(output):
                self.assertEqual(0, hygiene.main(argv))
            payload = json.loads(output.getvalue())
            self.assertEqual("handoff-verify-complete", payload["status"])
            self.assertEqual("clear", payload["verdicts"][0]["verdict"])
            junk.write_text("changed after approval", encoding="utf-8")
            handle, vcs = self.clear_probe_mocks()
            output = io.StringIO()
            with handle, vcs, redirect_stdout(output):
                self.assertEqual(3, hygiene.main(argv))
            payload = json.loads(output.getvalue())
            self.assertEqual("drifted", payload["verdicts"][0]["verdict"])
            self.assertTrue(junk.exists())


class _ClosedPipeStderr(io.StringIO):
    """A stderr stand-in whose writes fail the way a lost hook-host pipe does."""

    def write(self, s: str) -> int:
        raise BrokenPipeError(32, "Broken pipe")


class GuardTests(unittest.TestCase):
    @staticmethod
    def python_command() -> str:
        return guard._display_python()

    def setUp(self) -> None:
        # Hermetic kill switch: the guard resolves disk_hygiene_enabled by reading
        # settings.json files. The plain guard helpers patch the guard's own
        # `_resolve_user_settings_path` to our owned settings file directly (absent
        # = enabled default; present-false = audit-only) and stub the managed path
        # to a temp file — so they never touch the developer's real settings and
        # never perturb data-root authority resolution. The engine-gate helper
        # (which must pass --plugin-root to mirror hooks.json) points it at the fake
        # cache layout below, which derives back to the same owned settings.json.
        self._cfg = tempfile.TemporaryDirectory()
        self.addCleanup(self._cfg.cleanup)
        cfg = Path(self._cfg.name)
        self._plugin_root = (
            cfg / "plugins" / "cache" / "melodic-software" / "disk-hygiene" / "1.2.3"
        )
        self._plugin_root.mkdir(parents=True)
        self._settings = cfg / "settings.json"
        # Managed settings stay absent (points into the temp dir, never written),
        # so tests never read a real /etc or Program Files managed-settings.json.
        self._managed = cfg / "managed-settings.json"
        # Hermetic watchdog deadline for the same reason. The guard's own deny
        # diagnostic tells operators to raise
        # DISK_HYGIENE_GUARD_WATCHDOG_SECONDS, so it can legitimately be set in
        # the shell running this suite — and it reaches both the in-process
        # helpers and the ones that spawn the real script, silently rewriting
        # what every default-path assertion observes. Cases that want an
        # override set one explicitly.
        environ_patch = mock.patch.dict(os.environ)
        environ_patch.start()
        self.addCleanup(environ_patch.stop)
        os.environ.pop(guard._WATCHDOG_ENV_VAR, None)

    def _set_kill_switch(self, enabled: bool) -> None:
        if enabled:
            self._settings.unlink(missing_ok=True)
            return
        self._settings.write_text(
            json.dumps(
                {
                    "pluginConfigs": {
                        "disk-hygiene@melodic-software": {
                            "options": {"disk_hygiene_enabled": False}
                        }
                    }
                }
            ),
            encoding="utf-8",
        )

    def _invoke_guard(
        self, command: str, *, tool_name: str = "Bash", enabled: bool = True
    ) -> dict[str, object] | None:
        self._set_kill_switch(enabled)
        argv = [str(SCRIPT_DIR / "destructive_guard.py")]
        payload: dict[str, object] = {"tool_input": {"command": command}}
        if tool_name:
            payload["tool_name"] = tool_name
        stdin = io.StringIO(json.dumps(payload))
        stdout = io.StringIO()
        with (
            mock.patch("sys.stdin", stdin),
            redirect_stdout(stdout),
            mock.patch.object(guard.sys, "argv", argv),
            # Drive the kill switch through the trusted resolver directly (no env,
            # no --plugin-root), so data-root authority resolution is untouched.
            mock.patch.object(
                guard, "_resolve_user_settings_path", lambda: self._settings
            ),
            mock.patch.object(
                guard.killswitch_config,
                "managed_settings_path",
                lambda: self._managed,
            ),
        ):
            self.assertEqual(0, guard.main())
        value = stdout.getvalue()
        return json.loads(value) if value.strip() else None

    def run_guard(self, command: str) -> dict[str, object]:
        result = self._invoke_guard(command, enabled=True)
        assert result is not None
        return result

    def run_guard_disabled(self, command: str) -> dict[str, object]:
        result = self._invoke_guard(command, enabled=False)
        assert result is not None
        return result

    def run_guard_tool(
        self, command: str, tool_name: str, enabled: bool
    ) -> dict[str, object] | None:
        """Drive a specific tool lane with the kill switch set via user settings.

        Post-C′ the switch reaches the guard only by reading ``disk_hygiene_enabled``
        out of the user ``settings.json`` (located from ``--plugin-root``); the old
        ``--disk-hygiene-enabled`` argv and ``CLAUDE_PLUGIN_OPTION_*`` env channels
        are gone. This exercises that one real channel per tool.
        """
        return self._invoke_guard(command, tool_name=tool_name, enabled=enabled)

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

    def test_guard_allows_exact_handoff_verify_shape(self) -> None:
        script = SCRIPT_DIR / "hygiene.py"
        command = (
            f'"{self.python_command()}" "{script}" handoff-verify '
            "--snapshot s --paths p"
        )
        self.assertEqual(
            "allow",
            self.run_guard(command)["hookSpecificOutput"]["permissionDecision"],
        )

    def test_guard_allows_handoff_verify_in_audit_only_mode(self) -> None:
        # handoff-verify is read-only, so the kill switch must not block it —
        # audit-only consumers still get the manual-lane revalidation report.
        script = SCRIPT_DIR / "hygiene.py"
        command = (
            f'"{self.python_command()}" "{script}" handoff-verify '
            "--snapshot s --paths p"
        )
        self.assertEqual(
            "allow",
            self.run_guard_disabled(command)["hookSpecificOutput"][
                "permissionDecision"
            ],
        )

    def test_guard_denies_malformed_handoff_verify_shapes(self) -> None:
        script = SCRIPT_DIR / "hygiene.py"
        prefix = f'"{self.python_command()}" "{script}" handoff-verify'
        commands = [
            f"{prefix} --paths p --snapshot s",  # wrong flag order
            f"{prefix} --snapshot s",  # missing --paths
            f"{prefix} --snapshot s --paths p --report r",  # undeclared flag
            f"{prefix} --snapshot s --paths p extra",  # trailing token
        ]
        for command in commands:
            with self.subTest(command=command):
                self.assertEqual(
                    "deny",
                    self.run_guard(command)["hookSpecificOutput"][
                        "permissionDecision"
                    ],
                )

    def test_guard_allows_exact_kill_switch_probe_invocation(self) -> None:
        probe = SCRIPT_DIR.parent.parent / "setup" / "scripts" / "kill_switch_probe.py"
        command = f'"{self.python_command()}" "{probe}"'
        result = self.run_guard(command)["hookSpecificOutput"]
        self.assertEqual("allow", result["permissionDecision"])

    def test_guard_allows_kill_switch_probe_in_audit_only_mode(self) -> None:
        probe = SCRIPT_DIR.parent.parent / "setup" / "scripts" / "kill_switch_probe.py"
        command = f'"{self.python_command()}" "{probe}"'
        result = self.run_guard_disabled(command)["hookSpecificOutput"]
        self.assertEqual("allow", result["permissionDecision"])

    def test_guard_denies_kill_switch_probe_with_arguments(self) -> None:
        probe = SCRIPT_DIR.parent.parent / "setup" / "scripts" / "kill_switch_probe.py"
        for suffix in (" --settings-file s", " extra"):
            command = f'"{self.python_command()}" "{probe}"{suffix}'
            self.assertEqual(
                "deny",
                self.run_guard(command)["hookSpecificOutput"]["permissionDecision"],
                command,
            )

    def test_guard_denies_kill_switch_probe_via_bare_python(self) -> None:
        probe = SCRIPT_DIR.parent.parent / "setup" / "scripts" / "kill_switch_probe.py"
        result = self.run_guard(f'python "{probe}"')["hookSpecificOutput"]
        self.assertEqual("deny", result["permissionDecision"])

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

    def run_guard_engine_gate(
        self, command: str, tool_name: str = "Bash", enabled: bool = True
    ) -> dict[str, object] | None:
        """Drive the guard as the plugin-level engine-gate deployment would.

        Supplies ``--mode engine-gate`` plus the ``--plugin-root`` and
        ``--authorized-data-root`` substitution channels on argv, mirroring the
        shipped ``hooks/hooks.json`` exec-form registration. ``--plugin-root``
        points at the hermetic fake cache layout so the kill switch resolves from
        the owned settings.json — the sole post-C′ channel — while the explicit
        ``--authorized-data-root`` still drives data-root authority. Returns None
        when the guard deferred with no output.
        """
        self._set_kill_switch(enabled)
        argv = [
            str(SCRIPT_DIR / "destructive_guard.py"),
            "--mode",
            "engine-gate",
            "--plugin-root",
            os.fspath(self._plugin_root),
            "--authorized-data-root",
            str(SCRIPT_DIR / "data-root"),
        ]
        stdin = io.StringIO(
            json.dumps({"tool_name": tool_name, "tool_input": {"command": command}})
        )
        stdout = io.StringIO()
        with (
            mock.patch("sys.stdin", stdin),
            redirect_stdout(stdout),
            mock.patch.object(guard.sys, "argv", argv),
            mock.patch.dict("os.environ", {}, clear=True),
            mock.patch.object(
                guard.killswitch_config,
                "managed_settings_path",
                lambda: self._managed,
            ),
        ):
            self.assertEqual(0, guard.main())
        text = stdout.getvalue().strip()
        return json.loads(text) if text else None

    def test_engine_gate_defers_all_non_engine_commands(self) -> None:
        """Plugin-level deployment must never tax unrelated work in a session."""
        for tool_name, command in (
            ("Bash", "git --version"),
            ("Bash", "rm -rf /tmp/unrelated"),
            ("PowerShell", "Remove-Item -Recurse C:/tmp/unrelated"),
            ("PowerShell", "git status --short"),
        ):
            self.assertIsNone(
                self.run_guard_engine_gate(command, tool_name), (tool_name, command)
            )

    def test_engine_gate_defers_mere_mentions_of_the_engine(self) -> None:
        """Read-only commands that merely NAME the script must defer (P2 review).

        Runs from a neutral cwd: a bare `hygiene.py` mention in a real consumer
        session resolves to nothing (or to the consumer's own file) — resolving
        to the BUNDLED engine (cwd inside the plugin scripts dir) gates by
        identity, deliberately.
        """
        with tempfile.TemporaryDirectory() as tmp, chdir_context(tmp):
            for tool_name, command in (
                ("Bash", "git diff -- hygiene.py"),
                ("Bash", "rg hygiene.py README.md"),
                ("Bash", "echo hygiene.py"),
                ("PowerShell", "Select-String -Pattern guard hygiene.py"),
            ):
                self.assertIsNone(
                    self.run_guard_engine_gate(command, tool_name),
                    (tool_name, command),
                )

    def test_engine_gate_catches_interpreter_options_before_the_script(self) -> None:
        """Interpreter options must not slip the kill switch (P1 review)."""
        script = SCRIPT_DIR / "hygiene.py"
        result = self.run_guard_engine_gate(
            f'/usr/bin/python3 -B "{script}" apply --plan p --token t', "Bash", enabled=False
        )
        assert result is not None
        self.assertEqual("deny", result["hookSpecificOutput"]["permissionDecision"])

    def test_engine_gate_defers_consumer_owned_hygiene_scripts(self) -> None:
        """A different existing file named hygiene.py is not this engine (P2 review)."""
        with tempfile.TemporaryDirectory() as tmp:
            # realpath expands Windows 8.3 short segments (KYLESE~1): the guard
            # rejects `~` anywhere in a Bash command as a shell-expansion
            # character, and this test needs a parseable consumer path.
            consumer = Path(os.path.realpath(tmp)) / "hygiene.py"
            consumer.write_text("print('consumer tool')\n", encoding="utf-8")
            self.assertIsNone(
                self.run_guard_engine_gate(f'python3 "{consumer}" --help')
            )

    def test_engine_gate_defers_files_whose_name_merely_ends_in_the_marker(
        self,
    ) -> None:
        """A DIFFERENT filename containing the marker is not this engine (#1611).

        The gate's own suite lives in `test_hygiene.py`, whose name contains
        `hygiene.py`. A bare-substring marker test read that as an engine
        invocation and denied every Bash command naming it — including the
        command this plugin's contributors run to execute these very tests.
        The parseable path always basename-matched and deferred correctly; the
        operator-carrying path did not, so both shapes are pinned here.
        """
        suite = "plugins/disk-hygiene/skills/clean/scripts/test_hygiene.py"
        for command in (
            f"python3 -m unittest -v {suite}",
            f"cd /repo && python3 -m unittest -v {suite}",
            f"pytest {suite} -k guard",
            "python3 myhygiene.py --help",
        ):
            self.assertIsNone(self.run_guard_engine_gate(command), command)

    def test_engine_gate_still_gates_glued_engine_names(self) -> None:
        """Narrowing to a filename boundary must not open a gluing seam.

        `_carries_marker` tests a token's BASENAME, so whatever produces those
        tokens decides what the gate can still see. Splitting on shell
        metacharacters alone is not enough: an assignment glues the filename to
        its variable with `=`, which is not a metacharacter, so
        `engine=hygiene.py && python3 "$engine" apply` runs the real engine
        while presenting no token whose basename is the marker.
        `_MARKER_TOKEN_SPLIT` therefore keeps only path-legal characters, which
        the marker is itself spelled from — so any glue at all falls away.

        Runs from the scripts dir, where the bare name RESOLVES to the bundled
        engine: that is the shape an evasion actually takes.
        """
        with chdir_context(SCRIPT_DIR):
            for command in (
                'engine=hygiene.py && python3 "$engine" apply --plan p --token t',
                'FOO=1 BAR=hygiene.py python3 "$BAR" apply --plan p --token t',
                'bash -c "engine=hygiene.py; python3 $engine apply"',
                "foo;hygiene.py",
                "python3 foo;hygiene.py",
                "echo $(hygiene.py scan)",
                "true|hygiene.py",
            ):
                result = self.run_guard_engine_gate(command, "Bash", enabled=False)
                assert result is not None, command
                self.assertEqual(
                    "deny",
                    result["hookSpecificOutput"]["permissionDecision"],
                    command,
                )

    def test_engine_gate_catches_engine_across_a_line_continuation(self) -> None:
        """Bash eats `\\`+newline before word splitting; the gate must too.

        Otherwise the continuation stays welded to the filename as
        `hygiene.py\\`, no token's basename is the marker, and a multi-line
        invocation of the real engine slips the kill switch.
        """
        with chdir_context(SCRIPT_DIR):
            for command in (
                "python3 hygiene.py\\\n apply --plan p --token t",
                "python3 hygiene.py\\\r\n apply --plan p --token t",
            ):
                result = self.run_guard_engine_gate(command, "Bash", enabled=False)
                assert result is not None, repr(command)
                self.assertEqual(
                    "deny",
                    result["hookSpecificOutput"]["permissionDecision"],
                    repr(command),
                )

    def test_carries_marker_verdict_does_not_depend_on_the_host_platform(self) -> None:
        """`Path().name` is platform-flavoured; this predicate must not be.

        `PureWindowsPath("/x/hygiene.py\\").name` is `hygiene.py` while
        `PurePosixPath(...)` keeps the backslash, so a `Path`-based basename
        makes the guard gate on Windows and fail open on Linux — a divergence
        that passes on a developer's machine and un-gates CI. Asserted directly
        on the predicate so the case is checked identically on every host.
        """
        for token in (
            "/x/hygiene.py",
            "/x/hygiene.py\\",
            "C:\\x\\hygiene.py",
            "hygiene.py",
        ):
            self.assertTrue(guard._carries_marker(token), token)
        for token in (
            "/x/test_hygiene.py",
            "/x/myhygiene.py",
            "hygiene.pyc",
            "hygiene.py.bak",
        ):
            self.assertFalse(guard._carries_marker(token), token)

    def test_engine_gate_catches_wrapper_launchers_of_the_bundled_engine(self) -> None:
        """env / sh -c wrappers around the absolute engine path must gate (P1 review)."""
        script = SCRIPT_DIR / "hygiene.py"
        wrapped = self.run_guard_engine_gate(
            f'/usr/bin/env "{script}" apply --plan p --token t', "Bash", enabled=False
        )
        assert wrapped is not None
        self.assertEqual("deny", wrapped["hookSpecificOutput"]["permissionDecision"])
        compound = self.run_guard_engine_gate(
            f'sh -c "{script} apply --plan p --token t"', "Bash", enabled=False
        )
        assert compound is not None
        self.assertEqual("deny", compound["hookSpecificOutput"]["permissionDecision"])

    def test_engine_gate_catches_linked_aliases_of_the_bundled_engine(self) -> None:
        """A link to the engine under another name must gate by identity (P1 review)."""
        script = SCRIPT_DIR / "hygiene.py"
        with tempfile.TemporaryDirectory(dir=SCRIPT_DIR) as tmp:
            alias = Path(tmp) / "clean-engine"
            try:
                os.link(script, alias)
            except OSError as exc:  # pragma: no cover - filesystem-dependent
                self.skipTest(f"hard links unavailable here: {exc}")
            posix_alias = str(alias).replace("\\", "/")
            result = self.run_guard_engine_gate(
                f'"{posix_alias}" apply --plan p --token t', "Bash", enabled=False
            )
            assert result is not None
            self.assertEqual(
                "deny", result["hookSpecificOutput"]["permissionDecision"]
            )
            os.unlink(alias)

    def test_engine_gate_catches_alias_beside_shell_operator(self) -> None:
        """A literal alias path gates even in an operator-carrying command (P1 r6)."""
        script = SCRIPT_DIR / "hygiene.py"
        with tempfile.TemporaryDirectory(dir=SCRIPT_DIR) as tmp:
            alias = Path(tmp) / "clean-engine"
            try:
                os.link(script, alias)
            except OSError as exc:  # pragma: no cover - filesystem-dependent
                self.skipTest(f"hard links unavailable here: {exc}")
            posix_alias = str(alias).replace("\\", "/")
            result = self.run_guard_engine_gate(
                f'"{posix_alias}" apply --plan p --token t && true', "Bash", enabled=False
            )
            assert result is not None
            self.assertEqual(
                "deny", result["hookSpecificOutput"]["permissionDecision"]
            )
            os.unlink(alias)

    def test_engine_gate_defers_consumer_windows_path_on_powershell(self) -> None:
        """Backslash consumer paths must defer on PowerShell, not fail closed (P2 r6)."""
        with tempfile.TemporaryDirectory(dir=SCRIPT_DIR) as tmp:
            consumer = Path(tmp) / "hygiene.py"
            consumer.write_text("print('consumer tool')\n", encoding="utf-8")
            windows_path = str(consumer)  # native backslashes on Windows
            if "\\" not in windows_path:
                windows_path = windows_path.replace("/", "\\")
            self.assertIsNone(
                self.run_guard_engine_gate(
                    f"python {windows_path} --help", "PowerShell"
                )
            )

    def test_engine_gate_defers_consumer_script_in_compound_commands(self) -> None:
        """A provably-different hygiene.py defers even beside operators (P2 r7)."""
        with tempfile.TemporaryDirectory(dir=SCRIPT_DIR) as tmp:
            consumer = Path(tmp) / "hygiene.py"
            consumer.write_text("print('consumer tool')\n", encoding="utf-8")
            posix = str(consumer).replace("\\", "/")
            self.assertIsNone(
                self.run_guard_engine_gate(f"python3 {posix} --help && echo done")
            )
            self.assertIsNone(
                self.run_guard_engine_gate(
                    f"python {posix} --help; echo done", "PowerShell"
                )
            )

    def test_engine_gate_still_gates_engine_beside_consumer_decoy(self) -> None:
        """A decoy consumer file must not launder a real engine invocation (r7)."""
        script = SCRIPT_DIR / "hygiene.py"
        with tempfile.TemporaryDirectory(dir=SCRIPT_DIR) as tmp:
            consumer = Path(tmp) / "hygiene.py"
            consumer.write_text("print('consumer tool')\n", encoding="utf-8")
            posix = str(consumer).replace("\\", "/")
            result = self.run_guard_engine_gate(
                f'python3 {posix} --help && python3 "{script}" apply --plan p --token t',
                "Bash",
                enabled=False,
            )
            assert result is not None
            self.assertEqual(
                "deny", result["hookSpecificOutput"]["permissionDecision"]
            )

    def test_engine_gate_catches_path_resolved_engine_after_env_wrapper(self) -> None:
        """env VAR=... hygiene.py must gate as the effective command (P1 r8)."""
        result = self.run_guard_engine_gate(
            f"env PATH={SCRIPT_DIR}:/usr/bin hygiene.py apply --plan p --token t",
            "Bash",
            enabled=False,
        )
        assert result is not None
        self.assertEqual("deny", result["hookSpecificOutput"]["permissionDecision"])

    def test_engine_gate_catches_engine_after_wrapper_with_option_operands(self) -> None:
        """Wrapper option operands must not hide the bare engine name (P1 r9)."""
        result = self.run_guard_engine_gate(
            "env -i PATH=/usr/bin nice -n 10 hygiene.py apply --plan p --token t",
            "Bash",
            enabled=False,
        )
        assert result is not None
        self.assertEqual("deny", result["hookSpecificOutput"]["permissionDecision"])

    def test_engine_gate_catches_non_cpython_launch_of_bundled_engine(self) -> None:
        """A relative bundled-engine path gates under ANY launcher (P1 r10)."""
        with chdir_context(SCRIPT_DIR):
            result = self.run_guard_engine_gate(
                "pypy3 ./hygiene.py apply --plan p --token t", "Bash", enabled=False
            )
        assert result is not None
        self.assertEqual("deny", result["hookSpecificOutput"]["permissionDecision"])

    def test_engine_gate_fails_closed_on_unparsable_marker_commands(self) -> None:
        """Marker + shell operators/expansions the literal parser rejects → gate."""
        result = self.run_guard_engine_gate("python3 hygiene.py scan && echo done")
        assert result is not None
        self.assertEqual("deny", result["hookSpecificOutput"]["permissionDecision"])
        embedded = self.run_guard_engine_gate('bash -c "python3 hygiene.py scan --target t --output s"')
        assert embedded is not None
        self.assertEqual("deny", embedded["hookSpecificOutput"]["permissionDecision"])

    def test_engine_gate_gates_engine_invocations(self) -> None:
        script = SCRIPT_DIR / "hygiene.py"
        powershell = self.run_guard_engine_gate(
            f'& python "{script}" scan --target t --output s', "PowerShell"
        )
        assert powershell is not None
        self.assertEqual(
            "deny", powershell["hookSpecificOutput"]["permissionDecision"]
        )
        malformed = self.run_guard_engine_gate(f'python3 "{script}" apply --oops')
        assert malformed is not None
        self.assertEqual(
            "deny", malformed["hookSpecificOutput"]["permissionDecision"]
        )

    def test_engine_gate_fails_closed_on_engine_when_disabled(self) -> None:
        """Engine-referencing Bash under audit-only mode must deny, never defer.

        The argv kill-switch decision logic itself is proven by
        ``test_kill_switch_blocks_every_lane_via_argv``; this asserts the
        engine-gate mode routes an engine-referencing command into that logic
        instead of deferring past it.
        """
        script = SCRIPT_DIR / "hygiene.py"
        result = self.run_guard_engine_gate(
            f'python3 "{script}" scan --target t --output s', "Bash", enabled=False
        )
        assert result is not None
        self.assertEqual("deny", result["hookSpecificOutput"]["permissionDecision"])

    def run_guard_powershell(self, command: str) -> dict[str, object] | None:
        return self._invoke_guard(command, tool_name="PowerShell", enabled=True)

    def run_guard_powershell_disabled(
        self, command: str
    ) -> dict[str, object] | None:
        return self._invoke_guard(command, tool_name="PowerShell", enabled=False)

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
        """Drive the guard with the data root supplied directly via hook argv.

        Exercises the ``--authorized-data-root`` channel — the direct path a host
        that can substitute ``${CLAUDE_PLUGIN_DATA}`` itself (a plugin ``hooks.json``
        hook) may pass — with CLAUDE_PLUGIN_DATA absent from the process
        environment. The bundled ``clean`` skill instead uses ``--plugin-root``
        (see ``run_guard_plugin_root``), the only substitution a skill hook gets.
        """
        argv = [str(SCRIPT_DIR / "destructive_guard.py")]
        if authorized is not None:
            argv += ["--authorized-data-root", authorized]
        environment = {
            key: value
            for key, value in os.environ.items()
            if key != "CLAUDE_PLUGIN_DATA"
        }
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

    def test_guard_authorizes_preview_data_root_from_hook_argv_without_env(
        self,
    ) -> None:
        script = SCRIPT_DIR / "hygiene.py"
        with tempfile.TemporaryDirectory() as temporary:
            authorized = str(Path(temporary).resolve() / "plugin-data")
            other = str(Path(temporary).resolve() / "elsewhere")
            base = (
                f'"{self.python_command()}" "{script}" preview --snapshot s --plan p'
            )
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

    def test_guard_authorizes_apply_data_root_from_hook_argv_without_env(
        self,
    ) -> None:
        script = SCRIPT_DIR / "hygiene.py"
        with tempfile.TemporaryDirectory() as temporary:
            authorized = str(Path(temporary).resolve() / "plugin-data")
            other = str(Path(temporary).resolve() / "elsewhere")
            base = (
                f'"{self.python_command()}" "{script}" apply --execute --snapshot s '
                f'--plan p --confirm-tier high --approval-token {"a" * 24} --report r'
            )
            self.assertEqual(
                "ask",
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

    def run_guard_plugin_root(
        self, command: str, plugin_root: str
    ) -> dict[str, object]:
        """Drive the guard exactly as the shipped skill hook does.

        The skill-frontmatter hook passes ``--plugin-root ${CLAUDE_PLUGIN_ROOT}``
        (the only substitution a skill hook receives) and nothing else; the guard
        derives the authorized data root from it. CLAUDE_PLUGIN_DATA is absent from
        the process environment, the exact skill-hook condition.
        """
        argv = [str(SCRIPT_DIR / "destructive_guard.py"), "--plugin-root", plugin_root]
        environment = {
            key: value
            for key, value in os.environ.items()
            if key != "CLAUDE_PLUGIN_DATA"
        }
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

    def test_guard_derives_data_root_from_plugin_root_argv(self) -> None:
        script = SCRIPT_DIR / "hygiene.py"
        with tempfile.TemporaryDirectory() as temporary:
            plugins = Path(temporary).resolve() / "plugins"
            # The install root is the version leaf under cache/<mkt>/<name>/.
            plugin_root = plugins / "cache" / "acme" / "disk-hygiene" / "0.4.8"
            plugin_root.mkdir(parents=True)
            authorized = str(plugins / "data" / "disk-hygiene-acme")
            other = str(plugins / "data" / "elsewhere")
            base = f'"{self.python_command()}" "{script}" scan --target t --output s'
            self.assertEqual(
                "allow",
                self.run_guard_plugin_root(
                    f'{base} --data-root "{authorized}"', str(plugin_root)
                )["hookSpecificOutput"]["permissionDecision"],
            )
            self.assertEqual(
                "deny",
                self.run_guard_plugin_root(
                    f'{base} --data-root "{other}"', str(plugin_root)
                )["hookSpecificOutput"]["permissionDecision"],
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
            with mock.patch.object(
                guard.sys,
                "argv",
                [script, "--authorized-data-root", "/data/${weird}/root"],
            ):
                self.assertEqual(
                    "/data/${weird}/root",
                    guard.resolve_authorized_data_root(),
                    "only the exact placeholder is rejected; a real path that merely "
                    "contains ${ must be preserved as the argv authority",
                )

    def test_resolve_authorized_data_root_derives_from_plugin_root(self) -> None:
        script = str(SCRIPT_DIR / "destructive_guard.py")
        plugin_root = os.fspath(
            Path("/x/plugins/cache/acme/disk-hygiene/0.4.8")
        )
        derived = os.fspath(Path("/x/plugins/data/disk-hygiene-acme"))
        environment = {
            key: value
            for key, value in os.environ.items()
            if key != "CLAUDE_PLUGIN_DATA"
        }
        with mock.patch.dict("os.environ", environment, clear=True):
            with mock.patch.object(
                guard.sys, "argv", [script, "--plugin-root", plugin_root]
            ):
                self.assertEqual(derived, guard.resolve_authorized_data_root())
            # A direct --authorized-data-root outranks plugin-root derivation.
            with mock.patch.object(
                guard.sys,
                "argv",
                [script, "--authorized-data-root", "/direct", "--plugin-root", plugin_root],
            ):
                self.assertEqual("/direct", guard.resolve_authorized_data_root())
            # An unresolvable plugin-root layout yields no authority, then env.
            with mock.patch.object(
                guard.sys, "argv", [script, "--plugin-root", "/not/a/plugin/layout"]
            ):
                self.assertIsNone(guard.resolve_authorized_data_root())
        with mock.patch.dict(
            "os.environ", {"CLAUDE_PLUGIN_DATA": "/from-env"}, clear=False
        ):
            with mock.patch.object(
                guard.sys, "argv", [script, "--plugin-root", "/not/a/plugin/layout"]
            ):
                self.assertEqual("/from-env", guard.resolve_authorized_data_root())

    def test_plugin_data_root_from_root_follows_documented_layout(self) -> None:
        # Real marketplace install: the install root is the VERSION leaf under
        # <plugins>/cache/<marketplace>/<name>/<version>; data is <plugins>/data/<id>
        # with <id> the sanitized "<name>@<marketplace>". The version is ignored.
        self.assertEqual(
            os.fspath(Path("/x/plugins/data/disk-hygiene-melodic-software")),
            guard._plugin_data_root_from_root(
                os.fspath(
                    Path("/x/plugins/cache/melodic-software/disk-hygiene/0.4.8")
                )
            ),
        )
        # A directly-linked local install omits the <version> leaf; the name is
        # then the root itself.
        self.assertEqual(
            os.fspath(Path("/x/plugins/data/disk-hygiene-melodic-software")),
            guard._plugin_data_root_from_root(
                os.fspath(Path("/x/plugins/cache/melodic-software/disk-hygiene"))
            ),
        )
        # The "@" separator and every other disallowed character (".") collapse
        # to "-", per the documented id-sanitization rule.
        self.assertEqual(
            os.fspath(Path("/x/plugins/data/my-plugin-my-market")),
            guard._plugin_data_root_from_root(
                os.fspath(Path("/x/plugins/cache/my.market/my.plugin/1.2.3"))
            ),
        )
        # No <plugins>/cache marker, "cache" not under a "plugins" parent, or no
        # name segment after the marketplace: fail closed.
        for stray in (
            "/somewhere/else/plugin",
            "/a/b",
            "/x/store/cache/m/n",
            "/x/plugins/cache/only-marketplace",
        ):
            self.assertIsNone(
                guard._plugin_data_root_from_root(os.fspath(Path(stray))), stray
            )

    def test_argv_flag_value_parses_both_arg_spellings(self) -> None:
        self.assertEqual(
            "false",
            guard._argv_flag_value(["--disk-hygiene-enabled", "false"], "--disk-hygiene-enabled"),
        )
        self.assertEqual(
            "false",
            guard._argv_flag_value(["--disk-hygiene-enabled=false"], "--disk-hygiene-enabled"),
        )
        self.assertIsNone(
            guard._argv_flag_value(["--other", "false"], "--disk-hygiene-enabled")
        )
        self.assertIsNone(
            guard._argv_flag_value(["--disk-hygiene-enabled"], "--disk-hygiene-enabled")
        )

    @staticmethod
    def _skill_hook_command_and_args() -> tuple[str, list[str]]:
        """Return the frontmatter guard hook's `command` and parsed `args`."""
        text = (SCRIPT_DIR.parent / "SKILL.md").read_text(encoding="utf-8")
        args_line = next(
            line
            for line in text.splitlines()
            if "destructive_guard.py" in line and "args:" in line
        )
        args = json.loads(args_line[args_line.index("[") : args_line.rindex("]") + 1])
        command_line = next(
            line
            for line in text.splitlines()
            if line.strip().startswith("command:")
        )
        command = command_line.split(":", 1)[1].strip().strip('"')
        return command, args

    def test_skill_hook_args_launch_with_only_skill_available_substitutions(
        self,
    ) -> None:
        """Guard the guard's launch: the hook must reference only skill-available tokens.

        Claude Code refuses to launch a skill-frontmatter hook whose command or
        args reference any substitution token it does not provide to skill hooks,
        and treats that refusal as a non-blocking error — so the destructive-action
        guard silently never runs. Empirically the only token available to a skill
        hook is `${CLAUDE_PLUGIN_ROOT}`: `${CLAUDE_PLUGIN_DATA}` is plugin-only and
        `${user_config.*}` is not substituted for skill hooks, and either one
        reintroduces the fail-open. This asserts the declared tokens are within that
        allowlist; that the hook then launches is only fully verifiable in a live
        Claude Code session with the plugin installed.
        """
        command, args = self._skill_hook_command_and_args()
        tokens = set(re.findall(r"\$\{[^}]+\}", command))
        for value in args:
            tokens.update(re.findall(r"\$\{[^}]+\}", value))
        allowed = {"${CLAUDE_PLUGIN_ROOT}"}
        self.assertLessEqual(
            tokens,
            allowed,
            "skill-hook command/args reference tokens Claude Code does not "
            f"substitute for skill hooks: {sorted(tokens - allowed)}",
        )

    def test_skill_hook_passes_plugin_root_flag_matching_constant(self) -> None:
        """Lock the config<->code seam the data-root derivation depends on.

        The frontmatter hook must pass the exact flag literal the guard parses,
        immediately followed by the ${CLAUDE_PLUGIN_ROOT} token from which the
        guard derives the authorized data root. If either side is renamed without
        the other, the guard loses its authority and the engine lane fails closed —
        the regression this test guards.
        """
        _command, args = self._skill_hook_command_and_args()
        self.assertTrue(args[0].endswith("destructive_guard.py"), args)
        self.assertIn(guard._PLUGIN_ROOT_FLAG, args)
        flag_index = args.index(guard._PLUGIN_ROOT_FLAG)
        self.assertEqual(guard._PLUGIN_ROOT_PLACEHOLDER, args[flag_index + 1])

    @staticmethod
    def _engine_gate_hook_args() -> list[str]:
        """Return the plugin-level engine-gate hook's `args` from hooks.json."""
        hooks_path = SCRIPT_DIR.parents[2] / "hooks" / "hooks.json"
        config = json.loads(hooks_path.read_text(encoding="utf-8"))
        entries = config["hooks"]["PreToolUse"]
        commands = [
            hook
            for entry in entries
            for hook in entry.get("hooks", [])
            if hook.get("args")
            and any("destructive_guard.py" in arg for arg in hook["args"])
        ]
        assert len(commands) == 1, commands
        return commands[0]["args"]

    def test_engine_gate_hook_resolves_kill_switch_from_plugin_root_not_user_config(
        self,
    ) -> None:
        """Lock the engine-gate hook seam the kill-switch read now depends on.

        Post-C′ the plugin-level gate resolves ``disk_hygiene_enabled`` by reading
        user settings located from ``--plugin-root ${CLAUDE_PLUGIN_ROOT}`` — so that
        flag/token pair is load-bearing for the kill switch, not only the data root.
        And the bare ``${user_config.disk_hygiene_enabled}`` argument MUST stay
        removed: an unset-but-defaulted userConfig token drops the whole hook entry
        (the inert-by-default regression this fix closed). This test fails if either
        is reverted in hooks.json.
        """
        args = self._engine_gate_hook_args()
        self.assertIn(guard._PLUGIN_ROOT_FLAG, args)
        flag_index = args.index(guard._PLUGIN_ROOT_FLAG)
        self.assertEqual(guard._PLUGIN_ROOT_PLACEHOLDER, args[flag_index + 1])
        self.assertNotIn("--disk-hygiene-enabled", args)
        for arg in args:
            self.assertNotIn(
                "${user_config.",
                arg,
                "engine-gate hook must carry no ${user_config.*} token — its "
                "unset-default form drops the whole hook entry",
            )

    def test_skill_hook_interpreter_is_python3_and_resolves(self) -> None:
        """Lock the guard's launch interpreter and prove it resolves.

        The PreToolUse hook runs in exec form, so `command` is resolved on PATH
        with no shell. Bare `python` is absent on stock macOS and many Linux
        distros (and a legacy 2.x would crash the guard), which fails the launch
        open — the guard never intercepts. The static half locks the config at
        `python3`. The runtime half is the "interpreter actually resolves" probe:
        it skips where `python3` cannot run — absent from PATH, or resolved to a
        name that will not execute (a Windows App Execution Alias stub resolves
        to a real path yet exits non-zero) — because that is the documented
        residual host gap, not a regression; only a runnable `python3` is
        asserted to be 3.11+.
        """
        skill = SCRIPT_DIR.parent / "SKILL.md"
        command_line = next(
            (
                line
                for line in skill.read_text(encoding="utf-8").splitlines()
                if line.strip().startswith("command:")
            ),
            None,
        )
        self.assertIsNotNone(command_line, "frontmatter hook command line not found")
        assert command_line is not None
        interpreter = command_line.split(":", 1)[1].strip().strip('"')
        self.assertEqual("python3", interpreter)

        resolved = shutil.which(interpreter)
        if resolved is None:
            self.skipTest(f"{interpreter} does not resolve on this host")
        probe = subprocess.run(
            [resolved, "-c", "import sys; print('%d.%d' % sys.version_info[:2])"],
            capture_output=True,
            text=True,
        )
        if probe.returncode != 0 or not probe.stdout.strip():
            self.skipTest(
                f"{interpreter} resolved to a non-runnable interpreter "
                f"({(probe.stderr or probe.stdout).strip()})"
            )
        major, minor = (int(part) for part in probe.stdout.strip().split("."))
        self.assertGreaterEqual((major, minor), (3, 11), probe.stdout)

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

    def test_guard_scan_accepts_single_confirmed_large_scan_flag(self) -> None:
        script = SCRIPT_DIR / "hygiene.py"
        base = f'"{self.python_command()}" "{script}" scan --target t --output s'
        allowed = (
            f"{base} --confirmed-large-scan",
            f"{base} --confirmed-large-scan --max-depth 1",
            f"{base} --max-depth 1 --confirmed-large-scan",
            f"{base} --confirmed-large-scan --policy p",
        )
        denied = (
            f"{base} --confirmed-large-scan --confirmed-large-scan",
            f"{base} --confirmed-large-scan v",
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
            "Clear-RecycleBin -Force",
            "Microsoft.PowerShell.Management\\Clear-RecycleBin -Force",
            "Microsoft.PowerShell.Management\\Remove-Item -Recurse C:/tmp/example",
            "[IO.File]::Delete('C:/tmp/example')",
            "$item.Delete()",
            "(Get-Item C:/tmp/example).Delete()",
            "robocopy C:/src C:/dst /MIR",
            "robocopy C:/src C:/dst /E /PURGE",
            "robocopy C:/src C:/dst /MOV",
            "C:\\Windows\\System32\\robocopy.exe C:\\src C:\\dst /MIR",
            "& 'C:/Windows/System32/robocopy.exe' C:/src C:/dst /PURGE",
            "[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile('x', 'OnlyErrorDialogs', 'SendToRecycleBin')",
        ):
            result = self.run_guard_powershell(command)
            assert result is not None, command
            self.assertEqual(
                "ask",
                result["hookSpecificOutput"]["permissionDecision"],
                command,
            )

    def test_powershell_bare_name_mentions_defer_but_engine_identity_denies(self) -> None:
        """F6 (#1112): mentions defer via the invocation classifier; a command
        whose argument IS the bundled engine still denies — verb names prove
        nothing under alias/function shadowing (review round on this PR)."""
        script = SCRIPT_DIR / "hygiene.py"
        with tempfile.TemporaryDirectory() as tmp, chdir_context(tmp):
            self.assertIsNone(
                self.run_guard_powershell("Select-String -Pattern guard hygiene.py")
            )
        for command in (
            f'Select-String -Pattern "def main" {script}',
            f"Get-Content {script} -TotalCount 5",
        ):
            result = self.run_guard_powershell(command)
            assert result is not None, command
            self.assertEqual(
                "deny", result["hookSpecificOutput"]["permissionDecision"], command
            )

    def test_powershell_engine_invocation_still_denied_after_narrowing(self) -> None:
        script = SCRIPT_DIR / "hygiene.py"
        for command in (
            f'python3 "{script}" scan --target t --output s',
            f'& python "{script}" scan --target t --output s',
        ):
            result = self.run_guard_powershell(command)
            assert result is not None, command
            self.assertEqual(
                "deny", result["hookSpecificOutput"]["permissionDecision"], command
            )

    def test_powershell_read_only_support_work_defers(self) -> None:
        for command in (
            "git status --short",
            "gh pr list --repo owner/repo",
            "Get-ChildItem -Force C:/tmp",
            "Get-Item C:/tmp/example | Select-Object Length",
            "robocopy C:/src C:/dst /E",
            "C:\\Windows\\System32\\robocopy.exe C:\\src C:\\dst /E",
            "Get-Item C:/tmp/example | Select-Object IsDeleted",
        ):
            self.assertIsNone(self.run_guard_powershell(command), command)

    def test_powershell_deletion_spellings_denied_in_audit_only_mode(self) -> None:
        """Kill switch (B2): audit-only mode must deny PowerShell deletions, not ask."""
        for command in (
            "Remove-Item -Recurse -Force C:/tmp/example",
            "rm C:/tmp/example",
            "del C:/tmp/example",
            "Clear-RecycleBin -Force",
            "Microsoft.PowerShell.Management\\Clear-RecycleBin -Force",
            "[IO.File]::Delete('C:/tmp/example')",
            "$item.Delete()",
            "robocopy C:/src C:/dst /MIR",
            "[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile('x', 'OnlyErrorDialogs', 'SendToRecycleBin')",
        ):
            result = self.run_guard_powershell_disabled(command)
            assert result is not None, command
            self.assertEqual(
                "deny",
                result["hookSpecificOutput"]["permissionDecision"],
                command,
            )

    def test_kill_switch_blocks_every_lane_when_configured_false(self) -> None:
        """A configured ``disk_hygiene_enabled=false`` in user settings must block
        deletions on both the PowerShell and Bash lanes. This is the sole delivery
        channel post-C′: the guard reads the toggle out of the user settings file
        it locates from ``--plugin-root``; there is no argv or env channel."""
        script = SCRIPT_DIR / "hygiene.py"
        powershell = self.run_guard_tool(
            "Remove-Item -Recurse -Force C:/tmp/example",
            "PowerShell",
            enabled=False,
        )
        assert powershell is not None
        self.assertEqual(
            "deny", powershell["hookSpecificOutput"]["permissionDecision"]
        )
        apply_command = (
            f'"{self.python_command()}" "{script}" apply --execute --snapshot s '
            f'--plan p --confirm-tier high --approval-token {"a" * 24} --report r'
        )
        bash = self.run_guard_tool(apply_command, "Bash", enabled=False)
        assert bash is not None
        self.assertEqual("deny", bash["hookSpecificOutput"]["permissionDecision"])

    def test_kill_switch_enabled_gates_apply_as_ask(self) -> None:
        """With the switch enabled (settings absent → default on), an ``apply`` is
        gated (``ask``) rather than denied, confirming the resolved toggle — not a
        hardcoded deny — drives the decision."""
        script = SCRIPT_DIR / "hygiene.py"
        apply_command = (
            f'"{self.python_command()}" "{script}" apply --execute --snapshot s '
            f'--plan p --confirm-tier high --approval-token {"a" * 24} --report r'
        )
        result = self.run_guard_tool(apply_command, "Bash", enabled=True)
        assert result is not None
        self.assertEqual("ask", result["hookSpecificOutput"]["permissionDecision"])

    # -- #1423: exit-1 fail-open regression coverage -------------------------
    #
    # Before #1423, only the JSON-payload parse at the top of `main` was
    # wrapped in a try/except; everything after it (the whole decision body,
    # now `_decide`) had no exception handling at all. Any bug, unexpected
    # OSError subtype, or future regression reaching that code would fall
    # through to Python's default unhandled-exception behavior — exit 1 —
    # which PreToolUse treats as a *non-blocking* error: Claude Code proceeds
    # with the destructive command as if the guard had deliberately allowed
    # it. These tests inject real failures into the real call graph (not a
    # rewritten toy) and assert the fail-closed contract: exit 2, a non-empty
    # stderr diagnostic, no stdout JSON, and exit 1 never reachable.

    def _invoke_guard_raw(
        self,
        command: str,
        *,
        tool_name: str = "Bash",
        argv_extra: list[str] | None = None,
        stderr_stream: io.StringIO | None = None,
    ) -> tuple[int, str, str]:
        """Like `_invoke_guard`, but returns (exit_code, stdout, stderr) instead
        of asserting exit 0 — the exit-1/exit-2 regression tests need to see a
        non-zero code and its diagnostic, not just the decision JSON.

        `stderr_stream` substitutes the capture buffer, so a test can hand the
        guard a stream whose writes fail the way a closed hook-host pipe does.
        """
        self._set_kill_switch(True)
        argv = [str(SCRIPT_DIR / "destructive_guard.py"), *(argv_extra or [])]
        payload: dict[str, object] = {"tool_input": {"command": command}}
        if tool_name:
            payload["tool_name"] = tool_name
        stdin = io.StringIO(json.dumps(payload))
        stdout = io.StringIO()
        stderr = stderr_stream if stderr_stream is not None else io.StringIO()
        with (
            mock.patch("sys.stdin", stdin),
            redirect_stdout(stdout),
            redirect_stderr(stderr),
            mock.patch.object(guard.sys, "argv", argv),
            mock.patch.object(
                guard, "_resolve_user_settings_path", lambda: self._settings
            ),
            mock.patch.object(
                guard.killswitch_config,
                "managed_settings_path",
                lambda: self._managed,
            ),
        ):
            exit_code = guard.main()
        return exit_code, stdout.getvalue(), stderr.getvalue()

    def test_internal_failure_in_decide_exits_2_with_diagnostic_not_1(self) -> None:
        """AC 3 (core case): an injected internal failure denies at exit 2."""
        with mock.patch.object(
            guard,
            "_decide",
            side_effect=RuntimeError("injected failure for #1423 regression"),
        ):
            exit_code, stdout, stderr = self._invoke_guard_raw("rm -rf /tmp/example")
        self.assertEqual(2, exit_code)
        self.assertNotEqual(1, exit_code)
        self.assertTrue(stderr.strip(), "exit 2 must carry a stderr diagnostic")
        self.assertIn("injected failure", stderr)
        self.assertEqual(
            "", stdout, "exit 2 must not also emit stdout JSON (Claude Code ignores it)"
        )

    def test_every_call_graph_function_failure_denies_at_exit_2_never_1(self) -> None:
        """Sweep AC 3 across the real functions `_decide` calls, not one mock.

        Each of these is reachable from a real, gate-relevant Bash command in
        belt mode (the default — no ``--mode`` argv), so this exercises the
        actual wiring, not a synthetic stand-in.
        """
        script = SCRIPT_DIR / "hygiene.py"
        apply_command = (
            f'"{self.python_command()}" "{script}" apply --execute --snapshot s '
            f'--plan p --confirm-tier high --approval-token {"a" * 24} --report r'
        )
        targets = [
            "resolve_mode",
            "resolve_disk_hygiene_enabled",
            "resolve_authorized_data_root",
            "is_exact_kill_switch_probe",
            "classify_exact_engine_command",
        ]
        for target in targets:
            with self.subTest(target=target):
                with mock.patch.object(
                    guard, target, side_effect=ValueError(f"injected {target} failure")
                ):
                    exit_code, stdout, stderr = self._invoke_guard_raw(apply_command)
                self.assertEqual(2, exit_code, target)
                self.assertNotEqual(1, exit_code, target)
                self.assertTrue(stderr.strip(), target)
                self.assertEqual("", stdout, target)

    def test_engine_gate_relevance_check_failure_denies_at_exit_2_never_1(self) -> None:
        """The plugin-level engine-gate's own relevance check is in-scope too.

        ``_engine_gate_relevant`` only runs in ``--mode engine-gate`` (the
        plugin-level ``hooks/hooks.json`` registration), and only once
        ``resolve_mode`` has legitimately resolved to that mode — this is the
        function identified in the module's #1423 investigation note as the
        strongest candidate for the observed stall (it stats every
        separator-containing word of *every* Bash/PowerShell command in
        *every* session), so its failure path is covered explicitly.
        """
        script = SCRIPT_DIR / "hygiene.py"
        apply_command = (
            f'"{self.python_command()}" "{script}" apply --execute --snapshot s '
            f'--plan p --confirm-tier high --approval-token {"a" * 24} --report r'
        )
        with mock.patch.object(
            guard,
            "_engine_gate_relevant",
            side_effect=ValueError("injected _engine_gate_relevant failure"),
        ):
            exit_code, stdout, stderr = self._invoke_guard_raw(
                apply_command, argv_extra=["--mode", "engine-gate"]
            )
        self.assertEqual(2, exit_code)
        self.assertNotEqual(1, exit_code)
        self.assertTrue(stderr.strip())
        self.assertEqual("", stdout)

    def test_powershell_lane_failure_denies_at_exit_2_never_1(self) -> None:
        """The PowerShell decision branch is a separate code path from Bash."""
        with mock.patch.object(
            guard,
            "powershell_decision",
            side_effect=RuntimeError("injected powershell_decision failure"),
        ):
            exit_code, stdout, stderr = self._invoke_guard_raw(
                "Remove-Item -Recurse -Force C:/tmp/example", tool_name="PowerShell"
            )
        self.assertEqual(2, exit_code)
        self.assertNotEqual(1, exit_code)
        self.assertTrue(stderr.strip())
        self.assertEqual("", stdout)

    def test_keyboard_interrupt_mid_decision_denies_at_exit_2_never_1(self) -> None:
        """A ``KeyboardInterrupt`` (or any BaseException) mid-decision is not a
        deliberate, reasoned allow — it must deny too, not propagate."""
        with mock.patch.object(
            guard, "_decide", side_effect=KeyboardInterrupt
        ):
            exit_code, stdout, stderr = self._invoke_guard_raw("rm -rf /tmp/example")
        self.assertEqual(2, exit_code)
        self.assertNotEqual(1, exit_code)
        self.assertTrue(stderr.strip())
        self.assertEqual("", stdout)

    # -- #1423: internal watchdog -------------------------------------------

    def test_watchdog_seconds_resolves_default_and_validates_override(self) -> None:
        self.assertEqual(guard._WATCHDOG_DEFAULT_SECONDS, guard._watchdog_seconds())
        with mock.patch.dict(os.environ, {guard._WATCHDOG_ENV_VAR: "5"}):
            self.assertEqual(5.0, guard._watchdog_seconds())
        for invalid in ("not-a-number", "-3", "0", ""):
            with self.subTest(invalid=invalid):
                with mock.patch.dict(os.environ, {guard._WATCHDOG_ENV_VAR: invalid}):
                    self.assertEqual(
                        guard._WATCHDOG_DEFAULT_SECONDS, guard._watchdog_seconds()
                    )

    def test_watchdog_seconds_rejects_non_finite_overrides(self) -> None:
        """Non-finite overrides must fall back, not disarm the watchdog.

        `inf` parses through `float` and passes a bare `> 0` test, but
        `threading.Timer(inf, ...)` accepts `start()` and then dies in the
        timer thread with `OverflowError` — silently removing the watchdog on
        a fail-closed guard. `nan` fails `> 0` already; asserted here so the
        whole non-finite class is pinned by test, not by luck.
        """
        for raw in ("inf", "-inf", "Infinity", "nan", "1e400"):
            with self.subTest(raw=raw):
                with mock.patch.dict(os.environ, {guard._WATCHDOG_ENV_VAR: raw}):
                    resolved = guard._watchdog_seconds()
                self.assertEqual(guard._WATCHDOG_DEFAULT_SECONDS, resolved)
                self.assertTrue(math.isfinite(resolved))

    def test_watchdog_seconds_clamps_overrides_below_the_hook_timeout(self) -> None:
        """An override must never outlive the harness deadline it sits under.

        The watchdog is the primary mechanism and the declared hook `timeout`
        is the backstop, which only holds while the watchdog fires first. An
        override at or above the hook timeout inverts that: the harness kills
        the process instead, and a killed PreToolUse hook yields no
        `permissionDecision`, so the guarded command proceeds unguarded.
        """
        self.assertLess(
            guard._WATCHDOG_MAX_SECONDS, guard._DECLARED_HOOK_TIMEOUT_SECONDS
        )
        self.assertLess(guard._WATCHDOG_DEFAULT_SECONDS, guard._WATCHDOG_MAX_SECONDS)
        for raw in ("50", "60", "600", "1e300"):
            with self.subTest(raw=raw):
                with mock.patch.dict(os.environ, {guard._WATCHDOG_ENV_VAR: raw}):
                    resolved = guard._watchdog_seconds()
                self.assertEqual(guard._WATCHDOG_MAX_SECONDS, resolved)
                self.assertLess(resolved, guard._DECLARED_HOOK_TIMEOUT_SECONDS)
        # An override under the ceiling is still honoured verbatim.
        with mock.patch.dict(os.environ, {guard._WATCHDOG_ENV_VAR: "30"}):
            self.assertEqual(30.0, guard._watchdog_seconds())

    def test_declared_hook_timeouts_match_the_watchdog_ceiling(self) -> None:
        """Lock the config<->code seam the clamp is derived from.

        `_WATCHDOG_MAX_SECONDS` is computed from a copy of the registrations'
        `timeout`, because a PreToolUse payload does not carry the hook's own
        timeout and the guard cannot read it at runtime. Lowering either
        registration without lowering the constant would let a clamped
        override still outrun the harness — the fail-open the clamp closes.
        """
        hooks_path = SCRIPT_DIR.parents[2] / "hooks" / "hooks.json"
        config = json.loads(hooks_path.read_text(encoding="utf-8"))
        declared = [
            hook.get("timeout")
            for entry in config["hooks"]["PreToolUse"]
            for hook in entry.get("hooks", [])
            if hook.get("args")
            and any("destructive_guard.py" in arg for arg in hook["args"])
        ]
        self.assertEqual([guard._DECLARED_HOOK_TIMEOUT_SECONDS], declared)

        skill_text = (SCRIPT_DIR.parent / "SKILL.md").read_text(encoding="utf-8")
        timeout_lines = [
            line
            for line in skill_text.splitlines()
            if line.strip().startswith("timeout:")
        ]
        self.assertEqual(1, len(timeout_lines), timeout_lines)
        self.assertEqual(
            guard._DECLARED_HOOK_TIMEOUT_SECONDS,
            float(timeout_lines[0].split(":", 1)[1].strip()),
        )

    def test_main_denies_at_exit_2_when_watchdog_cannot_be_constructed(self) -> None:
        """Timer construction is inside the fail-closed boundary.

        Under OS thread/memory exhaustion `threading.Timer(...)` raises before
        `_decide` is ever reached; from outside the `try` that would reach the
        interpreter default (exit 1, non-blocking, destructive command runs).
        """
        with mock.patch.object(
            guard.threading, "Timer", side_effect=RuntimeError("can't start new thread")
        ):
            exit_code, stdout, stderr = self._invoke_guard_raw("rm -rf /tmp/example")
        self.assertEqual(2, exit_code)
        self.assertNotEqual(1, exit_code)
        self.assertTrue(stderr.strip())
        self.assertEqual("", stdout)

    def test_main_denies_at_exit_2_when_watchdog_thread_cannot_start(self) -> None:
        """`.start()` failing is the same fail-closed case as construction
        failing — the guard could not arm its own deadline, so it denies."""
        fake_timer = mock.Mock()
        fake_timer.start.side_effect = RuntimeError("can't start new thread")
        with mock.patch.object(guard.threading, "Timer", return_value=fake_timer):
            exit_code, stdout, stderr = self._invoke_guard_raw("rm -rf /tmp/example")
        self.assertEqual(2, exit_code)
        self.assertNotEqual(1, exit_code)
        self.assertTrue(stderr.strip())
        self.assertEqual("", stdout)
        fake_timer.cancel.assert_called_once()

    def test_main_denies_at_exit_2_when_the_diagnostic_write_fails(self) -> None:
        """A failed diagnostic write must not cost the deny.

        The deny is carried by the exit code; the stderr line only explains it.
        If the hook host has closed or lost the stderr pipe, the `print` inside
        the fail-closed handler raises `BrokenPipeError` and — unsuppressed —
        escapes before `return 2` runs, so the process exits with a status
        PreToolUse treats as non-blocking and the destructive command proceeds
        ungated: the exact fail-open this handler exists to close, reintroduced
        by its own diagnostic.
        """
        with mock.patch.object(
            guard, "_decide", side_effect=RuntimeError("injected failure")
        ):
            exit_code, stdout, _stderr = self._invoke_guard_raw(
                "rm -rf /tmp/example", stderr_stream=_ClosedPipeStderr()
            )
        self.assertEqual(2, exit_code)
        self.assertNotEqual(1, exit_code)
        self.assertEqual("", stdout)

    def test_watchdog_fire_hard_exits_2_when_the_diagnostic_write_fails(self) -> None:
        """Same protection on the timer thread, where the write would preempt
        `os._exit(2)` — and an exception on a background thread never reaches
        `main`'s exit-2 boundary at all, so the process would run on undenied."""
        with (
            mock.patch.object(guard.os, "_exit") as fake_exit,
            redirect_stderr(_ClosedPipeStderr()),
        ):
            guard._watchdog_fire(1.0)
        fake_exit.assert_called_once_with(2)

    def test_undeliverable_stdout_decision_denies_at_exit_2_in_a_real_process(
        self,
    ) -> None:
        """A decision the host never received must deny, not exit 0 or 120.

        The sibling cases above cover a broken *stderr*. Broken *stdout* is the
        other half and cannot be observed in-process: `_decide`'s decision
        `print` only buffers, so a closed stdout pipe raises nowhere inside
        `main` — it surfaces at interpreter shutdown, which CPython reports by
        replacing the exit status with 120. Non-blocking under the PreToolUse
        contract, so the destructive command runs even though the guard had
        decided to deny it. Only a real process with a real closed pipe shows
        this; against the pre-fix module tail it exits 120.
        """
        env = dict(os.environ)
        # Inherited unbuffered mode would make the decision `print` raise inside
        # `main`, denying at exit 2 by the generic internal-error path and never
        # reaching the shutdown-flush handler under test. Dropped so the child's
        # buffering never depends on how the suite itself was invoked.
        env.pop("PYTHONUNBUFFERED", None)
        read_fd, write_fd = os.pipe()
        os.close(read_fd)
        try:
            proc = subprocess.Popen(
                [self.python_command(), str(SCRIPT_DIR / "destructive_guard.py")],
                stdin=subprocess.PIPE,
                stdout=write_fd,
                stderr=subprocess.PIPE,
                text=True,
                env=env,
            )
        finally:
            os.close(write_fd)
        with proc:
            proc.stdin.write(
                json.dumps(
                    {"tool_name": "Bash", "tool_input": {"command": "rm -rf /tmp/x"}}
                )
            )
            proc.stdin.close()
            proc.wait(timeout=30)
            stderr = proc.stderr.read()
        self.assertEqual(2, proc.returncode)
        self.assertNotEqual(120, proc.returncode)
        self.assertIn("could not be written to stdout", stderr)

    def test_stderr_fd_closed_outright_still_denies_at_exit_2_in_a_real_process(
        self,
    ) -> None:
        """#1526's literal trigger: fd 2 *closed*, not merely broken.

        `_write_diagnostic`'s fallback (`_discard_stream`) opens the null
        device and `dup2`s it onto the broken fd. When fd 2 is closed
        outright rather than left open with a dead reader, `os.open` can
        return fd 2 itself (POSIX allocates the lowest free descriptor),
        making the `dup2` a no-op -- and the `finally: os.close(null_fd)`
        that follows then re-closes fd 2, undoing the very repair it just
        made. Against the pre-#1524 module tail (`raise SystemExit(main())`),
        the interpreter's own shutdown flush then hits that closed fd and
        CPython rewrites the exit status to 120: non-blocking under
        PreToolUse, so the destructive command would run even though the
        guard had decided to deny it (#1526, reproduced against merged
        `efb6c271`).

        This module's tail no longer depends on `_discard_stream` actually
        repairing the fd for the exit code to survive: every path now ends in
        `os._exit`, which skips the interpreter's normal shutdown flush --
        the mechanism `120` comes from -- entirely. So the #1526 trigger is
        closed as a structural side effect of the #1524 fix, not by touching
        `_discard_stream` itself (which still has the self-undoing dup2/close
        pattern described above; nothing downstream depends on it working).
        """
        env = dict(os.environ)
        script = str(SCRIPT_DIR / "destructive_guard.py")
        # Runs *inside* the subprocess: close fd 2 outright (not merely break
        # its reader) before the guard module executes, then run it as
        # `__main__` so the module tail under test actually runs.
        child = "\n".join(
            [
                "import os, runpy, sys",
                "os.close(2)",
                f"sys.argv = [{script!r}]",
                "runpy.run_path(sys.argv[0], run_name='__main__')",
            ]
        )
        proc = subprocess.Popen(
            [self.python_command(), "-c", child],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
        )
        # A JSON array, not an object: `payload.get(...)` raises
        # `AttributeError`, which main()'s inner
        # `except (KeyError, TypeError, ValueError, json.JSONDecodeError)`
        # does not catch -- it reaches the outer `except BaseException`,
        # which is the exit-2 diagnostic path `_write_diagnostic` (and so
        # `_discard_stream`) sits on.
        out, _err = proc.communicate(input=json.dumps([]), timeout=30)
        self.assertEqual(2, proc.returncode)
        self.assertNotEqual(120, proc.returncode)
        self.assertEqual("", out)

    def test_main_arms_watchdog_at_resolved_deadline_and_cancels_on_return(
        self,
    ) -> None:
        """Wiring check, no real thread: `main` must arm a `Timer` at the
        resolved deadline before calling `_decide`, and cancel it once
        `_decide` returns normally — a real watchdog thread firing here would
        `os._exit` the test runner, so this substitutes a mock `Timer`.

        Asserts the DEFAULT deadline specifically, so it must not observe an
        operator's `DISK_HYGIENE_GUARD_WATCHDOG_SECONDS` override leaking in
        from the test process's real environment — that would assert the
        override's value instead and fail on an otherwise-correct guard.
        """
        fake_timer = mock.Mock()
        with (
            mock.patch.dict(os.environ, {}, clear=False) as patched_environ,
            mock.patch.object(
                guard.threading, "Timer", return_value=fake_timer
            ) as timer_cls,
        ):
            patched_environ.pop(guard._WATCHDOG_ENV_VAR, None)
            exit_code, _stdout, _stderr = self._invoke_guard_raw("rm -rf /tmp/example")
        self.assertEqual(0, exit_code)
        timer_cls.assert_called_once_with(
            guard._WATCHDOG_DEFAULT_SECONDS,
            guard._watchdog_fire,
            args=(guard._WATCHDOG_DEFAULT_SECONDS,),
        )
        self.assertTrue(fake_timer.daemon)
        fake_timer.start.assert_called_once()
        fake_timer.cancel.assert_called_once()

    def test_main_arms_watchdog_before_reading_stdin(self) -> None:
        """The watchdog must start before `json.load(sys.stdin)`, not after.

        `json.load(sys.stdin)` blocks through EOF, and a Windows Win32 pipe
        can deliver the complete JSON payload but delay the EOF signal — a
        late-EOF stall with nothing armed to bound it would run past the
        declared hook `timeout` toward the harness's own non-blocking kill,
        the same shape #1423 exists to close. Wiring check via a mocked
        `Timer`, no real stdin stall or timer thread — the invariant is
        asserted from inside the read spy itself (not derived from a
        call-order list after the fact), so a future second `json.load` call
        earlier in the path could not silently satisfy it.
        `test_stdin_stall_denies_at_exit_2_via_real_watchdog` below proves the
        actual outcome (a real stalled read really exits 2) that this wiring
        check cannot.
        """
        fake_timer = mock.Mock()
        real_load = guard.json.load

        def _spy_load(*args: object, **kwargs: object) -> object:
            self.assertTrue(
                fake_timer.start.called,
                "watchdog must already be armed before the stdin read begins",
            )
            return real_load(*args, **kwargs)

        with (
            mock.patch.object(guard.threading, "Timer", return_value=fake_timer),
            mock.patch.object(guard.json, "load", side_effect=_spy_load),
        ):
            exit_code, _stdout, _stderr = self._invoke_guard_raw("rm -rf /tmp/example")
        self.assertEqual(0, exit_code)
        fake_timer.start.assert_called_once()

    def test_stdin_stall_denies_at_exit_2_via_real_watchdog(self) -> None:
        """Prove the OUTCOME on a real stalled stdin read, not just wiring order.

        Spawns the real script (mirroring
        `test_watchdog_fire_hard_exits_2_with_diagnostic_never_1`'s
        real-subprocess approach) with stdin opened as a pipe that is never
        written to or closed — the general "blocked in read" shape a Windows
        Win32-pipe late EOF produces, and one this test's host (whatever CI
        runs it on) can reproduce without needing an actual Win32 pipe. This
        fails against the pre-fix ordering (watchdog armed only after the
        stdin read returned): that code would hang past the deadline instead
        of denying, which
        `test_main_arms_watchdog_before_reading_stdin`'s mocked `Timer` can
        never demonstrate.
        """
        env = dict(os.environ)
        env[guard._WATCHDOG_ENV_VAR] = "1"
        with subprocess.Popen(
            [self.python_command(), str(SCRIPT_DIR / "destructive_guard.py")],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
        ) as proc:
            try:
                proc.wait(timeout=20)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
                self.fail(
                    "guard did not exit within the watchdog deadline on a "
                    "stalled stdin read — the pre-fix fail-open regression"
                )
            stdout = proc.stdout.read()
            stderr = proc.stderr.read()
        self.assertEqual(2, proc.returncode)
        self.assertNotEqual(1, proc.returncode)
        self.assertIn("internal deadline", stderr)
        self.assertEqual("", stdout)

    def test_main_cancels_watchdog_even_when_decide_raises(self) -> None:
        """The `finally` must cancel the timer on the exit-2 path too, so a
        `_decide` exception never leaves a stray timer thread behind."""
        fake_timer = mock.Mock()
        with (
            mock.patch.object(guard.threading, "Timer", return_value=fake_timer),
            mock.patch.object(guard, "_decide", side_effect=RuntimeError("boom")),
        ):
            exit_code, _stdout, _stderr = self._invoke_guard_raw("rm -rf /tmp/example")
        self.assertEqual(2, exit_code)
        fake_timer.cancel.assert_called_once()

    def test_watchdog_fire_hard_exits_2_with_diagnostic_never_1(self) -> None:
        """The watchdog callback's own contract, exercised in a real subprocess.

        `_watchdog_fire` calls `os._exit`, a hard process exit that must never
        be allowed to run in the test-runner process itself — a subprocess we
        spawned specifically for this is the only safe way to observe it.
        """
        completed = subprocess.run(
            [
                self.python_command(),
                "-c",
                "import sys; sys.path.insert(0, sys.argv[1]); "
                "import destructive_guard as guard; guard._watchdog_fire(1.5)",
                str(SCRIPT_DIR),
            ],
            capture_output=True,
            text=True,
            timeout=15,
        )
        self.assertEqual(2, completed.returncode)
        self.assertNotEqual(1, completed.returncode)
        self.assertTrue(completed.stderr.strip())
        self.assertIn("1.5", completed.stderr)


class DirectReadKillSwitchTests(unittest.TestCase):
    """The kill switch resolves by reading user-scope pluginConfigs directly.

    Post-C′ the guard ignores the ``--disk-hygiene-enabled`` argv flag and the
    ``CLAUDE_PLUGIN_OPTION_DISK_HYGIENE_ENABLED`` env var (both repo-tamperable
    or un-delivered) and instead reads ``disk_hygiene_enabled`` out of the
    ``settings.json`` ``pluginConfigs``. The user file is located **solely** from
    the tamper-resistant ``--plugin-root`` (``${CLAUDE_PLUGIN_ROOT}``), never an
    environment value; a managed policy at its fixed system path overrides it, and
    a marker-less (``--plugin-dir``) root leaves no trusted user path. Every
    absent/degraded read fails closed to enabled (safety on).
    """

    SCRIPT = str(SCRIPT_DIR / "destructive_guard.py")

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.config_dir = Path(self.tmp.name)
        # Reconstruct the real install layout so --plugin-root derivation finds
        # the sibling settings.json: <config>/plugins/cache/<mkt>/<name>/<ver>.
        self.plugin_root = (
            self.config_dir
            / "plugins"
            / "cache"
            / "melodic-software"
            / "disk-hygiene"
            / "1.2.3"
        )
        self.plugin_root.mkdir(parents=True)
        self.settings = self.config_dir / "settings.json"
        # Managed settings default to absent; managed tests write this file.
        self.managed = self.config_dir / "managed-settings.json"

    def _toggle_json(self, value: object) -> str:
        return json.dumps(
            {
                "pluginConfigs": {
                    "disk-hygiene@melodic-software": {
                        "options": {"disk_hygiene_enabled": value}
                    }
                }
            }
        )

    def write_toggle(self, value: object) -> None:
        self.settings.write_text(self._toggle_json(value), encoding="utf-8")

    def write_managed_toggle(self, value: object) -> None:
        self.managed.write_text(self._toggle_json(value), encoding="utf-8")

    def write_managed_dropin(self, name: str, value: object) -> None:
        dropin = self.config_dir / "managed-settings.d"
        dropin.mkdir(exist_ok=True)
        (dropin / name).write_text(self._toggle_json(value), encoding="utf-8")

    def resolve(self, argv_tail: list[str], env: dict[str, str]) -> bool:
        with (
            mock.patch.object(guard.sys, "argv", [self.SCRIPT, *argv_tail]),
            mock.patch.dict("os.environ", env, clear=True),
            mock.patch.object(
                guard.killswitch_config,
                "managed_settings_path",
                lambda: self.managed,
            ),
        ):
            return guard.resolve_disk_hygiene_enabled()

    def plugin_root_argv(self) -> list[str]:
        return ["--plugin-root", os.fspath(self.plugin_root)]

    def test_configured_false_via_plugin_root_channel_disables(self) -> None:
        self.write_toggle(False)
        self.assertFalse(self.resolve(self.plugin_root_argv(), {}))

    def test_configured_true_via_plugin_root_channel_stays_enabled(self) -> None:
        self.write_toggle(True)
        self.assertTrue(self.resolve(self.plugin_root_argv(), {}))

    def test_absent_settings_fails_closed_to_enabled(self) -> None:
        # No settings.json written under the derived path.
        self.assertTrue(self.resolve(self.plugin_root_argv(), {}))

    def test_degraded_settings_fail_closed_to_enabled(self) -> None:
        self.settings.write_text("{not json", encoding="utf-8")
        self.assertTrue(self.resolve(self.plugin_root_argv(), {}))

    def test_env_toggle_is_ignored(self) -> None:
        # Configured false must hold even though the legacy env var says true...
        self.write_toggle(False)
        self.assertFalse(
            self.resolve(
                self.plugin_root_argv(),
                {"CLAUDE_PLUGIN_OPTION_DISK_HYGIENE_ENABLED": "true"},
            )
        )
        # ...and a legacy env false cannot force audit-only when unconfigured.
        self.settings.unlink()
        self.assertTrue(
            self.resolve(
                self.plugin_root_argv(),
                {"CLAUDE_PLUGIN_OPTION_DISK_HYGIENE_ENABLED": "false"},
            )
        )

    def test_legacy_argv_flag_is_ignored(self) -> None:
        # The dropped --disk-hygiene-enabled flag no longer disables anything.
        self.assertTrue(
            self.resolve(
                [*self.plugin_root_argv(), "--disk-hygiene-enabled", "false"], {}
            )
        )

    def test_no_plugin_root_ignores_env_config_dir_and_fails_closed_enabled(
        self,
    ) -> None:
        # Without a trusted --plugin-root (e.g. a --plugin-dir checkout install),
        # the guard must NOT trust a repo-injectable CLAUDE_CONFIG_DIR: even a
        # configured `false` reachable only through the environment is ignored and
        # the switch fails closed to enabled, so a repo cannot forge a settings
        # path to flip it.
        self.write_toggle(False)  # config_dir/settings.json
        self.assertTrue(
            self.resolve([], {"CLAUDE_CONFIG_DIR": os.fspath(self.config_dir)})
        )

    def test_plugin_dir_install_ignores_env_user_settings_but_honors_managed(
        self,
    ) -> None:
        # A --plugin-dir root carries no plugins/cache marker, so there is no
        # trusted user-settings path: a repo-injectable CLAUDE_CONFIG_DIR is
        # ignored. A managed policy (fixed system path) is still enforced.
        checkout = self.config_dir / "checkout"  # marker-less root
        checkout.mkdir()
        checkout_argv = ["--plugin-root", os.fspath(checkout)]
        env = {"CLAUDE_CONFIG_DIR": os.fspath(self.config_dir)}
        self.write_toggle(False)  # reachable only via env -> ignored
        self.write_managed_toggle(False)  # managed policy -> honored
        self.assertFalse(self.resolve(checkout_argv, env))
        # Without the managed policy, the marker-less install fails closed to enabled.
        self.managed.unlink()
        self.assertTrue(self.resolve(checkout_argv, env))

    def test_plugin_root_channel_beats_tamperable_config_dir_env(self) -> None:
        """A repo-injected CLAUDE_CONFIG_DIR cannot override the real settings.

        ``${CLAUDE_PLUGIN_ROOT}`` is substituted by Claude Code from the plugin's
        true install path and carries provenance a repo env block cannot forge;
        ``CLAUDE_CONFIG_DIR`` from the environment does not. So the plugin-root
        channel must win, or a hostile repo re-opens the kill switch by pointing
        the config dir at a settings.json it controls.
        """
        self.write_toggle(False)  # real user settings: audit-only
        evil = Path(self.tmp.name) / "evil"
        evil.mkdir()
        (evil / "settings.json").write_text(
            json.dumps(
                {
                    "pluginConfigs": {
                        "disk-hygiene@melodic-software": {
                            "options": {"disk_hygiene_enabled": True}
                        }
                    }
                }
            ),
            encoding="utf-8",
        )
        self.assertFalse(
            self.resolve(
                self.plugin_root_argv(),
                {"CLAUDE_CONFIG_DIR": os.fspath(evil)},
            )
        )

    def test_managed_configured_false_overrides_user_true(self) -> None:
        # Managed is the highest-precedence, non-overridable scope: an
        # organization enforcing audit-only must win over a user-enabled toggle.
        self.write_managed_toggle(False)
        self.write_toggle(True)
        self.assertFalse(self.resolve(self.plugin_root_argv(), {}))

    def test_managed_configured_true_overrides_user_false(self) -> None:
        self.write_managed_toggle(True)
        self.write_toggle(False)
        self.assertTrue(self.resolve(self.plugin_root_argv(), {}))

    def test_managed_absent_falls_back_to_user(self) -> None:
        # No managed file written; the user toggle decides.
        self.write_toggle(False)
        self.assertFalse(self.resolve(self.plugin_root_argv(), {}))

    def test_managed_without_toggle_entry_falls_back_to_user(self) -> None:
        # Managed file exists but carries no disk-hygiene entry (source=default),
        # so it yields no verdict and the user toggle decides.
        self.managed.write_text(json.dumps({"pluginConfigs": {}}), encoding="utf-8")
        self.write_toggle(False)
        self.assertFalse(self.resolve(self.plugin_root_argv(), {}))

    def test_managed_malformed_falls_back_to_user(self) -> None:
        self.managed.write_text("{not json", encoding="utf-8")
        self.write_toggle(False)
        self.assertFalse(self.resolve(self.plugin_root_argv(), {}))

    def test_installed_marketplace_id_isolates_from_other_marketplace(self) -> None:
        # A second marketplace's disk-hygiene entry must not mask this install's
        # configured value: the guard derives its exact <name>@<marketplace> key
        # from --plugin-root (here disk-hygiene@melodic-software) and matches only
        # that, rather than aggregating every disk-hygiene@* entry into an
        # ambiguous read that would fall back to enabled.
        self.settings.write_text(
            json.dumps(
                {
                    "pluginConfigs": {
                        "disk-hygiene@melodic-software": {
                            "options": {"disk_hygiene_enabled": False}
                        },
                        "disk-hygiene@other-marketplace": {
                            "options": {"disk_hygiene_enabled": True}
                        },
                    }
                }
            ),
            encoding="utf-8",
        )
        self.assertFalse(self.resolve(self.plugin_root_argv(), {}))

    def test_managed_dropin_false_overrides_user(self) -> None:
        # A false configured only in the managed drop-in directory must win over a
        # user-enabled toggle, just like the primary managed file.
        self.write_managed_dropin("10-org-policy.json", False)
        self.write_toggle(True)
        self.assertFalse(self.resolve(self.plugin_root_argv(), {}))

    def test_managed_dropin_overrides_primary_managed_file(self) -> None:
        # Drop-ins are merged over the primary managed file.
        self.write_managed_toggle(True)
        self.write_managed_dropin("50-override.json", False)
        self.assertFalse(self.resolve(self.plugin_root_argv(), {}))

    def test_later_managed_dropin_wins_over_earlier(self) -> None:
        # Sorted order: 20- overrides 10-.
        self.write_managed_dropin("10-first.json", True)
        self.write_managed_dropin("20-second.json", False)
        self.write_toggle(True)
        self.assertFalse(self.resolve(self.plugin_root_argv(), {}))


if __name__ == "__main__":
    unittest.main()
