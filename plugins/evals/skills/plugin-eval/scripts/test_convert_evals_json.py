# test-scope: plugins/evals/skills/validate/scripts/validate-cases.py
"""Fixture suite for convert-evals-json.py.

Every fixture plugin is built in a temporary directory from the inline data
here, so no evals.json is tracked for it. The converted suite is checked with
the validate skill's validate-cases.py, the same check /evals:validate runs.

The suite is executed by convert-evals-json.test.sh, which run-plugin-tests.sh
discovers. Run it directly with: python3 test_convert_evals_json.py
"""

import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "convert-evals-json.py"
VALIDATOR = HERE.parents[1] / "validate" / "scripts" / "validate-cases.py"


def load_validator():
    spec = importlib.util.spec_from_file_location("validate_cases", str(VALIDATOR))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


VALIDATE = load_validator()

TRICKY = "Quotes 'single' and \"double\", a backslash \\d, and a #hash"

ALPHA_CASES = [
    {
        "id": 1,
        "name": "slash-start",
        "prompt": "/sample:alpha run it on README.md",
        "expected_output": "Reports the findings.",
        "expectations": ["Names at least one finding", TRICKY],
    },
    {
        "id": 2,
        "name": "natural-trigger",
        "prompt": "Can you check my README for problems?\n\nIt is short.",
        "expected_output": "Line one.\nLine two with a tab\there.",
        "expectations": ["Triggers the alpha flow without a slash command"],
        "difficulty": "hard",
        "why_hard": "The ask never names the skill.",
        "source": "an observed miss",
        "files": ["evals/fixtures/readme.md"],
    },
    {
        "id": "minimal-form",
        "prompt": "Summarize the doc.",
        "expected_output": "A three-line summary.",
    },
]

BETA_CASES = [
    {
        "id": 1,
        "name": "beta-stays-quiet",
        "prompt": "What time zone is UTC+2?",
        "expected_output": "Answers directly.",
        "expectations": ["Does not invoke the beta skill", "Answers the question"],
        "extra_key": True,
    }
]


def run(*args):
    return subprocess.run(
        [sys.executable, str(SCRIPT)] + [str(arg) for arg in args],
        capture_output=True,
        text=True,
    )


class ConverterTestCase(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.mkdtemp(prefix="convert-evals-json-")
        self.addCleanup(shutil.rmtree, self._tmp, True)
        self.plugin = Path(self._tmp) / "sample"
        manifest = self.plugin / ".claude-plugin" / "plugin.json"
        manifest.parent.mkdir(parents=True)
        manifest.write_text(json.dumps({"name": "sample"}), encoding="utf-8")

    def source(self, skill, cases):
        path = self.plugin / "skills" / skill / "evals" / "evals.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps({"skill_name": skill, "evals": cases}), encoding="utf-8"
        )
        return path

    def sample_plugin(self):
        alpha = self.source("alpha", ALPHA_CASES)
        fixture = alpha.parent / "fixtures" / "readme.md"
        fixture.parent.mkdir()
        fixture.write_text("# Readme\n", encoding="utf-8")
        beta = self.source("beta", BETA_CASES)
        return alpha, beta, fixture

    def case_yaml(self, case):
        text = (self.plugin / "evals" / case / "case.yaml").read_text(encoding="utf-8")
        return VALIDATE.parse_yaml(text)

    def prompt_md(self, case):
        text = (self.plugin / "evals" / case / "prompt.md").read_text(encoding="utf-8")
        block, body = VALIDATE.split_markdown(text)
        return VALIDATE.parse_yaml(block), body.strip()


class ConvertTest(ConverterTestCase):
    def test_sample_plugin_passes_the_validator(self):
        alpha, beta, fixture = self.sample_plugin()
        done = run(self.plugin)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("sample: 4 cases from 2 evals.json files", done.stdout)
        self.assertIn("skills/alpha/evals/evals.json: 3 cases", done.stdout)
        self.assertIn("skills/beta/evals/evals.json: 1 case\n", done.stdout)
        checked = subprocess.run(
            [sys.executable, str(VALIDATOR), str(self.plugin / "evals")],
            capture_output=True,
            text=True,
        )
        self.assertEqual(checked.returncode, 0, checked.stdout + checked.stderr)
        self.assertNotIn("FAIL", checked.stdout)

        cases = sorted(p.name for p in (self.plugin / "evals").iterdir())
        self.assertEqual(
            cases,
            [
                "alpha-minimal-form",
                "alpha-natural-trigger",
                "alpha-slash-start",
                "beta-stays-quiet",
            ],
        )
        self.assertFalse(alpha.exists())
        self.assertFalse(beta.exists())
        self.assertTrue(fixture.exists(), "fixtures stay where the case lists them")
        self.assertFalse(beta.parent.exists(), "an emptied evals/ dir is removed")

    def test_prompt_and_expected_outcome_survive(self):
        self.sample_plugin()
        self.assertEqual(run(self.plugin).returncode, 0)
        front, body = self.prompt_md("alpha-natural-trigger")
        self.assertEqual(body, ALPHA_CASES[1]["prompt"])
        self.assertEqual(front["expected_outcome"], ALPHA_CASES[1]["expected_output"])
        self.assertEqual(front["tags"], ["alpha", "hard"])
        self.assertIn("Why hard: The ask never names the skill.", front["description"])
        self.assertIn("skills/alpha/evals/fixtures/readme.md", front["description"])

    def test_each_expectation_becomes_an_llm_grader(self):
        self.sample_plugin()
        self.assertEqual(run(self.plugin).returncode, 0)
        data = self.case_yaml("alpha-slash-start")
        self.assertEqual(data["schema_version"], "1.1")
        self.assertEqual(data["name"], "alpha-slash-start")
        graders = data["graders"]
        self.assertEqual([g["type"] for g in graders], ["llm", "llm"])
        self.assertEqual(graders[1]["criteria"], TRICKY)

        minimal = self.case_yaml("alpha-minimal-form")["graders"]
        self.assertEqual(minimal[0]["name"], "expected-output")
        self.assertEqual(minimal[0]["criteria"], "A three-line summary.")

    def test_skill_grader_only_where_the_direction_is_known(self):
        self.sample_plugin()
        done = run(self.plugin)
        self.assertEqual(done.returncode, 0)
        natural = self.case_yaml("alpha-natural-trigger")["graders"]
        fired = [g for g in natural if g["name"] == "skill-fired"]
        self.assertEqual(len(fired), 1)
        self.assertEqual(fired[0]["tool"], "Skill")
        samples = self.plugin / "evals" / "alpha-natural-trigger" / "samples"
        self.assertTrue((samples / "skill-fired.json").is_file())

        for case in ("alpha-slash-start", "beta-stays-quiet"):
            names = [g["name"] for g in self.case_yaml(case)["graders"]]
            self.assertNotIn("skill-fired", names, case)
        self.assertIn("note beta-stays-quiet: its expectations may say", done.stdout)
        self.assertIn("source keys not carried over: extra_key", done.stdout)
        self.assertIn("note alpha-natural-trigger: lists fixtures", done.stdout)

    def test_expectation_graders_get_samples_from_expected_output(self):
        self.sample_plugin()
        self.assertEqual(run(self.plugin).returncode, 0)
        for case, source in (
            ("alpha-slash-start", ALPHA_CASES[0]),
            ("alpha-natural-trigger", ALPHA_CASES[1]),
            ("beta-stays-quiet", BETA_CASES[0]),
        ):
            samples = self.plugin / "evals" / case / "samples"
            for number in range(1, len(source["expectations"]) + 1):
                path = samples / ("expectation-%d.json" % number)
                data = json.loads(path.read_text(encoding="utf-8"))
                self.assertEqual(list(data), ["pass"], case)
                answers = [item["answer"] for item in data["pass"]]
                self.assertEqual(answers, [source["expected_output"]], case)
        minimal = self.plugin / "evals" / "alpha-minimal-form" / "samples"
        self.assertFalse(
            (minimal / "expected-output.json").exists(),
            "expected-output is its own criteria",
        )

    def test_expectations_without_expected_output_get_a_note(self):
        case = {
            "id": 1,
            "name": "no-output",
            "prompt": "Hi",
            "expectations": ["Greets"],
        }
        self.source("alpha", [case])
        done = run(self.plugin)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn(
            "note alpha-no-output: has expectations but no expected_output", done.stdout
        )
        samples = self.plugin / "evals" / "alpha-no-output" / "samples"
        self.assertEqual([p.name for p in samples.iterdir()], ["skill-fired.json"])

    def test_narration_is_carried_into_the_case(self):
        self.source("alpha", [dict(ALPHA_CASES[2], narration=True)])
        done = run(self.plugin)
        self.assertEqual(done.returncode, 0, done.stderr)
        front, _ = self.prompt_md("alpha-minimal-form")
        self.assertEqual(front["tags"], ["alpha", "narration"])
        self.assertIn("names fictional or consumer-repo paths", front["description"])
        self.assertNotIn("not carried over", done.stdout)

    def test_narration_that_is_not_a_boolean_gets_a_note(self):
        self.source("alpha", [dict(ALPHA_CASES[2], narration="yes")])
        done = run(self.plugin)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn(
            "note alpha-minimal-form: narration is not true or false", done.stdout
        )
        front, _ = self.prompt_md("alpha-minimal-form")
        self.assertEqual(front["tags"], ["alpha"])

    def test_path_prompt_and_separate_items_keep_the_skill_grader(self):
        case = {
            "id": 1,
            "name": "path-prompt",
            "prompt": "/srv/app fails to start; why?",
            "expectations": ["Does not edit any file", "Triggers the alpha skill"],
        }
        self.source("alpha", [case])
        self.assertEqual(run(self.plugin).returncode, 0)
        names = [g["name"] for g in self.case_yaml("alpha-path-prompt")["graders"]]
        self.assertEqual(names, ["expectation-1", "expectation-2", "skill-fired"])

    def test_dry_run_writes_nothing(self):
        alpha, beta, _ = self.sample_plugin()
        done = run(self.plugin, "--dry-run")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("sample: 4 cases from 2 evals.json files (dry run", done.stdout)
        self.assertFalse((self.plugin / "evals").exists())
        self.assertTrue(alpha.exists() and beta.exists())

    def test_no_source_is_a_count_of_zero(self):
        done = run(self.plugin)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("sample: 0 cases from 0 evals.json files", done.stdout)


class RefuseTest(ConverterTestCase):
    def assert_refused(self, done, message, *sources):
        self.assertEqual(done.returncode, 1, done.stdout)
        self.assertIn(message, done.stderr)
        self.assertIn("nothing was written or removed", done.stderr)
        for path in sources:
            self.assertTrue(path.exists(), path)

    def test_existing_case_directory_is_not_overwritten(self):
        alpha, beta, _ = self.sample_plugin()
        existing = self.plugin / "evals" / "alpha-slash-start"
        existing.mkdir(parents=True)
        (existing / "prompt.md").write_text("kept\n", encoding="utf-8")
        done = run(self.plugin)
        self.assert_refused(done, "evals/alpha-slash-start already exists", alpha, beta)
        self.assertEqual((existing / "prompt.md").read_text(encoding="utf-8"), "kept\n")
        self.assertEqual(
            [p.name for p in (self.plugin / "evals").iterdir()], ["alpha-slash-start"]
        )

    def test_two_cases_on_one_directory(self):
        case = {"id": 1, "name": "same", "prompt": "Hi", "expected_output": "Hello"}
        alpha = self.source("alpha", [case, dict(case, id=2)])
        self.assert_refused(run(self.plugin), "both map to evals/alpha-same", alpha)

    def test_non_string_expectation(self):
        case = {"id": 1, "prompt": "Hi", "expectations": [{"text": "Greets"}]}
        alpha = self.source("alpha", [case])
        self.assert_refused(run(self.plugin), "expectations item 1 is not a string", alpha)

    def test_case_with_no_criterion(self):
        alpha = self.source("alpha", [{"id": 1, "prompt": "Hi"}])
        self.assert_refused(run(self.plugin), "no expectations and no expected_output", alpha)

    def test_unreadable_source(self):
        path = self.plugin / "skills" / "alpha" / "evals" / "evals.json"
        path.parent.mkdir(parents=True)
        path.write_text("{not json", encoding="utf-8")
        self.assert_refused(run(self.plugin), "not readable JSON", path)

    def test_missing_plugin_dir_is_a_usage_error(self):
        done = run(Path(self._tmp) / "absent")
        self.assertEqual(done.returncode, 2)


if __name__ == "__main__":
    unittest.main()
