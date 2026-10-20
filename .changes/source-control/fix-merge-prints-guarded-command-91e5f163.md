---
bump: patch
---

### Fixed

- pull-request merge: the merge-after-AI-review script now prints the complete guarded merge
  command, with the PR number, repository and head sha filled in, after its `merge-ready` line, and
  the skill runs that line as-is. The guarded and admin merge templates now carry every clause the
  auto-mode allow entries require: both accepted authors, the full changed-files pattern, and a
  `NEUTRAL` review conclusion.
- worktree cleanup: the deferred-removal note says the reap takes `--worktree-path` and enters the
  candidate itself.
