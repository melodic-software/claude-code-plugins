#!/usr/bin/env python3
# test-scope: plugins/evals/scripts/case_skills.py
import importlib.util
import sys
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parent / "case_skills.py"


def _load_case_skills():
    spec = importlib.util.spec_from_file_location("evals_case_skills", str(MODULE_PATH))
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


case_skills = _load_case_skills()
Reference = case_skills.Reference


def skill_grader(input_match, name="fired", path="graders/fired.md"):
    return (
        name,
        {"type": "tool_used", "tool": "Skill", "input_match": input_match},
        path,
    )


def agent_grader(input_match, name="dispatched", path="graders/dispatched.md"):
    return (
        name,
        {"type": "tool_used", "tool": "Agent", "input_match": input_match},
        path,
    )


class CaseSkillsReferences(unittest.TestCase):
    def test_leading_plugin_skill_prompt(self):
        refs = case_skills.references(
            "/demo:real run this", "prompt.md", (), ()
        )
        self.assertEqual(
            [Reference("prompt", "prompt.md", "demo", "real", "skill", False, "literal")],
            refs,
        )
        self.assertEqual(("demo", "real"), case_skills.resolve(refs[0], "suite"))
        self.assertEqual(
            {("demo", "real")},
            case_skills.skills_under_test("/demo:real run this", "prompt.md", (), (), "suite"),
        )

    def test_leading_bare_slash_skill_prompt(self):
        refs = case_skills.references(
            "  /methodology check this", "prompt.md", (), ()
        )
        self.assertEqual(
            [
                Reference(
                    "prompt", "prompt.md", None, "methodology", "skill", False, "bare"
                )
            ],
            refs,
        )
        self.assertEqual(("evals", "methodology"), case_skills.resolve(refs[0], "evals"))
        self.assertEqual(
            {("evals", "methodology")},
            case_skills.skills_under_test(
                "  /methodology check this", "prompt.md", (), (), "evals"
            ),
        )

    def test_plugin_skill_tag(self):
        refs = case_skills.references(
            "Answer the question.",
            "prompt.md",
            [(["demo:real"], "case.yaml")],
            (),
        )
        self.assertEqual(
            [Reference("tag", "case.yaml", "demo", "real", "skill", False, "literal")],
            refs,
        )
        self.assertEqual(
            {("demo", "real")},
            case_skills.skills_under_test(
                "Answer the question.",
                "prompt.md",
                [(["demo:real"], "case.yaml")],
                (),
                "suite",
            ),
        )

    def test_bare_tag(self):
        refs = case_skills.references(
            "Answer the question.",
            "prompt.md",
            [(["methodology"], "prompt.md")],
            (),
        )
        self.assertEqual(
            [
                Reference(
                    "tag", "prompt.md", None, "methodology", "skill", False, "bare"
                )
            ],
            refs,
        )
        self.assertEqual(("evals", "methodology"), case_skills.resolve(refs[0], "evals"))
        self.assertEqual(
            {("evals", "methodology")},
            case_skills.skills_under_test(
                "Answer the question.",
                "prompt.md",
                [(["methodology"], "prompt.md")],
                (),
                "evals",
            ),
        )

    def test_tool_used_skill_grader_literal(self):
        graders = [skill_grader('"skill":"demo:real"')]
        refs = case_skills.references("Do the thing.", "prompt.md", (), graders)
        self.assertEqual(
            [
                Reference(
                    "grader",
                    "graders/fired.md",
                    "demo",
                    "real",
                    "skill",
                    False,
                    "literal",
                )
            ],
            refs,
        )
        self.assertEqual(
            {("demo", "real")},
            case_skills.skills_under_test("Do the thing.", "prompt.md", (), graders, "suite"),
        )

    def test_optional_prefix_grader_forms(self):
        cases = (
            ("bare-optional-prefix", "(?:demo:)?real", True),
            ("word-boundaries", r"\b(?:demo:)?real\b", False),
            ("anchors", r"^(?:demo:)?real$", False),
            ("json-wrapped", r'"skill"\s*:\s*"(?:demo:)?real"', False),
        )
        for label, pattern, expected_prefix in cases:
            with self.subTest(label):
                graders = [skill_grader(pattern)]
                refs = case_skills.references("Do it.", "prompt.md", (), graders)
                self.assertEqual(
                    [
                        Reference(
                            "grader",
                            "graders/fired.md",
                            "demo",
                            "real",
                            "skill",
                            expected_prefix,
                            "optional-prefix",
                        )
                    ],
                    refs,
                )
                self.assertEqual(
                    {("demo", "real")},
                    case_skills.skills_under_test(
                        "Do it.", "prompt.md", (), graders, "suite"
                    ),
                )
        self.assertEqual(
            [],
            case_skills.references(
                "Do it.", "prompt.md", (), [skill_grader(r"label:\s?value")]
            ),
        )

    def test_bare_json_skill_grader_form(self):
        for label, pattern in (
            ("compact", '"skill":"methodology"'),
            ("spaced-regex", r'"skill"\s*:\s*"methodology"'),
            ("escaped-quotes", r'\"skill\"\s*:\s*\"methodology\"'),
        ):
            with self.subTest(label):
                graders = [skill_grader(pattern)]
                refs = case_skills.references("Do it.", "prompt.md", (), graders)
                self.assertEqual(
                    [
                        Reference(
                            "grader",
                            "graders/fired.md",
                            None,
                            "methodology",
                            "skill",
                            False,
                            "bare",
                        )
                    ],
                    refs,
                )
                self.assertEqual(
                    {("evals", "methodology")},
                    case_skills.skills_under_test(
                        "Do it.", "prompt.md", (), graders, "evals"
                    ),
                )

    def test_agent_grader_literal(self):
        graders = [agent_grader('"subagent_type":"demo:helper"')]
        refs = case_skills.references("Do it.", "prompt.md", (), graders)
        self.assertEqual(
            [
                Reference(
                    "grader",
                    "graders/dispatched.md",
                    "demo",
                    "helper",
                    "agent",
                    False,
                    "literal",
                )
            ],
            refs,
        )
        self.assertEqual(
            set(),
            case_skills.skills_under_test("Do it.", "prompt.md", (), graders, "demo"),
        )

    def test_prompt_body_mention_after_first_line_is_not_a_source(self):
        prompt = "Check this repository.\nPlease use /demo:real if needed.\n"
        self.assertEqual([], case_skills.references(prompt, "prompt.md", (), ()))
        self.assertEqual(
            set(),
            case_skills.skills_under_test(prompt, "prompt.md", (), (), "demo"),
        )

    def test_non_literal_regex_parts_yield_no_reference(self):
        patterns = (
            ("alternation", "demo:(a|b)"),
            ("optional-prefix-alternation", r'"skill"\s*:\s*"(?:demo:)?(?:a|b)"'),
            ("bare-alternation", r'"skill"\s*:\s*"(?:a|b)"'),
            ("lookahead", "^(?=.*demo:real)"),
            ("character-class", "[demo:real]"),
        )
        for label, pattern in patterns:
            with self.subTest(label):
                self.assertEqual(
                    [],
                    case_skills.references(
                        "Do it.", "prompt.md", (), [skill_grader(pattern)]
                    ),
                )

    def test_ordering_and_per_grader_deduplication(self):
        refs = case_skills.references(
            "/demo:first go",
            "prompt.md",
            [(["demo:tag-one"], "case.yaml"), (["bare-two"], "prompt.md")],
            [
                skill_grader('"skill":"demo:dup"|"skill":"demo:dup"', path="g1.md"),
                skill_grader('"(?:demo:)?opt"', path="g2.md"),
            ],
        )
        self.assertEqual(
            [
                Reference("prompt", "prompt.md", "demo", "first", "skill", False, "literal"),
                Reference("tag", "case.yaml", "demo", "tag-one", "skill", False, "literal"),
                Reference("tag", "prompt.md", None, "bare-two", "skill", False, "bare"),
                Reference("grader", "g1.md", "demo", "dup", "skill", False, "literal"),
                Reference("grader", "g2.md", "demo", "opt", "skill", False, "optional-prefix"),
            ],
            refs,
        )


if __name__ == "__main__":
    unittest.main()
