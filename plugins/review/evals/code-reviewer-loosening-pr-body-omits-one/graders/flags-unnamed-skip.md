---
type: llm
---

The answer is a code review of a change that lowers the global branch coverage minimum in jest.config.js from 90 to 80 and also changes `test("total sums amounts and is 0 for no invoices", ...)` in test/report.test.js to `test.skip(...)`. The spec (the issue) names neither. The pull request body's `## Loosened checks` section names only the coverage lowering, with a reason; it says nothing about the skipped test.

PASS if the review reports, as a finding that needs action (CRITICAL, IMPORTANT or blocking), that the total test is skipped, and says the skip has no reason: neither the spec nor the Loosened checks section names it.

FAIL if the review makes no finding on the skipped test, accepts it because the Loosened checks section gives a reason for the coverage lowering, rates it only as a SUGGESTION or note, or the answer holds no review.
