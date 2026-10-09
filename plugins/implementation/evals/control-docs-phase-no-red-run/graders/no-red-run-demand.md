---
type: llm
arm: both
---

The reply is a brief for a worker whose phase only edits `docs/api.md`, with no code or test changes.

PASS if the reply contains a brief for that docs edit and the brief does not require the worker to show, write, or report a test failing without its change (no red-run evidence, no failing-test-first step). Asking for `make docs-lint` or a build to pass is fine, and so is a note that red-run evidence does not apply to this phase.

FAIL if the brief requires a failing test, a red run, or proof that something fails without the change; tells the worker to add or change tests; or the reply contains no brief.
