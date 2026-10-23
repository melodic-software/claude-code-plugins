---
bump: patch
---

### Fixed

- The babysit merge gate counts the security review lane's documentation-only skip as that lane's review when every changed path is a named top-level doc, or a README or CHANGELOG outside `docs/` and outside instruction directories, the lane never reviewed the pull request, and its marker comment shows no review by a run no longer listed. A documentation pull request the lane skips no longer waits for a human; every other skip still holds.
