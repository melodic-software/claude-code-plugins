#!/usr/bin/env python3
# test-scope: plugins/evals/skills/plugin-eval/scripts/select-cases.py .github/scripts/plugin-eval/select-plugins.mjs
"""Tests for the compare-refused line of select-cases.py.

Copies the repository's own select-plugins.mjs into a throwaway fixture
repository, so the refusal rules come from that one script.
"""

import json
import shutil
import tempfile
import unittest
from pathlib import Path

from select_test_helpers import (
    _build_fixture_repo,
    _commit_all,
    _git,
    _parse_blocks,
    _run_select,
    _write,
)

SELECT_PLUGINS = (
    Path(__file__).resolve().parents[5]
    / ".github"
    / "scripts"
    / "plugin-eval"
    / "select-plugins.mjs"
)


@unittest.skipUnless(shutil.which("node"), "needs node to run select-plugins.mjs")
class CompareRefusedTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self._tmp.name)
        _build_fixture_repo(self.repo)
        target = self.repo / ".github/scripts/plugin-eval/select-plugins.mjs"
        target.parent.mkdir(parents=True)
        shutil.copyfile(SELECT_PLUGINS, target)
        _commit_all(self.repo, "add select-plugins.mjs")
        _git(self.repo, "branch", "-f", "base")

    def tearDown(self):
        self._tmp.cleanup()

    def _edit_skill_body(self):
        path = self.repo / "plugins/alpha/skills/one/SKILL.md"
        text = path.read_text(encoding="utf-8").replace("carefully", "strictly")
        path.write_text(text, encoding="utf-8")

    def test_hooks_file_beside_skill_change_is_refused(self):
        self._edit_skill_body()
        _write(self.repo, "plugins/alpha/hooks/hooks.json", "{}\n")
        _commit_all(self.repo, "skill and hooks")

        refusal = "plugins/alpha/hooks/hooks.json: outside skills/, agents/, context/, evals/, reference/ and README.md"
        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        line = _parse_blocks(res.stdout)["plugins/alpha"]["compare-refused"]
        self.assertIn(refusal, line)
        self.assertIn("suite run on the default branch after merge", line)
        self.assertNotIn("SKILL.md", line)

        data = json.loads(_run_select(self.repo, as_json=True).stdout)
        self.assertEqual([refusal], data["plugins/alpha"]["compare-refused"])

    def test_readme_and_reference_beside_skill_change_are_not_refused(self):
        self._edit_skill_body()
        _write(self.repo, "plugins/alpha/README.md", "# Alpha\n")
        _write(self.repo, "plugins/alpha/reference/notes.md", "Notes.\n")
        _commit_all(self.repo, "skill, readme and reference")

        data = json.loads(_run_select(self.repo, as_json=True).stdout)
        self.assertEqual([], data["plugins/alpha"]["compare-refused"])

    def test_script_under_skills_is_refused(self):
        path = self.repo / "plugins/alpha/skills/one/scripts/tool.py"
        path.write_text("def run():\n    return 2\n", encoding="utf-8")
        _commit_all(self.repo, "edit skill script")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        line = _parse_blocks(res.stdout)["plugins/alpha"]["compare-refused"]
        self.assertIn("plugins/alpha/skills/one/scripts/tool.py: not markdown", line)

    def test_markdown_only_skill_change_is_not_refused(self):
        self._edit_skill_body()
        _commit_all(self.repo, "reword skill body")

        res = _run_select(self.repo)
        self.assertEqual(0, res.returncode, res.stderr)
        self.assertEqual("", res.stderr)
        block = _parse_blocks(res.stdout)["plugins/alpha"]
        self.assertNotIn("compare-refused", block)
        self.assertIn("cases", block)

        data = json.loads(_run_select(self.repo, as_json=True).stdout)
        self.assertEqual([], data["plugins/alpha"]["compare-refused"])


if __name__ == "__main__":
    unittest.main()
