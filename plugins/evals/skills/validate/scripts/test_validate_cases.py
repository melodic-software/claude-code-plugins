#!/usr/bin/env python3
"""Fixture suite for validate-cases.py.

Every fixture is built in a temporary directory from the inline strings here, so
no fixture tree is tracked: a tracked *.yaml has no test-selection mapping and a
tracked prompt.md would be linted as prose. One test runs the validator against
this repository's own pilot suite under plugins/evals/evals, which is the live
fixture for the clean path.

The suite is executed by validate-cases.test.sh, which run-plugin-tests.sh
discovers. Run it directly with: python3 test_validate_cases.py
"""

import json
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from textwrap import dedent

SCRIPT = Path(__file__).resolve().parent / "validate-cases.py"
REPO_ROOT = Path(__file__).resolve().parents[5]
PILOT_SUITE = REPO_ROOT / "plugins" / "evals" / "evals"

# One shared shape every FAIL fixture must emit, so a finding can never regress
# into a WARN at exit 0. Each test also asserts its own message below, which is
# what keeps the fixtures discriminating: this pattern alone does not.
FAIL_LINE = re.compile(
    r"^FAIL .*(unknown frontmatter key|duplicate grader|no grader|runs|not parsed"
    r"|schema_version|is required|requires|no prompt|sample)",
    re.MULTILINE,
)

CLEAN_PROMPT = """\
---
description: A read-only question
tags: [smoke]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
---

Answer the question in under 100 words.
"""

REGEX_GRADER = """\
---
type: regex
pattern: "conftest\\\\.py"
flags: i
arm: both
---
"""

SKILL_GRADER = """\
---
type: tool_used
tool: Skill
input_match: '"skill"\\\\s*:\\\\s*"(?:evals:)?methodology"'
---
"""


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(dedent(text), encoding="utf-8")


def run_validator(*args):
    return subprocess.run(
        [sys.executable, str(SCRIPT)] + list(args),
        capture_output=True,
        text=True,
    )


class ValidatorTestCase(unittest.TestCase):
    """Builds one throwaway eval dir per test."""

    def setUp(self):
        self._tmp = tempfile.mkdtemp(prefix="validate-cases-")
        self.addCleanup(shutil.rmtree, self._tmp, True)
        self.eval_dir = Path(self._tmp) / "evals"
        self.eval_dir.mkdir()

    def case(self, name, prompt=None, case_yaml=None, graders=None):
        case_dir = self.eval_dir / name
        case_dir.mkdir(parents=True, exist_ok=True)
        if prompt is not None:
            write(case_dir / "prompt.md", prompt)
        if case_yaml is not None:
            write(case_dir / "case.yaml", case_yaml)
        for grader_name, body in (graders or {}).items():
            write(case_dir / "graders" / (grader_name + ".md"), body)
        return case_dir

    def samples(self, case_name, grader_name, passing=(), failing=()):
        path = self.eval_dir / case_name / "samples" / (grader_name + ".json")
        path.parent.mkdir(parents=True, exist_ok=True)
        data = {
            "pass": [{"answer": answer} for answer in passing],
            "fail": [{"answer": answer} for answer in failing],
        }
        path.write_text(json.dumps(data), encoding="utf-8")

    def validate(self, *args):
        return run_validator(str(self.eval_dir), *args)

    def assert_fail(self, result, *substrings):
        self.assertEqual(
            1, result.returncode, "expected exit 1\n" + result.stdout + result.stderr
        )
        self.assertRegex(result.stdout, FAIL_LINE)
        for substring in substrings:
            self.assertIn(substring, result.stdout)

    def assert_clean(self, result):
        self.assertEqual(
            0, result.returncode, "expected exit 0\n" + result.stdout + result.stderr
        )
        self.assertNotIn("FAIL", result.stdout)
        # A sample set that could not be graded is a WARN, which would otherwise
        # let a broken mirror read as a clean pass.
        self.assertNotIn("samples not checked", result.stdout)


class UnknownKeyFixture(ValidatorTestCase):
    def test_unknown_prompt_frontmatter_key_fails(self):
        self.case(
            "unknown-key",
            prompt="""\
            ---
            description: An unknown key the binary rejects
            run_count: 3
            ---

            Do the thing.
            """,
            graders={"criteria": REGEX_GRADER},
        )
        result = self.validate()
        self.assert_fail(result, 'unknown frontmatter key "run_count"')
        self.assertIn("unknown-key/prompt.md", result.stdout)

    def test_undocumented_keys_the_binary_accepts_warn_without_failing(self):
        # Claude Code 2.1.287's case schema accepts both keys; the reference
        # page's prompt.md field table lists neither.
        self.case(
            "undocumented-keys",
            prompt="""\
            ---
            description: Two keys that load but are not documented
            artifact_publish: true
            growthbook_overrides: {some_flag: true}
            ---

            Do the thing.
            """,
            graders={"criteria": REGEX_GRADER},
        )
        self.samples("undocumented-keys", "criteria", ["conftest.py"], ["no"])
        result = self.validate()
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertNotIn("FAIL", result.stdout)
        for key in ("artifact_publish", "growthbook_overrides"):
            self.assertIn(
                'WARN undocumented-keys/prompt.md: frontmatter key "%s" loads but '
                "is undocumented" % key,
                result.stdout,
            )


class DuplicateGraderFixture(ValidatorTestCase):
    def test_duplicate_grader_name_across_yaml_and_dir_fails(self):
        self.case(
            "duplicate-grader",
            case_yaml="""\
            schema_version: "1.1"
            name: duplicate-grader
            execution:
              prompt: Do the thing.
            graders:
              - name: criteria
                type: regex
                pattern: "thing"
              - name: criteria
                type: regex
                pattern: "other"
            """,
        )
        result = self.validate()
        self.assert_fail(result, 'duplicate grader name "criteria"')

    def test_grader_list_and_grader_files_share_one_namespace(self):
        self.case(
            "duplicate-across-layouts",
            prompt=CLEAN_PROMPT,
            case_yaml="""\
            schema_version: "1.1"
            name: duplicate-across-layouts
            graders:
              - name: criteria
                type: regex
                pattern: "thing"
            """,
            graders={"criteria": REGEX_GRADER},
        )
        result = self.validate()
        self.assert_fail(result, 'duplicate grader name "criteria"')


class NoGraderFixture(ValidatorTestCase):
    def test_case_without_any_grader_fails(self):
        self.case("no-grader", prompt=CLEAN_PROMPT)
        result = self.validate()
        self.assert_fail(result, "no grader")
        self.assertIn("no-grader/", result.stdout)


class OverBoundsFixture(ValidatorTestCase):
    def test_every_bound_over_the_maximum_fails(self):
        self.case(
            "over-bounds",
            prompt="""\
            ---
            runs: 99
            max_turns: 500
            timeout_seconds: 7200
            ---

            Do the thing.
            """,
            graders={"criteria": REGEX_GRADER},
        )
        result = self.validate()
        self.assert_fail(result, "runs 99", "max_turns 500", "timeout_seconds 7200")

    def test_non_positive_grader_weight_fails(self):
        self.case(
            "zero-weight",
            prompt=CLEAN_PROMPT,
            graders={
                "criteria": """\
                ---
                type: regex
                pattern: "thing"
                weight: 0
                ---
                """
            },
        )
        result = self.validate()
        self.assertEqual(1, result.returncode, result.stdout)
        self.assertIn("weight 0", result.stdout)


class BadEnvKeyFixture(ValidatorTestCase):
    def test_env_key_without_the_eval_prefix_fails(self):
        self.case(
            "bad-env-key",
            prompt="""\
            ---
            env: { DEBUG: "1", EVAL_MODE: "fast" }
            ---

            Do the thing.
            """,
            graders={"criteria": REGEX_GRADER},
        )
        result = self.validate()
        self.assert_fail(result, 'env key "DEBUG"')
        self.assertNotIn("EVAL_MODE", result.stdout)


class PrecedenceFixture(ValidatorTestCase):
    def test_prompt_frontmatter_overrides_case_yaml(self):
        self.case(
            "precedence",
            prompt="""\
            ---
            runs: 99
            ---

            Do the thing.
            """,
            case_yaml="""\
            schema_version: "1.1"
            name: precedence
            runs: 3
            execution:
              max_turns: 10
            """,
            graders={"criteria": REGEX_GRADER},
        )
        result = self.validate()
        self.assert_fail(result, "runs 99")
        self.assertIn("precedence/prompt.md", result.stdout)

    def test_case_yaml_execution_bounds_are_read(self):
        self.case(
            "nested-bounds",
            case_yaml="""\
            schema_version: "1.1"
            name: nested-bounds
            execution:
              prompt: Do the thing.
              max_turns: 500
            graders:
              - name: criteria
                type: regex
                pattern: "thing"
            """,
        )
        result = self.validate()
        self.assertEqual(1, result.returncode, result.stdout)
        self.assertIn("max_turns 500", result.stdout)
        self.assertIn("nested-bounds/case.yaml", result.stdout)


class UnparsedFixture(ValidatorTestCase):
    def test_block_scalar_fails_closed(self):
        self.case(
            "unparsed-block-scalar",
            prompt="""\
            ---
            append_system_prompt: |
              Two lines
              of system prompt.
            ---

            Do the thing.
            """,
            graders={"criteria": REGEX_GRADER},
        )
        result = self.validate()
        self.assert_fail(result, "not parsed (block scalar)", "simplify or run the CLI")

    def test_anchor_fails_closed(self):
        self.case(
            "unparsed-anchor",
            case_yaml="""\
            schema_version: "1.1"
            name: unparsed-anchor
            tags: &defaults [smoke]
            graders:
              - name: criteria
                type: regex
                pattern: "thing"
            """,
        )
        result = self.validate()
        self.assert_fail(result, "not parsed (anchor)")

    def test_unsupported_double_quoted_escape_fails_closed(self):
        # "\d+" is not a valid YAML escape, so translating it to "d+" would
        # green-light a pattern the binary refuses and run a grader nobody wrote.
        self.case(
            "unparsed-escape",
            prompt=CLEAN_PROMPT,
            graders={
                "criteria": """\
                ---
                type: regex
                pattern: "\\d+"
                ---
                """
            },
        )
        result = self.validate()
        self.assert_fail(result, "not parsed (unsupported escape)")

    def test_indented_nested_sequence_fails_closed(self):
        # The compact `- - x` spelling is already rejected; the indented one is
        # the same construct and must fail the same way.
        self.case(
            "unparsed-nested-sequence",
            case_yaml="""\
            schema_version: "1.1"
            name: unparsed-nested-sequence
            tags:
              -
                - smoke
                - slow
            graders:
              - name: criteria
                type: regex
                pattern: "thing"
            """,
        )
        result = self.validate()
        self.assert_fail(result, "not parsed (nested sequence)")

    def test_unterminated_frontmatter_fails_closed(self):
        self.case(
            "unparsed-open",
            prompt="""\
            ---
            runs: 3

            Do the thing.
            """,
            graders={"criteria": REGEX_GRADER},
        )
        result = self.validate()
        self.assert_fail(result, "not parsed (unterminated frontmatter)")


class SchemaFixture(ValidatorTestCase):
    def test_case_yaml_alone_requires_schema_version_and_name(self):
        self.case(
            "yaml-only",
            case_yaml="""\
            execution:
              prompt: Do the thing.
            graders:
              - name: criteria
                type: regex
                pattern: "thing"
            """,
        )
        result = self.validate()
        self.assert_fail(
            result,
            'yaml-only/case.yaml: "schema_version" is required',
            'yaml-only/case.yaml: "name" is required',
        )

    def test_case_yaml_beside_prompt_md_still_requires_name(self):
        # A case `claude plugin eval` (2.1.295) refused with "invalid case.yaml:
        # name: Required": a case.yaml turns off the directory-name default
        # even when prompt.md carries the prompt.
        case_dir = self.case(
            "demo",
            prompt="""\
            ---
            description: "demo"
            allowed_tools: [Read]
            ---
            Say hi.
            """,
            case_yaml="""\
            schema_version: "1.1"
            context:
              scaffold_script: scaffold.sh
            """,
            graders={
                "says-hi": """\
                ---
                type: regex
                pattern: 'hi'
                ---
                """
            },
        )
        write(case_dir / "scaffold.sh", "#!/usr/bin/env bash\ntrue\n")
        result = self.validate()
        self.assert_fail(result, 'demo/case.yaml: "name" is required')
        self.assertNotIn('"schema_version" is required', result.stdout)

    def test_name_in_prompt_md_frontmatter_satisfies_a_case_yaml(self):
        self.case(
            "named-in-prompt",
            prompt=CLEAN_PROMPT.replace("---\n", "---\nname: named-in-prompt\n", 1),
            case_yaml="""\
            schema_version: "1.1"
            """,
            graders={"names-conftest": REGEX_GRADER, "skill-fired": SKILL_GRADER},
        )
        result = self.validate()
        self.assertEqual(0, result.returncode, result.stdout)
        self.assertNotIn("FAIL", result.stdout)

    def test_without_case_yaml_the_identity_defaults(self):
        self.case(
            "prose-only",
            prompt=CLEAN_PROMPT,
            graders={"names-conftest": REGEX_GRADER, "skill-fired": SKILL_GRADER},
        )
        result = self.validate()
        self.assertEqual(0, result.returncode, result.stdout)
        self.assertNotIn("FAIL", result.stdout)

    def test_an_empty_case_yaml_keeps_the_identity_default(self):
        # `claude plugin eval` (2.1.296) loads an empty, comment-only or
        # bare-marker case.yaml as no case.yaml: it reported only a grader
        # error for each, never "name: Required".
        for name, text in (("empty", ""), ("comment", "# x\n"), ("marker", "---\n")):
            self.case(
                name,
                prompt="Say hi.\n",
                case_yaml=text,
                graders={"names-conftest": REGEX_GRADER},
            )
        result = self.validate()
        self.assertEqual(0, result.returncode, result.stdout)
        self.assertNotIn("is required", result.stdout)

    def test_a_case_with_no_prompt_fails(self):
        # `claude plugin eval` refuses this case: "execution.prompt is required
        # (a prompt.md body, or execution.prompt in case.yaml)".
        self.case(
            "no-prompt",
            case_yaml="""\
            schema_version: "1.1"
            name: no-prompt
            execution:
              max_turns: 3
            graders:
              - name: criteria
                type: regex
                pattern: "thing"
            """,
        )
        self.assert_fail(self.validate(), "no-prompt/case.yaml: no prompt")

    def test_unsupported_schema_version_major_fails(self):
        self.case(
            "future-major",
            prompt="""\
            ---
            schema_version: "99.0"
            ---

            Do the thing.
            """,
            graders={"criteria": REGEX_GRADER},
        )
        result = self.validate()
        self.assert_fail(result, 'schema_version "99.0" is a major newer than 1')
        self.assertIn("future-major/prompt.md", result.stdout)

    def test_unsupported_schema_version_major_in_case_yaml_fails(self):
        self.case(
            "future-major-yaml",
            case_yaml="""\
            schema_version: "2.0"
            name: future-major-yaml
            execution:
              prompt: Do the thing.
            graders:
              - name: criteria
                type: regex
                pattern: "thing"
            """,
        )
        result = self.validate()
        self.assert_fail(result, 'schema_version "2.0" is a major newer than 1')

    def test_a_schema_version_with_no_leading_major_fails(self):
        # `claude plugin eval` refuses it: 'schema_version "next" is not a valid
        # version string'.
        self.case(
            "odd-version",
            prompt="""\
            ---
            schema_version: "next"
            ---

            Do the thing.
            """,
            graders={"names-conftest": REGEX_GRADER, "skill-fired": SKILL_GRADER},
        )
        self.assert_fail(
            self.validate(),
            'odd-version/prompt.md: schema_version "next" is not a valid version string',
        )

    def test_an_unquoted_schema_version_fails(self):
        self.case(
            "float-version",
            case_yaml="""\
            schema_version: 1.1
            name: float-version
            execution:
              prompt: Do the thing.
            graders:
              - name: criteria
                type: regex
                pattern: "thing"
            """,
        )
        self.assert_fail(
            self.validate(), "float-version/case.yaml: schema_version must be a quoted"
        )

    def test_each_grader_type_requires_its_options(self):
        # Messages `claude plugin eval` gave for the same shapes:
        # "graders.0.pattern: Required", "graders.2.tool: Required",
        # "graders.0.path: Required". An llm .md body stands in for criteria.
        self.case(
            "missing-options",
            prompt="Say hi.\n",
            case_yaml="""\
            schema_version: "1.1"
            name: missing-options
            graders:
              - name: made
                type: file_exists
            """,
            graders={
                "g": "---\ntype: regex\n---\n",
                "t": "---\ntype: tool_used\n---\n",
                "l": "---\ntype: llm\n---\nSays hi politely.\n",
            },
        )
        result = self.validate()
        self.assert_fail(
            result,
            'missing-options/case.yaml: grader type file_exists requires "path"',
            'missing-options/graders/g.md: grader type regex requires "pattern"',
            'missing-options/graders/t.md: grader type tool_used requires "tool"',
        )
        self.assertNotIn("graders/l.md: grader type llm requires", result.stdout)


class UnknownGraderOptionFixture(ValidatorTestCase):
    def test_unknown_option_for_the_declared_type_fails(self):
        self.case(
            "unknown-option",
            prompt=CLEAN_PROMPT,
            graders={
                "criteria": """\
                ---
                type: regex
                patterns: "thing"
                ---
                """
            },
        )
        result = self.validate()
        self.assertEqual(1, result.returncode, result.stdout)
        self.assertIn('unknown grader option "patterns"', result.stdout)

    def test_missing_type_reports_the_binary_message(self):
        self.case(
            "no-type",
            prompt=CLEAN_PROMPT,
            graders={
                "criteria": """\
                ---
                pattern: "thing"
                ---
                """
            },
        )
        result = self.validate()
        self.assertEqual(1, result.returncode, result.stdout)
        self.assertIn(
            'must include "type:" (regex | tool_order | tool_used | file_exists'
            " | llm | baseline)",
            result.stdout,
        )


class CleanFixture(ValidatorTestCase):
    def test_clean_case_exits_zero(self):
        self.case(
            "clean",
            prompt=CLEAN_PROMPT,
            graders={"names-conftest": REGEX_GRADER, "skill-fired": SKILL_GRADER},
        )
        self.assert_clean(self.validate())

    def test_flow_mapping_target_and_with_only_arm_parse(self):
        self.case(
            "flow-mapping",
            prompt=CLEAN_PROMPT,
            graders={
                "contents": """\
                ---
                type: regex
                pattern: "hello"
                target: { source: file, path: out.txt }
                arm: with-only
                ---
                """,
                "skill-fired": SKILL_GRADER,
            },
        )
        self.assert_clean(self.validate())

    def test_a_colon_inside_a_flow_mapping_value_is_not_a_key_separator(self):
        self.case(
            "flow-colons",
            prompt="""\
            ---
            env: { EVAL_URL: https://example.com, EVAL_AT: 12:30 }
            ---

            Do the thing.
            """,
            graders={"names-conftest": REGEX_GRADER, "skill-fired": SKILL_GRADER},
        )
        result = self.validate()
        self.assert_clean(result)
        self.assertNotIn("https", result.stdout)

    def test_grader_list_item_may_carry_a_block_mapping(self):
        # Three mapping levels: the document, the grader item, and target. The
        # graders sequence is not a level, so this is inside the subset.
        self.case(
            "block-target",
            case_yaml="""\
            schema_version: "1.1"
            name: block-target
            execution:
              prompt: Do the thing.
            graders:
              - name: contents
                type: regex
                pattern: "hello"
                target:
                  source: file
                  path: out.txt
            """,
        )
        self.assert_clean(self.validate())

    def test_a_fourth_mapping_level_still_fails_closed(self):
        self.case(
            "too-deep",
            case_yaml="""\
            schema_version: "1.1"
            name: too-deep
            execution:
              prompt: Do the thing.
            graders:
              - name: contents
                type: regex
                pattern: "hello"
                target:
                  source:
                    kind: file
                    path: out.txt
            """,
        )
        result = self.validate()
        self.assertEqual(1, result.returncode, result.stdout)
        self.assertIn("nesting deeper than three levels", result.stdout)

    def test_results_directory_is_not_a_case(self):
        self.case(
            "clean",
            prompt=CLEAN_PROMPT,
            graders={"names-conftest": REGEX_GRADER},
        )
        write(
            self.eval_dir / "results" / "2026-09-12T00-00-00-000Z" / "aggregate.json",
            '{"schemaVersion": 1}\n',
        )
        self.assert_clean(self.validate())

    def test_cases_may_be_grouped_under_a_non_case_directory(self):
        self.case(
            "group/nested",
            prompt=CLEAN_PROMPT,
            graders={"names-conftest": REGEX_GRADER},
        )
        result = self.validate()
        self.assert_clean(result)


class WarnTier(ValidatorTestCase):
    def test_warnings_do_not_change_the_exit_code(self):
        self.case(
            "warn-only",
            prompt="""\
            ---
            allowed_tools: [Read, Bash]
            ---

            Do the thing.
            """,
            graders={
                "created": """\
                ---
                type: file_exists
                path: "out/*.txt"
                ---
                """,
                "listed": """\
                ---
                type: regex
                pattern: "(?i)hello"
                target: files
                ---
                """,
            },
        )
        result = self.validate()
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertNotIn("FAIL", result.stdout)
        self.assertIn("WARN", result.stdout)
        self.assertIn("Bash", result.stdout)
        self.assertIn("(?i)", result.stdout)
        self.assertIn("target: files", result.stdout)

    def test_judge_only_case_warns_about_the_missing_deterministic_grader(self):
        self.case(
            "judge-only",
            prompt=CLEAN_PROMPT,
            graders={
                "criteria": """\
                ---
                type: llm
                ---

                PASS when the answer names conftest.py.
                """
            },
        )
        result = self.validate()
        self.assertEqual(0, result.returncode, result.stdout)
        self.assertIn("WARN", result.stdout)
        self.assertIn("judge grader", result.stdout)

    def test_a_sibling_write_case_does_not_silence_a_read_only_case(self):
        # Each case runs in its own throwaway workspace, so the write tool one
        # case asks for cannot make another case's file_exists satisfiable.
        self.case(
            "writes",
            prompt="""\
            ---
            allowed_tools: [Read, Write]
            ---

            Write out/report.txt.
            """,
            graders={"names-conftest": REGEX_GRADER},
        )
        self.case(
            "reads-only",
            prompt=CLEAN_PROMPT,
            graders={
                "created": """\
                ---
                type: file_exists
                path: "out/*.txt"
                ---
                """
            },
        )
        result = self.validate()
        self.assertEqual(0, result.returncode, result.stdout)
        self.assertIn("WARN reads-only/graders/created.md", result.stdout)
        self.assertEqual(1, result.stdout.count("file_exists in a read-only case"))

    def test_file_exists_does_not_warn_when_the_case_can_write(self):
        self.case(
            "writes",
            prompt="""\
            ---
            allowed_tools: [Read, Write]
            ---

            Write out/report.txt.
            """,
            graders={
                "created": """\
                ---
                type: file_exists
                path: "out/*.txt"
                ---
                """
            },
        )
        result = self.validate()
        self.assertEqual(0, result.returncode, result.stdout)
        self.assertNotIn("only files created during the run", result.stdout)


class OutputContract(ValidatorTestCase):
    def test_json_carries_one_object_per_finding(self):
        self.case("no-grader", prompt=CLEAN_PROMPT)
        result = self.validate("--json")
        self.assertEqual(1, result.returncode, result.stdout)
        findings = json.loads(result.stdout)
        self.assertTrue(findings)
        for finding in findings:
            self.assertEqual({"level", "case", "file", "message"}, set(finding))
        self.assertEqual("FAIL", findings[0]["level"])
        self.assertEqual("no-grader", findings[0]["case"])

    def test_empty_eval_dir_fails(self):
        result = self.validate()
        self.assertEqual(1, result.returncode, result.stdout)
        self.assertIn("no eval cases found", result.stdout)

    def test_missing_directory_is_a_usage_error(self):
        result = run_validator(str(self.eval_dir / "absent"))
        self.assertEqual(2, result.returncode, result.stdout + result.stderr)

    def test_no_argument_is_a_usage_error(self):
        self.assertEqual(2, run_validator().returncode)

    def test_help_prints_the_module_header(self):
        result = run_validator("--help")
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("validate-cases", result.stdout)
        self.assertIn("exit", result.stdout.lower())


def regex_grader(pattern, extra=""):
    return '---\ntype: regex\npattern: "%s"\n%s---\n' % (pattern, extra)


class SampleAnswers(ValidatorTestCase):
    def test_a_must_pass_answer_the_regex_rejects_fails(self):
        self.case("c", prompt=CLEAN_PROMPT, graders={"g": regex_grader("conftest")})
        self.samples("c", "g", passing=["use conftest.py", "a fixtures module"])
        result = self.validate()
        self.assert_fail(result, "must-pass sample 2 fails the grader")
        self.assertIn("c/samples/g.json", result.stdout)
        self.assertNotIn("must-pass sample 1", result.stdout)

    def test_a_must_fail_answer_the_regex_accepts_fails(self):
        self.case("c", prompt=CLEAN_PROMPT, graders={"g": regex_grader("conftest")})
        self.samples("c", "g", passing=["conftest.py"], failing=["a conftest file"])
        self.assert_fail(self.validate(), "must-fail sample 1 passes the grader")

    def test_samples_the_grader_sorts_correctly_are_clean(self):
        self.case("c", prompt=CLEAN_PROMPT, graders={"g": regex_grader("conftest")})
        self.samples("c", "g", passing=["conftest.py"], failing=["", "I don't know."])
        result = self.validate()
        self.assert_clean(result)
        self.assertNotIn("no sample answers", result.stdout)

    def test_the_why_label_appears_in_the_finding(self):
        self.case("c", prompt=CLEAN_PROMPT, graders={"g": regex_grader("conftest")})
        path = self.eval_dir / "c" / "samples" / "g.json"
        path.parent.mkdir(parents=True)
        path.write_text(
            json.dumps({"pass": [{"answer": "nope", "why": "R2 phrasing"}]}),
            encoding="utf-8",
        )
        self.assert_fail(self.validate(), 'must-pass sample 1 ("R2 phrasing") fails')

    def test_flags_i_is_honored_and_no_flags_is_case_sensitive(self):
        self.case(
            "c",
            prompt=CLEAN_PROMPT,
            graders={
                "loose": regex_grader("conftest", "flags: i\n"),
                "strict": regex_grader("conftest"),
            },
        )
        self.samples("c", "loose", passing=["CONFTEST.PY"], failing=["pytest"])
        self.samples("c", "strict", passing=["conftest.py"], failing=["CONFTEST.PY"])
        self.assert_clean(self.validate())

    def test_multiline_and_dotall_flags_change_the_match(self):
        self.case(
            "c",
            prompt=CLEAN_PROMPT,
            graders={
                "line": regex_grader("^two$", "flags: m\n"),
                "span": regex_grader("one.two", "flags: s\n"),
            },
        )
        self.samples("c", "line", passing=["one\ntwo\nthree"], failing=["one two"])
        self.samples("c", "span", passing=["one\ntwo"], failing=["one\n\ntwo"])
        self.assert_clean(self.validate())

    def test_not_contains_and_count_modes(self):
        self.case(
            "c",
            prompt=CLEAN_PROMPT,
            graders={
                "absent": regex_grader("TODO", "match: not_contains\n"),
                "twice": regex_grader("ok", 'match: "count:2"\n'),
            },
        )
        self.samples("c", "absent", passing=["done"], failing=["a TODO left"])
        self.samples("c", "twice", passing=["ok, ok"], failing=["ok", "ok ok ok"])
        self.assert_clean(self.validate())

    def test_a_javascript_named_group_is_translated(self):
        self.case(
            "c",
            prompt=CLEAN_PROMPT,
            graders={"g": regex_grader("(?<word>ab)\\\\k<word>")},
        )
        self.samples("c", "g", passing=["abab"], failing=["ab"])
        self.assert_clean(self.validate())

    def test_tool_used_matches_the_compact_json_input_and_its_bounds(self):
        self.case(
            "c",
            prompt=CLEAN_PROMPT,
            graders={
                "fired": """\
                ---
                type: tool_used
                tool: Skill
                input_match: '"skill":"(?:evals:)?methodology"'
                ---
                """,
                "never": """\
                ---
                type: tool_used
                tool: Skill
                min: 0
                max: 0
                arm: both
                ---
                """,
            },
        )
        skill = {"tool": "Skill", "input": {"skill": "evals:methodology"}}
        other = {"tool": "Skill", "input": {"skill": "evals:design"}}
        read = {"tool": "Read", "input": {"file_path": "a.md"}}
        self.samples(
            "c", "fired", passing=[[skill], [read, skill]], failing=[[], [other]]
        )
        self.samples("c", "never", passing=[[], [read]], failing=[[skill], [other]])
        self.assert_clean(self.validate())

    def test_tool_order_compares_the_first_matching_calls(self):
        self.case(
            "c",
            prompt=CLEAN_PROMPT,
            graders={
                "order": """\
                ---
                type: tool_order
                before: Read
                after: { tool: Skill, input_match: "design" }
                ---
                """
            },
        )
        read = {"tool": "Read", "input": {}}
        design = {"tool": "Skill", "input": {"skill": "evals:design"}}
        self.samples(
            "c",
            "order",
            passing=[[read, design], [read, design, read]],
            failing=[[design, read], [read], [design]],
        )
        self.assert_clean(self.validate())

    def test_file_exists_uses_the_anchored_glob(self):
        self.case(
            "c",
            prompt="""\
            ---
            allowed_tools: [Read, Write]
            ---

            Write the report.
            """,
            graders={
                "made": """\
                ---
                type: file_exists
                path: "out/**/*.txt"
                ---
                """,
                "absent": """\
                ---
                type: file_exists
                path: "*.log"
                exists: false
                ---
                """,
            },
        )
        self.samples(
            "c",
            "made",
            passing=[["out/a.txt"], ["out/x/y/b.txt"]],
            failing=[[], ["out/a.md"], ["src/out/a.txt"]],
        )
        self.samples(
            "c", "absent", passing=[[], ["logs/run.log"]], failing=[["run.log"]]
        )
        self.assert_clean(self.validate())

    def test_a_deterministic_grader_without_samples_warns(self):
        self.case("c", prompt=CLEAN_PROMPT, graders={"g": REGEX_GRADER})
        result = self.validate()
        self.assertEqual(0, result.returncode, result.stdout)
        self.assertIn("WARN c/graders/g.md: no sample answers", result.stdout)

    def test_a_one_sided_sample_file_warns(self):
        self.case("c", prompt=CLEAN_PROMPT, graders={"g": regex_grader("conftest")})
        self.samples("c", "g", passing=["conftest.py"])
        result = self.validate()
        self.assertEqual(0, result.returncode, result.stdout)
        self.assertIn("no must-fail answers", result.stdout)

    def test_judge_samples_warn_for_calibration_and_are_never_graded(self):
        self.case(
            "c",
            prompt=CLEAN_PROMPT,
            graders={
                "judge": "---\ntype: llm\n---\n\nPASS when the answer names conftest.py.\n",
                "g": REGEX_GRADER,
            },
        )
        # Samples a regex would sort the other way: a judge's are not graded.
        self.samples("c", "judge", passing=[""], failing=["conftest.py"])
        result = self.validate()
        self.assertEqual(0, result.returncode, result.stdout)
        self.assertIn("2 sample answers need judge calibration", result.stdout)
        self.assertNotIn("graders/judge.md: no sample answers", result.stdout)

    def test_samples_for_a_grader_in_case_yaml_are_found_by_name(self):
        self.case(
            "c",
            case_yaml="""\
            schema_version: "1.1"
            name: c
            execution:
              prompt: Do the thing.
            graders:
              - name: listed
                type: regex
                pattern: "thing"
            """,
        )
        self.samples("c", "listed", passing=["other"], failing=["nothing"])
        result = self.validate()
        self.assert_fail(
            result, "must-pass sample 1 fails", "must-fail sample 1 passes"
        )

    def test_malformed_samples_fail_closed(self):
        self.case(
            "c",
            prompt=CLEAN_PROMPT,
            graders={
                "a": regex_grader("x"),
                "b": regex_grader("x"),
                "d": regex_grader("x"),
            },
        )
        directory = self.eval_dir / "c" / "samples"
        directory.mkdir()
        (directory / "a.json").write_text("{not json", encoding="utf-8")
        (directory / "b.json").write_text('{"passes": []}', encoding="utf-8")
        (directory / "d.json").write_text('{"pass": [{"answer": 3}]}', encoding="utf-8")
        result = self.validate()
        self.assert_fail(
            result,
            "c/samples/a.json: samples not parsed",
            'unknown key "passes"',
            "answer must be a string for a regex grader",
        )

    def test_samples_for_no_grader_warn(self):
        self.case("c", prompt=CLEAN_PROMPT, graders={"g": regex_grader("x")})
        self.samples("c", "g", passing=["x"], failing=["y"])
        self.samples("c", "renamed", passing=["x"], failing=["y"])
        result = self.validate()
        self.assertEqual(0, result.returncode, result.stdout)
        self.assertIn('no grader named "renamed"', result.stdout)

    def test_an_unmirrorable_flag_warns_instead_of_grading(self):
        self.case(
            "c",
            prompt=CLEAN_PROMPT,
            graders={"g": regex_grader("x", "flags: y\n")},
        )
        self.samples("c", "g", passing=["no match here", "x"], failing=["x"])
        result = self.validate()
        self.assertEqual(0, result.returncode, result.stdout)
        self.assertIn("samples not checked: flag y", result.stdout)
        self.assertEqual(1, result.stdout.count("samples not checked"))


class R2Regression(ValidatorTestCase):
    """The tracked samples catch the regex that scored R2's with-arm 0."""

    R2_PATTERN = (
        "showpiece|fastest, most reliable, most scalable|headline (metric|number)"
        "|read(ing)? (a )?samples?"
    )

    def test_the_r2_regex_fails_the_tracked_samples(self):
        case_dir = self.eval_dir / "grading-method-choice"
        shutil.copytree(PILOT_SUITE / "grading-method-choice", case_dir)
        write(
            case_dir / "graders" / "methodology-wording.md",
            regex_grader(self.R2_PATTERN, "flags: i\narm: both\n"),
        )
        result = self.validate()
        # Samples 1 and 5 carry the two phrasings the R2 with-arm used.
        self.assert_fail(
            result,
            "must-pass sample 1 (",
            "must-pass sample 5 (",
            "must-fail sample 7 (",
        )

    def test_the_tracked_regex_passes_the_tracked_samples(self):
        shutil.copytree(
            PILOT_SUITE / "grading-method-choice",
            self.eval_dir / "grading-method-choice",
        )
        self.assert_clean(self.validate())


class PilotSuite(unittest.TestCase):
    def test_tracked_pilot_suite_passes(self):
        self.assertTrue(
            PILOT_SUITE.is_dir(),
            "the tracked pilot suite is missing at " + str(PILOT_SUITE),
        )
        result = run_validator(str(PILOT_SUITE))
        self.assertEqual(
            0,
            result.returncode,
            "the live fixture must validate clean\n" + result.stdout + result.stderr,
        )
        self.assertNotIn("FAIL", result.stdout)
        # Every deterministic grader in the pilot suite carries checked samples.
        self.assertNotIn("no sample answers", result.stdout)
        self.assertNotIn("samples not checked", result.stdout)


if __name__ == "__main__":
    unittest.main()
