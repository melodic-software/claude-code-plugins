---
bump: patch
---

### Fixed

- The verdict reader's carried listing first re-reads the pages around entries near expiry, up to a page cap, when it holds more than GitHub's live count. That over-count then takes at most one whole listing.
