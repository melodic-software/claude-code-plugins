#!/usr/bin/env bash
# A sandbox repository whose planning team file sets only verification: standard (plan_stress_test
# stays auto), pushed to a local bare origin, holding a small textkit package with a test, a feature
# branch that changes it, and a settled one-function draft plan with LOW blast radius and no
# stress-test trigger.
set -euo pipefail

git init -q -b main
mkdir -p textkit tests docs/conventions
printf 'verification: standard\n' >docs/conventions/planning.yaml
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

# A settled draft plan and a design early exit, so the run reaches Step 3 without open questions.
mkdir -p .work/slugify-max-length/design
cat >.work/slugify-max-length/PLAN.md <<'MD'
# slugify max_length

## Brief

### Problem
Slugs from long titles make URLs too long for the share links that embed them.

### Goal
`slugify` takes an optional `max_length` and returns a slug no longer than it, cut on a word boundary.

### Acceptance criteria
- AC1: `slugify(text)` with no `max_length` returns what it returns today.
- AC2: `slugify(text, max_length=n)` drops whole trailing words so the result is at most `n`
  characters and never ends in a hyphen; every hyphen in the output counts as a word boundary.
- AC3: When the first word alone is longer than `n`, the result is that word cut to `n` characters.
- AC4: `max_length` below 1 raises `ValueError`.

### Out-of-scope
- Unicode transliteration.

## Plan

### Behavior
- B1: no limit keeps today's output (AC1). Delivered by Phase 1.
- B2: a limit cuts whole words, or the first word, to fit (AC2, AC3). Delivered by Phase 1.
- B3: a limit below 1 is refused (AC4). Delivered by Phase 1.

### Phase 1: Add max_length [STATUS]
**Satisfies:** AC1, AC2, AC3, AC4
**Delivers:** B1, B2, B3

- In `textkit/slug.py`, add `max_length=None`; after joining, when it is set, cut the slug at the
  last hyphen at or before `max_length`, or at `max_length` when there is none.
- Raise `ValueError` when `max_length` is below 1.
- Add one test per criterion to `tests/test_slug.py`.

**Sanity Check:** `python -m unittest discover -s tests` exits 0.

### Files affected
| File | Action |
|---|---|
| `textkit/slug.py` | modify |
| `tests/test_slug.py` | modify |
MD
# The phase heading takes its status tag here, outside the heredoc.
plan=.work/slugify-max-length/PLAN.md
text="$(cat "$plan")"
printf '%s\n' "${text//'[STATUS]'/[TODO]}" >"$plan"
cat >.work/slugify-max-length/design/design-resolution.md <<'MD'
outcome: early-exit
tier: C
reason: One optional parameter on one existing function; no new types.
MD
