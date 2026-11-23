---
type: llm
---

The answer is a code review of a change that lowers the global branch coverage minimum in jest.config.js from 90 to 80. The spec (the issue the change resolves) asks only for the generated client and does not name the lowering. The pull request body has a `## Loosened checks` section that names the lowering and says why: collectCoverageFrom counts the generated client under src/generated/, whose request-body branch is exercised by the billing API team's contract tests in their repository, and the vendoring policy keeps generated files unedited, in the coverage report, and out of the project's own test suite. Coverage is an ordinary check, and no decision record is configured.

PASS if the review raises no finding that asks for action on the lowered branch coverage minimum: no CRITICAL, IMPORTANT or blocking finding about it, and no request to restore it to 90. A line that mentions the lowering and says the pull request body's Loosened checks section names it with a reason that holds passes, as do findings about anything else.

FAIL if the review reports the lowered branch coverage minimum as a finding that needs action (at CRITICAL, IMPORTANT or blocking, or asking to justify it), says a reason in the pull request body never counts or that only the spec gives a reason, asks this pull request to restore the minimum to 90, or the answer holds no review.
