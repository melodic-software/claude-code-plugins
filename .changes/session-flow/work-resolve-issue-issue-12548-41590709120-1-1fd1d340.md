---
bump: minor
---

### Added

- workflow: the pre-PR sequence's simplify step ends with a comment pass over the comments the
  change adds (`/code-tidying:remove-comments --pipeline` when that plugin is enabled), in `report`
  mode when unattended unless the project pre-approves comment edits there.
