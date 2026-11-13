#!/usr/bin/env bash
# A sandbox repository whose default branch, pushed to a local bare origin, sets the
# `verification` level named by $1 in docs/conventions/discipline.yaml, plus a small textkit
# package with a test, and a feature branch that changes it.
set -euo pipefail

level="$1"
git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p docs/conventions textkit tests
printf 'verification: %s\n' "$level" >docs/conventions/discipline.yaml
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

    def test_strips_punctuation(self):
        self.assertEqual(slugify("Hello, World!"), "hello-world")


if __name__ == "__main__":
    unittest.main()
PY
printf '.work/\n__pycache__/\n' >.gitignore
git add .
git commit -q -m "scaffold textkit"

# The level is read from the default branch on origin, so push main to a local bare origin.
mkdir -p .work/origin.git
git init -q --bare -b main .work/origin.git
git remote add origin "$PWD/.work/origin.git"
git push -q origin main
git remote set-head origin main
git checkout -q -b feat/strip-punctuation
cat >textkit/slug.py <<'PY'
import re


def slugify(text):
    words = re.sub(r"[^\w\s-]", "", text).lower().split()
    return "-".join(words)
PY
git commit -q -am "feat: strip punctuation in slugify"
