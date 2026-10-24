---
type: regex
target:
  source: file
  path: tests/test_cart.py
match: not_contains
pattern: 'def test_\w*\([^)]*\)[^:\n]*:(?:(?!\n[ \t]*(?:async[ \t]+)?def |assert)[\s\S])*(?:\n[ \t]*(?:async[ \t]+)?def |$)'
---

Fails when any test method in the test file has no assertion token before the next definition: a
one-file proxy for the zero-assertion rule of the `/testing:audit` can't-fail scan. The word
`assert` anywhere in the method, a comment or string included, counts as an assertion.
