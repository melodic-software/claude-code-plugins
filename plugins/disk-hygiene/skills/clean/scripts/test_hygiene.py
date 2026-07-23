#!/usr/bin/env python3
"""Behavioral tests for the disk-hygiene safety engine and scoped guard."""

from __future__ import annotations

import importlib.util
import io
import json
import os
import re
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
            mock.patch.object(guard.sys, "argv", [str(SCRIPT_DIR / "destructive_guard.py")]),
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
            mock.patch.object(guard.sys, "argv", [str(SCRIPT_DIR / "destructive_guard.py")]),
            mock.patch.dict(
                "os.environ", {"CLAUDE_PLUGIN_OPTION_DISK_HYGIENE_ENABLED": "false"}, clear=False
            ),
        ):
            self.assertEqual(0, guard.main())
        return json.loads(stdout.getvalue())

    def run_guard_enabled_argv(
        self, command: str, tool_name: str, enabled_arg: str
    ) -> dict[str, object] | None:
        """Drive the guard with the kill switch supplied via hook argv, not the env.

        Exercises the ``--disk-hygiene-enabled`` argv channel with
        CLAUDE_PLUGIN_OPTION_DISK_HYGIENE_ENABLED absent — the delivery a host that
        can substitute ``${user_config.disk_hygiene_enabled}`` (a plugin
        ``hooks.json`` hook) would use. The bundled skill-frontmatter hook cannot
        supply this value (Claude Code substitutes only ``${CLAUDE_PLUGIN_ROOT}``
        into skill-hook args), so this proves the guard's argv path itself, not the
        shipped skill deployment.
        """
        argv = [
            str(SCRIPT_DIR / "destructive_guard.py"),
            "--disk-hygiene-enabled",
            enabled_arg,
        ]
        environment = {
            key: value
            for key, value in os.environ.items()
            if key != "CLAUDE_PLUGIN_OPTION_DISK_HYGIENE_ENABLED"
        }
        stdin = io.StringIO(
            json.dumps({"tool_name": tool_name, "tool_input": {"command": command}})
        )
        stdout = io.StringIO()
        with (
            mock.patch("sys.stdin", stdin),
            redirect_stdout(stdout),
            mock.patch.object(guard.sys, "argv", argv),
            mock.patch.dict("os.environ", environment, clear=True),
        ):
            self.assertEqual(0, guard.main())
        value = stdout.getvalue()
        return json.loads(value) if value.strip() else None

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
        self, command: str, tool_name: str = "Bash", enabled_arg: str = "true"
    ) -> dict[str, object] | None:
        """Drive the guard as the plugin-level engine-gate deployment would.

        Supplies ``--mode engine-gate`` plus both plugin-level substitution
        channels (``--disk-hygiene-enabled`` and ``--authorized-data-root``) on
        argv, with the env channel absent — mirroring the shipped
        ``hooks/hooks.json`` exec-form registration. Returns None when the guard
        deferred with no output.
        """
        argv = [
            str(SCRIPT_DIR / "destructive_guard.py"),
            "--mode",
            "engine-gate",
            "--plugin-root",
            str(SCRIPT_DIR.parent.parent.parent),
            "--authorized-data-root",
            str(SCRIPT_DIR / "data-root"),
            "--disk-hygiene-enabled",
            enabled_arg,
        ]
        environment = {
            key: value
            for key, value in os.environ.items()
            if key != "CLAUDE_PLUGIN_OPTION_DISK_HYGIENE_ENABLED"
        }
        stdin = io.StringIO(
            json.dumps({"tool_name": tool_name, "tool_input": {"command": command}})
        )
        stdout = io.StringIO()
        with (
            mock.patch("sys.stdin", stdin),
            redirect_stdout(stdout),
            mock.patch.object(guard.sys, "argv", argv),
            mock.patch.dict("os.environ", environment, clear=True),
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
        """Read-only commands that merely NAME the script must defer (P2 review)."""
        for tool_name, command in (
            ("Bash", "git diff -- hygiene.py"),
            ("Bash", "rg hygiene.py README.md"),
            ("Bash", "echo hygiene.py"),
            ("PowerShell", "Select-String -Pattern guard hygiene.py"),
        ):
            self.assertIsNone(
                self.run_guard_engine_gate(command, tool_name), (tool_name, command)
            )

    def test_engine_gate_catches_interpreter_options_before_the_script(self) -> None:
        """Interpreter options must not slip the kill switch (P1 review)."""
        script = SCRIPT_DIR / "hygiene.py"
        result = self.run_guard_engine_gate(
            f'/usr/bin/python3 -B "{script}" apply --plan p --token t', "Bash", "false"
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

    def test_engine_gate_catches_wrapper_launchers_of_the_bundled_engine(self) -> None:
        """env / sh -c wrappers around the absolute engine path must gate (P1 review)."""
        script = SCRIPT_DIR / "hygiene.py"
        wrapped = self.run_guard_engine_gate(
            f'/usr/bin/env "{script}" apply --plan p --token t', "Bash", "false"
        )
        assert wrapped is not None
        self.assertEqual("deny", wrapped["hookSpecificOutput"]["permissionDecision"])
        compound = self.run_guard_engine_gate(
            f'sh -c "{script} apply --plan p --token t"', "Bash", "false"
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
                f'"{posix_alias}" apply --plan p --token t', "Bash", "false"
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
                f'"{posix_alias}" apply --plan p --token t && true', "Bash", "false"
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
                "false",
            )
            assert result is not None
            self.assertEqual(
                "deny", result["hookSpecificOutput"]["permissionDecision"]
            )

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
            f'python3 "{script}" scan --target t --output s', "Bash", "false"
        )
        assert result is not None
        self.assertEqual("deny", result["hookSpecificOutput"]["permissionDecision"])

    def run_guard_powershell(self, command: str) -> dict[str, object] | None:
        stdin = io.StringIO(
            json.dumps({"tool_name": "PowerShell", "tool_input": {"command": command}})
        )
        stdout = io.StringIO()
        with (
            mock.patch("sys.stdin", stdin),
            redirect_stdout(stdout),
            mock.patch.object(guard.sys, "argv", [str(SCRIPT_DIR / "destructive_guard.py")]),
            mock.patch.dict(
                "os.environ", {"CLAUDE_PLUGIN_OPTION_DISK_HYGIENE_ENABLED": "true"}, clear=False
            ),
        ):
            self.assertEqual(0, guard.main())
        value = stdout.getvalue()
        return json.loads(value) if value.strip() else None

    def run_guard_powershell_disabled(
        self, command: str
    ) -> dict[str, object] | None:
        stdin = io.StringIO(
            json.dumps({"tool_name": "PowerShell", "tool_input": {"command": command}})
        )
        stdout = io.StringIO()
        with (
            mock.patch("sys.stdin", stdin),
            redirect_stdout(stdout),
            mock.patch.object(guard.sys, "argv", [str(SCRIPT_DIR / "destructive_guard.py")]),
            mock.patch.dict(
                "os.environ",
                {"CLAUDE_PLUGIN_OPTION_DISK_HYGIENE_ENABLED": "false"},
                clear=False,
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

    def test_resolve_disk_hygiene_enabled_precedence(self) -> None:
        script = str(SCRIPT_DIR / "destructive_guard.py")

        def drive(argv_tail: list[str], env: dict[str, str]) -> bool:
            with (
                mock.patch.object(guard.sys, "argv", [script, *argv_tail]),
                mock.patch.dict("os.environ", env, clear=True),
            ):
                return guard.resolve_disk_hygiene_enabled()

        # Argv is authoritative over the environment, both directions.
        self.assertFalse(
            drive(
                ["--disk-hygiene-enabled", "false"],
                {"CLAUDE_PLUGIN_OPTION_DISK_HYGIENE_ENABLED": "true"},
            ),
            "a configured false in argv must disable even when the env says true",
        )
        self.assertTrue(
            drive(
                ["--disk-hygiene-enabled", "true"],
                {"CLAUDE_PLUGIN_OPTION_DISK_HYGIENE_ENABLED": "false"},
            )
        )
        # Case-insensitive, whitespace-tolerant false.
        self.assertFalse(drive(["--disk-hygiene-enabled", " FALSE "], {}))
        # A literal, unsubstituted placeholder falls back to the environment.
        self.assertFalse(
            drive(
                ["--disk-hygiene-enabled", "${user_config.disk_hygiene_enabled}"],
                {"CLAUDE_PLUGIN_OPTION_DISK_HYGIENE_ENABLED": "false"},
            ),
            "an unsubstituted placeholder must fall back to the environment",
        )
        # An empty substituted value falls back to the environment.
        self.assertFalse(
            drive(
                ["--disk-hygiene-enabled", ""],
                {"CLAUDE_PLUGIN_OPTION_DISK_HYGIENE_ENABLED": "false"},
            )
        )
        # No argv, env supplies the value.
        self.assertFalse(
            drive([], {"CLAUDE_PLUGIN_OPTION_DISK_HYGIENE_ENABLED": "false"})
        )
        # No channel supplies a value: fail safe to enabled (guard active).
        self.assertTrue(drive([], {}))

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

    def test_powershell_deletion_spellings_denied_in_audit_only_mode(self) -> None:
        """Kill switch (B2): audit-only mode must deny PowerShell deletions, not ask."""
        for command in (
            "Remove-Item -Recurse -Force C:/tmp/example",
            "rm C:/tmp/example",
            "del C:/tmp/example",
            "Clear-RecycleBin -Force",
            "Microsoft.PowerShell.Management\\Clear-RecycleBin -Force",
            "[IO.File]::Delete('C:/tmp/example')",
            "[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile('x', 'OnlyErrorDialogs', 'SendToRecycleBin')",
        ):
            result = self.run_guard_powershell_disabled(command)
            assert result is not None, command
            self.assertEqual(
                "deny",
                result["hookSpecificOutput"]["permissionDecision"],
                command,
            )

    def test_kill_switch_blocks_every_lane_via_argv_without_env(self) -> None:
        """A configured ``false`` reaching the guard only through the
        ``--disk-hygiene-enabled`` argv channel — the env var UNSET — must block
        deletions on both the PowerShell and Bash lanes. Proves the guard's argv
        kill-switch logic for a host that can deliver the value there."""
        script = SCRIPT_DIR / "hygiene.py"
        powershell = self.run_guard_enabled_argv(
            "Remove-Item -Recurse -Force C:/tmp/example", "PowerShell", "false"
        )
        assert powershell is not None
        self.assertEqual(
            "deny", powershell["hookSpecificOutput"]["permissionDecision"]
        )
        apply_command = (
            f'"{self.python_command()}" "{script}" apply --execute --snapshot s '
            f'--plan p --confirm-tier high --approval-token {"a" * 24} --report r'
        )
        bash = self.run_guard_enabled_argv(apply_command, "Bash", "false")
        assert bash is not None
        self.assertEqual("deny", bash["hookSpecificOutput"]["permissionDecision"])

    def test_kill_switch_enabled_via_argv_without_env_still_gates(self) -> None:
        """The argv channel with the env var unset also carries an enabling value:
        an ``apply`` is gated (``ask``) rather than denied, confirming the argv
        value — not a hardcoded default — drives the decision."""
        script = SCRIPT_DIR / "hygiene.py"
        apply_command = (
            f'"{self.python_command()}" "{script}" apply --execute --snapshot s '
            f'--plan p --confirm-tier high --approval-token {"a" * 24} --report r'
        )
        result = self.run_guard_enabled_argv(apply_command, "Bash", "true")
        assert result is not None
        self.assertEqual("ask", result["hookSpecificOutput"]["permissionDecision"])


if __name__ == "__main__":
    unittest.main()
