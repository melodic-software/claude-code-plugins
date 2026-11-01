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
        # Its must-not-fire expectation became a max-0 Skill grader, so the
        # direction is known and no "add one by hand" note is owed.
        self.assertNotIn("note beta-stays-quiet: its expectations may say", done.stdout)
        self.assertIn("source keys not carried over: extra_key", done.stdout)
        self.assertIn("note alpha-natural-trigger: lists fixtures", done.stdout)

    def test_expectation_graders_get_samples_from_expected_output(self):
        self.sample_plugin()
        self.assertEqual(run(self.plugin).returncode, 0)
        for case, source, first in (
            ("alpha-slash-start", ALPHA_CASES[0], 1),
            ("alpha-natural-trigger", ALPHA_CASES[1], 1),
            # Its first expectation is a must-not-fire Skill check.
            ("beta-stays-quiet", BETA_CASES[0], 2),
        ):
            samples = self.plugin / "evals" / case / "samples"
            for number in range(first, len(source["expectations"]) + 1):
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

    def skill_md(self, skill, text):
        path = self.plugin / "skills" / skill / "SKILL.md"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def converted_tools(self, skill, skill_text):
        self.skill_md(skill, skill_text)
        self.source(skill, [dict(ALPHA_CASES[2])])
        done = run(self.plugin)
        self.assertEqual(done.returncode, 0, done.stderr)
        front, _ = self.prompt_md(skill + "-minimal-form")
        return front["allowed_tools"]

    def test_a_precomputed_line_grants_bash(self):
        tools = self.converted_tools(
            "alpha",
            "---\ndescription: Check node.\n---\n\n- `node`: !`command -v node`\n",
        )
        self.assertEqual(tools, ["Read", "Glob", "Grep", "Skill", "Bash"])

    def test_frontmatter_allowed_tools_are_granted_by_name(self):
        tools = self.converted_tools(
            "alpha",
            "---\ndescription: Commit.\nallowed-tools: Bash(git *), Edit\n---\n\n"
            "Commit the change.\n",
        )
        self.assertEqual(tools, ["Read", "Glob", "Grep", "Skill", "Bash", "Edit"])

    def test_a_block_list_and_a_bash_body_do_not_repeat_a_tool(self):
        tools = self.converted_tools(
            "alpha",
            '---\nallowed-tools:\n  - "Bash(command -v node*)"\n  - Read\n---\n\n'
            "Run `node --version` through Bash.\n",
        )
        self.assertEqual(tools, ["Read", "Glob", "Grep", "Skill", "Bash"])

    def test_body_wording_alone_grants_bash(self):
        tools = self.converted_tools(
            "alpha", "---\ndescription: Check.\n---\n\nRun node --version through Bash.\n"
        )
        self.assertEqual(tools, ["Read", "Glob", "Grep", "Skill", "Bash"])

    def test_negated_bash_wording_grants_nothing(self):
        for skill, body in (
            ("negone", "Do not use the Bash tool."),
            ("negtwo", "Never run this with Bash."),
            ("negthree", "Don't call it through Bash; read the file."),
        ):
            with self.subTest(body=body):
                tools = self.converted_tools(
                    skill, "---\ndescription: Read.\n---\n\n%s\n" % body
                )
                self.assertEqual(tools, ["Read", "Glob", "Grep", "Skill"])

    def test_a_negation_in_another_clause_still_grants_bash(self):
        for skill, body in (
            (
                "posone",
                "Its pre-computed context lines do not run when the file is read, so run "
                "`command -v node`, `node --version`, `command -v jq` and `jq --version` "
                "through Bash.",
            ),
            (
                "postwo",
                "Its pre-computed context lines are not rendered when this skill reads\n"
                "the file, so run every probe via Bash.",
            ),
        ):
            with self.subTest(body=body):
                tools = self.converted_tools(
                    skill, "---\ndescription: Check.\n---\n\n%s\n" % body
                )
                self.assertEqual(tools, ["Read", "Glob", "Grep", "Skill", "Bash"])

    def test_a_negation_wrapped_onto_the_previous_line_grants_nothing(self):
        tools = self.converted_tools(
            "wrapneg", "---\ndescription: Read.\n---\n\nDo not run the script\nthrough Bash.\n"
        )
        self.assertEqual(tools, ["Read", "Glob", "Grep", "Skill"])

    def test_an_indented_item_or_blank_line_is_not_joined_to_a_negation(self):
        for skill, body in (
            ("nested", "- Do not edit the config\n  - run the check through Bash"),
            ("spaced", "Do not edit the file\n  \nRun the tests through Bash."),
        ):
            with self.subTest(body=body):
                tools = self.converted_tools(
                    skill, "---\ndescription: Check.\n---\n\n%s\n" % body
                )
                self.assertEqual(tools, ["Read", "Glob", "Grep", "Skill", "Bash"])

    def test_a_plain_skill_keeps_the_base_tools(self):
        tools = self.converted_tools(
            "alpha", "---\ndescription: Summarize.\n---\n\nSummarize the doc.\n"
        )
        self.assertEqual(tools, ["Read", "Glob", "Grep", "Skill"])

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


class DeterministicTest(ConverterTestCase):
    """An expectation whose whole wording is a mechanical check gets a
    deterministic grader with samples the validator grades offline."""

    def convert(self, skill, expectations, prompt="Check my README, please.", **case):
        self.source(
            skill,
            [dict({"id": 1, "name": "case", "prompt": prompt,
                   "expectations": expectations}, **case)],
        )
        done = run(self.plugin)
        self.assertEqual(done.returncode, 0, done.stderr)
        checked = subprocess.run(
            [sys.executable, str(VALIDATOR), str(self.plugin / "evals")],
            capture_output=True,
            text=True,
        )
        self.assertEqual(checked.returncode, 0, checked.stdout + checked.stderr)
        self.assertNotIn("FAIL", checked.stdout)
        self.assertNotIn("no sample answers", checked.stdout)
        case_dir = self.plugin / "evals" / (skill + "-case")
        graders = {g["name"]: g for g in self.case_yaml(skill + "-case")["graders"]}
        return graders, case_dir / "samples"

    def assert_sampled(self, samples, grader):
        data = json.loads((samples / (grader + ".json")).read_text(encoding="utf-8"))
        self.assertTrue(data.get("pass") and data.get("fail"), data)

    def skill_with_tools(self, skill, tools):
        path = self.plugin / "skills" / skill / "SKILL.md"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            "---\ndescription: Do it.\nallowed-tools: %s\n---\n\nDo it.\n" % tools,
            encoding="utf-8",
        )

    def test_invoking_the_own_skill_is_a_skill_tool_used(self):
        graders, samples = self.convert("alpha", ["Invokes the alpha skill"])
        grader = graders["expectation-1"]
        self.assertEqual(grader["type"], "tool_used")
        self.assertEqual(grader["tool"], "Skill")
        self.assertIn("alpha", grader["input_match"])
        self.assert_sampled(samples, "expectation-1")

    def test_a_skill_that_must_not_fire_is_a_max_zero_skill_tool_used(self):
        (self.plugin / "skills" / "beta").mkdir(parents=True)
        for number, wording in enumerate(
            (
                "Does not invoke /sample:beta",
                "No Skill call reaches sample:beta",
                "The beta skill is NOT invoked",
            )
        ):
            with self.subTest(wording=wording):
                shutil.rmtree(self.plugin / "evals", ignore_errors=True)
                graders, samples = self.convert("alpha", [wording])
                grader = graders["expectation-1"]
                self.assertEqual(grader["type"], "tool_used")
                self.assertEqual((grader["min"], grader["max"]), (0, 0))
                self.assertEqual(grader["arm"], "both")
                self.assertIn("beta", grader["input_match"])
                self.assert_sampled(samples, "expectation-1")

    def test_a_command_that_must_run_is_a_bash_tool_used(self):
        self.skill_with_tools("alpha", "Bash")
        graders, samples = self.convert(
            "alpha",
            [
                "Runs `scripts/check.py --data-dir`",
                "Runs `command -v node` through Bash",
                "Does not run `npm install -g ctx7@latest` itself",
            ],
        )
        for name in ("expectation-1", "expectation-2", "expectation-3"):
            self.assertEqual(graders[name]["type"], "tool_used", name)
            self.assertEqual(graders[name]["tool"], "Bash", name)
            self.assert_sampled(samples, name)
        self.assertNotIn("max", graders["expectation-1"])
        self.assertEqual(graders["expectation-3"]["max"], 0)
        self.assertEqual(graders["expectation-3"]["arm"], "both")

    def test_a_named_literal_is_a_regex_over_the_reply(self):
        graders, samples = self.convert(
            "alpha",
            [
                "Reports the line `fanout_diversity: lens (default)`",
                "Names /sample:alpha",
                "The response mentions `--runs 1`",
            ],
        )
        for name in ("expectation-1", "expectation-2", "expectation-3"):
            self.assertEqual(graders[name]["type"], "regex", name)
            self.assertEqual(graders[name]["target"], "last_message", name)
            self.assert_sampled(samples, name)

    def test_a_written_file_is_a_file_exists(self):
        self.skill_with_tools("alpha", "Write")
        graders, samples = self.convert(
            "alpha",
            [
                "Writes the record at docs/upstream/acme-agent-skills.md",
                "Writes the control skill under .claude/skills/control-shop/",
            ],
        )
        self.assertEqual(graders["expectation-1"]["type"], "file_exists")
        self.assertEqual(
            graders["expectation-1"]["path"], "**/docs/upstream/acme-agent-skills.md"
        )
        self.assertEqual(
            graders["expectation-2"]["path"], "**/.claude/skills/control-shop/**"
        )
        for name in ("expectation-1", "expectation-2"):
            self.assert_sampled(samples, name)

    def test_ambiguous_or_judgment_wording_stays_llm(self):
        wordings = [
            "Routes to /sample:alpha",
            "Names /sample:alpha as the correct sibling",
            "Invokes /discovery:trace-intent for the why part",
            "Invokes /other:alpha",
            "Invokes the music skill, not sfx",
            "Runs `/sample:setup apply`",
            "Names the browser session `<run id>-login-flow`",
            "Writes the record at docs/upstream/acme.md",
            "Gives a clear, well-reasoned answer",
        ]
        self.source(
            "alpha",
            [{"id": 1, "name": "case", "prompt": "Check my README, please.",
              "expected_output": "A short report.", "expectations": wordings}],
        )
        self.assertEqual(run(self.plugin).returncode, 0)
        graders = self.case_yaml("alpha-case")["graders"]
        judged = [g for g in graders if g["name"].startswith("expectation-")]
        self.assertEqual([g["type"] for g in judged], ["llm"] * len(wordings))

    def test_a_qualified_command_stays_llm_even_with_bash_granted(self):
        self.skill_with_tools("alpha", "Bash")
        wordings = [
            "Runs `scripts/check.py --data-dir` and reports its rows",
            "Does not run `npm install -g ctx7@latest` and explains why",
        ]
        self.source(
            "alpha",
            [{"id": 1, "name": "case", "prompt": "Check my README, please.",
              "expected_output": "A short report.", "expectations": wordings}],
        )
        self.assertEqual(run(self.plugin).returncode, 0)
        graders = self.case_yaml("alpha-case")["graders"]
        judged = [g for g in graders if g["name"].startswith("expectation-")]
        self.assertEqual([g["type"] for g in judged], ["llm"] * len(wordings))

    def test_a_command_without_a_bash_grant_stays_llm(self):
        self.source(
            "alpha",
            [{"id": 1, "name": "case", "prompt": "Check my README, please.",
              "expected_output": "A short report.",
              "expectations": ["Runs `scripts/check.py`"]}],
        )
        self.assertEqual(run(self.plugin).returncode, 0)
        graders = self.case_yaml("alpha-case")["graders"]
        self.assertEqual(graders[0]["type"], "llm")

    def test_a_command_merely_mentioned_is_not_a_run(self):
        self.skill_with_tools("alpha", "Bash")
        graders, _ = self.convert(
            "alpha",
            [
                "Runs `scripts/check.py --data-dir`",
                "Does not run `npm install -g ctx7@latest` itself",
            ],
        )

        def grade(name, command):
            calls = [{"tool": "Bash", "input": {"command": command}}]
            return VALIDATE.grade_tool_used(graders[name], calls)[0]

        self.assertFalse(grade("expectation-1", "cat scripts/check.py && echo --data-dir"))
        self.assertFalse(grade("expectation-1", "grep -n x scripts/check.py --data-dir"))
        self.assertTrue(grade("expectation-1", 'cd /w && python3 "/w/scripts/check.py" --data-dir /d'))
        self.assertTrue(grade("expectation-2", "echo 'npm install -g ctx7@latest'"))
        self.assertFalse(grade("expectation-2", "npm install -g ctx7@latest"))
        self.assertFalse(grade("expectation-2", "cd /w && npm install -g ctx7@latest"))

    def test_a_path_keeps_out_the_closing_period(self):
        self.skill_with_tools("alpha", "Write")
        graders, _ = self.convert("alpha", ["Writes the record at docs/result.md."])
        self.assertEqual(graders["expectation-1"]["path"], "**/docs/result.md")

    def test_a_literal_inside_the_stock_reply_still_validates(self):
        for word in ("answer", "names", "nothing", "skill"):
            with self.subTest(word=word):
                shutil.rmtree(self.plugin / "evals", ignore_errors=True)
                graders, _ = self.convert("alpha", ["Names `%s`" % word])
                self.assertEqual(graders["expectation-1"]["type"], "regex")

    def test_a_sibling_guard_keeps_the_own_skill_grader_and_no_note(self):
        (self.plugin / "skills" / "beta").mkdir(parents=True)
        self.source(
            "alpha",
            [{"id": 1, "name": "case", "prompt": "Check my README, please.",
              "expectations": ["Does not invoke /sample:beta"]}],
        )
        done = run(self.plugin)
        self.assertEqual(done.returncode, 0, done.stderr)
        names = [g["name"] for g in self.case_yaml("alpha-case")["graders"]]
        self.assertEqual(names, ["expectation-1", "skill-fired"])
        self.assertNotIn("may say the skill must not fire", done.stdout)

    def test_a_refused_mapped_literal_names_its_case(self):
        self.source(
            "alpha",
            [{"id": 1, "name": "case", "prompt": "Hi",
              "expectations": ["Names `a\x01b`"]}],
        )
        done = run(self.plugin)
        self.assertEqual(done.returncode, 1, done.stdout)
        self.assertIn(
            "skills/alpha/evals/evals.json case 1 holds a control", done.stderr
        )

    def test_a_slash_prompt_keeps_an_own_skill_invocation_llm(self):
        graders, _ = self.convert(
            "alpha", ["Invokes the alpha skill"], prompt="/sample:alpha check it",
            expected_output="A report.",
        )
        self.assertEqual(graders["expectation-1"]["type"], "llm")


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
