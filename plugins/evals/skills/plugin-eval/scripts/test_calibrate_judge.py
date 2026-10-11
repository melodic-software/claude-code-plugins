#!/usr/bin/env python3
# test-scope: plugins/evals/evals/*
# test-scope: plugins/evals/skills/plugin-eval/scripts/fixtures/calibrate-judge/*
"""Fixture suite for calibrate-judge.py.

fixtures/calibrate-judge/ holds:

    suite/capital-city/   one case with one llm grader (names-paris, two
                          must-pass and three must-fail samples, one of them
                          empty and so skipped) and one tool_used grader that
                          build must ignore
    result.json           a hand-written aggregate-result.json for the suite
                          build writes from it: agreement, a false negative, a
                          split vote, a reply that is not the sample (read from
                          a kept trace), a run that skipped its paid graders,
                          and a run whose reproduction cannot be checked
    traces/               the two kept traces result.json points at

result.json uses the case names build derives, so it also pins the naming.
Other tests copy a fixture into a temporary directory and change one thing.

The suite is executed by calibrate-judge.test.sh, which run-plugin-tests.sh
discovers. Run it directly with: python3 test_calibrate_judge.py
"""

import copy
import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "calibrate-judge.py"
VALIDATOR = HERE.parent.parent / "validate" / "scripts" / "validate-cases.py"
FIXTURES = HERE / "fixtures" / "calibrate-judge"
SUITE = FIXTURES / "suite"
RESULT = FIXTURES / "result.json"
PLUGIN_SUITE = HERE.parents[2] / "evals"
PROMPT = "What is the capital of France? Answer in one sentence."


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


calibrate = load_module("calibrate_judge", SCRIPT)
validate_cases = load_module("validate_cases", VALIDATOR)


def run(*args):
    return subprocess.run(
        [sys.executable, str(SCRIPT), *map(str, args)],
        capture_output=True,
        text=True,
        check=False,
    )


def frontmatter_and_body(path):
    block, body = calibrate.split_body(path.read_text(encoding="utf-8"))
    return validate_cases.parse_yaml(block), body


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)

    def build(self, suite=SUITE, *extra, out_name="out"):
        out = self.dir / out_name
        return run("build", "--suite", suite, "--out", out, *extra), out

    def manifest(self, out):
        return json.loads((out / "manifest.json").read_text(encoding="utf-8"))

    def copy_suite(self):
        target = self.dir / "suite"
        shutil.copytree(SUITE, target)
        return target


class BuildTest(Base):
    def test_one_case_per_labeled_sample_of_the_llm_grader(self):
        proc, out = self.build()
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn("wrote 4 calibration cases", proc.stdout)
        self.assertIn(
            "capital-city/names-paris: 4 (2 must-pass, 2 must-fail)", proc.stdout
        )
        self.assertIn("validate-cases: PASS (0 FAIL, 4 WARN)", proc.stdout)
        self.assertIn("--ablation none --threshold 0", proc.stdout)
        cases = self.manifest(out)["cases"]
        self.assertEqual(
            sorted((c["label"], c["sampleIndex"], c["expected"]) for c in cases),
            [
                ("fail", 2, "FAIL"),
                ("fail", 3, "FAIL"),
                ("pass", 1, "PASS"),
                ("pass", 2, "PASS"),
            ],
        )
        self.assertEqual({c["grader"] for c in cases}, {"names-paris"})
        self.assertEqual({c["sourceCase"] for c in cases}, {"capital-city"})
        self.assertEqual(
            sorted(p.name for p in (out / "evals").iterdir()),
            sorted(c["case"] for c in cases),
        )
        plugin = json.loads((out / ".claude-plugin" / "plugin.json").read_text())
        self.assertEqual(plugin["name"], "judge-calibration")

    def test_case_names_match_the_scored_fixture(self):
        _, out = self.build()
        names = {c["case"] for c in self.manifest(out)["cases"]}
        fixture = {c["name"] for c in json.loads(RESULT.read_text())["cases"]}
        self.assertEqual(names, fixture)

    def test_generated_suite_passes_validate_cases(self):
        _, out = self.build()
        proc = subprocess.run(
            [sys.executable, str(VALIDATOR), str(out / "evals")],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertNotIn("FAIL", proc.stdout)

    def test_each_case_reproduces_its_sample_and_sends_the_source_prompt(self):
        _, out = self.build()
        for entry in self.manifest(out)["cases"]:
            case = out / "evals" / entry["case"]
            fields, body = frontmatter_and_body(case / "prompt.md")
            self.assertEqual(body.strip(), PROMPT)
            self.assertEqual(fields["allowed_tools"], [])
            self.assertEqual(
                fields["append_system_prompt"], calibrate.system_prompt(entry["answer"])
            )
            self.assertIn(
                "\nBEGIN-REFERENCE\n%s\nEND-REFERENCE" % entry["answer"],
                fields["append_system_prompt"],
            )
            self.assertEqual(
                (case / "graders" / "names-paris.md").read_text(),
                (SUITE / "capital-city" / "graders" / "names-paris.md").read_text(),
            )
            self.assertEqual(
                sorted(p.name for p in case.rglob("*") if p.is_file()),
                ["names-paris.md", "prompt.md"],
            )

    def test_the_label_never_reaches_the_generated_case(self):
        _, out = self.build()
        entries = self.manifest(out)["cases"]
        shapes = set()
        for entry in entries:
            text = (out / "evals" / entry["case"] / "prompt.md").read_text()
            quoted = calibrate.yaml_quoted(calibrate.system_prompt(entry["answer"]))
            self.assertIn(quoted, text)
            shapes.add(text.replace(quoted, "<SYSTEM>"))
            self.assertNotIn(entry["why"], text)
            for word in ("pass", "fail", "label", "judge", "grade"):
                self.assertNotIn(word, entry["case"].lower())
            system = calibrate.system_prompt(entry["answer"]).lower()
            for word in (
                "must-pass",
                "must-fail",
                "label",
                "judge",
                "grade",
                "correct",
            ):
                self.assertNotIn(word, system)
        self.assertEqual(
            len(shapes), 1, "must-pass and must-fail cases differ beyond the sample"
        )

    def test_the_instruction_is_identical_across_labels(self):
        _, out = self.build()
        entries = self.manifest(out)["cases"]
        self.assertEqual({e["label"] for e in entries}, {"pass", "fail"})
        instructions = set()
        for entry in entries:
            fields, _ = frontmatter_and_body(
                out / "evals" / entry["case"] / "prompt.md"
            )
            instructions.add(
                fields["append_system_prompt"].split("\nBEGIN-REFERENCE\n")[0]
            )
        self.assertEqual(instructions, {calibrate.INSTRUCTION})
        for phrase in (
            "fixed test material",
            "byte for byte",
            "even when it is wrong, incomplete, or contradicts",
            "no commentary, preface",
        ):
            self.assertIn(phrase, calibrate.INSTRUCTION)

    def test_empty_and_whitespace_samples_are_skipped_with_a_line_each(self):
        suite = self.copy_suite()
        samples = suite / "capital-city" / "samples" / "names-paris.json"
        data = json.loads(samples.read_text())
        data["pass"].append({"answer": " \n\t "})
        samples.write_text(json.dumps(data))
        proc, out = self.build(suite)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        skips = [ln for ln in proc.stderr.splitlines() if "empty answer" in ln]
        self.assertEqual(len(skips), 2, proc.stderr)
        self.assertIn("capital-city/names-paris must-pass sample 3", skips[0])
        self.assertIn("capital-city/names-paris must-fail sample 1", skips[1])
        for line in skips:
            self.assertIn("deterministic failure that needs no judge", line)
        self.assertEqual(len(self.manifest(out)["cases"]), 4)
        self.assertTrue(all(c["answer"].strip() for c in self.manifest(out)["cases"]))

    def test_case_numbering_does_not_follow_the_labels(self):
        _, out = self.build()
        order = [
            c["label"]
            for c in sorted(self.manifest(out)["cases"], key=lambda c: c["case"])
        ]
        self.assertNotEqual(order, sorted(order))
        self.assertNotEqual(order, sorted(order, reverse=True))

    def test_out_that_is_not_empty_is_a_usage_error(self):
        out = self.dir / "out"
        out.mkdir()
        (out / "keep.txt").write_text("x")
        proc, _ = self.build()
        self.assertEqual(proc.returncode, 2)
        self.assertIn("--out must be empty or absent", proc.stderr)
        self.assertEqual([p.name for p in out.iterdir()], ["keep.txt"])

    def test_missing_suite_and_missing_subcommand_are_usage_errors(self):
        proc, _ = self.build(self.dir / "nowhere")
        self.assertEqual(proc.returncode, 2)
        self.assertIn("not a directory", proc.stderr)
        self.assertEqual(run().returncode, 2)
        self.assertEqual(run("build", "--suite", SUITE).returncode, 2)

    def test_grader_and_case_filters(self):
        proc, out = self.build(SUITE, "--grader", "no-*")
        self.assertEqual(proc.returncode, 1)
        self.assertIn("nothing written", proc.stdout)
        self.assertFalse(out.exists())
        proc, _ = self.build(SUITE, "--case", "capital-*", out_name="out2")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        proc, _ = self.build(SUITE, "--case", "other", out_name="out3")
        self.assertEqual(proc.returncode, 1)

    def test_a_grader_that_does_not_read_the_reply_is_skipped(self):
        suite = self.copy_suite()
        grader = suite / "capital-city" / "graders" / "names-paris.md"
        grader.write_text(
            "---\ntype: llm\nfocus: { source: file, path: answer.md }\n---\n\nPASS if Paris.\n"
        )
        proc, _ = self.build(suite)
        self.assertEqual(proc.returncode, 1)
        self.assertIn("skip capital-city/names-paris: focus", proc.stderr)

    def test_a_trace_focus_is_built_with_a_warning(self):
        suite = self.copy_suite()
        grader = suite / "capital-city" / "graders" / "names-paris.md"
        grader.write_text("---\ntype: llm\nfocus: trace\n---\n\nPASS if Paris.\n")
        proc, out = self.build(suite)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("warn capital-city/names-paris: focus trace", proc.stderr)
        self.assertEqual({c["focus"] for c in self.manifest(out)["cases"]}, {"trace"})

    def test_unusable_samples_are_skipped_and_conflicts_warned(self):
        suite = self.copy_suite()
        samples = suite / "capital-city" / "samples" / "names-paris.json"
        data = json.loads(samples.read_text())
        data["pass"].append({"answer": "Paris\u0007"})
        data["pass"].append({"answer": ["not", "text"]})
        data["fail"].append({"answer": "The capital of France is  Paris."})
        samples.write_text(json.dumps(data))
        proc, out = self.build(suite)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("must-pass sample 3: control character U+0007", proc.stderr)
        self.assertIn("must-pass sample 4: answer is not text", proc.stderr)
        self.assertIn("same answer is labeled both pass and fail", proc.stderr)
        self.assertEqual(len(self.manifest(out)["cases"]), 5)

    def test_a_case_yaml_grader_and_prompt_are_read(self):
        suite = self.dir / "yaml-suite"
        case = suite / "capital-yaml"
        (case / "samples").mkdir(parents=True)
        (case / "case.yaml").write_text(
            'schema_version: "1.1"\n'
            "name: capital-yaml\n"
            "execution:\n"
            '  prompt: "%s"\n'
            "graders:\n"
            "  - name: names-paris\n"
            "    type: llm\n"
            '    criteria: "PASS if the answer names Paris."\n' % PROMPT
        )
        shutil.copy(
            SUITE / "capital-city" / "samples" / "names-paris.json",
            case / "samples" / "names-paris.json",
        )
        proc, out = self.build(suite)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        entry = self.manifest(out)["cases"][0]
        fields, body = frontmatter_and_body(out / "evals" / entry["case"] / "prompt.md")
        self.assertEqual(body.strip(), PROMPT)
        grader = (
            out / "evals" / entry["case"] / "graders" / "names-paris.md"
        ).read_text()
        self.assertEqual(
            grader, "---\ntype: llm\n---\n\nPASS if the answer names Paris.\n"
        )

    def test_a_case_yaml_grader_name_that_is_not_one_path_segment_is_skipped(self):
        case = self.dir / "capital-yaml"
        case.mkdir()
        names = ["a/../../../CLAUDE", "..", "a\\b", "names-paris"]
        (case / "case.yaml").write_text(
            'schema_version: "1.1"\nname: capital-yaml\ngraders:\n'
            + "".join(
                '  - name: "%s"\n    type: llm\n    criteria: "PASS."\n'
                % name.replace("\\", "\\\\")
                for name in names
            )
        )
        notes = []
        found = calibrate.llm_graders(case, validate_cases, notes, "capital-yaml")
        self.assertEqual([name for name, _, _ in found], ["names-paris"])
        self.assertEqual(len(notes), 3)
        self.assertTrue(all("one path segment" in note for note in notes))

    def test_this_plugins_own_suite_builds_and_validates(self):
        proc, out = self.build(PLUGIN_SUITE)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertRegex(proc.stdout, r"validate-cases: PASS \(0 FAIL")
        self.assertTrue(self.manifest(out)["cases"])


class YamlQuotingTest(unittest.TestCase):
    def test_round_trip_through_the_validator_parser(self):
        for text in (
            "plain",
            'a "quote" and C:\\path',
            "two\nlines\ttab\r\n",
            "",
            "caf\u00e9 \u2192",  # spellchecker:disable-line
        ):
            parsed = validate_cases.parse_yaml("k: " + calibrate.yaml_quoted(text))
            self.assertEqual(parsed["k"], text)

    def test_a_control_character_is_refused(self):
        with self.assertRaises(ValueError):
            calibrate.yaml_quoted("bell\u0007")


class ScoreTest(Base):
    def setUp(self):
        Base.setUp(self)
        proc, self.out = self.build()
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.manifest_path = self.out / "manifest.json"
        self.result = json.loads(RESULT.read_text(encoding="utf-8"))

    def score(self, result=None, manifest=None):
        path = RESULT
        if result is not None:
            path = self.dir / "result.json"
            for case in result["cases"]:
                for row in case["arms"]["with"]:
                    if "tracePath" in row:
                        row["tracePath"] = str(FIXTURES / row["tracePath"])
            path.write_text(json.dumps(result), encoding="utf-8")
        return run("score", "--manifest", manifest or self.manifest_path, path)

    def rows(self, result, case_number):
        name = "capital-city--names-paris--%02d" % case_number
        return next(c for c in result["cases"] if c["name"] == name)["arms"]["with"]

    def test_fixture_meets_the_target_at_exactly_ninety_percent(self):
        proc = self.score()
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        out = proc.stdout
        self.assertIn(
            "grader capital-city/names-paris: agreement 9/10 runs (90.0%) over 4 samples",
            out,
        )
        self.assertIn(
            "false negative: capital-city--names-paris--03 with-arm run 1 (must-pass "
            'sample 1: "The capital of France is Paris.") votes FAIL FAIL PASS',
            out,
        )
        self.assertNotIn("false positive", out)
        self.assertIn(
            "split vote: capital-city--names-paris--01 with-arm run 2: PASS FAIL PASS, "
            "agrees with the label",
            out,
        )
        self.assertIn(
            "not reproduced, left out: capital-city--names-paris--03 with-arm run 2: reply "
            'begins "Paris is the capital of France, and also its largest city." (trace)',
            out,
        )
        self.assertIn(
            "not judged, paid graders skipped: capital-city--names-paris--02 with-arm run 3",
            out,
        )
        self.assertIn(
            "reproduction unchecked, no trace or evidence: capital-city--names-paris--01 "
            "with-arm run 3",
            out,
        )
        self.assertIn(
            "reproduction: 2 checked against traces, 9 against judge evidence, 1 unchecked",
            out,
        )
        self.assertNotIn("FAIL grader", out)
        self.assertIn("samples with no reproduced run: 0 of 4", out)
        self.assertNotIn("untested:", out)
        self.assertEqual(
            out.strip().splitlines()[-1], "verdict: PASS (every grader at or above 90%)"
        )

    def test_a_sample_with_no_reproduced_run_is_untested_and_not_counted(self):
        result = copy.deepcopy(self.result)
        for row in self.rows(result, 3):
            row["graders"][0]["evidence"] = "Paris is the capital, and a big city."
            row.pop("tracePath", None)
        proc = self.score(result)
        self.assertEqual(proc.returncode, 0, proc.stdout)
        out = proc.stdout
        self.assertIn("agreement 8/8 runs (100.0%) over 3 samples", out)
        self.assertIn("samples with no reproduced run: 1 of 4", out)
        self.assertIn(
            "untested: capital-city--names-paris--03 (must-pass sample 1: "
            '"The capital of France is Paris."), counted in no agreement',
            out,
        )
        self.assertEqual(
            out.strip().splitlines()[-1],
            "verdict: PASS (every grader at or above 90%; 1 untested)",
        )

    def test_an_unchecked_run_is_excluded_from_the_agreement(self):
        result = copy.deepcopy(self.result)
        del self.rows(result, 4)[3]["graders"][0]["evidence"]
        proc = self.score(result)
        out = proc.stdout
        self.assertIn("agreement 8/9 runs (88.9%) over 4 samples", out)
        self.assertIn("8 against judge evidence, 2 unchecked", out)
        self.assertIn(
            "reproduction unchecked, no trace or evidence: capital-city--names-paris--04 "
            "with-arm run 4",
            out,
        )

    def test_a_sample_with_only_unchecked_runs_is_untested(self):
        result = copy.deepcopy(self.result)
        for row in self.rows(result, 1):
            row.pop("tracePath", None)
            for grader in row["graders"]:
                grader.pop("evidence", None)
        proc = self.score(result)
        out = proc.stdout
        self.assertIn("samples with no reproduced run: 1 of 4", out)
        self.assertIn("untested: capital-city--names-paris--01", out)

    def test_a_false_positive_drops_the_grader_under_the_target(self):
        result = copy.deepcopy(self.result)
        grader = self.rows(result, 4)[0]["graders"][0]
        grader["judgeVotes"], grader["passed"] = [True, True, False], True
        proc = self.score(result)
        self.assertEqual(proc.returncode, 1, proc.stdout)
        self.assertIn("agreement 8/10 runs (80.0%)", proc.stdout)
        self.assertIn(
            "false positive: capital-city--names-paris--04 with-arm run 1 (must-fail "
            'sample 3: "The capital of France is Marseille.") votes PASS PASS FAIL',
            proc.stdout,
        )
        self.assertIn(
            "FAIL grader capital-city/names-paris: agreement 80.0% is under the 90% target",
            proc.stdout,
        )
        self.assertTrue(
            proc.stdout.strip().endswith("verdict: FAIL (capital-city/names-paris)")
        )

    def test_the_verdict_is_the_vote_majority_not_passed(self):
        result = copy.deepcopy(self.result)
        grader = self.rows(result, 3)[0]["graders"][0]
        grader["passed"] = True  # votes stay FAIL FAIL PASS
        proc = self.score(result)
        self.assertIn(
            "false negative: capital-city--names-paris--03 with-arm run 1", proc.stdout
        )

    def test_without_votes_the_passed_field_decides(self):
        result = copy.deepcopy(self.result)
        grader = self.rows(result, 3)[0]["graders"][0]
        del grader["judgeVotes"]
        proc = self.score(result)
        self.assertIn("no judgeVotes, read passed", proc.stdout)

    def test_a_reproduced_reply_differing_only_in_whitespace_counts(self):
        result = copy.deepcopy(self.result)
        self.rows(result, 3)[2]["graders"][0]["evidence"] = (
            "  The capital\nof France is Paris.\n"
        )
        proc = self.score(result)
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn("agreement 9/10 runs", proc.stdout)

    def test_a_reproduced_reply_that_adds_bold_counts(self):
        result = copy.deepcopy(self.result)
        self.rows(result, 3)[2]["graders"][0]["evidence"] = (
            "**The capital** of France is __Paris__."
        )
        proc = self.score(result)
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn("agreement 9/10 runs", proc.stdout)

    def test_a_trace_focus_never_reads_the_evidence(self):
        manifest = self.manifest(self.out)
        for entry in manifest["cases"]:
            entry["focus"] = "trace"
        path = self.dir / "trace-manifest.json"
        path.write_text(json.dumps(manifest))
        proc = self.score(manifest=path)
        self.assertIn(
            "reproduction: 2 checked against traces, 0 against judge evidence, 10 unchecked",
            proc.stdout,
        )
        self.assertIn("agreement 1/1 runs (100.0%) over 1 samples", proc.stdout)

    def test_a_case_missing_from_the_result_is_named(self):
        result = copy.deepcopy(self.result)
        result["cases"] = [c for c in result["cases"] if not c["name"].endswith("--02")]
        proc = self.score(result)
        self.assertIn(
            "missing from the result: capital-city--names-paris--02", proc.stdout
        )

    def test_a_grader_with_no_judged_run_fails(self):
        result = copy.deepcopy(self.result)
        for case in result["cases"]:
            for row in case["arms"]["with"]:
                row["skippedPaidGraders"] = True
        proc = self.score(result)
        self.assertEqual(proc.returncode, 1)
        self.assertIn("grader capital-city/names-paris: no judged run", proc.stdout)
        self.assertIn(
            "FAIL grader capital-city/names-paris: no judged run is under the 90% target",
            proc.stdout,
        )

    def test_unreadable_inputs_are_usage_errors(self):
        bad = self.dir / "bad.json"
        bad.write_text("not json")
        self.assertEqual(run("score", "--manifest", bad, RESULT).returncode, 2)
        self.assertEqual(
            run("score", "--manifest", self.manifest_path, bad).returncode, 2
        )
        self.assertEqual(
            run("score", "--manifest", self.dir / "none.json", RESULT).returncode, 2
        )
        self.assertEqual(run("score", RESULT).returncode, 2)
        empty = self.dir / "empty.json"
        empty.write_text('{"cases": []}')
        proc = run("score", "--manifest", empty, RESULT)
        self.assertEqual(proc.returncode, 2)
        self.assertIn("lists no cases", proc.stderr)


if __name__ == "__main__":
    unittest.main()
