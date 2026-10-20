---
bump: patch
---

### Fixed

- The merge-base lane (`pr-unblock` update-branch and resolve-conflicts) no longer escalates
  `workflow-staged` when the merge only brings in the default branch's own `.github/workflows/`
  files: `post.sh` lets the merge through when every staged workflow entry is the trusted base's
  (mode and blob), no head workflow is dropped, and the PR's own diff against every merge base
  touches no workflow. Every other case still escalates.
