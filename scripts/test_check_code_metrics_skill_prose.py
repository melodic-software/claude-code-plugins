#!/usr/bin/env python3
"""The prose-default gate fails when a skill sentence drifts from the defaults."""

from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

_GATE_PATH = Path(__file__).resolve().parent / "check-code-metrics-skill-prose.py"
_SPEC = importlib.util.spec_from_file_location("check_code_metrics_skill_prose", _GATE_PATH)
assert _SPEC is not None and _SPEC.loader is not None
gate = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(gate)

DEFAULTS = {
    "duplication": {
        "min_tokens": 50,
        "min_lines": 5,
        "max_size": "1mb",
        "max_lines": None,
        "rollup_depth": 2,
    },
    "coverage": {
        "artifacts": [],
        "path_prefix_strip": [],
        "reference": None,
        "crap": {"reference": None},
    },
    "type_debt": {"reference": None},
    "complexity": {"cyclomatic": {"reference": 20}},
    "size": {"file_lines": 1000},
}


def _write(root: Path, relative: str, text: str) -> None:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


class ProseGateTests(unittest.TestCase):
    def _materialize(self, root: Path) -> None:
        chunks: dict[str, list[str]] = {}
        for relative, phrase in gate.expected_phrases(DEFAULTS):
            chunks.setdefault(relative, []).append(phrase)
        for relative, phrases in chunks.items():
            _write(root, relative, "\n".join(phrases) + "\n")

    def test_matching_sentences_pass(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self._materialize(root)
            self.assertEqual(gate.check(root, DEFAULTS), [])

    def test_a_drifted_number_is_named(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self._materialize(root)
            drifted = root / "plugins/code-metrics/skills/setup/SKILL.md"
            drifted.write_text(
                drifted.read_text(encoding="utf-8").replace("(20", "(15"),
                encoding="utf-8",
            )
            problems = gate.check(root, DEFAULTS)
            self.assertEqual(len(problems), 1)
            self.assertIn("setup/SKILL.md", problems[0])

    def test_the_shipped_tree_matches(self) -> None:
        defaults = json.loads(gate.DEFAULT_DEFAULTS.read_text(encoding="utf-8"))
        self.assertEqual(gate.check(gate.REPO_ROOT, defaults), [])


if __name__ == "__main__":
    unittest.main()
