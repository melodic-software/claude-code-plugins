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
        for entry in sys.path:
            self.assertNotEqual(
                Path(entry).resolve() if entry else LIB_DIR,
                engine_dir,
                "precondition: the engine's script dir must NOT be on sys.path for this test",
            )
        self.assertTrue(callable(spawn_noise.summarize_spawn_samples))
        self.assertTrue(callable(spawn_noise.spawn_probe))

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


if __name__ == "__main__":
    unittest.main()
