# test-scope: plugins/planning/surface/index.html plugins/planning/reference/html-chrome.html
"""The interview page carries the canonical chrome's theme toggle, comment box and rules."""

from __future__ import annotations

import re
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
PAGE = HERE / "index.html"
CHROME = HERE.parent / "reference" / "html-chrome.html"

BLOCKS = {
    "toggle": re.compile(r'<div class="rv-theme"[^\n]*?</div>'),
    "comment": re.compile(r'<section class="rv-comment".*?</section>', re.S),
    "rules": re.compile(r"/\* rv-chrome:begin \*/.*?/\* rv-chrome:end \*/", re.S),
}


def flat(text):
    """The text with each line's leading spaces and tabs dropped."""
    return re.sub(r"(?m)^[ \t]+", "", text)


class TestPageChrome(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.page = PAGE.read_text(encoding="utf-8")
        cls.chrome = CHROME.read_text(encoding="utf-8")

    def test_page_carries_each_chrome_block_verbatim(self):
        for name, pattern in BLOCKS.items():
            with self.subTest(block=name):
                want = pattern.search(self.chrome)
                self.assertIsNotNone(want, f"the chrome reference has no {name}")
                got = pattern.search(self.page)
                self.assertIsNotNone(got, f"the page has no {name}")
                self.assertEqual(flat(got.group(0)), flat(want.group(0)))

    def test_toggle_opens_on_system(self):
        self.assertRegex(self.page, r'data-rv-theme="system" aria-pressed="true"')
        self.assertNotRegex(self.page, r'data-rv-theme="(light|dark)" aria-pressed="true"')

    def test_no_theme_override_or_other_theme_control(self):
        for gone in ("themeOverride", "applyTheme", "data.theme", 'setting("theme")', 'row("theme"'):
            with self.subTest(gone=gone):
                self.assertNotIn(gone, self.page)
        self.assertNotRegex(self.page, r"(?i)data-accent|data-palette|accent picker|palette picker")

    def test_chrome_tokens_are_defined(self):
        root = re.search(r"(?m)^:root\{([^}]*)\}", self.page)
        self.assertIsNotNone(root)
        for token in ("--bg:", "--fg:", "--muted:"):
            with self.subTest(token=token):
                self.assertIn(token, root.group(1))

    def test_dark_tokens_follow_the_toggle(self):
        dark = r"(?:^|\n)@media \(prefers-color-scheme: dark\)\{\s*:root:not\(\[data-theme=\"light\"\]\)\{"
        self.assertRegex(self.page, dark)
        self.assertRegex(self.page, r'(?m)^:root\[data-theme="dark"\]\{')
        unguarded = len(re.findall(r"prefers-color-scheme:\s*dark\)\s*\{", self.page))
        guarded = len(
            re.findall(
                r"prefers-color-scheme:\s*dark\)\s*\{\s*:root:not\(\[data-theme=\"light\"\]\)",
                self.page,
            )
        )
        self.assertEqual(unguarded, guarded)


if __name__ == "__main__":
    unittest.main()
