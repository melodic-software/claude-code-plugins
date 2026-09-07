#!/usr/bin/env python3
"""Tests for the disk-hygiene bounded guard-decision record."""

from __future__ import annotations

import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

LIB_DIR = Path(__file__).resolve().parent


def load_module(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, LIB_DIR / filename)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


decision_log = load_module("guard_decision_log", "guard_decision_log.py")


class GuardDecisionLogTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.data_root = Path(self._tmp.name) / "data-root"
        environ_patch = mock.patch.dict(os.environ)
        environ_patch.start()
        self.addCleanup(environ_patch.stop)
        os.environ.pop(decision_log.DISABLE_ENV, None)

    @property
    def log_file(self) -> Path:
        return decision_log.log_path(str(self.data_root))

    def read_records(self, path: Path | None = None) -> list[dict]:
        # A rotation leaves no live file until the next append, so an absent
        # file is a real state rather than a test failure.
        path = self.log_file if path is None else path
        if not path.exists():
            return []
        text = path.read_text(encoding="utf-8")
        return [json.loads(line) for line in text.splitlines() if line.strip()]

    def write_one(self, **overrides) -> bool:
        fields = {
            "hook": "destructive-guard",
            "decision": "deny",
            "rule": "not-exact-engine-command",
            "tool": "Bash",
            "mode": "engine-gate",
            "command": "rm -rf /tmp/example",
            "reason": "Disk-hygiene fails closed.",
        }
        fields.update(overrides)
        return decision_log.record(str(self.data_root), **fields)

    # --- the record exists at all, with no configuration -------------------

    def test_record_creates_the_log_under_the_data_root(self) -> None:
        self.assertTrue(self.write_one())
        self.assertTrue(self.log_file.is_file())
        self.assertEqual(
            self.data_root / decision_log.LOG_DIRNAME / decision_log.LOG_FILENAME,
            self.log_file,
        )

    def test_record_carries_decision_rule_command_and_timestamp(self) -> None:
        self.write_one()
        (entry,) = self.read_records()
        self.assertEqual("deny", entry["decision"])
        self.assertEqual("not-exact-engine-command", entry["rule"])
        self.assertEqual("rm -rf /tmp/example", entry["command"])
        self.assertEqual("Bash", entry["tool"])
        self.assertEqual("engine-gate", entry["mode"])
        self.assertEqual("Disk-hygiene fails closed.", entry["reason"])
        self.assertEqual(decision_log.SCHEMA_VERSION, entry["schema_version"])
        self.assertTrue(entry["timestamp"].endswith("Z"), entry["timestamp"])

    def test_records_append_one_line_each(self) -> None:
        self.write_one(decision="allow")
        self.write_one(decision="deny")
        entries = self.read_records()
        self.assertEqual(["allow", "deny"], [entry["decision"] for entry in entries])
        # One JSON object per physical line is what makes the file readable
        # with `tail`/`grep` and parseable a line at a time.
        self.assertEqual(2, len(self.log_file.read_text(encoding="utf-8").splitlines()))

    def test_a_command_containing_a_newline_stays_one_line(self) -> None:
        self.write_one(command="first\nsecond")
        self.assertEqual(1, len(self.log_file.read_text(encoding="utf-8").splitlines()))
        (entry,) = self.read_records()
        self.assertEqual("first\nsecond", entry["command"])

    def test_extra_fields_ride_along(self) -> None:
        decision_log.record(
            str(self.data_root),
            hook="guard-launch-monitor",
            decision=decision_log.DECISION_NOT_RUN,
            rule="hook-non-blocking-error",
            extra={"failure_count": 2, "exit_code": 1},
        )
        (entry,) = self.read_records()
        self.assertEqual("not-run", entry["decision"])
        self.assertEqual(2, entry["failure_count"])
        self.assertEqual(1, entry["exit_code"])

    # --- bounded, enforced -------------------------------------------------

    def test_long_command_and_reason_are_truncated(self) -> None:
        self.write_one(command="x" * 5000, reason="y" * 5000)
        (entry,) = self.read_records()
        self.assertEqual(decision_log.MAX_TEXT_CHARS + 3, len(entry["command"]))
        self.assertTrue(entry["command"].endswith("..."))
        self.assertEqual(decision_log.MAX_TEXT_CHARS + 3, len(entry["reason"]))

    def test_the_log_rotates_at_the_bound_and_keeps_one_generation(self) -> None:
        with mock.patch.object(decision_log, "MAX_BYTES", 2000):
            for _ in range(200):
                self.write_one()
            rotated = self.log_file.parent / decision_log.ROTATED_FILENAME
            self.assertTrue(rotated.is_file())
            # The bound is two generations of MAX_BYTES plus the line that
            # crossed it, enforced on the write path rather than advertised.
            total = self.log_file.stat().st_size + rotated.stat().st_size
            self.assertLess(total, 2 * 2000 + 4096, total)
            # The live file is genuinely a fresh generation, not the old one.
            self.assertLess(self.log_file.stat().st_size, 2000)

    def test_rotation_discards_only_the_generation_before_last(self) -> None:
        with mock.patch.object(decision_log, "MAX_BYTES", 900):
            for index in range(200):
                self.write_one(rule=f"rule-{index}")
        rotated = self.log_file.parent / decision_log.ROTATED_FILENAME
        surviving = [
            entry["rule"] for entry in self.read_records(rotated) + self.read_records()
        ]
        # The most recent decisions are the ones that survive the bound.
        self.assertIn("rule-199", surviving)
        self.assertNotIn("rule-0", surviving)

    # --- never changes anything, never raises ------------------------------

    def test_absent_data_root_records_nothing_and_reports_false(self) -> None:
        self.assertFalse(decision_log.record(None, hook="h", decision="deny", rule="r"))
        self.assertFalse(decision_log.record("", hook="h", decision="deny", rule="r"))

    def test_disable_env_turns_the_record_off(self) -> None:
        for value in ("0", "off", "OFF", "false", "no"):
            with self.subTest(value=value):
                os.environ[decision_log.DISABLE_ENV] = value
                self.assertFalse(self.write_one())
                self.assertFalse(self.log_file.exists())

    def test_an_unrecognised_disable_value_leaves_the_record_on(self) -> None:
        os.environ[decision_log.DISABLE_ENV] = "maybe"
        self.assertTrue(self.write_one())

    def test_an_unwritable_data_root_reports_false_and_does_not_raise(self) -> None:
        # The data root's parent is a FILE, so both the append and the mkdir
        # that follows it fail: the full-disk / read-only-root shape.
        blocker = Path(self._tmp.name) / "not-a-directory"
        blocker.write_text("", encoding="utf-8")
        self.assertFalse(
            decision_log.record(
                str(blocker / "root"), hook="h", decision="deny", rule="r"
            )
        )

    def test_a_failing_write_reports_false_and_does_not_raise(self) -> None:
        with mock.patch.object(
            decision_log.Path, "open", side_effect=OSError("No space left on device")
        ):
            self.assertFalse(self.write_one())

    def test_an_unserialisable_field_reports_false_and_does_not_raise(self) -> None:
        self.assertFalse(self.write_one(extra={"bad": object()}))

    def test_a_failing_rotation_does_not_raise_and_keeps_the_record(self) -> None:
        with mock.patch.object(decision_log, "MAX_BYTES", 1):
            with mock.patch.object(
                decision_log.os, "replace", side_effect=OSError("busy")
            ):
                self.assertFalse(self.write_one())
        # The line still landed before the rotation attempt failed.
        self.assertEqual(1, len(self.read_records()))


if __name__ == "__main__":
    unittest.main()
