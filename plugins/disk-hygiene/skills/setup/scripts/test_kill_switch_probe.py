#!/usr/bin/env python3
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


probe = load_module("kill_switch_probe", "kill_switch_probe.py")


class ProbeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.settings = Path(self.tmp.name) / "settings.json"

    def write_settings(self, payload: object) -> None:
        self.settings.write_text(json.dumps(payload), encoding="utf-8")

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
        self.write_settings(
            {
                "pluginConfigs": {
                    "disk-hygiene@melodic-software": {
                        "options": {"disk_hygiene_enabled": False}
                    }
                }
            }
        )
        result = self.run_probe()
        self.assertFalse(result["effective"])
        self.assertEqual("configured", result["source"])
        self.assertFalse(result["degraded"])
        self.assertEqual(
            ["disk-hygiene@melodic-software"],
            [entry["key"] for entry in result["entries"]],
        )

    def test_configured_true_reported_as_configured(self) -> None:
        self.write_settings(
            {
                "pluginConfigs": {
                    "disk-hygiene@melodic-software": {
                        "options": {"disk_hygiene_enabled": True}
                    }
                }
            }
        )
        result = self.run_probe()
        self.assertTrue(result["effective"])
        self.assertEqual("configured", result["source"])

    def test_bare_plugin_key_without_marketplace_suffix_matches(self) -> None:
        self.write_settings(
            {"pluginConfigs": {"disk-hygiene": {"options": {"disk_hygiene_enabled": False}}}}
        )
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
        self.write_settings(
            {
                "pluginConfigs": {
                    "disk-hygiene@melodic-software": {
                        "options": {"disk_hygiene_enabled": "False"}
                    }
                }
            }
        )
        result = self.run_probe()
        self.assertFalse(result["effective"])
        self.assertEqual("configured", result["source"])

    def test_unparsable_settings_degrade_honestly(self) -> None:
        self.settings.write_text("{not json", encoding="utf-8")
        result = self.run_probe()
        self.assertTrue(result["effective"])
        self.assertEqual("indeterminate", result["source"])
        self.assertTrue(result["degraded"])
        self.assertIn("assuming", result["detail"].lower())

    def test_invalid_value_type_degrades(self) -> None:
        self.write_settings(
            {
                "pluginConfigs": {
                    "disk-hygiene@melodic-software": {
                        "options": {"disk_hygiene_enabled": 42}
                    }
                }
            }
        )
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
        self.write_settings(
            {
                "pluginConfigs": {
                    "disk-hygiene@melodic-software": {
                        "options": {"disk_hygiene_enabled": False}
                    }
                }
            }
        )
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
            self.assertEqual(
                0, probe.main(["--settings-file", str(self.settings)])
            )
        text = stdout.getvalue()
        self.assertEqual(1, len([line for line in text.splitlines() if line]))
        json.loads(text)


if __name__ == "__main__":
    unittest.main()
