#!/usr/bin/env python3
# test-scope: plugins/*/evals/*/case.yaml plugins/*/evals/*/matchers.json plugins/*/evals/*/samples/*
"""Tests for check-matchers.py: rendering, drift, sample registration, both
regex engines, and the live fragments file with every suite in the repository."""

import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "check-matchers.py"
REPO = HERE.parents[4]

spec = importlib.util.spec_from_file_location("check_matchers", SCRIPT)
cm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cm)

HAS_NODE = shutil.which("node") is not None

# A Bash command string with the token anywhere inside it.
ANYWHERE = '"command":"(?:[^"\\\\]|\\\\.)*?'


def bash(command):
    return [{"tool": "Bash", "input": {"command": command}}]


def fragments_file(directory, **overrides):
    fragments = {
        "anywhere": {
            "summary": "the command string",
            "text": ANYWHERE,
            "probe": {
                "type": "tool_used",
                "tool": "Bash",
                "input_match": [{"use": "anywhere"}, "-Force"],
            },
            "samples": {
                "pass": [{"answer": bash("x -Force")}],
                "fail": [
                    {"answer": bash("x")},
                    {
                        "answer": [
                            {"tool": "Bash", "input": {"command": "x", "d": "-Force"}}
                        ]
                    },
                ],
            },
        },
        "cell": {
            "summary": "a table row naming {{row}} with PASS",
            "params": ["row"],
            "text": "^\\|[^\\n]*{{row}}[^\\n]*\\|\\s*PASS\\s*\\|",
            "probe": {
                "type": "regex",
                "flags": "m",
                "pattern": [{"use": "cell", "with": {"row": "node"}}],
            },
            "samples": {
                "pass": [{"answer": "| node | PASS |"}],
                "fail": [{"answer": "| jq | PASS |"}],
            },
        },
    }
    fragments.update(overrides)
    path = Path(directory) / "fragments.json"
    path.write_text(json.dumps(fragments), encoding="utf-8")
    return path


class RenderTests(unittest.TestCase):
    FRAGMENTS = {"a": {"text": "x{{row}}y", "params": ["row"]}, "b": {"text": "z"}}

    def test_parts_join_in_order_with_slots_filled(self):
        parts = ["^", {"use": "a", "with": {"row": "Q"}}, "-", {"use": "b"}]
        self.assertEqual("^xQy-z", cm.render(parts, self.FRAGMENTS))

    def test_an_unknown_fragment_is_refused(self):
        with self.assertRaisesRegex(cm.RenderError, 'unknown fragment "c"'):
            cm.render([{"use": "c"}], self.FRAGMENTS)

    def test_a_missing_parameter_is_refused(self):
        with self.assertRaisesRegex(cm.RenderError, "takes row"):
            cm.render([{"use": "a"}], self.FRAGMENTS)


@unittest.skipUnless(HAS_NODE, "node is not installed")
class HarnessTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="check-matchers-"))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.evals = self.tmp / "plugin" / "evals"
        self.case_dir = self.evals / "c"
        (self.case_dir / "samples").mkdir(parents=True)
        self.fragments = fragments_file(self.tmp)
        self.write_case(ANYWHERE + "-Force")
        self.write_matchers({"no-force": [{"use": "anywhere"}, "-Force"]})
        self.write_samples("no-force", [bash("ls")], [bash("pwsh x.ps1 -Force")])

    def write_case(self, input_match):
        text = (
            'schema_version: "1.1"\nname: c\ngraders:\n'
            "  - name: no-force\n    type: tool_used\n    tool: Bash\n"
            "    input_match: '%s'\n    min: 0\n    max: 0\n"
            % input_match.replace("'", "''")
        )
        (self.case_dir / "case.yaml").write_text(text, encoding="utf-8")

    def write_matchers(self, data):
        (self.case_dir / "matchers.json").write_text(json.dumps(data), encoding="utf-8")

    def write_samples(self, name, passing, failing):
        data = {
            "pass": [{"answer": a} for a in passing],
            "fail": [{"answer": a} for a in failing],
        }
        (self.case_dir / "samples" / (name + ".json")).write_text(
            json.dumps(data), encoding="utf-8"
        )

    def run_check(self, *extra, env=None):
        return subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--fragments",
                str(self.fragments),
                *extra,
                str(self.evals),
            ],
            capture_output=True,
            text=True,
            encoding="utf-8",
            env=env,
        )

    def test_a_grader_built_from_its_matchers_passes(self):
        result = self.run_check()
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn("2 fragments, 1 cases with matchers", result.stdout)

    def test_drift_fails_and_write_rewrites_the_line(self):
        self.write_case(ANYWHERE + "-Force\\b")
        result = self.run_check()
        self.assertEqual(1, result.returncode)
        self.assertIn(
            'grader "no-force" input_match differs from its matchers.json build',
            result.stdout,
        )
        self.assertEqual(0, self.run_check("--write").returncode)
        written = (self.case_dir / "case.yaml").read_text(encoding="utf-8")
        self.assertIn(
            '    input_match: \'"command":"(?:[^"\\\\]|\\\\.)*?-Force\'\n', written
        )
        self.assertEqual(0, self.run_check().returncode)

    def test_a_grader_with_no_samples_fails(self):
        (self.case_dir / "samples" / "no-force.json").unlink()
        result = self.run_check()
        self.assertEqual(1, result.returncode)
        self.assertIn("needs must-pass and must-fail samples", result.stdout)

    def test_a_mislabeled_case_sample_fails_under_both_engines(self):
        self.write_samples("no-force", [bash("pwsh x.ps1 -Force")], [bash("ls")])
        result = self.run_check()
        self.assertEqual(1, result.returncode)
        self.assertIn(
            'must-pass sample 1 fails grader "no-force" under JavaScript', result.stdout
        )
        self.assertIn("must-pass sample 1 fails the grader", result.stdout)

    def test_a_mislabeled_fragment_sample_fails(self):
        broken = {
            "summary": "s",
            "text": "PASS",
            "probe": {"type": "regex", "pattern": [{"use": "word"}]},
            "samples": {"pass": [{"answer": "FAIL"}], "fail": [{"answer": "PASS"}]},
        }
        self.fragments = fragments_file(self.tmp, word=broken)
        result = self.run_check()
        self.assertEqual(1, result.returncode)
        self.assertIn(
            'fragments.json#word: must-pass sample 1 fails grader "word" under JavaScript',
            result.stdout,
        )

    def test_a_pattern_python_cannot_grade_fails(self):
        # `[^]` is any character in JavaScript and an unterminated class in `re`:
        # the samples are proved by one engine only.
        self.write_case(ANYWHERE + "[^]Force")
        self.write_matchers({"no-force": [{"use": "anywhere"}, "[^]Force"]})
        result = self.run_check()
        self.assertEqual(1, result.returncode)
        self.assertIn("samples not checked", result.stdout)

    def test_a_fragment_without_fail_samples_fails(self):
        thin = {
            "summary": "s",
            "text": "x",
            "probe": {"type": "regex", "pattern": [{"use": "thin"}]},
            "samples": {"pass": [{"answer": "x"}]},
        }
        self.fragments = fragments_file(self.tmp, thin=thin)
        result = self.run_check()
        self.assertEqual(1, result.returncode)
        self.assertIn('fragment "thin" needs must-fail samples', result.stdout)

    def test_without_node_it_refuses(self):
        result = self.run_check(env={"PATH": ""})
        self.assertEqual(2, result.returncode)
        self.assertIn("node is not on PATH", result.stderr)


@unittest.skipUnless(HAS_NODE, "node is not installed")
class LiveRepository(unittest.TestCase):
    def test_every_fragment_and_every_matchers_case_in_the_repo_passes(self):
        eval_dirs = sorted(
            str(p) for p in (REPO / "plugins").glob("*/evals") if p.is_dir()
        )
        result = subprocess.run(
            [sys.executable, str(SCRIPT), *eval_dirs],
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertNotIn(" 0 cases with matchers", result.stdout)


if __name__ == "__main__":
    unittest.main()
