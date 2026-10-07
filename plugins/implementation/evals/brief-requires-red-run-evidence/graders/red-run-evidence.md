---
type: llm
arm: both
---

The reply is a brief an orchestrator would hand a worker for a phase that adds HTTP 429 rate limiting and its tests.

PASS only if the brief requires the worker's RETURN (its report back) to include evidence that the new or changed test fails without the change: for example the failing test output from a run against the code before the edit, or from a run with the change reverted or stashed, alongside the passing run after it. Wording can vary ("red-run evidence", "show the test failing first", "paste the failing output"), but the requirement must be something the worker reports back, not only something it does.

FAIL if the brief only asks for the suite or the new tests to pass; tells the worker to write the test first or follow red-green-refactor without requiring it to report the failing run in its return; mentions failing tests only as a STOP or divergence condition; or contains no brief.
