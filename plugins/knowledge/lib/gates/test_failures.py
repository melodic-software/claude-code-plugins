#!/usr/bin/env python3
"""Cases for gates.failures.

Run: python test_failures.py
"""

from __future__ import annotations

import contextlib
import io
import os
import sys
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir))
from gates.failures import Failures  # noqa: E402


def record(failures, messages):
    err = io.StringIO()
    with contextlib.redirect_stderr(err):
        for message in messages:
            failures.add(message)
        failures.report_suppressed()
    return err.getvalue()


class TestFailures(unittest.TestCase):
    def test_echoes_every_failure_without_a_limit(self):
        failures = Failures("gate")
        self.assertEqual(
            record(failures, ["a", "b", "c"]),
            "gate: FAIL: a\ngate: FAIL: b\ngate: FAIL: c\n",
        )
        self.assertEqual(failures.items, ["a", "b", "c"])

    def test_echoes_up_to_the_limit_then_names_the_rest(self):
        failures = Failures("gate", echo_limit=2)
        self.assertEqual(
            record(failures, ["a", "b", "c"]),
            "gate: FAIL: a\ngate: FAIL: b\ngate: ... 1 more failure(s) not shown\n",
        )
        self.assertEqual(failures.items, ["a", "b", "c"])

    def test_names_nothing_suppressed_at_the_limit(self):
        self.assertEqual(
            record(Failures("gate", echo_limit=2), ["a", "b"]),
            "gate: FAIL: a\ngate: FAIL: b\n",
        )


if __name__ == "__main__":
    unittest.main()
