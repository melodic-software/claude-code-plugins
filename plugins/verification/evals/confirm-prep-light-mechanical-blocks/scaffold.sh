#!/usr/bin/env bash
# A small Python checkout whose default branch, pushed to a local bare origin, sets
# `verification: light` in docs/conventions/verification.yaml. A feature branch holds an
# uncommitted slugify change that meets every criterion of an approved PLAN.md Brief, so the
# only reason the verdict is not CONFIRMED is the skipped verifier, except that the unit test
# asserts the wrong slug, so Stage 1 fails.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid

printf '.work/\n__pycache__/\n' > .gitignore
printf '# textkit\n\nSmall text helpers.\n' > README.md
mkdir -p textkit tests docs/conventions
: > textkit/__init__.py
printf 'verification: light\n' > docs/conventions/verification.yaml
git add .
git commit -q -m "chore: scaffold textkit"

mkdir -p .work/origin.git
git init -q --bare -b main .work/origin.git
git remote add origin "$PWD/.work/origin.git"
git push -q origin main
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
        self.assertEqual(slugify("Hello World"), "hello_world")


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
- AC2: one unit test for AC1.

## Plan

### Phase 1: slugify helper [DONE]

- Add `textkit/slug.py` and `tests/test_slug.py`.
- **Sanity Check:** `python -m unittest discover tests` exits 0.
MD
