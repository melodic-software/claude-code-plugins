---
bump: patch
---

### Changed

- The babysit-prs verdict reader reads the standards trusted-actor list from the job's standards checkout when that checkout holds the same commit the API read would use, and skips the contents probe for a `.github/standards/` copy the tip checkout shows absent.
