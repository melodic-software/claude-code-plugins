---
bump: patch
---

### Fixed

- `dependency --ci` returns `owner_reason` in its verdict: `intent`, `design`, `security` or
  `cost` on an `escalate` the owner decides, else `none`, which sends the stop to a session
  builder instead of the owner.
