#!/usr/bin/env python3
"""Tests for render-review.py. Run with pytest, or directly: python3 test_render_review.py"""

import contextlib
import importlib.util
import io
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "render-review.py"


def run(cases, fmt):
    """Render `cases` in `fmt`; return (exit code, output text, stderr)."""
    with tempfile.TemporaryDirectory() as tmp:
        source = Path(tmp) / "cases.json"
        source.write_text(json.dumps(cases), encoding="utf-8")
        out = Path(tmp) / "review.out"
        proc = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                str(source),
                "--format",
                fmt,
                "--out",
                str(out),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        text = out.read_text(encoding="utf-8") if out.exists() else ""
    return proc.returncode, text, proc.stderr


class UnknownFormat(unittest.TestCase):
    def test_unknown_format_exits_non_zero_and_writes_nothing(self):
        code, text, err = run([{"id": 1, "prompt": "hi"}], "pdf")
        self.assertNotEqual(code, 0)
        self.assertEqual(text, "")
        self.assertIn("markdown", err)


class BadInput(unittest.TestCase):
    def test_input_that_is_not_an_array_of_objects_exits_2_and_writes_nothing(self):
        for cases in ({"id": 1}, [1, 2], "text"):
            with self.subTest(cases=cases):
                code, text, err = run(cases, "markdown")
                self.assertEqual(code, 2)
                self.assertEqual(text, "")
                self.assertIn("array of case objects", err)


SKILL_CASES = [
    {
        "id": 1,
        "name": "happy-path",
        "prompt": "Summarize the deploy notes.",
        "expected_output": "A three-line summary.",
        "expectations": ["Names the release", "Under 60 words"],
        "difficulty": "hard",
        "why_hard": "Two releases share a name.",
        "source": "a failure seen in review",
    },
    {
        "id": 2,
        "name": "refusal",
        "prompt": "Delete prod.",
        "expected_output": "Refuses.",
    },
]


def table_rows(text):
    return [line for line in text.splitlines() if line.startswith("|")]


def unescaped_pipes(line):
    return line.replace("\\|", "").count("|")


class Markdown(unittest.TestCase):
    def test_table_has_header_separator_and_one_row_per_case(self):
        code, text, _ = run(SKILL_CASES, "markdown")
        self.assertEqual(code, 0)
        rows = table_rows(text)
        self.assertEqual(len(rows), 2 + len(SKILL_CASES))
        header = [cell.strip() for cell in rows[0].strip("|").split("|")]
        self.assertEqual(header[:2], ["id", "name"])
        for field in (
            "difficulty",
            "why_hard",
            "source",
            "expected_output",
            "expectations",
        ):
            self.assertIn(field, header)
        self.assertNotIn("prompt", header)
        self.assertIn("Two releases share a name.", rows[2])
        self.assertIn("Names the release; Under 60 words", rows[2])

    def test_pipes_in_cells_are_escaped_so_the_row_keeps_its_cell_count(self):
        cases = [{"id": 1, "name": "a|b", "source": "x | y\nz", "prompt": "p | q"}]
        code, text, _ = run(cases, "markdown")
        self.assertEqual(code, 0)
        header, _, row = table_rows(text)
        self.assertIn(r"a\|b", row)
        self.assertIn(r"x \| y z", row)
        self.assertEqual(unescaped_pipes(row), unescaped_pipes(header))

    def test_one_fenced_block_per_case_longer_than_any_backtick_run(self):
        tricky = "before\n`````\n<script>x</script>\nafter"
        cases = [{"id": 1, "prompt": tricky}, {"id": 2, "input": "plain"}]
        code, text, _ = run(cases, "markdown")
        self.assertEqual(code, 0)
        self.assertIn("``````text\n" + tricky + "\n``````\n", text)
        self.assertIn("```text\nplain\n```\n", text)
        self.assertEqual(text.count("text\n"), len(cases))


PAYLOAD = """<script>alert("x")</script> & 'q'"""
ESCAPED = "&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt; &amp; &#x27;q&#x27;"


class Html(unittest.TestCase):
    def test_every_key_and_value_is_escaped(self):
        fields = (
            "id",
            "name",
            "prompt",
            "expected_output",
            "difficulty",
            "why_hard",
            "source",
            "golden_answer",
            "grading",
            "rubric",
        )
        case = {field: f"{field} {PAYLOAD}" for field in fields}
        case["expectations"] = [f"expectation {PAYLOAD}"]
        case[f"key {PAYLOAD}"] = f"extra {PAYLOAD}"
        code, text, _ = run([case], "html")
        self.assertEqual(code, 0)
        self.assertNotIn("<script", text)
        self.assertNotIn(PAYLOAD, text)
        for field in fields + ("expectation", "key", "extra"):
            self.assertIn(f"{field} {ESCAPED}", text)


class FormatTable(unittest.TestCase):
    def test_a_new_format_is_one_function_and_one_table_entry(self):
        spec = importlib.util.spec_from_file_location("render_review", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.assertEqual(sorted(module.FORMATS), ["html", "markdown"])
        module.FORMATS["count"] = lambda cases: f"{len(cases)} cases\n"
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "cases.json"
            source.write_text(json.dumps(SKILL_CASES), encoding="utf-8")
            out = Path(tmp) / "review.txt"
            with contextlib.redirect_stdout(io.StringIO()):
                code = module.main(
                    [str(source), "--format", "count", "--out", str(out)]
                )
            self.assertEqual(code, 0)
            self.assertEqual(out.read_text(encoding="utf-8"), "2 cases\n")


class MarkdownCells(unittest.TestCase):
    def test_table_cells_carry_no_live_html(self):
        code, text, _ = run([{"id": 1, "name": PAYLOAD, "prompt": PAYLOAD}], "markdown")
        self.assertEqual(code, 0)
        row = table_rows(text)[2]
        self.assertNotIn("<script", row)
        self.assertIn("&lt;script&gt;", row)


if __name__ == "__main__":
    unittest.main()
