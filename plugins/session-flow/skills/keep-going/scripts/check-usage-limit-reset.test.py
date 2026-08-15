#!/usr/bin/env python3
import importlib.util
import os
import subprocess
import sys
import unittest
from datetime import datetime
from pathlib import Path
from unittest import mock
from zoneinfo import ZoneInfo


SCRIPT = Path(__file__).resolve().parent / "check-usage-limit-reset.py"
VENDOR_ZIP = Path(__file__).resolve().parent / "vendor" / "tzdata-zoneinfo.zip"
MSG = "You've hit your session limit · resets 2:30am (America/New_York)"


def _load_module():
    spec = importlib.util.spec_from_file_location("check_usage_limit_reset", SCRIPT)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CheckUsageLimitResetTests(unittest.TestCase):
    def invoke(
        self,
        *extra: str,
        env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        run_env = os.environ.copy()
        if env:
            run_env.update(env)
        return subprocess.run(
            [sys.executable, str(SCRIPT), *extra],
            capture_output=True,
            text=True,
            check=False,
            env=run_env,
        )

    def test_lifted_after_reset_same_day(self) -> None:
        result = self.invoke(MSG, "--now", "2026-07-25T10:25:00-04:00")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("lifted", result.stdout)

    def test_blocked_before_reset_same_day(self) -> None:
        result = self.invoke(MSG, "--now", "2026-07-25T01:00:00-04:00")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("blocked", result.stdout)

    def test_lifted_after_evening_reset_next_morning(self) -> None:
        msg = "You've hit your session limit · resets 11pm (America/New_York)"
        result = self.invoke(msg, "--now", "2026-07-26T01:00:00-04:00")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("lifted", result.stdout)

    def test_timezone_less_uses_local_offset_from_now(self) -> None:
        # 3:45pm local when --now carries -04:00 should block before that wall time.
        msg = "You've hit your session limit · resets 3:45pm"
        result = self.invoke(msg, "--now", "2026-07-25T14:00:00-04:00")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("blocked", result.stdout)

        result = self.invoke("session limit reached")
        self.assertEqual(result.returncode, 2, result.stderr)

    def test_iana_timezone_parses_with_bundled_tzdata(self) -> None:
        """Regression #2647: IANA keys must resolve even without a system TZDB."""
        self.assertTrue(
            VENDOR_ZIP.is_file(),
            "expected vendored tzdata zip next to the script",
        )
        # Empty PYTHONTZPATH hides the system zoneinfo tree (Windows-like).
        result = self.invoke(
            "You've hit your session limit - resets 7:10pm (America/New_York)",
            "--now",
            "2026-08-14T20:24:00-04:00",
            env={"PYTHONTZPATH": ""},
        )
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        self.assertIn("lifted", result.stdout)
        self.assertNotIn("unparsed", result.stderr)

    def test_parse_reset_accepts_iana_zone_directly(self) -> None:
        mod = _load_module()
        now = datetime.fromisoformat("2026-08-14T20:24:00-04:00")
        reset_at = mod.parse_reset(
            "You've hit your session limit - resets 7:10pm (America/New_York)",
            now=now,
        )
        self.assertEqual(reset_at.tzinfo, ZoneInfo("America/New_York"))
        self.assertEqual(reset_at.hour, 19)
        self.assertEqual(reset_at.minute, 10)

    def test_timezone_unavailable_is_not_unparsed(self) -> None:
        mod = _load_module()
        with mock.patch.object(
            mod,
            "resolve_zone",
            side_effect=mod.TimezoneUnavailableError(
                "No time zone found with key X"
            ),
        ):
            code = mod.main(
                [
                    "You've hit your session limit · resets 2:30am (America/New_York)",
                    "--now",
                    "2026-07-25T10:25:00-04:00",
                ]
            )
        self.assertEqual(code, 3)


if __name__ == "__main__":
    unittest.main()
