---
bump: patch
---

### Changed

- **No merge partition reads a work class.** The work-class label references now say only the untrusted-provenance floor decides anything by the `work-class:` label, matching the babysit loop's rung partition, which reads no class (#12748).
