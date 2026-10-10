#!/usr/bin/env python3
"""Self-test for the line-citation gate.

Each case builds a throwaway git repository holding a copy of the gate, a
ten-line cited file and one citing markdown file, so the suite proves the
detector rather than the current state of this checkout.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

# FIXTURE ISOLATION: `git init` and `git add` below must never reach the
# caller's repository through an inherited git environment. The variable list
# mirrors scripts/test-git-helpers.sh; scripts/check-fixture-git-isolation.sh
# keeps it true.
for _leaked_git_var in (
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_INDEX_FILE",
    "GIT_COMMON_DIR",
    "GIT_PREFIX",
    "GIT_OBJECT_DIRECTORY",
    "GIT_CONFIG",
):
    os.environ.pop(_leaked_git_var, None)
del _leaked_git_var

GATE = Path(__file__).resolve().parent / "check-line-citations.py"
TEN_LINES = "".join(f"line {n}\n" for n in range(1, 11))


def run_gate(citing: str, citing_path: str = "docs/guide.md"):
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "scripts").mkdir()
        shutil.copy(GATE, root / "scripts" / GATE.name)
        (root / "src").mkdir()
        (root / "src" / "ten.py").write_text(TEN_LINES)
        doc = root / citing_path
        doc.parent.mkdir(parents=True, exist_ok=True)
        doc.write_text(citing)
        subprocess.run(["git", "init", "-q"], cwd=root, check=True)
        subprocess.run(["git", "add", "-A"], cwd=root, check=True)
        result = subprocess.run(
            [sys.executable, str(root / "scripts" / GATE.name)],
            cwd=root,
            capture_output=True,
            text=True,
        )
        return result.returncode, result.stdout


class Fires(unittest.TestCase):
    def assert_fires(self, citing: str, citing_path: str = "docs/guide.md"):
        code, out = run_gate(citing, citing_path)
        self.assertEqual(code, 1, out)
        self.assertIn("has 10 lines", out)

    def test_line_past_end(self):
        self.assert_fires("See `src/ten.py:11` for the loop.\n")

    def test_range_end_past_end(self):
        self.assert_fires("See src/ten.py:8-12 for the loop.\n")

    def test_later_item_of_a_list_past_end(self):
        self.assert_fires("See `src/ten.py:2-3,9-40`.\n")

    def test_path_relative_to_citing_file(self):
        self.assert_fires("See `../ten.py:99`.\n", "src/docs/guide.md")

    def test_sentence_end_punctuation(self):
        self.assert_fires("The loop is at src/ten.py:11.\n")


class StaysQuiet(unittest.TestCase):
    def assert_quiet(self, citing: str, citing_path: str = "docs/guide.md"):
        code, out = run_gate(citing, citing_path)
        self.assertEqual(code, 0, out)

    def test_valid_line_and_range(self):
        self.assert_quiet("See `src/ten.py:10` and src/ten.py:1-10.\n")

    def test_nonexistent_path(self):
        self.assert_quiet("See `src/gone.py:500` and `ten.py:500`.\n")

    def test_url_with_port(self):
        self.assert_quiet(
            "Open http://localhost:8080/src/ten.py:99 or localhost:8080.\n"
        )

    def test_external_repo_citation(self):
        self.assert_quiet("See melodic-software/standards:src/ten.py:99.\n")

    def test_time_of_day(self):
        self.assert_quiet("The run starts at 10:30 and ends at 11:45-12:00.\n")

    def test_line_and_column(self):
        self.assert_quiet("Reported at src/ten.py:99:4 by the linter.\n")

    def test_fenced_example(self):
        self.assert_quiet("```text\n| 1 | src/ten.py:42 | sample row |\n```\n")

    def test_point_in_time_record(self):
        self.assert_quiet("Cut `src/ten.py:13-30`.\n", "docs/adr/0001-cut.md")
        self.assert_quiet("- Fixed `src/ten.py:99`.\n", "plugins/x/CHANGELOG.md")

    def test_citation_after_a_closed_fence_still_fires(self):
        code, out = run_gate("```\nsrc/ten.py:99\n```\n\nSee `src/ten.py:99`.\n")
        self.assertEqual(code, 1, out)
        self.assertIn("docs/guide.md:5:", out)


if __name__ == "__main__":
    unittest.main()
