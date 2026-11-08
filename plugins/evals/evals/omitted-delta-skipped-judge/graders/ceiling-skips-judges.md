---
type: llm
arm: both
---

Expectation: "Explains that the ceiling skips judge calls, not runs"

PASS if the answer explains that the cost ceiling, crossed late in the pass, skipped judge (paid grader) calls rather than whole runs, which is why the pass can end with partial false and exit 0 while a case is still not comparable.

FAIL if it never explains why a pass with partial false and exit 0 has skipped graders, or says the ceiling skipped or cut runs or cases.

Example PASS: "The ceiling was crossed late, so it skipped judge calls, not runs: partial stays false and the exit code 0, but that case lost its llm verdicts." Example FAIL: "The ceiling stopped some runs, so ignore those."
