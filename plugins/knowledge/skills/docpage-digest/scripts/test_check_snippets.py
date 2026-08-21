#!/usr/bin/env python3
"""Negative-control suite for check-snippets.py.

The campaign quote gate never parsed Prompt snippets; five fabricated
snippets shipped under a clean count. These cases are the evidence that
this gate fails that class before its PASS is believed.

Run: python test_check_snippets.py
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
GATE = os.path.join(HERE, "check-snippets.py")

SOURCE = (
    "Intro line.\n"
    "keep me \n"
    "You are a helpful assistant.\n"
    "prompt example here\n"
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
        proc = subprocess.run(
            [sys.executable, GATE, "--source", self.source,
             "--digest", digest],
            capture_output=True)
        if proc.returncode != expect_code:
            raise AssertionError(
                f"exit {proc.returncode}, expected {expect_code}; "
                f"stdout={proc.stdout!r} stderr={proc.stderr!r}")
        return proc


CLEAN = """# Unit

## Key claims (verbatim)

**C1.** `cc-applicable`

```
keep me 
```

## Prompt snippets (exact)

```
You are a helpful assistant.
```

```
prompt example here
```
"""


class TestCleanPass(GateHarness):
    def test_clean_pass_names_coverage(self):
        proc = self.run_gate(CLEAN, 0)
        out = proc.stdout.decode()
        self.assertIn("PASS", out)
        self.assertIn("2 Prompt-snippets", out)
        self.assertIn("NO per-line strip", out)
        self.assertIn("Nothing outside Prompt snippets", out)

    def test_recognised_none_is_clean_zero(self):
        text = """## Prompt snippets (exact)

none
"""
        proc = self.run_gate(text, 0)
        out = proc.stdout.decode()
        self.assertIn("PASS", out)
        self.assertIn("0 Prompt-snippets", out)


class TestFailLoudUnparsed(GateHarness):
    def test_no_digest_arg_is_unusable(self):
        proc = subprocess.run(
            [sys.executable, GATE, "--source", self.source],
            capture_output=True)
        self.assertEqual(proc.returncode, 2)
        self.assertIn(b"no --digest", proc.stderr)

    def test_missing_section_fails(self):
        proc = self.run_gate("# Unit\n\n## Summary\n\nNo snippets heading.\n", 1)
        self.assertIn(b"no '## Prompt snippets'", proc.stderr)

    def test_unparsed_prose_zero_fences_fails(self):
        # The shipped-under-CLEAN class: section exists, no fence, recall text.
        text = """## Prompt snippets (exact)

You are a helpful assistant.
"""
        proc = self.run_gate(text, 1)
        self.assertIn(b"parsed ZERO fences", proc.stderr)
        self.assertNotIn(b"PASS", proc.stdout)

    def test_fabricated_snippet_fails(self):
        text = """## Prompt snippets (exact)

```
this prompt was recalled, not copied
```
"""
        proc = self.run_gate(text, 1)
        self.assertIn(b"not an exact contiguous substring", proc.stderr)

    def test_indented_snippet_fence_fails(self):
        text = """## Prompt snippets (exact)

    ```
    You are a helpful assistant.
    ```
"""
        proc = self.run_gate(text, 1)
        self.assertIn(b"indented", proc.stderr)

    def test_key_claims_only_does_not_satisfy_this_gate(self):
        text = """## Key claims (verbatim)

**C1.** `cc-applicable`

```
keep me 
```
"""
        proc = self.run_gate(text, 1)
        self.assertIn(b"no '## Prompt snippets'", proc.stderr)


if __name__ == "__main__":
    unittest.main()
