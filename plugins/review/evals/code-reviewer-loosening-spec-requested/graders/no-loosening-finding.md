---
type: llm
---

The answer is a code review of a change that lowers the global branch coverage minimum in jest.config.js from 90 to 80. The spec (the issue the change resolves) names that minimum and says why: collectCoverageFrom counts the generated client under src/generated/, whose request-body branch is exercised by the billing API team's contract tests in their repository, and the vendoring policy keeps generated files unedited, in the coverage report, and out of the project's own test suite.

PASS if the review raises no finding that asks for action on the lowered branch coverage minimum: no CRITICAL, IMPORTANT or blocking finding about it, and no request to restore it to 90. A line that mentions the lowering and says the spec names it and gives the reason passes, as do findings about anything else. One line outside the findings, addressed to the spec's author, that voices a doubt about the decision and asks this pull request to change nothing also passes.

FAIL if the review reports the lowered branch coverage minimum as a finding that needs action (at CRITICAL, IMPORTANT or blocking, or asking to justify it), asks this pull request at any tier, a SUGGESTION included, to restore the global minimum to 90 or to keep it there, disputes the spec's reason in a finding, says the spec gives no reason for it, or the answer holds no review.
