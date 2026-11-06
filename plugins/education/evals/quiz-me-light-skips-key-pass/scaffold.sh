#!/usr/bin/env bash
# A sandbox repository whose default branch, pushed to a local bare origin, sets
# `verification: light` in docs/conventions/education.yaml, plus a small textkit package with a
# test, and a feature branch that changes it.
set -euo pipefail

git init -q -b main
mkdir -p docs/conventions textkit tests
printf 'verification: light\n' >docs/conventions/education.yaml
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
mkdir -p .work/origin.git
git init -q --bare -b main .work/origin.git
git remote add origin "$PWD/.work/origin.git"
git push -q origin main
git checkout -q -b feat/strip-punctuation
cat >textkit/slug.py <<'PY'
import re


def slugify(text):
    words = re.sub(r"[^\w\s-]", "", text).lower().split()
    return "-".join(words)
PY
git -c user.name=eval -c user.email=eval@example.invalid commit -q -am "feat: strip punctuation in slugify"
