---
bump: patch
---

### Fixed

- Never update a dependency-manager PR branch before merging (ask the manager to rebase instead), and skip the update on a merge-queue base; the branch-refresh helper refuses a dependency-manager PR.
