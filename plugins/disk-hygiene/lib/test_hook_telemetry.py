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
    def _wait_for_envelope(self, out_file: Path, timeout: float = 5.0) -> dict:
        """Poll until the fire-and-forget sink has written a non-empty envelope.

        `emit` never waits for its sink subprocess, and the sink's `>` redirect
        creates the file EMPTY before `cat` writes into it, so polling for mere
        existence loses the race on a fast host and json.loads reads "".
        Wait for content, the same discipline the sibling telemetry cases in
        test_guard_launch_monitor.py and test_hygiene.py use.
        """
        deadline = time.perf_counter() + timeout
        while time.perf_counter() < deadline:
            if out_file.exists():
                try:
                    text = out_file.read_text(encoding="utf-8").strip()
                except OSError:
                    text = ""
                if text:
                    try:
                        return json.loads(text)
                    except json.JSONDecodeError:
                        pass  # truncated mid-write; keep polling until deadline
            time.sleep(0.05)
        self.fail(f"timed out waiting for the telemetry sink to write {out_file}")

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
            envelope = self._wait_for_envelope(out_file)
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
            envelope = self._wait_for_envelope(out_file)
            self.assertEqual("guard-launch-monitor", envelope["hook"])
            self.assertEqual("Stop", envelope["hook_event"])


if __name__ == "__main__":
    unittest.main()
