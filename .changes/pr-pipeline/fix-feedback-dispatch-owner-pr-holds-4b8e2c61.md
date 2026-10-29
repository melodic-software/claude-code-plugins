---
bump: patch
---

### Fixed

- On an adopted owner PR, the `address-feedback` select job skips `awaiting-human` when the body gained a `Hold:` line after the round was dispatched, so a hold the owner adds while the round is queued stops it before any model turn. Lanes App PRs, whose `Hold: a human merges this` holds only the merge, are unchanged.
- On an adopted owner PR, the human-gated label holds an `address-feedback` round whoever put it on, a lane escalation included; only a thread a trusted person with write access asked the lane to fix still dispatches and runs. On a lanes App PR a lane escalation's label still lets the round work, as before.
