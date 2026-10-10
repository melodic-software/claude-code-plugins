#!/usr/bin/env python3
"""Tests for js-complexity-share.py, the counter behind the js-complexity-share ratchet.

Each case builds a throwaway git repository, puts a fake `lizard` first on PATH,
and runs the counter at its command line. The fake records the files it was
handed and prints one lizard CSV record per `// cc=N` marker in each file, so
every expected value below comes from the fixture and the scope rules in the
counter's docstring, not from running the counter.
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

for _leaked_git_var in ("GIT_DIR", "GIT_WORK_TREE", "GIT_CONFIG", "GIT_INDEX_FILE"):
    os.environ.pop(_leaked_git_var, None)

SCRIPT = Path(__file__).resolve().parent / "js-complexity-share.py"

FAKE_LIZARD = r"""
import csv, os, re, sys
args = sys.argv[1:]
if args == ["--version"]:
    print("9.9.9")
    sys.exit(0)
files = [a for a in args if a.endswith((".js", ".jsx", ".mjs", ".cjs"))]
with open(os.environ["FAKE_LIZARD_ARGS"], "w", encoding="utf-8") as handle:
    handle.write("\n".join(files))
writer = csv.writer(sys.stdout, lineterminator="\n")
for path in files:
    with open(path, encoding="utf-8") as source:
        for number, line in enumerate(source, 1):
            match = re.search(r"// cc=(\d+)", line)
            if match:
                name = f"f{number}"
                writer.writerow([3, match.group(1), 10, 0, 1,
                                 f"{name}@{number}-{number}@{path}", path, name,
                                 f"{name} ( )", number, number])
"""


class JsComplexityShareTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        base = Path(self._tmp.name)
        self.repo = base / "repo"
        self.stubs = base / "stubs"
        self.args_file = base / "lizard-args.txt"
        self.repo.mkdir()
        self.stubs.mkdir()
        fake = self.stubs / "fake_lizard.py"
        fake.write_text(FAKE_LIZARD, encoding="utf-8")
        posix = self.stubs / "lizard"
        posix.write_text(f'#!/bin/sh\nexec "{sys.executable}" "{fake}" "$@"\n')
        posix.chmod(0o755)
        # Windows finds the fake through PATHEXT.
        (self.stubs / "lizard.cmd").write_text(f'@"{sys.executable}" "{fake}" %*\n')
        subprocess.run(["git", "init", "-q", str(self.repo)], check=True)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def write(self, rel: str, text: str) -> None:
        path = self.repo / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def stage(self) -> None:
        subprocess.run(["git", "-C", str(self.repo), "add", "-A"], check=True)

    def run_counter(self, path: str | None = None) -> subprocess.CompletedProcess:
        if path is None:
            path = f"{self.stubs}{os.pathsep}{os.environ.get('PATH', '')}"
        env = dict(os.environ, PATH=path, FAKE_LIZARD_ARGS=str(self.args_file))
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--registry", "registry.txt"],
            cwd=self.repo,
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_scope_and_share(self) -> None:
        self.write(
            "registry.txt",
            "# sanctioned copies\nlib/shared.mjs\n"
            "tools/canon.js -> plugins/*/tools/canon.js\n",
        )
        # In scope: one production file per extension.
        self.write("src/app.js", "// cc=25\n// cc=3\n")
        self.write("src/view.jsx", "// cc=4\n")
        self.write("src/mod.cjs", "// cc=20\n")
        # Copies count once: the first path outside plugins/, else the first
        # path, is the one kept.
        self.write("src/copy-of-app.js", "// cc=25\n// cc=3\n")
        self.write("plugins/a/lib/shared.mjs", "// cc=30\n")
        self.write("plugins/b/lib/shared.mjs", "// cc=30\n// cc=1\n")
        self.write("tools/canon.js", "// cc=2\n")
        self.write("plugins/a/tools/canon.js", "// cc=40\n")
        # Out of scope.
        self.write("src/app.test.mjs", "// cc=50\n")
        self.write("src/app.spec.js", "// cc=50\n")
        self.write("plugins/a/fixtures/big.js", "// cc=50\n")
        self.write("node_modules/dep/index.js", "// cc=50\n")
        self.write(".github/standards/sync.js", "// cc=50\n")
        self.write("src/gen.js", "// DO NOT EDIT\n// cc=50\n")
        self.write("src/script.ts", "// cc=50\n")
        self.stage()
        self.write("src/untracked.js", "// cc=50\n")

        result = self.run_counter()

        self.assertEqual(result.returncode, 0, result.stderr)
        handed = sorted(self.args_file.read_text(encoding="utf-8").split("\n"))
        self.assertEqual(
            handed,
            [
                "plugins/a/lib/shared.mjs",
                "src/app.js",
                "src/mod.cjs",
                "src/view.jsx",
                "tools/canon.js",
            ],
        )
        # Functions: app.js 25 and 3, view.jsx 4, mod.cjs 20, shared.mjs 30,
        # canon.js 2. Six functions, three at or above 20: 50.00 percent.
        self.assertEqual(
            result.stdout.strip(),
            "lizard=9.9.9 files=5 functions=6 over=3 share=50.00",
        )

    def test_missing_lizard_exits_2(self) -> None:
        self.write("registry.txt", "")
        self.write("src/app.js", "// cc=25\n")
        self.stage()
        empty = Path(self._tmp.name) / "empty-path"
        empty.mkdir()

        result = self.run_counter(str(empty))

        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")
        self.assertIn("lizard is not on PATH", result.stderr)

    def test_no_function_measured_exits_2(self) -> None:
        self.write("registry.txt", "")
        self.write("src/empty.js", "const x = 1;\n")
        self.stage()

        result = self.run_counter()

        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")
        self.assertIn("measured no function", result.stderr)


if __name__ == "__main__":
    unittest.main()
