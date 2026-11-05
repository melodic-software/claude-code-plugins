# test-scope: plugins/planning/shared/web/app.js plugins/planning/shared/web/app.css plugins/planning/shared/web/proto.js
# test-scope: plugins/planning/reference/html-chrome.html
"""The shared-session page carries the canonical chrome's theme toggle, comment box and rules.

Expected values come from reference/html-chrome.html, the canonical chrome. The page builds its markup in
app.js, so these checks read the source; ui_surfaces.js checks the rendered page in a browser.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
WEB = HERE.parent / "web"
CHROME = HERE.parent.parent / "reference" / "html-chrome.html"
RULES = re.compile(r"/\* rv-chrome:begin \*/.*?/\* rv-chrome:end \*/", re.S)
GONE = (
    "ACCENTS",
    "PALETTES",
    "themePicker",
    "sessionTheme",
    "Default theme for everyone",
    "vf-swatch",
    "vf-palettes",
    "data-accent",
    "data-palette",
    "dataset.accent",
    "dataset.palette",
    "settings?.theme",
    "st().theme",
)


def flat(text):
    """The text with each line's leading spaces and tabs dropped."""
    return re.sub(r"(?m)^[ \t]+", "", text)


def literal(text):
    """`text` as a JavaScript string literal in double quotes."""
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


class TestSharedPageChrome(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.chrome = CHROME.read_text(encoding="utf-8")
        cls.js = (WEB / "app.js").read_text(encoding="utf-8")
        cls.css = (WEB / "app.css").read_text(encoding="utf-8")
        cls.proto = (WEB / "proto.js").read_text(encoding="utf-8")

    def test_css_carries_the_chrome_rules_verbatim(self):
        want = RULES.search(self.chrome)
        self.assertIsNotNone(want, "the chrome reference has no rv-chrome rules")
        got = RULES.search(self.css)
        self.assertIsNotNone(got, "app.css has no rv-chrome rules")
        self.assertEqual(flat(got.group(0)), flat(want.group(0)))

    def test_chrome_tokens_are_defined(self):
        app = re.search(r"(?m)^\.app \{([^}]*)\}", self.css)
        self.assertIsNotNone(app)
        for token in ("--bg:", "--fg:", "--muted:"):
            with self.subTest(token=token):
                self.assertIn(token, app.group(1))

    def test_toggle_is_the_chrome_group_of_its_three_choices(self):
        toggle = re.search(r'<div class="rv-theme" role="group" aria-label="([^"]+)">(.*?)</div>', self.chrome)
        self.assertIsNotNone(toggle, "the chrome reference has no toggle")
        choices = re.findall(r'data-rv-theme="([a-z]+)" aria-pressed="(?:true|false)">([^<]+)<', toggle.group(2))
        self.assertEqual([c for c, _ in choices], ["system", "light", "dark"])
        self.assertIn('E("div", "rv-theme")', self.js)
        self.assertIn(f'g.setAttribute("aria-label", {literal(toggle.group(1))})', self.js)
        modes = ", ".join(f"[{literal(c)}, {literal(label)}]" for c, label in choices)
        self.assertIn(f"const MODES = [{modes}];", self.js)
        self.assertIn("b.dataset.rvTheme = k", self.js)

    def test_toggle_opens_on_system(self):
        self.assertIn('const m = pref("theme", "system");', self.js)
        self.assertRegex(self.proto, r'p\.theme === "light" \|\| p\.theme === "dark" \? p\.theme : "system"')

    def test_comment_box_is_the_chrome_comment_box(self):
        box = re.search(r'<section class="rv-comment".*?</section>', self.chrome, re.S)
        self.assertIsNotNone(box, "the chrome reference has no comment box")
        box = box.group(0)
        heading = re.search(r'<h2 id="([^"]+)">([^<]+)</h2>', box)
        label = re.search(r'<label for="([^"]+)">([^<]+)</label>', box)
        field = re.search(r'<textarea id="([^"]+)" data-rv-note="([^"]+)" placeholder="([^"]+)">', box)
        for part in (heading, label, field):
            self.assertIsNotNone(part)
        for want in (
            'E("section", "rv-comment")',
            f'setAttribute("aria-labelledby", {literal(heading.group(1))})',
            f'E("h2", null, {literal(heading.group(2))})',
            f"discBoxH.id = {literal(heading.group(1))}",
            f'E("label", null, {literal(label.group(2))})',
            f"discLabel.htmlFor = {literal(label.group(1))}",
            f"discTa.id = {literal(field.group(1))}",
            f"discTa.dataset.rvNote = {literal(field.group(2))}",
            f"discTa.placeholder = {literal(field.group(3))}",
        ):
            with self.subTest(want=want):
                self.assertIn(want, self.js)

    def test_no_accent_palette_or_session_theme_remains(self):
        for name, text in (("app.js", self.js), ("app.css", self.css), ("proto.js", self.proto)):
            for gone in GONE:
                with self.subTest(file=name, gone=gone):
                    self.assertNotIn(gone, text)


if __name__ == "__main__":
    unittest.main()
