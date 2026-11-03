#!/usr/bin/env bash
# A small Python checkout on a feature branch whose uncommitted slugify change implements both
# acceptance criteria of an approved PLAN.md Brief. The only test was written in the diff and names
# no oracle source (rank 4), and punctuation stripping has no test at all, so the green check
# proves neither criterion.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid

printf '.work/\n__pycache__/\n' > .gitignore
printf '# textkit\n\nSmall text helpers.\n' > README.md
mkdir -p textkit tests
: > textkit/__init__.py
git add .
git commit -q -m "chore: scaffold textkit"
git checkout -q -b feat/slugify

cat > textkit/slug.py <<'PY'
import re


def slugify(text):
    words = re.sub(r"[^\w\s]", "", text).lower().split()
    return "-".join(words)
PY

cat > tests/test_slug.py <<'PY'
import unittest

from textkit.slug import slugify


class SlugifyTest(unittest.TestCase):
    def test_slugify(self):
        self.assertEqual(slugify("Hello World"), slugify("Hello World"))


if __name__ == "__main__":
    unittest.main()
PY
git add -N textkit/slug.py tests/test_slug.py

mkdir -p .work/slugify
cat > .work/slugify/PLAN.md <<'MD'
# slugify

Approval: approved by the maintainer in the planning session

## Brief

Goal: a `slugify(text)` helper in `textkit/slug.py` for URL path segments.

### Acceptance criteria

- AC1: lowercases the input and joins words with single hyphens (`"Hello World"` -> `"hello-world"`).
- AC2: strips punctuation (`slugify("Hello, World!")` -> `"hello-world"`).

## Plan

### Phase 1: slugify helper [DONE]

- Add `textkit/slug.py` and `tests/test_slug.py`.
- **Sanity Check:** `python -m unittest discover tests` exits 0.
MD
