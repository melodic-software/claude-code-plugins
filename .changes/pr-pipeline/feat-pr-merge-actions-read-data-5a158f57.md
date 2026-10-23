---
bump: patch
---

### Changed

- The pr-merge lane token now carries Actions read (owner decision Q8), for its verdict and run reads to fall back on; the verdict downloads, listing and run records still read with `GITHUB_TOKEN`.
