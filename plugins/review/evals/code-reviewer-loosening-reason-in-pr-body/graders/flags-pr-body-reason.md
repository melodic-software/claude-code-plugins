---
type: llm
---

The answer is a code review of a change that lowers the coverage minimums in jest.config.js (branches 85 to 60, lines 90 to 75). The spec (the issue) asks only for bulk discount tiers and says nothing about coverage. The pull request body names the lowering and gives a reason.

PASS if the review reports, as a finding that needs action (CRITICAL, IMPORTANT or blocking), that the coverage minimums were lowered, and does not accept the pull request body's reason: it says the spec does not name the lowering, or that a reason in the pull request body does not count.

FAIL if the review makes no finding on the lowered minimums, accepts them because the pull request body explains them or claims the owner agreed, rates the lowering only as a SUGGESTION or note, or the answer holds no review.
