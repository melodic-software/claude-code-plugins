---
bump: minor
---

### Added

- `ratchet` takes check counts from `/performance:target` as a counter source: checks per hook stage or CI job, files a check scans, or test suites a change selects, so a lane's growth fails the change that adds to it while its duration stays unratcheted.
