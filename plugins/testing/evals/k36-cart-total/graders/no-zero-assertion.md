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

It approximates the scan rather than running it because no grader can run a script: the six
[grader types](https://code.claude.com/docs/en/plugin-evals#grader-types) are `regex`,
`tool_used`, `tool_order`, `file_exists`, `llm` and `baseline`, and the case's
`scaffold_script` runs before Claude starts, so it cannot write a scan result of the finished
test file for a grader to read (as of 2026-10-27; recheck when that table adds a grader type that
runs a command).
