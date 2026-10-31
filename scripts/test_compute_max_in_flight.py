#!/usr/bin/env python3
# test-scope: scripts/compute-max-in-flight.py docs/conventions/pr-pipeline.yaml docs/conventions/pr-pipeline/pr-pipeline.schema.json
"""Tests for scripts/compute-max-in-flight.py and the cap's one ceiling."""

from __future__ import annotations

import importlib.util
import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
SPEC = importlib.util.spec_from_file_location(
    "compute_max_in_flight", HERE / "compute-max-in-flight.py"
)
compute = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(compute)

sys.path.insert(0, str(ROOT / "plugins/source-control/skills/babysit-prs/scripts"))
import babysit_merge_policy as policy  # noqa: E402

INPUTS = {
    "peak-merges-per-hour": 11,
    "mean-minutes-in-flight": 58,
    "app-hourly-limit": 5200,
    "app-target-percent": 70,
    "app-peak-hourly-used": 1974,
    "app-calls-per-candidate": 9,
    "reader-runs-per-hour": 4,
}


def pipeline(cap: int, **changes: int) -> str:
    sizing = "".join(
        f"    {key}: {value}\n" for key, value in {**INPUTS, **changes}.items()
    )
    return f"merge:\n  max-in-flight: {cap}\n  in-flight-sizing:\n{sizing}"


class FormulaTest(unittest.TestCase):
    def test_the_rate_term_rounds_up(self) -> None:
        self.assertEqual(compute.cap(INPUTS), 11)
        self.assertEqual(compute.cap({**INPUTS, "peak-merges-per-hour": 6}), 6)

    def test_the_api_term_binds_when_it_is_lower(self) -> None:
        tight = {**INPUTS, "app-peak-hourly-used": 3460}
        self.assertEqual(compute.cap(tight), 5)

    def test_a_spent_budget_never_computes_a_cap_below_one(self) -> None:
        self.assertEqual(compute.cap({**INPUTS, "app-peak-hourly-used": 5200}), 1)


class CheckTest(unittest.TestCase):
    def run_check(self, text: str) -> tuple[int, str]:
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "pipeline.yaml"
            path.write_text(text, encoding="utf-8")
            out, err = io.StringIO(), io.StringIO()
            with redirect_stdout(out), redirect_stderr(err):
                code = compute.main(["--check"], path)
        return code, out.getvalue() + err.getvalue()

    def test_a_matching_value_passes(self) -> None:
        self.assertEqual(self.run_check(pipeline(11))[0], 0)

    def test_a_different_value_fails_naming_both(self) -> None:
        code, text = self.run_check(pipeline(10))
        self.assertEqual(code, 1)
        self.assertIn("10", text)
        self.assertIn("11", text)

    def test_a_missing_input_fails(self) -> None:
        text = pipeline(11).replace("    reader-runs-per-hour: 4\n", "")
        code, message = self.run_check(text)
        self.assertEqual(code, 1)
        self.assertIn("reader-runs-per-hour", message)

    def test_this_repository_is_computed(self) -> None:
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(compute.main(["--check"]), 0)


class CeilingTest(unittest.TestCase):
    def test_the_schema_and_the_reader_share_one_ceiling(self) -> None:
        schema = json.loads(
            (ROOT / "docs/conventions/pr-pipeline/pr-pipeline.schema.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(
            schema["$defs"]["merge"]["properties"]["max-in-flight"]["maximum"],
            policy.MAX_IN_FLIGHT_CEILING,
        )


if __name__ == "__main__":
    unittest.main()
