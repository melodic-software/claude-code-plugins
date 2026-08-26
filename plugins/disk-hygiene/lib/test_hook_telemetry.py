#!/usr/bin/env python3
"""Tests for the disk-hygiene Python telemetry emitter."""

from __future__ import annotations

import importlib.util
import json
import os
import tempfile
import time
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


telemetry = load_module("hook_telemetry", "hook_telemetry.py")


class HookTelemetryTests(unittest.TestCase):
    def test_unset_sink_is_noop(self) -> None:
        with mock.patch.dict(os.environ, {}, clear=True):
            telemetry.emit("destructive-guard", "PreToolUse", "ok", time.perf_counter())

    def test_relative_sink_resolved_against_project_dir(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out_file = Path(tmp) / "events.jsonl"
            project = Path(tmp) / "repo"
            project.mkdir()
            rel_sink = ".claude/hooks/sink.sh"
            (project / ".claude" / "hooks").mkdir(parents=True)
            target = project / rel_sink
            target.write_text(f'#!/bin/sh\ncat >"{out_file}"\n', encoding="utf-8")
            target.chmod(0o755)
            with mock.patch.dict(
                os.environ,
                {
                    "HOOK_TELEMETRY_SINK": rel_sink,
                    "CLAUDE_PROJECT_DIR": str(project),
                },
                clear=True,
            ):
                start = time.perf_counter()
                telemetry.emit(
                    "destructive-guard",
                    "PreToolUse",
                    "blocked",
                    start,
                    {"tool": "Bash", "decision": "deny"},
                    str(project),
                )
            deadline = time.perf_counter() + 2.0
            while time.perf_counter() < deadline and not out_file.exists():
                time.sleep(0.05)
            self.assertTrue(out_file.exists(), "sink should receive envelope")
            envelope = json.loads(out_file.read_text(encoding="utf-8").strip())
            self.assertEqual("destructive-guard", envelope["hook"])
            self.assertEqual("PreToolUse", envelope["hook_event"])
            self.assertEqual("blocked", envelope["status"])
            self.assertEqual("deny", envelope["data"]["decision"])

    def test_absolute_sink_used_as_is(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out_file = Path(tmp) / "event.json"
            sink = Path(tmp) / "sink.sh"
            sink.write_text(f'#!/bin/sh\ncat >"{out_file}"\n', encoding="utf-8")
            sink.chmod(0o755)
            with mock.patch.dict(
                os.environ,
                {"HOOK_TELEMETRY_SINK": str(sink)},
                clear=True,
            ):
                telemetry.emit(
                    "guard-launch-monitor", "Stop", "ok", time.perf_counter()
                )
            deadline = time.perf_counter() + 2.0
            while time.perf_counter() < deadline and not out_file.exists():
                time.sleep(0.05)
            self.assertTrue(out_file.exists())
            envelope = json.loads(out_file.read_text(encoding="utf-8").strip())
            self.assertEqual("guard-launch-monitor", envelope["hook"])
            self.assertEqual("Stop", envelope["hook_event"])


if __name__ == "__main__":
    unittest.main()
