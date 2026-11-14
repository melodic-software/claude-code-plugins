#!/usr/bin/env bash
# A small textkit package with one test, committed, so /discovery:explore has something to read.
set -euo pipefail

git init -q -b main
mkdir -p textkit tests
printf '# textkit\n\nSmall text helpers. slugify lives in textkit/slug.py.\n' >README.md
: >textkit/__init__.py
cat >textkit/slug.py <<'PY'
def slugify(text):
    return "-".join(text.lower().split())
PY
cat >tests/test_slug.py <<'PY'
import unittest

from textkit.slug import slugify


class SlugifyTest(unittest.TestCase):
    def test_lowercases_and_hyphenates(self):
        self.assertEqual(slugify("Hello World"), "hello-world")


if __name__ == "__main__":
    unittest.main()
PY
printf '.work/\n__pycache__/\n' >.gitignore
git add .
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "scaffold textkit"
