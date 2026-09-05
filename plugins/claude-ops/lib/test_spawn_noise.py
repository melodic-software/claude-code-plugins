#!/usr/bin/env python3
"""Contract tests for the spawn-noise lib, beside its canonical copy.

These deliberately do NOT restate the six `TestSpawnCostSummary` cases in
`skills/audit-performance/scripts/test_audit_performance.py`. Those exercise the
summary through the engine's re-export and prove the move was behavior-neutral;
duplicating them here would be a second way to say the same thing.

What this suite adds is what the engine's suite structurally cannot:

1. the module imports and works with no engine on the path at all, which is the
   whole point of promoting it, and
2. the `bimodal-spawn-latency` predicate is genuinely TWO-part -- asserted by
   showing the two arms produce DIFFERENT verdicts, not merely that each arm
   produced its own expected string. A predicate test where both arms happen to
   agree would pass while proving nothing, which is the exact failure mode this
   lib exists to help callers avoid.
"""

from __future__ import annotations

import subprocess
import sys
import unittest
from pathlib import Path

LIB_DIR = Path(__file__).resolve().parent
if str(LIB_DIR) not in sys.path:
    sys.path.insert(0, str(LIB_DIR))

import spawn_noise  # noqa: E402  (path set above)


class TestModuleStandsAlone(unittest.TestCase):
    """The promotion is pointless if the lib still needs the engine to work."""

    def test_the_lib_imports_without_the_engine_on_the_path(self):
        engine_dir = LIB_DIR.parent / "skills" / "audit-performance" / "scripts"
        self.assertTrue(engine_dir.is_dir(), "precondition: engine dir must exist to be excluded")
        # A fresh isolated interpreter, not this process: sys.path here is shared with every
        # other suite a pytest run collected alongside this one (CI's Python lane collects the
        # engine's suite in the same process, and pytest prepends each suite's directory), so
        # an in-process check can only prove what happens to be absent right now. `-I` starts
        # with neither the cwd nor PYTHONPATH on the path; the child then proves the exclusion
        # itself before importing.
        probe = (
            "import pathlib, sys\n"
            f"engine = pathlib.Path({str(engine_dir)!r})\n"
            "assert all(pathlib.Path(p).resolve() != engine for p in sys.path if p), sys.path\n"
            f"sys.path.insert(0, {str(LIB_DIR)!r})\n"
            "import spawn_noise\n"
            "assert callable(spawn_noise.summarize_spawn_samples)\n"
            "assert callable(spawn_noise.spawn_probe)\n"
            "print('stands-alone')\n"
        )
        result = subprocess.run(
            [sys.executable, "-I", "-c", probe], capture_output=True, text=True, timeout=60,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "stands-alone")

    def test_the_threshold_constants_are_owned_here(self):
        self.assertEqual(spawn_noise.BIMODAL_SPREAD_RATIO, 3.0)
        self.assertEqual(spawn_noise.SLOW_SPAWN_FLOOR_MS, 500.0)


class TestBimodalPredicateIsTwoPart(unittest.TestCase):
    """A wide ratio alone is not the contention signature; the slow mode must be slow too."""

    #: Same spread ratio (~7.7x), opposite absolute scale. Only the slow one is contended.
    FAST_WIDE_SPREAD = [18.0, 120.0, 140.0]
    SLOW_WIDE_SPREAD = [180.0, 1200.0, 1400.0]

    def _findings(self, durations):
        return spawn_noise.summarize_spawn_samples(durations, 0, 300)["findings"]

    def test_the_two_arms_share_a_spread_ratio_so_only_the_absolute_scale_can_differ(self):
        # Precondition. If the arms did not share a ratio, this suite would be
        # comparing two unrelated inputs and its verdict would mean nothing.
        fast = spawn_noise.summarize_spawn_samples(self.FAST_WIDE_SPREAD, 0, 300)
        slow = spawn_noise.summarize_spawn_samples(self.SLOW_WIDE_SPREAD, 0, 300)
        self.assertGreaterEqual(fast["spread_ratio"], spawn_noise.BIMODAL_SPREAD_RATIO)
        self.assertGreaterEqual(slow["spread_ratio"], spawn_noise.BIMODAL_SPREAD_RATIO)
        self.assertAlmostEqual(fast["spread_ratio"], slow["spread_ratio"], delta=0.5)

    def test_the_arms_actually_discriminate(self):
        # discriminating-skip-required: a predicate test whose arms agree proves nothing.
        fast = self._findings(self.FAST_WIDE_SPREAD)
        slow = self._findings(self.SLOW_WIDE_SPREAD)
        self.assertNotEqual(
            fast,
            slow,
            "both arms produced the same findings, so this test would pass whether or not "
            "the predicate checks the absolute scale",
        )
        self.assertNotIn("bimodal-spawn-latency", fast)
        self.assertIn("bimodal-spawn-latency", slow)


class TestMeasurabilityVerdict(unittest.TestCase):
    """The refusal must discriminate, and must never be a dead end."""

    QUIET = [120.0, 130.0, 125.0]
    CONTENDED = [180.0, 1200.0, 1400.0]

    def test_a_quiet_host_is_measurable_and_a_contended_one_is_not(self):
        # discriminating-skip-required: a refusal that fires on every host refuses nothing.
        quiet_ok, quiet_why = spawn_noise.is_measurable(
            spawn_noise.summarize_spawn_samples(self.QUIET, 0, 200)
        )
        loud_ok, loud_why = spawn_noise.is_measurable(
            spawn_noise.summarize_spawn_samples(self.CONTENDED, 0, 900)
        )
        self.assertNotEqual(
            quiet_ok,
            loud_ok,
            "both hosts produced the same verdict, so this test would pass whether or not "
            "is_measurable looks at the samples at all",
        )
        self.assertTrue(quiet_ok, quiet_why)
        self.assertFalse(loud_ok, loud_why)

    def test_a_refusal_states_the_numbers_that_caused_it(self):
        _, why = spawn_noise.is_measurable(
            spawn_noise.summarize_spawn_samples(self.CONTENDED, 0, 900)
        )
        # An unexplained refusal gets overridden reflexively, so the reason has to
        # carry the evidence rather than just naming the finding.
        self.assertIn("180.0", why)
        self.assertIn("1400.0", why)

    def test_a_timeout_outranks_the_bimodal_reason(self):
        # A timed-out sample is recorded at the timeout ceiling, so max_ms is
        # censored. If bimodality were reported first, the reader would get a
        # spread computed from that ceiling described as an observed slow mode,
        # which reads as a finite measurement of an unbounded tail.
        # discriminating-skip-required: this is the only case where both findings
        # co-occur, so without it the precedence can silently invert.
        summary = spawn_noise.summarize_spawn_samples([180.0, 1400.0, 20000.0], 1, 900)
        self.assertIn("spawn-probe-timed-out", summary["findings"])
        self.assertIn("bimodal-spawn-latency", summary["findings"])
        ok, why = spawn_noise.is_measurable(summary)
        self.assertFalse(ok)
        self.assertIn("timeout", why)
        self.assertNotIn("bimodal contention signature", why)

    def test_an_uncharacterized_host_is_refused_rather_than_assumed_fine(self):
        ok, why = spawn_noise.is_measurable(spawn_noise.summarize_spawn_samples([], 0, None))
        self.assertFalse(ok)
        self.assertIn("never characterized", why)


class TestPercentileFloor(unittest.TestCase):
    """`1/(1-p)` is the only sample-count rule this repo can actually ground."""

    def test_the_documented_floors(self):
        self.assertEqual(spawn_noise.percentile_floor(0.5), 2)
        self.assertEqual(spawn_noise.percentile_floor(0.95), 20)
        self.assertEqual(spawn_noise.percentile_floor(0.99), 100)

    def test_a_percentile_outside_the_open_unit_interval_raises(self):
        for bad in (0.0, 1.0, -0.1, 1.5):
            with self.subTest(percentile=bad), self.assertRaises(ValueError):
                spawn_noise.percentile_floor(bad)


if __name__ == "__main__":
    unittest.main()
