---
bump: patch
---

### Fixed

- On an adopted owner PR, the `address-feedback` select job skips `awaiting-human` when the body gained a `Hold:` line after the round was dispatched, so a hold the owner adds while the round is queued stops it before any model turn. Lanes App PRs, whose `Hold: a human merges this` holds only the merge, are unchanged.
- On an adopted owner PR, a lane escalation's human-gated label lets an `address-feedback` round dispatch and run only as it lets fix-ci work the PR (`gate-source.mjs` `prHold`): it holds after an `address-feedback` escalation, or once a person commented or reviewed after the label went on, and then only a thread a trusted person with write access asked the lane to fix is worked. On a lanes App PR a lane escalation's label still lets the round work, as before.
