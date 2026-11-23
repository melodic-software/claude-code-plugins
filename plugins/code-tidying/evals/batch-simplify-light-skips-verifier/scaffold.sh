#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
mkdir -p docs/conventions textkit tests
printf 'verification: light\n' >docs/conventions/code-tidying.yaml
: >textkit/__init__.py
printf '.work/\n__pycache__/\n' >.gitignore
git add .
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "scaffold textkit"
mkdir -p .work/origin.git
git init -q --bare -b main .work/origin.git
git remote add origin "$PWD/.work/origin.git"
git push -q origin main
git checkout -q -b feat/count-words

cat >textkit/words.py <<'PY'
def count_words(text):
    result = 0
    parts = text.split()
    if len(parts) > 0:
        for i in range(0, len(parts)):
            if parts[i] != "":
                result = result + 1
            else:
                result = result + 0
    else:
        result = 0
    return result
PY

cat >tests/test_words.py <<'PY'
import unittest

from textkit.words import count_words


class CountWordsTest(unittest.TestCase):
    def test_counts(self):
        self.assertEqual(count_words("a b  c"), 3)
        self.assertEqual(count_words(""), 0)


if __name__ == "__main__":
    unittest.main()
PY
git add .
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "feat: count words"
