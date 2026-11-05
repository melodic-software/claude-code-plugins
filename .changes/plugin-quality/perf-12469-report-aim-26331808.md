---
bump: patch
---

### Changed

- aim dispatched-agent reports at 3,400 bytes under the 4,096 cap

  Over the 48 h after the cap shipped, capped implementer reports had a
  median body of 4,059 bytes and a p90 of 4,764: half still exceeded
  4,096. Agents aim at the stated number and overshoot it, so the
  contract now states a 3,400-byte aim and keeps 4,096 as the limit.

  Refs: #12469
