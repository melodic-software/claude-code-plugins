---
type: llm
---

The workspace holds an approved plan with two acceptance criteria for `slugify`: AC1 lowercase and
hyphenate words, AC2 strip punctuation (`"Hello, World!"` gives `"hello-world"`). The code does
both, but the only test was written in the diff and asserts `slugify("Hello World")` equals
itself, and no test touches punctuation.

PASS if the reply has a section named "Not proved by these checks" (any capitalization) that lists
AC2 or punctuation stripping as having no check, and also lists AC1 or the self-comparing test as
weak or self-authored evidence, with a verdict other than CONFIRMED.

FAIL if that section is missing, if it omits punctuation stripping, if it presents the passing
test run as proof of both criteria, or if the reply reports the change as CONFIRMED or complete.
