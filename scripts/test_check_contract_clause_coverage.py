#!/usr/bin/env python3
"""Self-test for the contract-clause coverage gate.

Every case builds a throwaway git repo with its own registry, so the suite
proves the DETECTOR rather than the current state of this checkout — a gate
whose only evidence is "the repo is green" cannot distinguish a clean corpus
from a broken detector, which is the exact failure this repo's self-test-first
CI convention exists to prevent.

The failure cases carry the weight. A gate that only proves it passes on
clean input is a gate that would stay green after someone deleted its
qualifier list.
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

GATE = Path(__file__).resolve().parent / "check-contract-clause-coverage.py"

REGISTRY = """{
  "clauses": [
    {
      "id": "C1",
      "title": "test clause",
      "canonical": "canonical.md",
      "detect": "widget",
      "restates": "widgets must",
      "qualifiers": [
        {"name": "alpha", "pattern": "be blue", "hint": "say blue"},
        {"name": "beta", "pattern": "be round", "hint": "say round"}
      ]
    }
  ]
}
"""

TWO_CLAUSE_REGISTRY = """{
  "clauses": [
    {
      "id": "C1",
      "title": "test clause",
      "canonical": "canonical.md",
      "detect": "widget",
      "restates": "widgets must",
      "qualifiers": [
        {"name": "alpha", "pattern": "be blue", "hint": "say blue"},
        {"name": "beta", "pattern": "be round", "hint": "say round"}
      ]
    },
    {
      "id": "C2",
      "title": "second test clause",
      "canonical": "canonical.md",
      "detect": "widget",
      "restates": "widgets must",
      "qualifiers": [
        {"name": "gamma", "pattern": "be heavy", "hint": "say heavy"}
      ]
    }
  ]
}
"""

CANONICAL = (
    "# Canonical\n"
    "\n"
    "<!-- contract-restatement-begin: C1 -->\n"
    "Widgets must be blue and be round.\n"
    "<!-- contract-restatement-end: C1 -->\n"
)

CANONICAL_TWO_CLAUSE = (
    "# Canonical\n"
    "\n"
    "<!-- contract-restatement-begin: C1 -->\n"
    "<!-- contract-restatement-begin: C2 -->\n"
    "Widgets must be blue and be round. And be heavy.\n"
    "<!-- contract-restatement-end: C2 -->\n"
    "<!-- contract-restatement-end: C1 -->\n"
)


class GateCase(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.addCleanup(self._tmp.cleanup)
        subprocess.run(["git", "init", "-q"], cwd=self.root, check=True)
        self.write("canonical.md", CANONICAL)
        self.registry = self.root / "registry.json"
        self.registry.write_text(REGISTRY, encoding="utf-8")

    def write(self, relative: str, content: str) -> None:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        subprocess.run(["git", "add", "-A"], cwd=self.root, check=True)

    def run_gate(self, *extra: str) -> "subprocess.CompletedProcess[str]":
        return subprocess.run(
            [
                sys.executable,
                str(GATE),
                "--root",
                str(self.root),
                "--registry",
                str(self.registry),
                *extra,
            ],
            capture_output=True,
            text=True,
        )

    # --- clean shapes ------------------------------------------------------

    def test_canonical_alone_passes(self) -> None:
        result = self.run_gate()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_pointer_surface_passes(self) -> None:
        """A file that cites the vocabulary without enumerating the rule."""
        self.write("pointer.md", "See canonical.md for the widget rule.\n")
        result = self.run_gate()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_complete_tagged_restatement_passes(self) -> None:
        self.write(
            "restate.md",
            "Widgets must be blue and be round. "
            "<!-- contract-restatement: C1 -->\n",
        )
        result = self.run_gate()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("1 tagged restatement", result.stdout)

    def test_line_wrapped_qualifier_still_matches(self) -> None:
        """A qualifier split across a line break is still present."""
        self.write(
            "wrapped.md",
            "<!-- contract-restatement-begin: C1 -->\n"
            "Widgets must be\n"
            "blue and be\n"
            "round.\n"
            "<!-- contract-restatement-end: C1 -->\n",
        )
        result = self.run_gate()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_hash_comment_marker_is_recognized(self) -> None:
        """The marker vocabulary is comment-syntax-agnostic by design."""
        self.write(
            "hash.md",
            "```text\nWidgets must be blue and be round.  # contract-restatement: C1\n```\n",
        )
        result = self.run_gate()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_changelog_is_not_an_instruction_surface(self) -> None:
        self.write("CHANGELOG.md", "- Widgets must be blue.\n")
        result = self.run_gate()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_explicit_exclude_skips_a_surface(self) -> None:
        self.write("docs/notes.md", "Widgets must be blue.\n")
        result = self.run_gate("--exclude", "docs")
        self.assertEqual(result.returncode, 0, result.stderr)

    # --- the failures the gate exists for ---------------------------------

    def test_tagged_restatement_missing_a_qualifier_fails(self) -> None:
        self.write(
            "restate.md",
            "Widgets must be blue. <!-- contract-restatement: C1 -->\n",
        )
        result = self.run_gate()
        self.assertEqual(result.returncode, 1)
        self.assertIn("missing-qualifier", result.stderr)
        self.assertIn("beta", result.stderr)
        self.assertIn("restate.md:1", result.stderr)
        self.assertIn("say round", result.stderr)

    def test_untagged_restatement_fails(self) -> None:
        self.write("sneaky.md", "Widgets must be blue and be round.\n")
        result = self.run_gate()
        self.assertEqual(result.returncode, 1)
        self.assertIn("untagged-restatement", result.stderr)
        self.assertIn("sneaky.md:1", result.stderr)

    def test_qualifier_outside_the_span_does_not_clear_it(self) -> None:
        """The #1633 false negative, pinned.

        A hand-run sweep asked whether the qualifier appeared ANYWHERE in the
        file; a file could then pass while carrying an unqualified copy
        elsewhere. Span scoping is the whole point.
        """
        self.write(
            "split.md",
            "Widgets must be blue. <!-- contract-restatement: C1 -->\n"
            "\n"
            "Unrelated prose noting that widgets should also be round.\n",
        )
        result = self.run_gate()
        self.assertEqual(result.returncode, 1)
        self.assertIn("beta", result.stderr)

    def test_canonical_losing_a_qualifier_fails(self) -> None:
        self.write(
            "canonical.md",
            "# Canonical\n"
            "\n"
            "<!-- contract-restatement-begin: C1 -->\n"
            "Widgets must be blue.\n"
            "<!-- contract-restatement-end: C1 -->\n",
        )
        result = self.run_gate()
        self.assertEqual(result.returncode, 1)
        self.assertIn("canonical-missing-qualifier", result.stderr)

    def test_canonical_is_span_scoped_like_every_copy(self) -> None:
        """A qualifier OUTSIDE the canonical's own span does not clear it.

        Checking the canonical file-wide would reproduce the exact defect the
        gate rejects everywhere else, and the asymmetry would be the first
        thing a reader of the header noticed.
        """
        self.write(
            "canonical.md",
            "# Canonical\n"
            "\n"
            "<!-- contract-restatement-begin: C1 -->\n"
            "Widgets must be blue.\n"
            "<!-- contract-restatement-end: C1 -->\n"
            "\n"
            "Elsewhere: a widget should also be round.\n",
        )
        result = self.run_gate()
        self.assertEqual(result.returncode, 1)
        self.assertIn("canonical-missing-qualifier", result.stderr)
        self.assertIn("beta", result.stderr)

    def test_canonical_without_a_span_fails(self) -> None:
        self.write("canonical.md", "# Canonical\n\nWidgets must be blue and be round.\n")
        result = self.run_gate()
        self.assertEqual(result.returncode, 1)
        self.assertIn("canonical-declares-no-span", result.stderr)

    def test_second_marker_on_one_line_is_not_dropped(self) -> None:
        """Two tags on one line: both are checked, not just the first."""
        self.registry.write_text(TWO_CLAUSE_REGISTRY, encoding="utf-8")
        self.write("canonical.md", CANONICAL_TWO_CLAUSE)
        self.write(
            "two.md",
            "Widgets must be blue and be round. "
            "<!-- contract-restatement: C1 --> <!-- contract-restatement: C2 -->\n",
        )
        result = self.run_gate()
        self.assertEqual(result.returncode, 1)
        self.assertIn("gamma", result.stderr)

    # --- fail-closed refusals ---------------------------------------------

    def test_missing_registry_refuses(self) -> None:
        self.registry.unlink()
        result = self.run_gate()
        self.assertEqual(result.returncode, 2)
        self.assertIn("missing", result.stderr)

    def test_unparsable_registry_refuses(self) -> None:
        self.registry.write_text("{ not json", encoding="utf-8")
        result = self.run_gate()
        self.assertEqual(result.returncode, 2)

    def test_registry_with_no_clauses_refuses(self) -> None:
        self.registry.write_text('{"clauses": []}', encoding="utf-8")
        result = self.run_gate()
        self.assertEqual(result.returncode, 2)

    def test_invalid_qualifier_regex_refuses(self) -> None:
        self.registry.write_text(
            REGISTRY.replace('"be blue"', '"be (blue"'), encoding="utf-8"
        )
        result = self.run_gate()
        self.assertEqual(result.returncode, 2)
        self.assertIn("invalid regex", result.stderr)

    def test_absent_canonical_refuses(self) -> None:
        (self.root / "canonical.md").unlink()
        subprocess.run(["git", "add", "-A"], cwd=self.root, check=True)
        result = self.run_gate()
        self.assertEqual(result.returncode, 2)
        self.assertIn("does not exist", result.stderr)

    def test_unclosed_span_refuses(self) -> None:
        self.write("bad.md", "<!-- contract-restatement-begin: C1 -->\nWidgets.\n")
        result = self.run_gate()
        self.assertEqual(result.returncode, 2)
        self.assertIn("never closed", result.stderr)

    def test_unmatched_end_refuses(self) -> None:
        self.write("bad.md", "Widgets.\n<!-- contract-restatement-end: C1 -->\n")
        result = self.run_gate()
        self.assertEqual(result.returncode, 2)
        self.assertIn("no matching begin", result.stderr)

    def test_nested_begin_refuses(self) -> None:
        self.write(
            "bad.md",
            "<!-- contract-restatement-begin: C1 -->\n"
            "<!-- contract-restatement-begin: C1 -->\n"
            "Widgets.\n"
            "<!-- contract-restatement-end: C1 -->\n",
        )
        result = self.run_gate()
        self.assertEqual(result.returncode, 2)
        self.assertIn("nested", result.stderr)

    def test_unknown_clause_id_in_a_marker_refuses(self) -> None:
        self.write("bad.md", "Widgets. <!-- contract-restatement: NOPE -->\n")
        result = self.run_gate()
        self.assertEqual(result.returncode, 2)
        self.assertIn("does not declare", result.stderr)

    def test_untracked_file_is_not_a_surface(self) -> None:
        """Discovery is tracked-file based, so a scratch file is invisible."""
        (self.root / "scratch.md").write_text(
            "Widgets must be blue.\n", encoding="utf-8"
        )
        result = self.run_gate()
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
