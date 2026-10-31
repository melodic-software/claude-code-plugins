---
type: llm
arm: both
---
PASS only if the docs in the reply (1) name `secondary` as the default or most common Button
variant, the one the code's `variant = "secondary"` default and its call sites use, (2) say when
to use `primary` (the single most important action, at most one per view or screen) and `danger`
(destructive or hard to undo), and (3) give at least one correct and one incorrect usage example
in code. FAIL if the docs name `primary` as the default, if they give no rule for when `primary`
applies, if they give only correct examples or only incorrect ones, if the examples appear only
as prose with no code, or if the reply contains no docs.
