#!/usr/bin/env python3
"""Black-box tests for change-shape.py.

Runs the script as a subprocess so the exit-code contract a shell gate relies
on is what gets asserted, not an internal function. Grammar-dependent cases
skip VISIBLY when tree-sitter or a grammar is absent; the degradation case
always runs, because a suite that can be entirely skipped proves nothing.
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("change-shape.py")


def run(before: str, after: str, ext: str, *extra: str) -> tuple[int, str, str]:
    with tempfile.TemporaryDirectory() as tmp:
        b = Path(tmp, f"before{ext}")
        a = Path(tmp, f"after{ext}")
        b.write_text(before)
        a.write_text(after)
        proc = subprocess.run(
            [sys.executable, str(SCRIPT), *extra, str(b), str(a)],
            capture_output=True,
            text=True,
            check=False,
        )
        return proc.returncode, proc.stdout, proc.stderr


def grammar_available(ext: str) -> bool:
    code, _, _ = run("x = 1\n", "x = 1\n", ext)
    return code != 3


TS_BASE = """// leading comment
export function helper(x: number): number {
  // increment x
  return x + 1;
}
"""

SH_BASE = """#!/usr/bin/env bash
# explain the retry
retry_count=3
run() { echo "$retry_count"; }
"""


@unittest.skipUnless(grammar_available(".ts"), "tree-sitter typescript grammar not installed")
class TypeScriptVerdicts(unittest.TestCase):
    def test_comment_deletion_is_comment_only(self):
        after = TS_BASE.replace("// leading comment\n", "").replace("  // increment x\n", "")
        code, out, _ = run(TS_BASE, after, ".ts")
        self.assertEqual(code, 0, out)
        self.assertTrue(out.startswith("COMMENT-ONLY"), out)

    def test_reindent_is_comment_only(self):
        after = TS_BASE.replace("  return", "      return").replace("  //", "      //")
        code, out, _ = run(TS_BASE, after, ".ts")
        self.assertEqual(code, 0, out)

    def test_consistent_rename_is_rename_only_with_mapping(self):
        after = TS_BASE.replace("helper", "incrementByOne")
        code, out, _ = run(TS_BASE, after, ".ts", "--json")
        self.assertEqual(code, 10, out)
        self.assertIn('"mapping": {"helper": "incrementByOne"}', out)

    def test_literal_change_is_code_changed(self):
        after = TS_BASE.replace("x + 1", "x + 2")
        code, out, _ = run(TS_BASE, after, ".ts")
        self.assertEqual(code, 20, out)
        self.assertIn("number", out)

    def test_comment_deletion_plus_literal_change_is_not_masked(self):
        after = TS_BASE.replace("// leading comment\n", "").replace("x + 1", "x + 2")
        code, out, _ = run(TS_BASE, after, ".ts")
        self.assertEqual(code, 20, out)

    def test_unparsable_after_is_unprovable(self):
        after = TS_BASE.replace("return x + 1;", "return x + ;")
        code, out, _ = run(TS_BASE, after, ".ts")
        self.assertEqual(code, 21, out)
        self.assertTrue(out.startswith("UNPROVABLE"), out)


@unittest.skipUnless(grammar_available(".sh"), "tree-sitter bash grammar not installed")
class BashVerdicts(unittest.TestCase):
    def test_comment_deletion_is_comment_only(self):
        after = SH_BASE.replace("# explain the retry\n", "")
        code, out, _ = run(SH_BASE, after, ".sh")
        self.assertEqual(code, 0, out)

    def test_shebang_deletion_is_not_comment_only(self):
        after = SH_BASE.replace("#!/usr/bin/env bash\n", "")
        code, out, _ = run(SH_BASE, after, ".sh")
        self.assertEqual(code, 20, out)

    def test_heredoc_body_edit_is_code_changed(self):
        before = SH_BASE + "cat >f <<'EOF'\n# looks like a comment\nEOF\n"
        after = SH_BASE + "cat >f <<'EOF'\n# looks different\nEOF\n"
        code, out, _ = run(before, after, ".sh")
        self.assertEqual(code, 20, out)

    def test_value_change_that_orphans_the_comment_is_code_changed(self):
        after = SH_BASE.replace("retry_count=3", "retry_count=5")
        code, out, _ = run(SH_BASE, after, ".sh")
        self.assertEqual(code, 20, out)


class Degradation(unittest.TestCase):
    """Always runs: proves the unavailable path is loud and distinct."""

    def test_missing_tree_sitter_exits_3_with_reason(self):
        with tempfile.TemporaryDirectory() as tmp:
            b = Path(tmp, "a.py")
            a = Path(tmp, "b.py")
            b.write_text("x = 1\n")
            a.write_text("x = 1\n")
            # -S drops site-packages, so `import tree_sitter` cannot resolve.
            proc = subprocess.run(
                [sys.executable, "-S", str(SCRIPT), str(b), str(a)],
                capture_output=True,
                text=True,
                check=False,
                env={**os.environ, "PYTHONPATH": tmp},
            )
        self.assertEqual(proc.returncode, 3, proc.stderr)
        self.assertIn("UNAVAILABLE", proc.stderr)
        self.assertIn("tree-sitter", proc.stderr)

    def test_unknown_extension_is_usage_error(self):
        code, _, err = run("x", "x", ".unknownext")
        self.assertEqual(code, 2, err)
        self.assertIn("--lang", err)


if __name__ == "__main__":
    unittest.main(verbosity=2)
