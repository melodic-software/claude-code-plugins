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
    r"^FAIL .*(unknown frontmatter key|duplicate grader|no grader|runs|not parsed)",
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

    def test_file_exists_does_not_warn_when_the_suite_can_write(self):
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


if __name__ == "__main__":
    unittest.main()
