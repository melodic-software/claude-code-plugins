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

# One case builds a throwaway git repository. Under an inherited absolute GIT_DIR
# (or GIT_WORK_TREE / GIT_CONFIG) `git init` would write into the caller's
# repository instead of the fixture, so clear the ambient git environment once
# (scripts/check-fixture-git-isolation.sh).
for _leaked_git_var in ("GIT_DIR", "GIT_WORK_TREE", "GIT_CONFIG"):
    os.environ.pop(_leaked_git_var, None)
del _leaked_git_var

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


def run(
    *args: str, cwd: Path, python_flags: tuple[str, ...] = ()
) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, *python_flags, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        check=False,
        cwd=str(cwd),
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
        self.assertEqual(
            rep["raw"]["comment_lines"], rep["deduped"]["comment_lines"] + 2
        )

    def test_token_estimate_is_bytes_over_four_and_labelled(self):
        rep = self.report()
        self.assertEqual(
            rep["deduped"]["approx_tokens"], rep["deduped"]["comment_bytes"] // 4
        )
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
        text = run(
            ".", "--layer", "pygments", "--baseline", "base.json", cwd=self.tmp
        ).stdout
        self.assertIn("delta vs baseline", text)

    def test_output_is_deterministic(self):
        a = run(".", "--layer", "pygments", cwd=self.tmp).stdout
        b = run(".", "--layer", "pygments", cwd=self.tmp).stdout
        self.assertEqual(a, b)


FAKE_SCC = """#!/usr/bin/env python3
import json, os, sys
with open(os.environ["FAKE_SCC_ARGV"], "w") as fh:
    json.dump(sys.argv[1:], fh)
files = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
print(json.dumps([{"Name": "Python", "Files": [
    {"Location": f, "Comment": 1, "Code": 1, "Lines": 2, "Complexity": 0} for f in files
]}]))
"""


class SccArgv(unittest.TestCase):
    """The scc argv contract, checked against a recording shim so it runs without scc.

    A tracked file named like a flag (`-o=evil.py`) must reach scc as a path,
    never as an option (CWE-88): every file follows a `--` terminator and none
    is spelled with a leading hyphen.
    """

    def test_flag_shaped_filename_is_passed_as_a_path(self):
        tmp = Path(tempfile.mkdtemp())
        try:
            fixture(tmp)
            (tmp / "-o=evil.py").write_text(MOD_PY)
            shim_dir = tmp / "bin"
            shim_dir.mkdir()
            shim = shim_dir / "scc"
            shim.write_text(FAKE_SCC)
            shim.chmod(0o755)
            argv_file = tmp / "argv.json"
            env = {
                **os.environ,
                "PATH": f"{shim_dir}{os.pathsep}{os.environ.get('PATH', '')}",
                "FAKE_SCC_ARGV": str(argv_file),
            }
            p = subprocess.run(
                [sys.executable, str(SCRIPT), ".", "--json", "--layer", "scc"],
                capture_output=True,
                text=True,
                check=False,
                cwd=str(tmp),
                env=env,
            )
            self.assertEqual(p.returncode, 0, p.stderr)
            argv = json.loads(argv_file.read_text())
            self.assertIn("--", argv)
            paths = argv[argv.index("--") + 1 :]
            self.assertTrue(paths, "no files reached scc")
            self.assertTrue(all(a.startswith(("./", "/")) for a in paths), paths)
            self.assertIn("./-o=evil.py", paths)
            self.assertNotIn("-o=evil.py", argv[: argv.index("--")])
            self.assertFalse((tmp / "evil.py").exists())
        finally:
            shutil.rmtree(tmp)


@unittest.skipUnless(shutil.which("scc"), "scc not on PATH")
class SccLayer(unittest.TestCase):
    def test_flag_shaped_filename_is_scanned_not_parsed(self):
        tmp = Path(tempfile.mkdtemp())
        try:
            fixture(tmp)
            (tmp / "-o=evil.py").write_text(MOD_PY)
            p = run(".", "--json", "--layer", "scc", cwd=tmp)
            self.assertEqual(p.returncode, 0, p.stderr)
            rep = json.loads(p.stdout)
            self.assertFalse(
                (tmp / "evil.py").exists(), "scc parsed a filename as its output flag"
            )
            self.assertTrue(
                any(r["path"].endswith("-o=evil.py") for r in rep["files"]),
                rep["files"],
            )
        finally:
            shutil.rmtree(tmp)

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
                capture_output=True,
                text=True,
                check=False,
                cwd=str(tmp),
                env=env,
            )
            self.assertEqual(p.returncode, 3, p.stderr)
            self.assertIn("UNAVAILABLE", p.stderr)
            self.assertIn("pygments", p.stderr)
        finally:
            shutil.rmtree(tmp)

    @unittest.skipUnless(pygments_present(), "pygments not installed")
    def test_tracked_subdirectory_target_lists_its_files(self):
        # `git ls-files -- <dir>` run from inside <dir> looks for <dir>/<dir> and
        # matches nothing, so a directory target used to census zero files.
        tmp = Path(tempfile.mkdtemp())
        try:
            env = {
                k: v for k, v in os.environ.items() if not k.startswith("GIT_CONFIG")
            }
            env.update(
                {
                    "GIT_AUTHOR_NAME": "t",
                    "GIT_AUTHOR_EMAIL": "t@x",
                    "GIT_COMMITTER_NAME": "t",
                    "GIT_COMMITTER_EMAIL": "t@x",
                }
            )
            subprocess.run(["git", "init", "-q", str(tmp)], check=True, env=env)
            sub = tmp / "plugins" / "thing"
            sub.mkdir(parents=True)
            (sub / "m.py").write_text(MOD_PY)
            (tmp / "top.py").write_text(MOD_PY)
            subprocess.run(["git", "-C", str(tmp), "add", "-A"], check=True, env=env)
            subprocess.run(
                ["git", "-C", str(tmp), "commit", "-q", "-m", "init"],
                check=True,
                env=env,
            )
            p = run("plugins/thing", "--json", "--layer", "pygments", cwd=tmp)
            self.assertEqual(p.returncode, 0, p.stderr)
            rep = json.loads(p.stdout)
            self.assertEqual(
                [r["path"] for r in rep["files"]],
                [os.path.join("plugins", "thing", "m.py")],
                rep["files"],
            )
        finally:
            shutil.rmtree(tmp)

    def test_missing_path_is_usage_error(self):
        p = run("/definitely/not/here", cwd=Path.cwd())
        self.assertEqual(p.returncode, 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
