#!/usr/bin/env python3
"""Negative-control suite for check-snippets.py.

The campaign quote gate never parsed Prompt snippets; five fabricated
snippets shipped under a clean count. These cases are the evidence that
this gate fails that class before its PASS is believed. The temp-dir fixture
and the gate invocation come from gate_harness.py.

Run: python test_check_snippets.py
"""

from __future__ import annotations

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gate_harness import KEEP, GateTestCase, gate_path, write  # noqa: E402

GATE = gate_path("check-snippets.py")
SOURCE = (
    "Intro line.\n" + KEEP + "\nYou are a helpful assistant.\nprompt example here\n"
)


class GateHarness(GateTestCase):
    gate = GATE
    source_text = SOURCE


CLEAN = f"""# Unit

## Key claims (verbatim)

**C1.** `cc-applicable`

```
{KEEP}
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
        proc = self.invoke_argv("--source", self.source)
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

    def test_blank_section_is_not_a_none_marker(self):
        text = "## Prompt snippets (exact)\n\n"
        proc = self.run_gate(text, 1)
        self.assertIn(b"blank", proc.stderr)
        self.assertNotIn(b"PASS", proc.stdout)

    def test_empty_snippet_fence_fails(self):
        text = """## Prompt snippets (exact)

```
```
"""
        proc = self.run_gate(text, 1)
        self.assertIn(b"empty", proc.stderr)

    def test_key_claims_only_does_not_satisfy_this_gate(self):
        text = f"""## Key claims (verbatim)

**C1.** `cc-applicable`

```
{KEEP}
```
"""
        proc = self.run_gate(text, 1)
        self.assertIn(b"no '## Prompt snippets'", proc.stderr)

    def test_longer_outer_fence_keeps_inner_backtick_run(self):
        inner = "Wrap code like this:\n```\nprint(1)\n```"
        source = write(self.dir, "src-nested.md", inner + "\n")
        text = f"""## Prompt snippets (exact)

````
{inner}
````
"""
        digest = write(self.dir, "d-nested.md", text)
        proc = self.invoke(source, digest)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn(b"PASS", proc.stdout)
        self.assertIn(b"1 Prompt-snippets", proc.stdout)


if __name__ == "__main__":
    unittest.main()
