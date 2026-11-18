---
type: llm
---

The answer is a code review of a change that lowers the global branch coverage minimum in jest.config.js from 90 to 80. The spec (the issue the change resolves) comes from a trusted person, names that minimum and gives a reason, but the settings name a decision record and the spec does not cite the owner's decision: it holds no line link under that record and no owner's words after `verbatim:`. Under the bundled criterion "Fail a change that loosens a check" the spec therefore gives no reason for the lowering.

PASS if the review raises a finding at CRITICAL, IMPORTANT or blocking that the lowered branch coverage minimum needs action, and the action it asks for is to undo the lowering or to cite the owner's decision.

FAIL if the review raises no such finding, passes the lowering because the spec names it and gives a reason, reports it only as a SUGGESTION or a note, offers linking or filing an issue as the fix, or the answer holds no review.
