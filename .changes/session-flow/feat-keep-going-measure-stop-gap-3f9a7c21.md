---
bump: minor
---

### Added

- keep-going measures how long the session was stopped from transcript timestamps with a bundled `measure-stop-gap.py`, states the gap in its report, and re-reads limit windows, leases, PR state and CI runs older than the gap instead of trusting them.
