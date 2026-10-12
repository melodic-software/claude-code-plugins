---
bump: patch
---

### Fixed

- The cloud-session GitHub note no longer says the proxy serves a pinned set of GraphQL operations;
  one pointer record in the GitHub adapter's "View item" section now owns that fact and every other
  site cites it.
- The permission preflight no longer calls Claude Code's default worktree placement a sibling
  layout.
- `preflight.sh` output changed: the uncovered-worktree-root gap now says every out-of-tree write
  will prompt (not that `acceptEdits` will), and the autonomous-mode and UNREAD LAYER headers no
  longer say main-checkout rules apply in every worktree since v2.1.211 unconditionally; they
  qualify it to where approvals save at the repository root.

### Changed

- Restated Claude Code behavior in the permission preflight, the work-loop standing-mode and
  telemetry references, and the attend-queue and setup spoke-path notes is replaced with anchored
  pointer records (pointer, as-of date, recheck trigger).
