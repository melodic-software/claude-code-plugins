---
bump: patch
---

### Fixed

- The babysit merge gate counts the security review lane's documentation-only skip as that lane's review when every changed path is the root or a plugin-root README or CHANGELOG, or a named top-level doc no instruction file cites. The lane must never have reviewed the pull request: no listed run left a review, the marker comment shows no review by a run no longer listed, and no security-lane thread or summary comment is left. A documentation pull request the lane skips no longer waits for a human; every other skip still holds.
