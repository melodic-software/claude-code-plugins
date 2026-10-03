#!/usr/bin/env python3
"""Fixture suite for noise-report.py.

Every fixture is a small synthetic aggregate-result.json built in a temporary
directory, in the shape a real `claude plugin eval` result file carries: a
per-run `score`, a per-run `graders` list joined by name to the case-level
`graders` definitions, and `with` and `without` arms. No real result file is
tracked.

The suite is executed by noise-report.test.sh, which run-plugin-tests.sh
discovers. Run it directly with: python3 test_noise_report.py
"""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "noise-report.py"

GRADER_NAMES = ("g1", "g2", "g3", "g4")


def make_run(score, error=None, skipped=False, include_score=True, graders=None):
    """A run whose four equal-weight graders pass in proportion to `score`."""
    if graders is None:
        passed = round(score * len(GRADER_NAMES))
        graders = [
            {
                "name": name,
                "passed": index < passed,
                "weight": 1,
                "explanation": "",
                "withOnly": False,
                "scored": True,
            }
            for index, name in enumerate(GRADER_NAMES)
        ]
    run = {
        "passed": score >= 1.0,
        "turns": 3,
        "costUsd": 0.1,
        "judgeCostUsd": 0,
        "durationSeconds": 10,
        "startedAt": "2026-10-01T00:00:00.000Z",
        "error": error,
        "skippedPaidGraders": skipped,
        "graders": graders,
    }
    if include_score:
        run["score"] = score
    return run


def make_case(name, with_scores, without_scores=None, grader_defs=None):
    """A case whose arms hold one run per listed score."""
    if grader_defs is None:
        grader_defs = [
            {"name": n, "type": "regex", "weight": 1, "config": {}}
            for n in GRADER_NAMES
        ]
    arms = {"with": [make_run(s) for s in with_scores]}
    if without_scores is not None:
        arms["without"] = [make_run(s) for s in without_scores]
    return {"name": name, "graders": grader_defs, "arms": arms, "aggregates": {}}


def make_result(cases, partial=False, partial_reason=None, cost=1.5):
    return {
        "schemaVersion": 1,
        "partial": partial,
        "partialReason": partial_reason,
        "costUsd": cost,
        "suite": {"ablation": "with-without", "threshold": 1.0},
        "aggregates": {},
        "cases": cases,
    }


class NoiseReportTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def report(self, result, *args):
        path = Path(self.tmp.name) / "aggregate-result.json"
        path.write_text(json.dumps(result), encoding="utf-8")
        proc = subprocess.run(
            [sys.executable, str(SCRIPT), str(path), *args],
            capture_output=True,
            text=True,
            check=False,
        )
        return proc

    def test_every_delta_plus_one_is_too_small_to_call(self):
        cases = [make_case("c%d" % i, [1, 1, 1], [0, 0, 0]) for i in range(4)]
        proc = self.report(make_result(cases))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("n too small to call", proc.stdout)
        self.assertNotIn("within noise", proc.stdout)

    def test_delta_interval_containing_zero_is_within_noise(self):
        cases = [
            make_case("a", [1, 1, 1], [0.75, 0.75, 0.75]),
            make_case("b", [1, 1, 1], [1, 1, 1]),
            make_case("c", [0.75, 0.75, 0.75], [1, 1, 1]),
            make_case("d", [1, 1, 1], [0.75, 0.75, 0.75]),
        ]
        proc = self.report(make_result(cases))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        # deltas +0.25, 0, -0.25, +0.25: mean 0.0625, sd 0.2394, half-width 0.2346
        self.assertIn(
            "delta (with minus without), paired over 4 cases: +0.06, 95% interval -0.17 to +0.30",
            proc.stdout,
        )
        self.assertIn("within noise", proc.stdout)
        self.assertNotIn("n too small to call", proc.stdout)

    def test_delta_interval_excluding_zero_says_so(self):
        cases = [
            make_case("a", [1, 1, 1], [0, 0, 0]),
            make_case("b", [1, 1, 1], [0.25, 0.25, 0.25]),
            make_case("c", [1, 1, 1], [0, 0, 0]),
            make_case("d", [1, 1, 1], [0.25, 0.25, 0.25]),
        ]
        proc = self.report(make_result(cases))
        self.assertIn("95% interval +0.73 to +1.00", proc.stdout)
        self.assertIn("the interval excludes 0", proc.stdout)
        self.assertNotIn("within noise", proc.stdout)

    def test_fewer_than_three_cases_is_too_small_to_call(self):
        cases = [
            make_case("a", [1, 1, 1], [0, 0, 0]),
            make_case("b", [1, 1, 1], [0.75, 0.75, 0.75]),
        ]
        proc = self.report(make_result(cases))
        self.assertIn("n too small to call", proc.stdout)
        self.assertNotIn("within noise", proc.stdout)

    def test_each_arm_mean_gets_a_normal_interval(self):
        cases = [
            make_case("a", [1, 1, 1], [0.75, 0.75, 0.75]),
            make_case("b", [1, 1, 1], [1, 1, 1]),
            make_case("c", [0.75, 0.75, 0.75], [1, 1, 1]),
            make_case("d", [1, 1, 1], [0.75, 0.75, 0.75]),
        ]
        proc = self.report(make_result(cases))
        self.assertIn(
            "with-arm mean: 0.94, 95% interval 0.82 to 1.00 (normal, 4 cases)",
            proc.stdout,
        )
        self.assertIn(
            "without-arm mean: 0.88, 95% interval 0.73 to 1.00 (normal, 4 cases)",
            proc.stdout,
        )

    def test_baseline_at_095_or_higher_leaves_no_headroom(self):
        near = [
            make_case("a", [1, 1, 1], [1, 1, 1]),
            make_case("b", [1, 1, 1], [1, 1, 1]),
            make_case("c", [1, 1, 1], [0.75, 1, 1]),
            make_case("d", [1, 1, 1], [1, 1, 1]),
        ]
        proc = self.report(make_result(near))
        self.assertIn("near ceiling: without-arm mean 0.98", proc.stdout)
        self.assertIn("the baseline leaves no headroom", proc.stdout)

        below = [
            make_case("a", [1, 1, 1], [0.75, 0.75, 0.75]),
            make_case("b", [1, 1, 1], [1, 1, 1]),
            make_case("c", [1, 1, 1], [1, 1, 1]),
        ]
        proc = self.report(make_result(below))
        self.assertNotIn("no headroom", proc.stdout)

    def pass_count_cases(self):
        return [
            make_case("a", [1, 1, 1], [0.75, 0.75, 0.75]),
            make_case("b", [1, 1, 1], [1, 1, 1]),
            make_case("c", [0.75, 0.75, 0.75], [1, 1, 1]),
            make_case("d", [1, 1, 1], [0.75, 0.75, 0.75]),
        ]

    def test_pass_count_uses_the_chosen_interval_method(self):
        result = make_result(self.pass_count_cases())
        proc = self.report(result)
        self.assertIn(
            "with-arm pass count at threshold 1.00: 3 of 4, 95% interval 0.33 to 1.00 (normal)",
            proc.stdout,
        )
        proc = self.report(result, "--interval-method", "wilson")
        self.assertIn(
            "with-arm pass count at threshold 1.00: 3 of 4, 95% interval 0.30 to 0.95 (wilson)",
            proc.stdout,
        )
        self.assertIn(
            "without-arm pass count at threshold 1.00: 2 of 4, 95% interval 0.15 to 0.85 (wilson)",
            proc.stdout,
        )
        # Beta(k + 0.5, n - k + 0.5) quantiles, checked by direct numerical integration
        proc = self.report(result, "--interval-method", "jeffreys")
        self.assertIn(
            "with-arm pass count at threshold 1.00: 3 of 4, 95% interval 0.28 to 0.97 (jeffreys)",
            proc.stdout,
        )
        self.assertIn(
            "without-arm pass count at threshold 1.00: 2 of 4, 95% interval 0.12 to 0.88 (jeffreys)",
            proc.stdout,
        )
        # score intervals stay normal whatever the method
        self.assertIn(
            "with-arm mean: 0.94, 95% interval 0.82 to 1.00 (normal, 4 cases)",
            proc.stdout,
        )

    def test_threshold_moves_the_pass_count(self):
        proc = self.report(make_result(self.pass_count_cases()), "--threshold", "0.75")
        self.assertIn("with-arm pass count at threshold 0.75: 4 of 4", proc.stdout)
        self.assertIn("without-arm pass count at threshold 0.75: 4 of 4", proc.stdout)

    def weighted_graders(self, weight_on_run=True):
        graders = [
            {
                "name": "result",
                "passed": True,
                "weight": 3,
                "scored": True,
                "withOnly": False,
            },
            {
                "name": "process",
                "passed": False,
                "weight": 1,
                "scored": True,
                "withOnly": False,
            },
            {
                "name": "skill-fired",
                "passed": False,
                "weight": 1,
                "scored": False,
                "withOnly": True,
            },
        ]
        if not weight_on_run:
            for grader in graders:
                del grader["weight"]
        return graders

    def weighted_case(self, weight_on_run=True):
        defs = [
            {"name": "result", "type": "llm", "weight": 3, "config": {}},
            {"name": "process", "type": "tool_order", "weight": 1, "config": {}},
            {"name": "skill-fired", "type": "tool_used", "weight": 1, "config": {}},
        ]
        case = make_case("w", [], [1, 1, 1], grader_defs=defs)
        case["arms"]["with"] = [
            make_run(
                0, include_score=False, graders=self.weighted_graders(weight_on_run)
            )
            for _ in range(3)
        ]
        return case

    def test_missing_run_score_is_recomputed_from_weighted_graders(self):
        proc = self.report(make_result([self.weighted_case()]))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        # result (weight 3) passed, process (weight 1) failed, skill-fired not scored
        self.assertIn("with-arm mean: 0.75 (1 case", proc.stdout)

    def test_grader_weight_falls_back_to_the_case_definition(self):
        proc = self.report(make_result([self.weighted_case(weight_on_run=False)]))
        self.assertIn("with-arm mean: 0.75 (1 case", proc.stdout)

    def test_reported_score_is_cross_checked_against_the_graders(self):
        case = self.weighted_case()
        case["arms"]["with"][1]["score"] = 1.0
        case["arms"]["with"][2]["score"] = 0.75
        proc = self.report(make_result([case]))
        self.assertIn(
            "score check: case w, with-arm run 2 reports 1.00, its graders give 0.75;"
            " the reported score is used",
            proc.stdout,
        )
        self.assertNotIn("run 3 reports", proc.stdout)
        # run 1 has no score, run 2 reports 1.00, run 3 reports 0.75
        self.assertIn("with-arm mean: 0.83 (1 case", proc.stdout)

    def test_incomparable_cases_are_named_and_left_out(self):
        errored = make_case("errored", [1, 1, 1], [0, 0, 0])
        errored["arms"]["with"][0] = make_run(
            0, error="timed out after 300s", graders=[]
        )
        skipped = make_case("skipped", [1, 1, 1], [0, 0, 0])
        skipped["arms"]["without"][2]["skippedPaidGraders"] = True
        omitted = make_case("omitted", [1, 1, 1], [0, 0, 0])
        omitted["aggregates"] = {"score": 1, "passRate": 1}
        cases = [
            errored,
            skipped,
            omitted,
            make_case("a", [1, 1, 1], [0, 0, 0]),
            make_case("b", [1, 1, 1], [0.25, 0.25, 0.25]),
            make_case("c", [1, 1, 1], [0, 0, 0]),
        ]
        proc = self.report(make_result(cases))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn(
            "not comparable: case errored (with-arm run 1 ended with an error)",
            proc.stdout,
        )
        self.assertIn(
            "not comparable: case skipped (without-arm run 3 skipped its paid graders)",
            proc.stdout,
        )
        self.assertIn(
            "not comparable: case omitted (the result omits its delta)", proc.stdout
        )
        self.assertIn("paired over 3 cases", proc.stdout)
        self.assertIn("with-arm pass count at threshold 1.00: 3 of 3", proc.stdout)

    def test_one_arm_result_reports_the_with_arm_only(self):
        cases = [make_case(name, [1, 1, 0.75]) for name in ("a", "b", "c")]
        proc = self.report(make_result(cases))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("with-arm mean: 0.92", proc.stdout)
        self.assertIn(
            "no without-arm runs in this result, so there is no delta to read",
            proc.stdout,
        )
        self.assertNotIn("without-arm mean", proc.stdout)
        self.assertNotIn("headroom", proc.stdout)

    def test_partial_result_stops_before_any_number(self):
        cases = [make_case(name, [1, 1, 1], [0, 0, 0]) for name in ("a", "b", "c")]
        proc = self.report(
            make_result(cases, partial=True, partial_reason="cost_ceiling")
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("partial result (cost_ceiling)", proc.stdout)
        self.assertNotIn("mean", proc.stdout)
        self.assertNotIn("verdict", proc.stdout)

    def test_unreadable_result_file_exits_2(self):
        path = Path(self.tmp.name) / "broken.json"
        path.write_text("{not json", encoding="utf-8")
        proc = subprocess.run(
            [sys.executable, str(SCRIPT), str(path)],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 2)
        self.assertIn("error:", proc.stderr)
        proc = subprocess.run(
            [sys.executable, str(SCRIPT), str(Path(self.tmp.name) / "missing.json")],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 2)

    def voted_case(self, votes):
        case = self.weighted_case()
        for run, run_votes in zip(case["arms"]["with"], votes):
            run["graders"][0]["judgeVotes"] = run_votes
        return case

    def test_judge_vote_agreement_per_llm_grader(self):
        case = self.voted_case(
            [[True, True, True], [True, True, False], [True, True, True]]
        )
        proc = self.report(make_result([case]), "--grader-agreement")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn(
            "judge agreement: case w, grader result: unanimous in 2 of 3 runs"
            " (8 of 9 votes match their run's majority)",
            proc.stdout,
        )
        # tool_order and tool_used graders carry no judge
        self.assertNotIn("grader process", proc.stdout)

    def test_judge_votes_as_verdict_objects_are_read(self):
        verdicts = [[{"verdict": "PASS"}, {"verdict": "FAIL"}, {"verdict": "PASS"}]] * 3
        proc = self.report(
            make_result([self.voted_case(verdicts)]), "--grader-agreement"
        )
        self.assertIn("unanimous in 0 of 3 runs (6 of 9 votes", proc.stdout)

    def test_agreement_line_is_off_without_the_flag(self):
        case = self.voted_case([[True, True, True]] * 3)
        proc = self.report(make_result([case]))
        self.assertNotIn("judge", proc.stdout)

    def test_missing_judge_votes_are_reported_not_invented(self):
        proc = self.report(make_result([self.weighted_case()]), "--grader-agreement")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn(
            "the result file holds no judge votes, so agreement cannot be read",
            proc.stdout,
        )
        self.assertNotIn("unanimous", proc.stdout)

    def test_suite_without_llm_graders_has_no_agreement_to_read(self):
        cases = [make_case(name, [1, 1, 1], [0, 0, 0]) for name in ("a", "b", "c")]
        proc = self.report(make_result(cases), "--grader-agreement")
        self.assertIn(
            "no llm grader in this result, so there is no judge agreement to read",
            proc.stdout,
        )

    def test_cost_prints_beside_the_scores(self):
        cases = [make_case(name, [1, 1, 1], [0, 0, 0]) for name in ("a", "b", "c")]
        proc = self.report(make_result(cases, cost=3.2))
        self.assertIn(
            "cost: 3.20 USD for the whole suite (list-price estimate)", proc.stdout
        )

    def test_unknown_interval_method_falls_back_to_normal(self):
        proc = self.report(
            make_result(self.pass_count_cases()), "--interval-method", "bayes"
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn(
            "interval method 'bayes' is not normal, wilson or jeffreys; using normal",
            proc.stdout,
        )
        self.assertIn("3 of 4, 95% interval 0.33 to 1.00 (normal)", proc.stdout)

    def test_case_missing_its_without_arm_is_not_comparable(self):
        cases = [make_case(n, [1, 1, 1], [0, 0, 0]) for n in ("a", "b", "c")]
        cases.append(make_case("lonely", [1, 1, 1]))
        proc = self.report(make_result(cases))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn(
            "not comparable: case lonely (no without-arm runs for this case)",
            proc.stdout,
        )
        self.assertIn("paired over 3 cases", proc.stdout)

    def test_non_list_graders_value_does_not_crash(self):
        case = make_case("odd", [1, 1, 1], [0, 0, 0])
        run = case["arms"]["with"][0]
        del run["score"]
        run["graders"] = 5
        cases = [case] + [make_case(n, [1, 1, 1], [0, 0, 0]) for n in ("a", "b", "c")]
        proc = self.report(make_result(cases))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("not comparable: case odd", proc.stdout)

    def test_too_small_verdict_names_the_count_without_a_plural_slip(self):
        proc = self.report(make_result([make_case("a", [1, 1, 1], [0, 0, 0])]))
        self.assertIn("n too small to call (comparable cases: 1;", proc.stdout)


if __name__ == "__main__":
    unittest.main()
