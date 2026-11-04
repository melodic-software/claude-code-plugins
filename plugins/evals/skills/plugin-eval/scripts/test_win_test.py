#!/usr/bin/env python3
"""Fixture suite for win-test.py.

Each fixture is a small synthetic aggregate-result.json, the shape
test_noise_report.py builds: per-run scores in `with` and `without` arms. The
suite is executed by win-test.test.sh, which run-plugin-tests.sh discovers.
Run it directly with: python3 test_win_test.py
"""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "win-test.py"
NAMES = ("c1", "c2", "c3", "c4", "x@y")
A = (0.5, 0.6, 0.4, 0.7, 0.5)


def shifted(deltas, base=A):
    return [round(b + d, 4) for b, d in zip(base, deltas)]


def result(scores, names=NAMES, cost=1.0, partial=False):
    def run(score):
        return {"score": score, "error": None, "skippedPaidGraders": False}

    return {
        "partial": partial,
        "partialReason": "ceiling" if partial else None,
        "costUsd": cost,
        "suite": {"ablation": "with-without", "threshold": 1.0},
        "cases": [
            {
                "name": name,
                "arms": {"with": [run(s)] * 3, "without": [run(0.2)] * 3},
                "aggregates": {},
            }
            for name, s in zip(names, scores)
        ],
    }


QUIET = shifted((0.02, -0.03, 0.01, -0.02, 0.03))
WIN = shifted((0.30, 0.25, 0.35, 0.28, 0.32))


class WinTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())

    def write(self, name, value):
        path = self.tmp / name
        path.write_text(value if isinstance(value, str) else json.dumps(value), encoding="utf-8")
        return str(path)

    def run_test(self, a2, b=None, a=A, extra=(), names=NAMES, a_cost=1.0):
        args = ["--a", self.write("a.json", result(a, names, a_cost))]
        args += ["--a2", self.write("a2.json", result(a2, names))]
        if b is not None:
            args += ["--edit", self.write("b.json", result(b, names))]
        proc = subprocess.run(
            [sys.executable, str(SCRIPT), *args, *extra],
            capture_output=True,
            text=True,
            check=False,
        )
        return proc

    def assertGate(self, proc, gate):
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("gate: %s:" % gate, proc.stdout.splitlines()[-1])

    def test_win(self):
        proc = self.run_test(QUIET, WIN)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn("a/a with-arm change (a2 minus a), paired over 5 cases: +0.00", proc.stdout)
        self.assertIn("edit with-arm change (b minus a), paired over 5 cases: +0.30", proc.stdout)
        self.assertTrue(proc.stdout.splitlines()[-1].startswith("win: "))

    def test_baseline_proceeds_without_an_edit(self):
        proc = self.run_test(QUIET)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertTrue(proc.stdout.splitlines()[-1].startswith("proceed: "))

    def test_no_win_below_the_margin(self):
        proc = self.run_test(QUIET, shifted((0.05, -0.05, 0.1, 0.0, 0.02)))
        self.assertGate(proc, "margin")

    def test_a_gain_inside_the_aa_interval_does_not_win(self):
        # The a/a interval runs -0.06 to +0.24, so an edit whose lower end
        # clears 0.05 but not the a/a upper end still loses.
        noisy = shifted((0.20, 0.15, -0.20, 0.18, 0.12))
        proc = self.run_test(noisy, shifted((0.12, 0.10, 0.11, 0.13, 0.12)))
        self.assertGate(proc, "margin")
        self.assertIn("above the a/a upper end", proc.stdout)

    def test_aa_too_noisy_stops_before_the_edit(self):
        proc = self.run_test(shifted((0.2, 0.25, 0.22, 0.18, 0.21)), WIN)
        self.assertGate(proc, "aa-noise")
        self.assertNotIn("edit with-arm change", proc.stdout)

    def test_aa_case_drop_stops(self):
        proc = self.run_test(shifted((0.05, 0.04, 0.03, -0.4, 0.06)))
        self.assertGate(proc, "aa-drop")
        self.assertIn("case c4 fell from 0.70 to 0.30", proc.stdout)

    def test_edit_case_drop_stops_a_gain(self):
        proc = self.run_test(QUIET, shifted((0.45, 0.4, 0.5, -0.4, 0.45)))
        self.assertGate(proc, "edit-drop")
        self.assertIn("case c4 fell from 0.70 to 0.30", proc.stdout)

    def test_an_invalid_pass_stops(self):
        valid = self.write("valid.txt", "complete: PASS\nverdict: VALID\n")
        invalid = self.write("invalid.txt", "complete: FAIL\nverdict: INVALID (the run is partial)\n")
        proc = self.run_test(QUIET, WIN, extra=["--validity", valid, "--validity", invalid])
        self.assertGate(proc, "validity")
        self.assertIn("invalid.txt", proc.stdout)
        ok = self.run_test(QUIET, WIN, extra=["--validity", valid])
        self.assertEqual(ok.returncode, 0, ok.stdout)

    def test_excluded_health_lines_leave_the_case_out(self):
        summary = self.write(
            "summary.md",
            "Health, with-arm runs:\n\n"
            "- c1: skill loaded: yes; fired in 3 of 3 runs with a kept trace (3 runs)\n"
            "- c2: skill loaded: no; fired in 0 of 3 runs with a kept trace (3 runs)\n"
            "- x@​y: skill loaded: unknown (no kept trace lists skills); no kept trace of 3 runs\n",
        )
        proc = self.run_test(QUIET, WIN, extra=["--health", summary])
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn("excluded: case c2 (skill loaded: no)", proc.stdout)
        self.assertIn("excluded: case x@y (skill loaded: unknown)", proc.stdout)
        self.assertIn("paired over 3 cases", proc.stdout)
        self.assertNotIn("excluded: case c1", proc.stdout)

    def test_too_few_cases_after_exclusions(self):
        names = NAMES[:4]
        summary = self.write("summary.md", "- c1: skill loaded: no; x\n- c2: skill loaded: no; x\n")
        proc = self.run_test(QUIET[:4], WIN[:4], a=A[:4], names=names, extra=["--health", summary])
        self.assertGate(proc, "cases")

    def test_no_headroom(self):
        high = (0.96, 0.97, 0.95, 1.0, 0.98)
        proc = self.run_test(high, a=high)
        self.assertGate(proc, "headroom")

    def test_a_pass_over_the_ceiling_stops(self):
        proc = self.run_test(QUIET, a_cost=5.5)
        self.assertGate(proc, "cost")

    def test_a_partial_pass_stops(self):
        args = ["--a", self.write("a.json", result(A)), "--a2", self.write("p.json", result(QUIET, partial=True))]
        proc = subprocess.run([sys.executable, str(SCRIPT), *args], capture_output=True, text=True, check=False)
        self.assertGate(proc, "partial")

    def test_an_unreadable_file_is_a_usage_error(self):
        proc = subprocess.run(
            [sys.executable, str(SCRIPT), "--a", str(self.tmp / "none.json"), "--a2", str(self.tmp / "none.json")],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 2)


if __name__ == "__main__":
    unittest.main()
