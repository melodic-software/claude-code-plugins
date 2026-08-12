#!/usr/bin/env python3
import subprocess
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parent / "check-usage-limit-reset.py"
MSG = "You've hit your session limit · resets 2:30am (America/New_York)"


class CheckUsageLimitResetTests(unittest.TestCase):
    def invoke(self, *extra: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["python3", str(SCRIPT), *extra],
            capture_output=True,
            text=True,
            check=False,
        )

    def test_lifted_after_reset_same_day(self) -> None:
        result = self.invoke(MSG, "--now", "2026-07-25T10:25:00-04:00")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("lifted", result.stdout)

    def test_blocked_before_reset_same_day(self) -> None:
        result = self.invoke(MSG, "--now", "2026-07-25T01:00:00-04:00")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("blocked", result.stdout)

    def test_unparsed_without_reset_clause(self) -> None:
        result = self.invoke("session limit reached")
        self.assertEqual(result.returncode, 2, result.stderr)


if __name__ == "__main__":
    unittest.main()
