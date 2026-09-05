#!/usr/bin/env python3
"""Black-box tests for comment-census.py.

The pygments path is exercised whenever pygments is importable (it is pinned
for CI); the scc path skips visibly when scc is not on PATH; the degradation
path always runs.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("comment-census.py")

HEREDOC_SH = """#!/usr/bin/env bash
# real comment one
cat >f <<'EOF'
# NOT a comment: heredoc data
# also not a comment
EOF
x=1  # trailing comment
y="${v#prefix}"
"""

MOD_PY = '''"""Docstring is a string, not a comment."""
# a comment
x = 1
'''


def fixture(tmp: Path) -> None:
    (tmp / "a.sh").write_text(HEREDOC_SH)
    (tmp / "m.py").write_text(MOD_PY)
    (tmp / "copy1.py").write_text(MOD_PY)
    (tmp / "copy2.py").write_text(MOD_PY)
    (tmp / "README.md").write_text("# markdown heading, never counted\n")


def run(*args: str, cwd: Path, python_flags: tuple[str, ...] = ()) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, *python_flags, str(SCRIPT), *args],
        capture_output=True, text=True, check=False, cwd=str(cwd),
    )


def pygments_present() -> bool:
    try:
        import pygments  # noqa: F401
    except ImportError:
        return False
    return True


@unittest.skipUnless(pygments_present(), "pygments not installed")
class PygmentsLayer(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        fixture(self.tmp)

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def report(self, *extra: str) -> dict:
        p = run(".", "--json", "--layer", "pygments", *extra, cwd=self.tmp)
        self.assertEqual(p.returncode, 0, p.stderr)
        return json.loads(p.stdout)

    def test_heredoc_bodies_and_param_expansion_are_not_comments(self):
        rep = self.report()
        sh = next(r for r in rep["files"] if r["path"].endswith("a.sh"))
        # Lines 2, 7 are comments; the shebang is a directive; heredoc lines are data;
        # ${v#prefix} is an expansion.
        self.assertEqual(sh["comment_lines"], 2, sh)
        self.assertGreater(sh["comment_bytes"], 0)

    def test_docstring_is_not_a_comment(self):
        rep = self.report()
        py = next(r for r in rep["files"] if r["path"].endswith("m.py"))
        self.assertEqual(py["comment_lines"], 1, py)

    def test_markdown_is_never_counted(self):
        rep = self.report()
        self.assertFalse(any(r["path"].endswith(".md") for r in rep["files"]))

    def test_byte_identical_copies_collapse_in_deduped_totals_only(self):
        rep = self.report()
        self.assertEqual(rep["raw"]["files"], 4)
        self.assertEqual(rep["deduped"]["files"], 2)
        self.assertEqual(rep["deduped"]["duplicate_copies_collapsed"], 2)
        self.assertEqual(rep["raw"]["comment_lines"], rep["deduped"]["comment_lines"] + 2)

    def test_token_estimate_is_bytes_over_four_and_labelled(self):
        rep = self.report()
        self.assertEqual(rep["deduped"]["approx_tokens"], rep["deduped"]["comment_bytes"] // 4)
        self.assertEqual(rep["token_estimate"], "comment_bytes / 4")
        text = run(".", "--layer", "pygments", cwd=self.tmp).stdout
        self.assertIn("tokens are an estimate", text)
        self.assertIn("bytes=pygments", text)

    def test_baseline_delta_reports_movement(self):
        base = self.report()
        (self.tmp / "base.json").write_text(json.dumps(base))
        (self.tmp / "m.py").write_text("x = 1\n")
        (self.tmp / "copy1.py").write_text("x = 1\n")
        (self.tmp / "copy2.py").write_text("x = 1\n")
        after = self.report("--baseline", "base.json")
        self.assertEqual(after["delta"]["comment_lines"], -1, after["delta"])
        self.assertLess(after["delta"]["comment_bytes"], 0)
        text = run(".", "--layer", "pygments", "--baseline", "base.json", cwd=self.tmp).stdout
        self.assertIn("delta vs baseline", text)

    def test_output_is_deterministic(self):
        a = run(".", "--layer", "pygments", cwd=self.tmp).stdout
        b = run(".", "--layer", "pygments", cwd=self.tmp).stdout
        self.assertEqual(a, b)


@unittest.skipUnless(shutil.which("scc"), "scc not on PATH")
class SccLayer(unittest.TestCase):
    def test_scc_supplies_lines_and_complexity(self):
        tmp = Path(tempfile.mkdtemp())
        try:
            fixture(tmp)
            p = run(".", "--json", "--layer", "scc", cwd=tmp)
            self.assertEqual(p.returncode, 0, p.stderr)
            rep = json.loads(p.stdout)
            self.assertEqual(rep["sources"]["lines"], "scc")
            self.assertEqual(rep["sources"]["complexity"], "scc")
            sh = next(r for r in rep["files"] if r["path"].endswith("a.sh"))
            self.assertIn("complexity", sh)
        finally:
            shutil.rmtree(tmp)


class Degradation(unittest.TestCase):
    def test_no_layer_exits_3_with_install_hint(self):
        tmp = Path(tempfile.mkdtemp())
        try:
            fixture(tmp)
            env = {**os.environ, "PATH": str(tmp), "PYTHONPATH": str(tmp)}
            p = subprocess.run(
                [sys.executable, "-S", str(SCRIPT), ".", "--layer", "pygments"],
                capture_output=True, text=True, check=False, cwd=str(tmp), env=env,
            )
            self.assertEqual(p.returncode, 3, p.stderr)
            self.assertIn("UNAVAILABLE", p.stderr)
            self.assertIn("pygments", p.stderr)
        finally:
            shutil.rmtree(tmp)

    def test_missing_path_is_usage_error(self):
        p = run("/definitely/not/here", cwd=Path.cwd())
        self.assertEqual(p.returncode, 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
