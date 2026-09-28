"""Refusal rules for the Windows Recycle Bin primitive. Covers windows_recycle.py."""

from __future__ import annotations

import ast
import unittest
from pathlib import Path
from unittest import mock

import windows_recycle as recycle

FIXED = recycle.VolumeFacts("fixed", True, 1024)
PATH = Path("C:/Users/<user>/orphan.tmp")


class RefusalTests(unittest.TestCase):
    def test_enumerated_refusals(self) -> None:
        cases = (
            (Path("\\\\server\\share\\a"), 1, FIXED, recycle.NETWORK_PATH),
            (PATH, 1, recycle.VolumeFacts("network", True, 1024), recycle.NETWORK_PATH),
            (PATH, 1, recycle.VolumeFacts("removable", True, 1024), recycle.REMOVABLE_VOLUME),
            (PATH, 1, recycle.VolumeFacts("cdrom", None, None), recycle.REMOVABLE_VOLUME),
            (PATH, 1, recycle.VolumeFacts("fixed", False, 1024), recycle.RECYCLE_BIN_DISABLED),
            (PATH, 1, recycle.VolumeFacts("fixed", None, 1024), recycle.RECYCLE_BIN_DISABLED),
            (PATH, 2048, FIXED, recycle.RECYCLE_BIN_SIZE_LIMIT),
            (PATH, None, FIXED, recycle.RECYCLE_VOLUME_UNVERIFIED),
            (PATH, 1, recycle.VolumeFacts("unknown", True, 1024), recycle.RECYCLE_VOLUME_UNVERIFIED),
        )
        for path, size, facts, reason in cases:
            with self.subTest(reason=reason, path=path):
                self.assertEqual(reason, recycle.refusal_reason(path, size, facts))

    def test_a_passing_precheck_is_none(self) -> None:
        self.assertIsNone(recycle.refusal_reason(PATH, 10, FIXED))

    def test_failed_recycle_does_not_call_another_deleter(self) -> None:
        calls: list[str] = []

        def performer(path: Path, flags: int) -> None:
            calls.append("recycle")
            raise recycle.RecycleFailed("bin full")

        def permanent(path: Path, flags: int) -> None:
            calls.append("permanent")

        outcome = recycle.recycle_or_refuse(
            PATH, size=10, facts=FIXED, performer=performer
        )
        self.assertFalse(outcome.recycled)
        self.assertIn(recycle.RECYCLE_FAILED, outcome.reason or "")
        self.assertEqual(["recycle"], calls)
        self.assertFalse(permanent.__name__ in "".join(calls))

    def test_missing_recycle_flag_does_not_call_the_performer(self) -> None:
        def performer(path: Path, flags: int) -> None:
            raise AssertionError("performer ran without FOFX_RECYCLEONDELETE")

        outcome = recycle.recycle_or_refuse(
            PATH, size=10, facts=FIXED, performer=performer, flags=0
        )
        self.assertFalse(outcome.recycled)
        self.assertIn("FOFX_RECYCLEONDELETE", outcome.reason or "")

    def test_flag_constant_includes_recycle_on_delete(self) -> None:
        self.assertEqual(0x00080000, recycle.FOFX_RECYCLEONDELETE)
        self.assertTrue(recycle.RECYCLE_FLAGS & recycle.FOFX_RECYCLEONDELETE)

    def test_module_has_no_permanent_delete_api(self) -> None:
        source = Path(recycle.__file__).read_text(encoding="utf-8")
        tree = ast.parse(source)
        names = {node.name for node in ast.walk(tree) if isinstance(node, ast.FunctionDef)}
        self.assertNotIn("unlink", names)
        self.assertNotIn("rmtree", names)
        self.assertNotIn("permanent_delete", names)
        for forbidden in (
            "os.unlink",
            "os.rmdir",
            "shutil.rmtree",
            "DeleteFileW",
            "SHFileOperation",
            "Remove-Item",
        ):
            self.assertNotIn(forbidden, source)

    def test_non_windows_probe_is_unknown_and_recycle_path_refuses(self) -> None:
        if recycle.primitive_available():
            self.skipTest("this host can call IFileOperation")
        self.assertEqual("unknown", recycle.probe_volume(PATH).kind)
        with self.assertRaises(recycle.RecycleRefused) as raised:
            recycle.recycle_path(PATH, 1)
        self.assertEqual(recycle.RECYCLE_PRIMITIVE_UNAVAILABLE, raised.exception.reason)

    def test_recycle_path_raises_the_refusal_reason(self) -> None:
        with (
            mock.patch.object(recycle, "primitive_available", return_value=True),
            mock.patch.object(
                recycle, "probe_volume", return_value=recycle.VolumeFacts("network", None, None)
            ),
        ):
            with self.assertRaises(recycle.RecycleRefused) as raised:
                recycle.recycle_path(PATH, 1)
        self.assertEqual(recycle.NETWORK_PATH, raised.exception.reason)


if __name__ == "__main__":
    unittest.main()
