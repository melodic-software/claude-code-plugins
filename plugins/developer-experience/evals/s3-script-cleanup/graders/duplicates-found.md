---
type: llm
focus: last_message
---

Rubric item: `test.sh` / `run_tests.sh` found as duplicates.

User prompt: "Our scripts have gotten messy. Which of them do we still need?" (Python repo `brackenfold`). In the fixture, `scripts/test.sh` runs the same command as `scripts/run_tests.sh` with the flags in a different order.

PASS when the output states that `scripts/test.sh` and `scripts/run_tests.sh` do the same thing (duplicate, redundant, equivalent). FAIL when it does not identify them as duplicates, or treats them as different tools.
