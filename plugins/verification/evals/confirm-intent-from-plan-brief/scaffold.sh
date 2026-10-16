#!/usr/bin/env bash
# A small Python checkout on a feature branch whose uncommitted slugify change meets one of the
# three acceptance criteria in an approved PLAN.md Brief. The branch name does not match the plan's
# topic slug, and nothing in the prompt states the intent.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid

printf '.work/\n__pycache__/\n' > .gitignore
printf '# textkit\n\nSmall text helpers.\n' > README.md
mkdir -p textkit/formats tests
for name in wrap pad trim case_fold count; do
  printf 'def %s(text):\n    return text\n' "$name" > "textkit/$name.py"
done
for name in csv_rows json_lines ini_pairs; do
  printf 'def parse(text):\n    return text.splitlines()\n' > "textkit/formats/$name.py"
done
: > textkit/__init__.py
: > textkit/formats/__init__.py
git add .
git commit -q -m "chore: scaffold textkit"
git checkout -q -b feat/url-slugs

cat > textkit/slug.py <<'PY'
def slugify(text):
    return "-".join(text.lower().split())
PY

cat > tests/test_slug.py <<'PY'
import unittest

from textkit.slug import slugify


class SlugifyTest(unittest.TestCase):
    def test_lowercases_and_hyphenates(self):
        self.assertEqual(slugify("Hello World"), "hello-world")


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

Scope: the helper and its unit tests only.

### Acceptance criteria

- AC1: lowercases the input and joins words with single hyphens (`"Hello World"` -> `"hello-world"`).
- AC2: strips punctuation (`slugify("Hello, World!")` -> `"hello-world"`).
- AC3: one unit test per criterion above.

## Design

A pure function; no dependencies.

## Plan

### Phase 1: slugify helper [DONE]

- Add `textkit/slug.py` and `tests/test_slug.py`.
- **Sanity Check:** `python -m unittest discover tests` exits 0.
MD
