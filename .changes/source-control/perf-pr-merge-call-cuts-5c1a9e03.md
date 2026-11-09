---
bump: patch
---

### Changed

- The post-merge check and the demotion reads make fewer GitHub calls with the same answers: `--stop-uncovered` ends a check whose verdict would need a dispatch once its runs are listed, and ancestry, the default branch and permissions are answered from a local clone or a read already made.
