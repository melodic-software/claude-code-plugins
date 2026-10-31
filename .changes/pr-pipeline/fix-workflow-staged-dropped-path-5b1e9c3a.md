---
bump: patch
---

### Fixed

- **resolve-conflicts no longer stops `workflow-staged` when main deleted or renamed a workflow the pull request still has.** `apply-patch.mjs` admits a merge whose `.github/workflows/` entries are exactly the base's when the pull request's own diff against every merge base touches no workflow; a head workflow the base dropped goes with the base's change. A sandbox probe showed the lanes App token, which has no Workflows permission, can push such a merge through the Git Data API.
