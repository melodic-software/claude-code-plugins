---
bump: patch
---

### Changed

- `/source-control:pull-request`, `/source-control:worktree` gather their repository context as separate Bash calls sent in parallel in one message, one turn instead of one per command, with the rule text generated from `docs/conventions/gather-block/block.md`.
- `/source-control:commit` drops its four git gathers, which no step read; its config-layer probes stay as they were.
