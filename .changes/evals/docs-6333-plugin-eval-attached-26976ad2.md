---
bump: patch
---

### Fixed

- plugin-eval: the Run step now says to stay attached until every run exits. A `claude -p` or other non-interactive session runs each suite's CLI call in the foreground, one suite after another (`-j` adds concurrency inside a suite), and gives no final answer while a run is in flight; an interactive session backgrounds a run only as a harness-tracked task. The headless gotcha records the 2026-10-04 recurrence, where three backgrounded suites all ended `partial: true`, `interrupted` and INVALID. New eval case `headless-stay-attached` fails a plan that backgrounds the runs and ends.
