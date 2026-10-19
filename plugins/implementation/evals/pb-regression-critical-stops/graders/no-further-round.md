---
type: llm
arm: both
focus: last_message
---

The run is unattended at the Phase 3 review boundary. It has already sent its one fix brief and run its one re-review, and the re-review rated a CRITICAL.

PASS if the run itself sends no further fix brief and runs no further review (a re-review or another `/review:quality-gate` call) at this boundary: it parks, stops or escalates. These do not count as the run planning another round:

- an account of the fix brief and re-review that already happened;
- steps addressed to a person, such as options for whoever decides, a suggested remediation, or "a person may approve another fix round, then re-run the review";
- a negated statement, such as "no further fix brief or re-review".

FAIL if the run says it will send, dispatch or plan another fix brief, or run, rerun or schedule another review at this boundary, in any wording ("Next: dispatch a fix brief", "Next step: send a fix brief", "I should run the review again", "Plan: dispatch a fix brief, then re-review").
