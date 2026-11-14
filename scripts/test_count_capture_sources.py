#!/usr/bin/env python3
# test-scope: scripts/count-capture-sources.py plugins/app-control/scripts/affected_features.py
"""Tests for scripts/count-capture-sources.py."""

from __future__ import annotations

import importlib.util
import io
import json
import os
import subprocess
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("count_capture_sources", HERE / "count-capture-sources.py")
ccs = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ccs)

HUB = ".claude/skills/control-app/SKILL.md"
HUB_TEXT = """# control

## Features

- alpha | features/alpha/README.md | entry points: 4 | sources: plugins/alpha/skills/*/SKILL.md
- beta | features/beta/README.md | entry points: 4 | sources: plugins/beta/skills/*/SKILL.md
- docs | features/docs.md | entry points: 1 | sources: docs/**
"""
for _leaked_git_var in ("GIT_DIR", "GIT_WORK_TREE", "GIT_CONFIG", "GIT_INDEX_FILE"):
    os.environ.pop(_leaked_git_var, None)
ENV = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}


class WidenTest(unittest.TestCase):
    def test_a_skill_md_glob_becomes_the_plugin_skills_scripts_and_agents(self) -> None:
        line = "- alpha | features/alpha/README.md | entry points: 4 | sources: plugins/alpha/skills/*/SKILL.md"
        self.assertEqual(
            ccs.widen(line),
            "- alpha | features/alpha/README.md | entry points: 4 | sources: "
            "plugins/alpha/skills/**, plugins/alpha/scripts/**, plugins/alpha/agents/**",
        )

    def test_other_globs_and_lines_stay_as_written(self) -> None:
        line = "- docs | features/docs.md | entry points: 1 | sources: docs/**, README.md"
        self.assertEqual(ccs.widen(line), "- docs | features/docs.md | entry points: 1 | sources: docs/**, README.md")
        self.assertEqual(ccs.widen("## Features"), "## Features")


class CountTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = self.tmp.name
        self.git("init", "-q", "-b", "main")
        self.write(HUB, HUB_TEXT)
        self.commit("init")
        self.write("plugins/alpha/skills/x/SKILL.md", "x")
        self.commit("feat(alpha): add x (#1)")
        self.write("plugins/alpha/skills/x/scripts/run.sh", "echo")
        self.commit("fix(alpha): x script (#2)")
        self.write("plugins/beta/agents/a.md", "a")
        self.commit("chore(beta): agent (#3)")
        self.write("README.md", "r")
        self.commit("docs: readme (#4)")
        self.write("plugins/alpha/skills/x/SKILL.md", "y")
        self.commit("direct push with no pull request")

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def git(self, *args: str) -> None:
        subprocess.run(
            ["git", "-C", self.repo, "-c", "user.name=t", "-c", "user.email=t@example.com",
             "-c", "commit.gpgsign=false", *args],
            check=True, capture_output=True, env=ENV,
        )

    def write(self, rel: str, text: str) -> None:
        path = Path(self.repo, rel)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def commit(self, subject: str) -> None:
        self.git("add", "-A")
        self.git("commit", "-q", "-m", subject)

    def test_counts_each_merged_pull_request_under_both_patterns(self) -> None:
        result = ccs.count(self.repo, "main", 14, HUB)
        rows = {r["pr"]: (r["current"], r["wider"]) for r in result["rows"]}
        self.assertEqual(
            rows,
            {
                1: (["alpha"], ["alpha"]),
                2: ([], ["alpha"]),
                3: ([], ["beta"]),
                4: ([], []),
            },
        )
        self.assertEqual(result["prs"], 4)
        self.assertEqual(result["totals"]["current"], {"prs_driven": 1, "features_driven": 1})
        self.assertEqual(result["totals"]["wider"], {"prs_driven": 3, "features_driven": 3})

    def test_report_names_the_extra_captures(self) -> None:
        out = io.StringIO()
        with redirect_stdout(out):
            code = ccs.main(["count", "--repo", self.repo, "--ref", "main", "--hub", HUB])
        self.assertEqual(code, 0)
        self.assertIn("current: 1 of 4 pull requests driven, 1 feature drives", out.getvalue())
        self.assertIn("wider: 3 of 4 pull requests driven, 3 feature drives", out.getvalue())
        self.assertIn("Extra captures under the wider pattern: 2 pull requests, 2 feature drives", out.getvalue())
        self.assertIn("#2: 0 -> 1 (alpha)", out.getvalue())

    def test_json_carries_the_rows(self) -> None:
        out = io.StringIO()
        with redirect_stdout(out):
            ccs.main(["count", "--repo", self.repo, "--ref", "main", "--hub", HUB, "--json"])
        self.assertEqual(json.loads(out.getvalue())["prs"], 4)

    def test_a_missing_hub_or_ref_exits_1(self) -> None:
        for args in (["--hub", "nope/SKILL.md", "--ref", "main"], ["--hub", HUB, "--ref", "no-such-ref"]):
            err = io.StringIO()
            with redirect_stderr(err):
                self.assertEqual(ccs.main(["count", "--repo", self.repo, *args]), 1)
            self.assertIn("count-capture-sources.py:", err.getvalue())

    def test_a_bad_days_value_is_usage(self) -> None:
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as raised:
            ccs.main(["count", "--repo", self.repo, "--days", "0"])
        self.assertEqual(raised.exception.code, 2)


if __name__ == "__main__":
    unittest.main()
