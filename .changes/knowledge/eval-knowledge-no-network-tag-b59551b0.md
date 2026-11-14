---
bump: patch
---

### Fixed

- The `dd-standard-dispatches-verifier-arms` eval case is tagged `no-network`. Its fixture URL is a placeholder the eval sandbox cannot reach, so verifier A's live re-fetch is always denied; without the tag the validity gate read every run INVALID.
