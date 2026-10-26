---
bump: patch
---

### Changed

- `enable-auto-merge` no longer spends most of its lane-room time limit on a full post-merge check when the run's report was refused only because an issue the lanes App opened was edited since (`demotion-changed`). The room reads the demotion records alone and keeps the report when they are unchanged, so a slow API window no longer risks running past the time limit and disarming every armed lanes App pull request.
