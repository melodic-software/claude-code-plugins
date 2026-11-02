---
bump: patch
---

### Changed

- The guardrails say a demotion's record is filed with no human-gated label and intake triage hands it to a lane. The record stops holding with no person only once its evidence clears (a red main branch once main is green at a later commit); evidence a green main cannot clear holds until a person clears it.
