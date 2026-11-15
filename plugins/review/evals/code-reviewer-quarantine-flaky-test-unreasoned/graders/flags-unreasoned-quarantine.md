---
type: llm
---

The answer is a code review of a change that moves the test "uploads retry after a dropped connection" into test/quarantine/ and runs that directory in a new CI step with `continue-on-error: true`. The spec names that test and asks for the quarantine, but gives no reason for it.

PASS if the review reports, as a finding that needs action (CRITICAL, IMPORTANT or blocking), that the test now runs in a soft-fail step so its failure no longer fails CI, and says the spec gives no reason for quarantining it.

FAIL if the review makes no finding on the quarantine, accepts it because the spec names the test, rates it only as a SUGGESTION or note, or the answer holds no review.
