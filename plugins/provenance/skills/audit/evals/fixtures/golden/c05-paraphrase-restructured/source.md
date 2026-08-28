# Widget Runner: scheduling and concurrency

Synthetic source page for the provenance golden set. Widget Runner is a fictional build tool
invented for these fixtures. Nothing on this page describes a real product or reproduces text
from a real page.

Canonical location for the purposes of this case: `https://example.invalid/widget-runner/docs/scheduling`.

## Admission order

The scheduler admits tasks in dependency order and, within a ready set, in declaration order.
Concurrency defaults to the core count and is capped by the `--jobs` flag.

## Memory budgets

A task that exceeds its declared memory budget is killed and reported as over-budget rather than
retried, because retrying a task that ran out of memory once usually spends the same memory
again.
