# Widget Runner: retry and backoff

Synthetic source page for the provenance golden set. Widget Runner is a fictional build tool
invented for these fixtures. Nothing on this page describes a real product or reproduces text
from a real page.

Canonical location for the purposes of this case: `https://example.invalid/widget-runner/docs/retry`.

This page is the shared basis for the three adversarial synonym-rotation cases (c08, c09, c10),
which differ only in how densely the passage below is rotated. Holding the source fixed is what
makes rotation density the single variable.

## The retry policy

When a task fails, Widget Runner consults the retry policy attached to that task before it
decides whether to schedule the task again. The policy names a strategy, a ceiling on attempts,
and an optional jitter fraction. A task with no policy of its own inherits the workspace default,
which retries twice with linear backoff and no jitter. The runner records every attempt
separately in the log, so a task that eventually succeeds still shows its failures.
