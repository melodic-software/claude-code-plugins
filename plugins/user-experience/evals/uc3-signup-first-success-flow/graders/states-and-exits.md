---
type: llm
arm: both
---
PASS only if the flow runs from sign-up to the first saved recipe using the steps in the project's
PRD or app routes (sign-up, email verification, the optional pantry setup, adding the first recipe),
and each step names the states it must handle (for example empty, loading, error, success) and its
exits or branches (for example an unverified email, skipping pantry setup, leaving part way). FAIL
if a step has no states, the exits are missing, or the steps ignore the project's files.
