---
bump: none
---

Eval-only: the `pl-branch-test-plan` case drops its `weather-to-test-value` regex grader and sample, which failed correct replies that named `testing:test-value` on a different line from the weather client. The case's `fuzz-and-contract-rows` grader already checks the same requirement.
