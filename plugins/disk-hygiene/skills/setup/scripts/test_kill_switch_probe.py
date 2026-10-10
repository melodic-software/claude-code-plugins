#!/usr/bin/env python3
# test-scope: plugins/disk-hygiene/*
"""Behavioral tests for the deterministic kill-switch probe.

The probe exists so ``/disk-hygiene:setup check`` (and the clean skill when its
body token arrives unexpanded) can report the *actually configured*
``disk_hygiene_enabled`` value instead of presenting an assumed default as the
configured one. Every degraded read must be labeled as assumed, never as
configured.
"""

from __future__ import annotations

import importlib.util
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

SCRIPT_DIR = Path(__file__).resolve().parent
PLUGIN_ROOT = SCRIPT_DIR.parents[2]
PROBE_RELPATH = Path("skills", "setup", "scripts", "kill_switch_probe.py")
GUARD_RELPATH = Path("skills", "clean", "scripts", "destructive_guard.py")
CONTEXT_RELPATH = Path("skills", "clean", "scripts", "engine_context.py")


def load_module(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPT_DIR / filename)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


probe = load_module("kill_switch_probe", "kill_switch_probe.py")


class ProbeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.settings = Path(self.tmp.name) / "settings.json"

    def write_settings(self, payload: object) -> None:
        self.settings.write_text(json.dumps(payload), encoding="utf-8")

    def write_toggle(
        self, value: object, key: str = "disk-hygiene@melodic-software"
    ) -> None:
        """Settings whose single ``pluginConfigs`` entry carries the toggle."""
        self.write_settings(
            {"pluginConfigs": {key: {"options": {"disk_hygiene_enabled": value}}}}
        )

    def run_probe(self, argv: list[str] | None = None) -> dict[str, object]:
        if argv is None:
            argv = ["--settings-file", str(self.settings)]
        stdout = io.StringIO()
        with redirect_stdout(stdout):
            self.assertEqual(0, probe.main(argv))
        return json.loads(stdout.getvalue())

    def test_missing_settings_file_reports_default_not_degraded(self) -> None:
        result = self.run_probe(
            ["--settings-file", str(Path(self.tmp.name) / "absent.json")]
        )
        self.assertTrue(result["effective"])
        self.assertEqual("default", result["source"])
        self.assertFalse(result["degraded"])

    def test_configured_false_reported_with_provenance(self) -> None:
        self.write_toggle(False)
        result = self.run_probe()
        self.assertFalse(result["effective"])
        self.assertEqual("configured", result["source"])
        self.assertFalse(result["degraded"])
        self.assertEqual(
            ["disk-hygiene@melodic-software"],
            [entry["key"] for entry in result["entries"]],
        )

    def test_configured_true_reported_as_configured(self) -> None:
        self.write_toggle(True)
        result = self.run_probe()
        self.assertTrue(result["effective"])
        self.assertEqual("configured", result["source"])

    def test_bare_plugin_key_without_marketplace_suffix_matches(self) -> None:
        self.write_toggle(False, key="disk-hygiene")
        result = self.run_probe()
        self.assertFalse(result["effective"])
        self.assertEqual("configured", result["source"])

    def test_unrelated_plugin_entry_does_not_match(self) -> None:
        self.write_settings(
            {
                "pluginConfigs": {
                    "disk-hygiene-extras@other": {
                        "options": {"disk_hygiene_enabled": False}
                    },
                    "other-plugin@m": {"options": {"disk_hygiene_enabled": False}},
                }
            }
        )
        result = self.run_probe()
        self.assertTrue(result["effective"])
        self.assertEqual("default", result["source"])
        self.assertFalse(result["degraded"])

    def test_matched_entry_without_toggle_reports_default(self) -> None:
        self.write_settings(
            {"pluginConfigs": {"disk-hygiene@melodic-software": {"options": {}}}}
        )
        result = self.run_probe()
        self.assertTrue(result["effective"])
        self.assertEqual("default", result["source"])
        self.assertFalse(result["degraded"])

    def test_string_boolean_values_accepted(self) -> None:
        self.write_toggle("False")
        result = self.run_probe()
        self.assertFalse(result["effective"])
        self.assertEqual("configured", result["source"])

    def test_directory_at_settings_path_degrades(self) -> None:
        directory = Path(self.tmp.name) / "settings-as-dir"
        directory.mkdir()
        result = self.run_probe(["--settings-file", str(directory)])
        self.assertTrue(result["effective"])
        self.assertEqual("indeterminate", result["source"])
        self.assertTrue(result["degraded"])

    def test_uninspectable_settings_path_degrades(self) -> None:
        with mock.patch.object(
            probe.Path, "stat", side_effect=PermissionError("denied")
        ):
            result = self.run_probe()
        self.assertTrue(result["effective"])
        self.assertEqual("indeterminate", result["source"])
        self.assertTrue(result["degraded"])

    def test_non_object_settings_root_degrades_without_crashing(self) -> None:
        self.settings.write_text("[]", encoding="utf-8")
        result = self.run_probe()
        self.assertTrue(result["effective"])
        self.assertEqual("indeterminate", result["source"])
        self.assertTrue(result["degraded"])

    def test_default_reports_name_their_user_settings_only_scope(self) -> None:
        for setup in ("missing", "no-entry"):
            with self.subTest(setup):
                if setup == "missing":
                    argv = [
                        "--settings-file",
                        str(Path(self.tmp.name) / "absent.json"),
                    ]
                else:
                    self.write_settings({"pluginConfigs": {}})
                    argv = None
                result = self.run_probe(argv)
                self.assertEqual("default", result["source"])
                self.assertIn("cannot see", result["detail"])

    def test_unparsable_settings_degrade_honestly(self) -> None:
        self.settings.write_text("{not json", encoding="utf-8")
        result = self.run_probe()
        self.assertTrue(result["effective"])
        self.assertEqual("indeterminate", result["source"])
        self.assertTrue(result["degraded"])
        self.assertIn("assuming", result["detail"].lower())

    def test_invalid_value_type_degrades(self) -> None:
        self.write_toggle(42)
        result = self.run_probe()
        self.assertTrue(result["effective"])
        self.assertEqual("indeterminate", result["source"])
        self.assertTrue(result["degraded"])

    def test_conflicting_entries_degrade_and_fail_safe_to_enabled(self) -> None:
        self.write_settings(
            {
                "pluginConfigs": {
                    "disk-hygiene@a": {"options": {"disk_hygiene_enabled": False}},
                    "disk-hygiene@b": {"options": {"disk_hygiene_enabled": True}},
                }
            }
        )
        result = self.run_probe()
        self.assertTrue(result["effective"])
        self.assertEqual("indeterminate", result["source"])
        self.assertTrue(result["degraded"])
        self.assertEqual(2, len(result["entries"]))

    def test_consistent_duplicate_entries_stay_configured(self) -> None:
        self.write_settings(
            {
                "pluginConfigs": {
                    "disk-hygiene@a": {"options": {"disk_hygiene_enabled": False}},
                    "disk-hygiene@b": {"options": {"disk_hygiene_enabled": False}},
                }
            }
        )
        result = self.run_probe()
        self.assertFalse(result["effective"])
        self.assertEqual("configured", result["source"])
        self.assertFalse(result["degraded"])

    def test_default_path_honors_claude_config_dir(self) -> None:
        self.write_toggle(False)
        with mock.patch.dict(
            "os.environ", {"CLAUDE_CONFIG_DIR": self.tmp.name}, clear=False
        ):
            result = self.run_probe([])
        self.assertFalse(result["effective"])
        self.assertEqual("configured", result["source"])
        self.assertEqual(str(self.settings), result["settings_path"])

    def test_output_is_single_line_json(self) -> None:
        stdout = io.StringIO()
        with redirect_stdout(stdout):
            self.assertEqual(0, probe.main(["--settings-file", str(self.settings)]))
        text = stdout.getvalue()
        self.assertEqual(1, len([line for line in text.splitlines() if line]))
        json.loads(text)

    def test_report_carries_launch_disclosure_beside_kill_switch_fields(self) -> None:
        self.write_toggle(False)
        result = self.run_probe()
        for key in ("effective", "source", "degraded", "detail", "settings_path"):
            self.assertIn(key, result)
        self.assertFalse(result["effective"])
        self.assertEqual(
            os.fspath(Path(sys.executable).resolve()).replace("\\", "/"),
            result["hook_python"],
        )
        self.assertTrue(os.path.isabs(str(result["hook_python"])))
        self.assertIn("data_root", result)


class LaunchDisclosureParityTests(unittest.TestCase):
    """The probe reports the interpreter the belt's denial names and the data
    root the guard-values note names, run for run.

    Every side runs as a subprocess of the same interpreter from the same install
    root, the way the ``clean`` belt admits the probe, with ``CLAUDE_PLUGIN_DATA``
    absent (it is not in the Bash tool's environment, and a skill hook gets none).
    """

    _GUARD_INTERPRETER = re.compile(r'the interpreter must be "([^"]+)"')
    _NOTE_DATA_ROOT = re.compile(r'^data_root: (?:"([^"]+)"|none\b)', re.MULTILINE)

    def setUp(self) -> None:
        self.environment = {
            key: value
            for key, value in os.environ.items()
            if key != "CLAUDE_PLUGIN_DATA"
        }

    def run_probe(self, plugin_root: Path) -> dict[str, object]:
        completed = subprocess.run(
            [sys.executable, os.fspath(plugin_root / PROBE_RELPATH)],
            capture_output=True,
            text=True,
            env=self.environment,
            check=True,
        )
        return json.loads(completed.stdout)

    def run_belt_denial(self, plugin_root: Path) -> str:
        """The belt's reason for denying the probe under a bare interpreter name."""
        command = f'python "{(plugin_root / PROBE_RELPATH).as_posix()}"'
        completed = subprocess.run(
            [
                sys.executable,
                os.fspath(plugin_root / GUARD_RELPATH),
                "--plugin-root",
                os.fspath(plugin_root),
            ],
            input=json.dumps({"tool_name": "Bash", "tool_input": {"command": command}}),
            capture_output=True,
            text=True,
            env=self.environment,
            check=True,
        )
        output = json.loads(completed.stdout)["hookSpecificOutput"]
        self.assertEqual("deny", output["permissionDecision"])
        return output["permissionDecisionReason"]

    def assert_parity(self, plugin_root: Path) -> dict[str, object]:
        reported = self.run_probe(plugin_root)
        reason = self.run_belt_denial(plugin_root)
        interpreter = self._GUARD_INTERPRETER.search(reason)
        self.assertIsNotNone(interpreter, reason)
        self.assertEqual(interpreter.group(1), reported["hook_python"])
        note = self.run_context(plugin_root)
        data_root = self._NOTE_DATA_ROOT.search(note)
        self.assertIsNotNone(data_root, note)
        self.assertEqual(data_root.group(1), reported["data_root"])
        return reported

    def run_context(self, plugin_root: Path) -> str:
        """The guard-values note ``/disk-hygiene:clean`` expands with."""
        completed = subprocess.run(
            [
                sys.executable,
                os.fspath(plugin_root / CONTEXT_RELPATH),
                "--plugin-root",
                os.fspath(plugin_root),
            ],
            input="{}",
            capture_output=True,
            text=True,
            env=self.environment,
            check=True,
        )
        return json.loads(completed.stdout)["hookSpecificOutput"]["additionalContext"]

    def test_marketplace_cache_install_reports_the_denial_values(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            plugins = Path(temporary).resolve() / "plugins"
            plugin_root = plugins / "cache" / "acme" / "disk-hygiene" / "0.4.8"
            shutil.copytree(
                PLUGIN_ROOT,
                plugin_root,
                ignore=shutil.ignore_patterns("__pycache__", ".*_cache", ".venv", "node_modules", ".work"),
            )
            reported = self.assert_parity(plugin_root)
            self.assertEqual(
                (plugins / "data" / "disk-hygiene-acme").as_posix(),
                reported["data_root"],
            )

    def test_checkout_install_reports_the_denial_values(self) -> None:
        self.assert_parity(PLUGIN_ROOT)


if __name__ == "__main__":
    unittest.main()
