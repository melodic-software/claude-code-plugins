#!/usr/bin/env python3
"""Negative-control suite for check-prose-terms.py.

Pipeline vocabulary leaked into digest prose and only a verifier caught it.
These cases show the gate fails that class, names file, section and term, and
leaves fence payloads alone. The temp-dir fixture comes from gate_harness.py.

Run: python test_check_prose_terms.py
"""

from __future__ import annotations

import os
import sys
import unittest

sys.dont_write_bytecode = True  # the plugin's own tree is not a cache
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gate_harness import GateTestCase, gate_path, write  # noqa: E402

GATE = gate_path("check-prose-terms.py")

CLEAN = """# Unit

## Summary

The hook runs before each tool call.

## Key claims (verbatim)

**C1.** `cc-applicable`

```
Hooks run before tool calls.
```

## Implications for daily use

A hook can block a call.

## Open questions for interview

Does the hook run for subagents?
"""


class GateHarness(GateTestCase):
    gate = GATE
    source_text = "unused\n"

    def run_digest(self, text: str, expect_code: int, name: str = "digest.md"):
        path = write(self.dir, name, text)
        proc = self.invoke_argv("--digest", path)
        if proc.returncode != expect_code:
            raise AssertionError(
                f"exit {proc.returncode}, expected {expect_code}; "
                f"stdout={proc.stdout!r} stderr={proc.stderr!r}"
            )
        return proc


class TestCleanPass(GateHarness):
    def test_clean_digest_passes(self):
        proc = self.run_digest(CLEAN, 0)
        out = proc.stdout.decode()
        self.assertIn("PASS", out)
        self.assertIn("unit NN, SOURCES.md", out)
        self.assertIn("Fence payloads were not read", out)

    def test_similar_words_do_not_match(self):
        text = CLEAN.replace(
            "A hook can block a call.",
            "A community 3 times larger, and the unitary 4 case.",
        )
        self.run_digest(text, 0)


class TestFailures(GateHarness):
    def test_unit_number_in_implications_fails_with_file_section_term(self):
        text = CLEAN.replace(
            "A hook can block a call.", "As unit 03 shows, a hook can block a call."
        )
        proc = self.run_digest(text, 1)
        err = proc.stderr.decode()
        self.assertIn("digest.md", err)
        self.assertIn("Implications for daily use", err)
        self.assertIn("'unit NN'", err)
        self.assertIn("'unit 03'", err)
        self.assertIn("FAILED", proc.stdout.decode())

    def test_sources_md_in_open_questions_fails(self):
        text = CLEAN.replace(
            "Does the hook run for subagents?", "See SOURCES.md for the hook row."
        )
        proc = self.run_digest(text, 1)
        err = proc.stderr.decode()
        self.assertIn("Open questions for interview", err)
        self.assertIn("'SOURCES.md'", err)

    def test_term_match_is_case_insensitive(self):
        text = CLEAN.replace("A hook can block a call.", "Unit 7 and sources.md.")
        proc = self.run_digest(text, 1)
        self.assertEqual(proc.stderr.decode().count("pipeline term"), 2)

    def test_every_digest_is_checked(self):
        good = write(self.dir, "good.md", CLEAN)
        bad = write(self.dir, "bad.md", CLEAN + "\nunit 12 again\n")
        proc = self.invoke_argv("--digest", good, "--digest", bad)
        self.assertEqual(proc.returncode, 1)
        self.assertIn("bad.md", proc.stderr.decode())
        self.assertNotIn("good.md", proc.stderr.decode())


class TestFences(GateHarness):
    def test_terms_inside_fences_are_ignored(self):
        text = CLEAN.replace(
            "Hooks run before tool calls.",
            "unit 03 and SOURCES.md are quoted verbatim.\n## not a heading",
        )
        self.run_digest(text, 0)

    def test_prose_after_a_fence_is_still_read(self):
        text = CLEAN.replace(
            "A hook can block a call.",
            "```\nunit 03\n```\n\nBut unit 04 here.",
        )
        proc = self.run_digest(text, 1)
        err = proc.stderr.decode()
        self.assertIn("'unit 04'", err)
        self.assertNotIn("'unit 03'", err)


class TestNothingRead(GateHarness):
    def test_unclosed_fence_fails(self):
        proc = self.run_digest("## Summary\n\n```\nunit 03\n", 1)
        self.assertIn("never closed", proc.stderr.decode())

    def test_all_fence_digest_fails(self):
        proc = self.run_digest("```\nonly a quote\n```\n", 1)
        self.assertIn("no prose outside fences", proc.stderr.decode())

    def test_term_in_heading_fails(self):
        proc = self.run_digest(CLEAN + "\n## Notes from SOURCES.md\n\nText.\n", 1)
        self.assertIn("'SOURCES.md'", proc.stderr.decode())


class TestUnusableInput(GateHarness):
    def test_no_digest_is_usage_error(self):
        self.assertEqual(self.invoke_argv().returncode, 2)

    def test_missing_digest_is_usage_error(self):
        proc = self.invoke_argv("--digest", os.path.join(self.dir, "absent.md"))
        self.assertEqual(proc.returncode, 2)

    def test_empty_digest_is_usage_error(self):
        self.run_digest("", 2)


if __name__ == "__main__":
    unittest.main()
