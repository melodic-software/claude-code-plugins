#!/usr/bin/env python3
"""Negative-control suite for check-fences-exact.py.

These cases are why the gate is a required artifact: PASS is not believed
until the known-bad fixtures fail. Run: python test_check_fences_exact.py
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
GATE = os.path.join(HERE, "check-fences-exact.py")

# Trailing space on KEEP is load-bearing — the hook strips it from a
# bare code span; a fence must preserve it. The space lives inside the
# quotes so this file has no physical trailing whitespace (editorconfig).
KEEP = "keep me "
SOURCE = (
    "Intro line.\n" + KEEP + "\nA list:\n* star item\n1. one\nprompt example here\n"
)


def write(dirpath: str, name: str, text: str) -> str:
    path = os.path.join(dirpath, name)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    return path


class GateHarness(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.source = write(self.dir, "source.md", SOURCE)

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def run_gate(self, digest_text: str, expect_code: int):
        digest = write(self.dir, "digest.md", digest_text)
        cmd = [sys.executable, GATE, "--source", self.source, "--digest", digest]
        proc = subprocess.run(cmd, capture_output=True)
        if proc.returncode != expect_code:
            raise AssertionError(
                f"exit {proc.returncode}, expected {expect_code}; "
                f"stdout={proc.stdout!r} stderr={proc.stderr!r}"
            )
        return proc


CLEAN = f"""# Unit

## Summary

A summary.

## Key claims (verbatim)

**C1.** `cc-applicable`

```
{KEEP}
```

**C2.** `cc-applicable`

```
* star item
```

## Prompt snippets (exact)

```
prompt example here
```
"""


class TestCleanPass(GateHarness):
    def test_clean_pass_names_coverage(self):
        proc = self.run_gate(CLEAN, 0)
        out = proc.stdout.decode()
        self.assertIn("PASS", out)
        self.assertIn("2 **CN.**", out)
        self.assertIn("NO per-line strip", out)
        self.assertIn("Nothing outside Key claims", out)

    def test_trailing_space_preserved(self):
        # SOURCE has "keep me \\n" — the fence payload must keep the space.
        proc = self.run_gate(CLEAN, 0)
        self.assertIn(b"PASS", proc.stdout)


class TestFailLoudZeroParse(GateHarness):
    def test_no_digest_arg_is_unusable(self):
        proc = subprocess.run(
            [sys.executable, GATE, "--source", self.source], capture_output=True
        )
        self.assertEqual(proc.returncode, 2)
        self.assertIn(b"no --digest", proc.stderr)

    def test_empty_source_is_unusable(self):
        empty = write(self.dir, "empty.md", "")
        digest = write(self.dir, "d.md", CLEAN)
        proc = subprocess.run(
            [sys.executable, GATE, "--source", empty, "--digest", digest],
            capture_output=True,
        )
        self.assertEqual(proc.returncode, 2)
        self.assertIn(b"empty", proc.stderr)

    def test_missing_key_claims_heading(self):
        proc = self.run_gate("# Unit\n\nNo claims section.\n", 1)
        self.assertIn(b"no '## Key claims'", proc.stderr)

    def test_zero_claims_is_failure_not_pass(self):
        proc = self.run_gate(
            "## Key claims (verbatim)\n\nNo labelled claims here.\n", 1
        )
        self.assertIn(b"parsed ZERO claims", proc.stderr)
        self.assertNotIn(b"PASS", proc.stdout)


class TestFenceContract(GateHarness):
    def test_indented_fence_fails(self):
        # REPAIR-pass corruption: indent the fence. strip() would hide this.
        text = CLEAN.replace(f"```\n{KEEP}\n```", f"    ```\n    {KEEP}\n    ```")
        proc = self.run_gate(text, 1)
        self.assertIn(b"indented", proc.stderr)

    def test_trailing_space_stripped_fails(self):
        text = CLEAN.replace(f"{KEEP}\n```", "keep me\n```")
        proc = self.run_gate(text, 1)
        self.assertIn(b"not an exact contiguous substring", proc.stderr)

    def test_blockquote_instead_of_fence(self):
        text = f"""## Key claims (verbatim)

**C1.** `cc-applicable`

> {KEEP}
"""
        proc = self.run_gate(text, 1)
        self.assertIn(b"blockquote", proc.stderr)

    def test_inline_code_instead_of_fence(self):
        text = """## Key claims (verbatim)

**C1.** `cc-applicable`

`keep me `
"""
        proc = self.run_gate(text, 1)
        self.assertIn(b"inline code span", proc.stderr)

    def test_fabricated_quote_fails(self):
        text = """## Key claims (verbatim)

**C1.** `cc-applicable`

```
this was never in the source
```
"""
        proc = self.run_gate(text, 1)
        self.assertIn(b"not an exact contiguous substring", proc.stderr)

    def test_unlabelled_fence_is_unparsed_surface(self):
        text = CLEAN.replace(
            "## Prompt snippets", "```\nIntro line.\n```\n\n## Prompt snippets"
        )
        proc = self.run_gate(text, 1)
        self.assertIn(b"unlabelled fence", proc.stderr)

    def test_duplicate_label(self):
        text = f"""## Key claims (verbatim)

**C1.** `cc-applicable`

```
{KEEP}
```

**C1.** `cc-applicable`

```
* star item
```
"""
        proc = self.run_gate(text, 1)
        self.assertIn(b"duplicate", proc.stderr)

    def test_empty_fence_payload_fails(self):
        text = """## Key claims (verbatim)

**C1.** `cc-applicable`

```
```
"""
        proc = self.run_gate(text, 1)
        self.assertIn(b"empty", proc.stderr)

    def test_blockquote_plus_later_fence_still_fails(self):
        text = f"""## Key claims (verbatim)

**C1.** `cc-applicable`

> fabricated quote

```
{KEEP}
```
"""
        proc = self.run_gate(text, 1)
        self.assertIn(b"blockquote", proc.stderr)

    def test_heading_inside_fence_does_not_truncate_section(self):
        source = write(self.dir, "src2.md", "## Configuration\nkeep me \n")
        text = """## Key claims (verbatim)

**C1.** `cc-applicable`

```
## Configuration
```

## Prompt snippets (exact)

none
"""
        digest = write(self.dir, "d2.md", text)
        proc = subprocess.run(
            [sys.executable, GATE, "--source", source, "--digest", digest],
            capture_output=True,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn(b"PASS", proc.stdout)

    def test_star_list_inside_fence_is_not_rewritten(self):
        # The defect the hook caused in a blockquote; a fence holds "* ".
        proc = self.run_gate(CLEAN, 0)
        self.assertIn(b"PASS", proc.stdout)

    def test_longer_outer_fence_keeps_inner_backtick_run(self):
        # CommonMark: a 3-tick line inside a 4-tick wrapper is payload.
        # Closing on any 3+ tick-only line truncated this to "" or to the
        # prose prefix — a false empty-payload FAIL or a false PASS.
        inner = "Wrap code like this:\n```\nprint(1)\n```"
        source = write(self.dir, "src-nested.md", inner + "\n")
        text = f"""## Key claims (verbatim)

**C1.** `cc-applicable`

````
{inner}
````
"""
        digest = write(self.dir, "d-nested.md", text)
        proc = subprocess.run(
            [sys.executable, GATE, "--source", source, "--digest", digest],
            capture_output=True,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn(b"PASS", proc.stdout)
        self.assertIn(b"1 **CN.**", proc.stdout)

    def test_four_tick_wrapper_around_immediate_inner_fence(self):
        # Truncation at the first inner ``` used to yield payload "" and
        # fail the empty-payload check on a valid verbatim quote.
        inner = "```\nprint(1)\n```"
        source = write(self.dir, "src-immediate.md", inner + "\n")
        text = f"""## Key claims (verbatim)

**C1.** `cc-applicable`

````
{inner}
````
"""
        digest = write(self.dir, "d-immediate.md", text)
        proc = subprocess.run(
            [sys.executable, GATE, "--source", source, "--digest", digest],
            capture_output=True,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn(b"PASS", proc.stdout)


if __name__ == "__main__":
    unittest.main()
