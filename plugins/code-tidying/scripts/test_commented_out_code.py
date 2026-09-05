#!/usr/bin/env python3
"""Black-box tests for commented-out-code.py.

Each language gets a prose comment that must NOT be flagged and a commented-out
block that MUST be, because the failure that matters is deleting prose that
merely parses. Grammar cases skip visibly; the degradation case always runs.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("commented-out-code.py")


def scan(text: str, ext: str) -> tuple[int, list, str]:
    with tempfile.TemporaryDirectory() as tmp:
        f = Path(tmp, f"t{ext}")
        f.write_text(text)
        p = subprocess.run(
            [sys.executable, str(SCRIPT), "--json", str(f)],
            capture_output=True,
            text=True,
            check=False,
        )
        rows = json.loads(p.stdout) if p.returncode == 0 else []
        return p.returncode, rows, p.stderr


def available(ext: str) -> bool:
    code, _, _ = scan("x\n", ext)
    return code != 3


def lines(rows) -> set[int]:
    return {r["start"] for r in rows}


@unittest.skipUnless(available(".py"), "python grammar not installed")
class Python(unittest.TestCase):
    def test_prose_is_not_flagged_but_code_is(self):
        src = (
            "# increment the counter before the retry\n"
            "# todo\n"
            "x = 1\n"
            "# y = compute(x)\n"
            "# return y\n"
            "# type: ignore\n"
        )
        code, rows, err = scan(src, ".py")
        self.assertEqual(code, 0, err)
        self.assertEqual(lines(rows), {4}, rows)
        self.assertEqual(rows[0]["end"], 5)

    def test_long_commented_out_block_is_one_finding(self):
        # Each two-line fragment of this block fails to parse on its own; only
        # the whole run parses, so a merge cap would turn it into a false negative.
        src = (
            "x = 1\n"
            "# def old_path(a):\n"
            "#     if a:\n"
            "#         return a\n"
            "#     return None\n"
            "y = 2\n"
        )
        code, rows, err = scan(src, ".py")
        self.assertEqual(code, 0, err)
        self.assertEqual([(r["start"], r["end"]) for r in rows], [(2, 5)], rows)


@unittest.skipUnless(available(".sh"), "bash grammar not installed")
class Bash(unittest.TestCase):
    def test_sentences_parse_as_commands_and_are_still_not_flagged(self):
        src = (
            "#!/usr/bin/env bash\n"
            "# cd into the dir and print the result\n"
            "# shellcheck disable=SC2034\n"
            "x=1\n"
            '# rm -rf "$TMP"\n'
            '# if [[ -n "$x" ]]; then echo yes; fi\n'
        )
        code, rows, err = scan(src, ".sh")
        self.assertEqual(code, 0, err)
        self.assertEqual(lines(rows), {5}, rows)
        self.assertEqual(rows[0]["end"], 6)


@unittest.skipUnless(available(".ts"), "typescript grammar not installed")
class TypeScript(unittest.TestCase):
    def test_prose_vs_code(self):
        src = (
            "// leading explanation of the helper\n"
            "export function f(x: number) {\n"
            "  // const y = x + 1;\n"
            "  // return y;\n"
            "  return x;\n"
            "}\n"
        )
        code, rows, err = scan(src, ".ts")
        self.assertEqual(code, 0, err)
        self.assertEqual(lines(rows), {3}, rows)


@unittest.skipUnless(available(".cs"), "c-sharp grammar not installed")
class CSharp(unittest.TestCase):
    def test_prose_vs_code(self):
        src = (
            "/// <summary>Public doc.</summary>\n"
            "public class W {\n"
            "    // the count is reset on each pass\n"
            "    // var n = Count(items);\n"
            "    private int Count = 3;\n"
            "}\n"
        )
        code, rows, err = scan(src, ".cs")
        self.assertEqual(code, 0, err)
        self.assertEqual(lines(rows), {4}, rows)


@unittest.skipUnless(available(".yml"), "yaml grammar not installed")
class Yaml(unittest.TestCase):
    def test_prose_vs_mapping(self):
        src = (
            "# workflow for the nightly build\n"
            "name: ci\n"
            "#   timeout-minutes: 30\n"
            "#   runs-on: ubuntu-latest\n"
        )
        code, rows, err = scan(src, ".yml")
        self.assertEqual(code, 0, err)
        self.assertEqual(lines(rows), {3}, rows)


class Degradation(unittest.TestCase):
    def test_missing_tree_sitter_exits_3(self):
        with tempfile.TemporaryDirectory() as tmp:
            f = Path(tmp, "t.py")
            f.write_text("# x = 1\n")
            p = subprocess.run(
                [sys.executable, "-S", str(SCRIPT), str(f)],
                capture_output=True,
                text=True,
                check=False,
                env={**os.environ, "PYTHONPATH": tmp},
            )
        self.assertEqual(p.returncode, 3, p.stderr)
        self.assertIn("UNAVAILABLE", p.stderr)

    def test_missing_file_is_usage_error(self):
        p = subprocess.run(
            [sys.executable, str(SCRIPT), "/no/such/file.py"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(p.returncode, 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
