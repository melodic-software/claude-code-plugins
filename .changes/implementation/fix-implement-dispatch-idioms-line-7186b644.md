---
bump: patch
---

### Changed

- `/implementation:implement-dispatch` carries the `language idioms:` line on the dispatched path. Each worker brief gets a `Language idioms:` line that has the worker resolve the idioms by `/implementation:implement`'s type-decision rule and return each `language idioms:` line it printed, and the final report repeats every returned line. The `type-decision-no-idioms-declared-proceeds-on-neutral-rules` case is now also a `claude plugin eval` case, `implement-type-decision-no-idioms-declared-proceeds-on-neutral-rules`, whose regex grader matches the line in any case.
