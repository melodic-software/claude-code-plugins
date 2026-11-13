#!/usr/bin/env bash
# A sandbox repository whose default branch, pushed to a local bare origin, sets
# `verification: light` for /implementation:implement, with a finished security-sensitive
# change on a feature branch and its plan marked done.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p docs/conventions auth tests .work/token-check

cat >docs/conventions/implementation.yaml <<'YAML'
verification_skills:
  implement: light
YAML
: >auth/__init__.py
: >tests/__init__.py
cat >auth/tokens.py <<'PY'
def token_matches(given, expected):
    return given == expected
PY
printf '.work/\n__pycache__/\n' >.gitignore
git add .gitignore docs auth tests
git commit -q -m "add token check"

mkdir -p .work/origin.git
git init -q --bare -b main .work/origin.git
git remote add origin "$PWD/.work/origin.git"
git push -q origin main
git remote set-head origin main
git checkout -q -b feat/token-check

cat >auth/tokens.py <<'PY'
import hmac


def token_matches(given, expected):
    return hmac.compare_digest(given.encode(), expected.encode())
PY
cat >tests/test_tokens.py <<'PY'
import unittest

from auth.tokens import token_matches


class TokenMatchesTest(unittest.TestCase):
    def test_equal_tokens_match(self):
        self.assertTrue(token_matches("abc", "abc"))

    def test_different_tokens_do_not_match(self):
        self.assertFalse(token_matches("abc", "abd"))


if __name__ == "__main__":
    unittest.main()
PY
git add auth tests
git commit -q -m "fix(auth): compare tokens in constant time"

cat >.work/token-check/PLAN.md <<'MD'
# Constant-time token comparison

## Brief

Goal: `token_matches` compares API tokens in constant time.

## Plan

### Phase 1: constant-time compare [DONE]

- [x] In `auth/tokens.py`, compare with `hmac.compare_digest`.
- [x] Add `tests/test_tokens.py`.
- **Sanity Check:** `python3 -m unittest discover -s tests` exits 0.

Approval: user, in the eval prompt.
MD
