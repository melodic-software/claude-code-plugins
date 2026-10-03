#!/usr/bin/env python3
"""Contract tests for registry_manager.py: the write gate and the read paths."""

from __future__ import annotations

import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))

import registry_manager as rm  # noqa: E402

ADD = [
    "add",
    "7",
    "--repo",
    "o/r",
    "--title",
    "t",
    "--url",
    "https://example.test/7",
    "--category",
    "degraded",
    "--feature",
    "f",
    "--impact",
    "i",
]


def run(argv: list[str]) -> tuple[int, str, str]:
    out, err = io.StringIO(), io.StringIO()
    saved = sys.argv
    sys.argv = ["registry_manager.py", *argv]
    try:
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            try:
                rm.main()
                rc = 0
            except SystemExit as exc:
                rc = exc.code if isinstance(exc.code, int) else 1
    finally:
        sys.argv = saved
    return rc, out.getvalue(), err.getvalue()


class TestWriteGate(unittest.TestCase):
    def test_add_writes_the_registry(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            rc, out, _ = run(["--data-dir", tmp, *ADD])
            self.assertEqual(rc, 0)
            self.assertNotIn("dry_run", json.loads(out))
            saved = json.loads((Path(tmp) / "registry.json").read_text())
            self.assertEqual(len(saved["issues"]), 1)

    def test_dry_run_reports_without_writing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            rc, out, _ = run(["--data-dir", tmp, "--dry-run", *ADD])
            self.assertEqual(rc, 0)
            self.assertTrue(json.loads(out)["dry_run"])
            self.assertFalse((Path(tmp) / "registry.json").exists())

    def test_reads_do_not_create_the_data_dir(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "absent"
            rc, out, _ = run(["--data-dir", str(target), "stats"])
            self.assertEqual(rc, 0)
            self.assertEqual(json.loads(out)["data"]["total"], 0)
            self.assertFalse(target.exists())

    def test_unwritable_data_dir_is_a_clean_error(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            blocker = Path(tmp) / "file"
            blocker.write_text("x", encoding="utf-8")
            rc, _, err = run(["--data-dir", str(blocker / "sub"), *ADD])
            self.assertEqual(rc, 2)
            self.assertIn("Error writing", err)


class TestMalformedRegistry(unittest.TestCase):
    def test_non_object_registry_is_a_validation_error(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "registry.json").write_text("[]", encoding="utf-8")
            rc, _, err = run(["--data-dir", tmp, "stats"])
            self.assertEqual(rc, 2)
            self.assertIn("Invalid schema", err)


class TestDataDirResolution(unittest.TestCase):
    """Another plugin's SessionStart hook can export its own data dir into every
    Bash call as CLAUDE_PLUGIN_DATA; the registry must never resolve there."""

    def resolve(self, env_value: str, home: Path) -> Path:
        with mock.patch.dict(os.environ, {"CLAUDE_PLUGIN_DATA": env_value}):
            with mock.patch.object(Path, "home", return_value=home):
                return rm.resolve_data_dir(None)

    def test_inherited_value_naming_this_plugin_is_used(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            own = Path(tmp) / "harness-ops-melodic-software"
            self.assertEqual(self.resolve(str(own), Path(tmp) / "home"), own.resolve())

    def test_inherited_value_naming_another_plugin_is_ignored(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp) / "home"
            got = self.resolve(str(Path(tmp) / "codex-openai-codex"), home)
            self.assertEqual(
                got,
                home / ".claude" / "plugins" / "data" / "harness-ops-melodic-software",
            )

    def test_explicit_flag_wins_over_any_inherited_value(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            flag = Path(tmp) / "explicit"
            with mock.patch.dict(
                os.environ, {"CLAUDE_PLUGIN_DATA": str(Path(tmp) / "harness-ops-x")}
            ):
                self.assertEqual(rm.resolve_data_dir(flag), flag.resolve())

    def test_unsubstituted_placeholder_flag_is_refused(self) -> None:
        for placeholder in ("${CLAUDE_PLUGIN_DATA}", "<plugin-data>"):
            with self.assertRaises(SystemExit):
                rm.resolve_data_dir(Path(placeholder))


if __name__ == "__main__":
    unittest.main()
