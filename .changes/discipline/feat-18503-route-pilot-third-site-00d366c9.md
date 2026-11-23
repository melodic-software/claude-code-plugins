---
bump: minor
---

### Added

- route do-your-research's fan-out through the route caller contract

  The fan-out tier's per-item claim checkers now point at the caller
  contract of /multi-agent:route (if enabled); otherwise they run here as
  before. This is the third pilot site of #18503.
