#!/usr/bin/env python3
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "measure-stop-gap.py"


def _entry(kind: str, stamp: str, **extra: object) -> str:
    return json.dumps({"type": kind, "timestamp": stamp, **extra})


class MeasureStopGapTests(unittest.TestCase):
    def setUp(self) -> None:
        self._dir = tempfile.TemporaryDirectory()
        self.addCleanup(self._dir.cleanup)
        self.dir = Path(self._dir.name)

    def run_on(self, lines: list[str], now: str) -> subprocess.CompletedProcess[str]:
        path = self.dir / "t.jsonl"
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        return self.invoke(str(path), now)

    def invoke(self, path: str, now: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, "-I", str(SCRIPT), path, "--now", now],
            capture_output=True,
            text=True,
            check=False,
        )

    def test_limit_entry_sets_the_stop(self) -> None:
        result = self.run_on(
            [
                _entry("user", "2026-10-18T08:00:00Z"),
                _entry("assistant", "2026-10-18T09:00:00Z"),
                _entry("assistant", "2026-10-18T09:05:00Z", isApiErrorMessage=True),
            ],
            "2026-10-18T11:05:30Z",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertEqual(data["last_assistant"], "2026-10-18T09:00:00+00:00")
        self.assertEqual(data["limit_or_error"], "2026-10-18T09:05:00+00:00")
        self.assertEqual(data["gap_seconds"], 2 * 3600 + 30)
        self.assertEqual(data["gap"], "2h 30s")

    def test_no_limit_entry_uses_last_assistant(self) -> None:
        result = self.run_on(
            [
                _entry("assistant", "2026-10-18T09:00:00Z"),
                _entry("user", "2026-10-18T09:30:00Z"),
            ],
            "2026-10-19T10:01:01Z",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertIsNone(data["limit_or_error"])
        self.assertEqual(data["stop_at"], data["last_assistant"])
        self.assertEqual(data["gap"], "1d 1h 1m 1s")

    def test_resumed_turn_error_entry_does_not_move_the_stop(self) -> None:
        result = self.run_on(
            [
                _entry("user", "2026-10-18T08:00:00Z"),
                _entry("assistant", "2026-10-18T09:00:00Z"),
                _entry("assistant", "2026-10-18T09:05:00Z", isApiErrorMessage=True),
                _entry("user", "2026-10-18T15:00:00Z"),
                _entry("assistant", "2026-10-18T15:00:05Z"),
                _entry("system", "2026-10-18T15:00:10Z", level="error"),
            ],
            "2026-10-18T15:05:00Z",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertEqual(data["last_assistant"], "2026-10-18T09:00:00+00:00")
        self.assertEqual(data["limit_or_error"], "2026-10-18T09:05:00+00:00")
        self.assertEqual(data["stop_at"], "2026-10-18T09:05:00+00:00")
        self.assertEqual(data["gap_seconds"], 6 * 3600)

    def test_resumed_turn_without_error_entry_is_ignored(self) -> None:
        result = self.run_on(
            [
                _entry("user", "2026-10-18T08:00:00Z"),
                _entry("assistant", "2026-10-18T09:00:00Z"),
                _entry("assistant", "2026-10-18T09:05:00Z", isApiErrorMessage=True),
                _entry("user", "2026-10-18T15:00:00Z"),
                _entry("assistant", "2026-10-18T15:00:20Z"),
            ],
            "2026-10-18T15:05:00Z",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertEqual(data["last_assistant"], "2026-10-18T09:00:00+00:00")
        self.assertEqual(data["stop_at"], "2026-10-18T09:05:00+00:00")
        self.assertEqual(data["gap_seconds"], 6 * 3600)

    def test_resumed_turn_after_stop_without_error_entry_is_ignored(self) -> None:
        result = self.run_on(
            [
                _entry("assistant", "2026-10-18T09:00:00Z"),
                _entry("user", "2026-10-18T20:00:00Z"),
                _entry("assistant", "2026-10-18T20:00:05Z"),
            ],
            "2026-10-18T20:00:10Z",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertIsNone(data["limit_or_error"])
        self.assertEqual(data["last_assistant"], "2026-10-18T09:00:00+00:00")
        self.assertEqual(data["stop_at"], "2026-10-18T09:00:00+00:00")
        self.assertEqual(data["gap_seconds"], 11 * 3600 + 10)

    def test_empty_file_exits_nonzero(self) -> None:
        result = self.run_on([], "2026-10-18T10:00:00Z")
        self.assertEqual(result.returncode, 2)
        self.assertIn("gap-unknown", result.stderr)
        self.assertEqual(result.stdout, "")

    def test_missing_file_exits_nonzero(self) -> None:
        result = self.invoke(str(self.dir / "absent.jsonl"), "2026-10-18T10:00:00Z")
        self.assertEqual(result.returncode, 2)
        self.assertIn("gap-unknown", result.stderr)

    def test_no_assistant_entry_exits_nonzero(self) -> None:
        result = self.run_on(
            [_entry("user", "2026-10-18T09:00:00Z"), "not json"],
            "2026-10-18T10:00:00Z",
        )
        self.assertEqual(result.returncode, 2)

    def test_mixed_offsets_compare_as_instants(self) -> None:
        # 12:00+05:00 is 07:00Z, earlier than 09:00Z despite the larger clock.
        result = self.run_on(
            [
                _entry("assistant", "2026-10-18T12:00:00+05:00"),
                _entry("assistant", "2026-10-18T09:00:00Z"),
                _entry("system", "2026-10-18T04:30:00-04:00", level="error"),
            ],
            "2026-10-18T05:00:00-05:00",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertEqual(data["last_assistant"], "2026-10-18T09:00:00+00:00")
        # The error (08:30Z) precedes the last assistant entry, so it is not the stop.
        self.assertEqual(data["stop_at"], data["last_assistant"])
        self.assertEqual(data["gap_seconds"], 3600)

    def test_error_after_assistant_with_offset(self) -> None:
        result = self.run_on(
            [
                _entry("assistant", "2026-10-18T09:00:00Z"),
                _entry("assistant", "2026-10-18T06:00:00-04:00", error="rate_limit"),
            ],
            "2026-10-18T10:30:00Z",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertEqual(data["stop_at"], "2026-10-18T06:00:00-04:00")
        self.assertEqual(data["gap_seconds"], 1800)


if __name__ == "__main__":
    unittest.main()
