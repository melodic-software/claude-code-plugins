---
bump: patch
---

### Fixed

- A lanes App pull request the merge gate refuses `verify:earlier-fail` no longer dead-ends once
  its pr-verify fail-note threads are resolved. The dispatcher sends an address-feedback model
  round naming the FAILed heads (`verify-earlier-fail-heads`, from the reader's `earlierFails`)
  even with no unresolved thread. `address-feedback-select`, now with `actions: read`, reads
  those FAILs' notes from their verdict artifacts as the model's work items, and stops
  `feedback-verdict-unreadable` when it cannot. A push fixing a named note ends as any fix
  round; no push with every note already addressed stops `feedback-already-addressed` with
  `needs-session`.
