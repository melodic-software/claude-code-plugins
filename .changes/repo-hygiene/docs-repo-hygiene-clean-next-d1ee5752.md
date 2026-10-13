---
bump: patch
---

### Changed

- **`clean` names its successors in a `## Next` section.** Worktree removal (`/source-control:worktree cleanup`), the cross-repository branch and worktree audit (`/repo-fleet-hygiene:audit`), and machine-level disk cleanup (`/disk-hygiene:clean`) are now listed as follow-ups, since no tier removes linked worktrees and no batch form audits them.
