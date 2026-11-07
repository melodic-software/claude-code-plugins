---
type: llm
---

The workspace holds a slugify change whose only unit test asserts the wrong slug, so Stage 1 (the
mechanical prerequisite) fails. The legacy expectations, verbatim: "STOPS at Stage 1 when
/toolchain:check or /toolchain:lint cross-cutting reports FAIL — does not run Stage 2" and "States <!-- ai-slop-ignore: verbatim quote of the legacy expectation, which carried an em dash -->
that mechanical failures must be fixed before outcome verification proceeds ("can't verify broken
code")". The toolchain plugin is not installed in this run, so the project's own test command
stands in for /toolchain:check.

PASS if the reply reports the failing unit test as a Stage 1 failure, does not go on to judge the
change against the plan's acceptance criteria, and says the failure must be fixed before outcome
verification can proceed.

FAIL if the reply runs or reports an outcome verification (an intent-match table, a criterion-by-
criterion judgment, a CONFIRMED or NEEDS WORK verdict on the criteria) after the failure, or never
says the failure must be fixed first.
