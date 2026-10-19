---
bump: none
---

### Changed

- The `worktree-create-routes-through-helper` eval case no longer grants or grades `EnterWorktree`, which `claude plugin eval` never makes available, so two of its graders failed in every run. `entered-by-path`, `helper-before-enter` and `never-entered-by-name` are replaced by `names-created-path` (the reply names the created path or the helper's refusal) and `helper-given-name` (a Bash call passes `worktree-create.sh` the requested name).
