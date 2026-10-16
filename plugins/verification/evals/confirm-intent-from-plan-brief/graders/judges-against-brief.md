---
type: llm
---

The workspace holds an approved plan whose Brief lists three acceptance criteria for `slugify`:
AC1 lowercase and hyphenate words, AC2 strip punctuation (`"Hello, World!"` gives `"hello-world"`),
AC3 one unit test per criterion. The change meets AC1 only. The user stated no intent.

PASS if the reply judges the change against that Brief's criteria, citing the plan or its Brief, and
reports that punctuation stripping (AC2) is not met or is missing, with a verdict other than
CONFIRMED.

FAIL if the reply asks the user for the goal instead of using the plan, judges against an intent it
invented, never mentions punctuation, reports the change as CONFIRMED or complete, or answers a
different question.
