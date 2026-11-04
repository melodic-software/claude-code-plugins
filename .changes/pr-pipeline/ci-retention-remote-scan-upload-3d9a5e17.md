---
bump: patch
---

### Changed

- The artifact-retention check counts ci-workflows' `scan-upload` action pinned to a full commit
  SHA as a leak scan, as it does the local one; a tag, a branch or a short SHA does not count.
  The key-credit probing marker's row in `.github/artifact-retention.json` now says
  `scan: upload`, and the check verifies the scan before that upload.
