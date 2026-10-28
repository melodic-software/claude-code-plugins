#!/usr/bin/env python3
"""Cases for gates.headings, one group per option set a caller uses.

Expected values follow CommonMark's ATX heading, setext heading and fenced
code block rules (https://spec.commonmark.org/0.31.2/), narrowed or widened by
the option under test.

Run: python test_headings.py
"""

from __future__ import annotations

import os
import sys
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir))
from gates import headings  # noqa: E402


def atx(pattern, line):
    m = pattern.match(line)
    return m and (m.group(1), m.group(2))


class TestAtxHeading(unittest.TestCase):
    def test_any_level_with_a_closing_run_kept_in_the_text(self):
        p = headings.atx_heading()
        self.assertEqual(atx(p, "## Title ##"), ("##", "Title ##"))
        self.assertEqual(atx(p, "   ###### six"), ("######", "six"))
        self.assertEqual(atx(p, "#"), ("#", None))
        for line in ("####### seven", "#x", "    # four spaces", "\t# tab"):
            self.assertIsNone(p.match(line), line)

    def test_closing_trail_drops_a_closing_run_even_without_a_space(self):
        p = headings.atx_heading(trail=headings.TRAIL_CLOSING)
        self.assertEqual(atx(p, "## x ##"), ("##", "x"))
        self.assertEqual(atx(p, "## x#"), ("##", "x"))

    def test_fixed_level_with_required_text_and_no_indent(self):
        p = headings.atx_heading(
            level=2, max_indent=0, title_required=True, trail=headings.TRAIL_WHITESPACE
        )
        self.assertEqual(atx(p, "## Title\r"), ("##", "Title"))
        for line in ("##", "## ", "### x", " ## x", "# x"):
            self.assertIsNone(p.match(line), line)

    def test_closing_sequence_needs_a_blank_before_it(self):
        p = headings.closing_sequence()
        self.assertEqual(p.sub("", "Title ##  "), "Title")
        self.assertEqual(p.sub("", "C#"), "C#")

    def test_binary_patterns_match_bytes(self):
        self.assertEqual(atx(headings.atx_heading(binary=True), b"# T"), (b"#", b"T"))
        self.assertEqual(headings.closing_sequence(binary=True).sub(b"", b"T #"), b"T")


class TestSetext(unittest.TestCase):
    def test_underline(self):
        p = headings.setext_underline()
        self.assertEqual(p.match("===").group(1), "===")
        self.assertEqual(p.match("  --- ").group(1), "---")
        for line in ("    ---", "- -", "=-"):
            self.assertIsNone(p.match(line), line)


class TestHtmlHeading(unittest.TestCase):
    def test_line_start_with_an_id(self):
        p = headings.html_heading(line_start=True, require_id=True)
        m = p.match('  <H2 class="c" id="a">A</h2>')
        self.assertEqual((m.group(1), m.group(2)), ("2", "A</h2>"))
        for line in (
            "<h2>no id</h2>",
            '<h2 data-id="x">X</h2>',
            "text <h2 id=a>A</h2>",
            "<h7 id=a>",
        ):
            self.assertIsNone(p.match(line), line)

    def test_anywhere_without_an_id(self):
        p = headings.html_heading(binary=True)
        self.assertEqual(
            [m.group(1) for m in p.finditer(b"a <h3>b</h3> <H1 class=x>c")],
            [b"3", b"1"],
        )
        self.assertIsNone(p.search(b"<h7> <header>"))


class TestFence(unittest.TestCase):
    def test_any_indent_both_characters(self):
        p = headings.fence()
        m = p.match("\t~~~~ py")
        self.assertEqual(
            (m.group(1), m.group(2), m.start(1) > 0), ("~~~~", " py", True)
        )
        self.assertEqual(p.match("```").start(1), 0)
        self.assertIsNone(p.match("``"))

    def test_commonmark_indent(self):
        p = headings.fence(indent=headings.INDENT_COMMONMARK, binary=True)
        self.assertEqual(p.match(b"   ```").group(1), b"```")
        self.assertIsNone(p.match(b"    ```"))
        self.assertIsNone(p.match(b"\t```"))

    def test_backticks_only(self):
        p = headings.fence(chars="`", indent=headings.INDENT_SPACES_TABS)
        self.assertIsNone(p.match("~~~"))
        self.assertIsNone(p.match("\f```"))
        self.assertEqual(p.match(" \t````x").group(1), "````")

    def test_closes_fence(self):
        p = headings.fence()
        self.assertTrue(headings.closes_fence(p.match("~~~~~"), "~~~~"))
        self.assertFalse(headings.closes_fence(p.match("~~~"), "~~~~"))
        self.assertFalse(headings.closes_fence(p.match("```"), "~~~"))
        self.assertFalse(headings.closes_fence(p.match("~~~ x"), "~~~"))
        self.assertFalse(headings.closes_fence(None, "~~~"))
        self.assertTrue(headings.closes_fence(p.match("``` \f"), "```"))
        self.assertFalse(headings.closes_fence(p.match("``` \f"), "```", blank=" \t"))
        self.assertTrue(headings.closes_fence(p.match("``` \t"), "```", blank=" \t"))


if __name__ == "__main__":
    unittest.main()
