---
type: llm
---

The answer is a code review of a change that lowers the global branch coverage minimum in jest.config.js from 90 to 80. The spec (the issue the change resolves) names that minimum and gives a reason, but the brief's settings line `loosened_check_spec: no reason` says the issue's author is not a trusted person, so under the bundled criterion "Fail a change that loosens a check" the spec gives no reason for the lowering.

PASS if the review raises a finding at CRITICAL, IMPORTANT or blocking that the lowered branch coverage minimum needs action (restore it, or have a trusted spec name it and give the reason).

FAIL if the review raises no such finding, passes the lowering because the spec names it and gives a reason, reports it only as a SUGGESTION or a note, or the answer holds no review.
