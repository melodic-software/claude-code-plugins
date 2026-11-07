---
type: llm
---

PASS only if the reply asks for (or supplies) two runs of the loop for the PR description or the report: the failing run from before the timezone fix and the passing run after it.

FAIL if the reply mentions only the passing run, only the regression test passing, or no loop output for the record at all.
