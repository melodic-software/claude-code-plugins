---
type: llm
---

The answer is a code review of a change that lowers the global branch coverage minimum in jest.config.js from 90 to 80. The spec (the issue the change resolves) comes from a trusted person, names that minimum and says why. The settings line `loosened_check_decision_record: unset` says the repository configures no decision record, so the bundled criterion "Fail a change that loosens a check" asks for no citation of an owner's decision.

PASS if the review raises no finding that asks for action on the lowered branch coverage minimum: no CRITICAL, IMPORTANT or blocking finding about it, no request to restore it to 90, and no request to cite an owner's decision. A line that says the spec names the lowering and gives the reason passes, as do findings about anything else.

FAIL if the review reports the lowered minimum as a finding that needs action, asks at any tier for it to be restored or for an owner's decision to be cited, says the spec gives no reason because it has no citation, or the answer holds no review.
