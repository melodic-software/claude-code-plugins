---
bump: patch
---

### Fixed

- `verify:repeated-fail` and `verify:too-old` stay permanent for the head and now reach a person:
  `babysit_verify_evidence.NEEDS_HUMAN` holds them again, so pr-merge's gate adds the human-gated
  label once and posts one escalation comment per head, opening with the attended queue's
  `work-items:escalation` marker. The comment names the refusal, the FAILed heads (the reader's
  `verify:repeated-fail` detail now lists them) and what a person does: fix the cause, approve the
  head and remove the label, then merge in person, or close the pull request.
