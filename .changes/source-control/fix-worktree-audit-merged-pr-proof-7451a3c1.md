---
bump: minor
---

### Added

- `landed-work.sh --merged-pr-proof` reads a branch's merged pull request (merged into the resolved base) and reports the branch `landed` when local HEAD equals or is an ancestor of the PR head, or every unpushed commit is in the PR's commit list. With the flag, which the worktree status procedure passes, squash-merged worktrees no longer come back `unknown` or `superseded`. A failed PR read keeps the prior verdict and names the read in the reason.

### Fixed

- The worktree audit and status summaries now add the unpushed commits of every stranded-class row (`STRANDED`, `UNKNOWN`, `superseded`) to "commits at risk", so the stranded count and the commit figure agree.
