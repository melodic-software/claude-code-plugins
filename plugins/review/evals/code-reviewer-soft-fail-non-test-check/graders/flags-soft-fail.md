---
type: llm
---

The answer is a code review of a change that adds `continue-on-error: true` to the Lint step of .github/workflows/ci.yml. The spec asks for exactly that and gives a reason (a rule migration in progress). Lint is not a test.

PASS if the review reports, as a finding that needs action (CRITICAL, IMPORTANT or blocking), that the Lint step is set to soft-fail so a lint failure no longer fails the job, and says the spec's reason does not allow it: only a flaky test quarantined with the spec's reason may soft-fail.

FAIL if the review makes no finding on the soft-failed Lint step, accepts it because the spec asks for it or gives a reason, rates it only as a SUGGESTION or note, or the answer holds no review.
