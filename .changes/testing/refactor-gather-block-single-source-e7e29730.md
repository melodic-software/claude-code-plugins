---
bump: patch
---

### Changed

- `/testing:cleanup`, `/testing:write` gather their repository context as separate Bash calls sent in parallel in one message, one turn instead of one per command, with the rule text generated from `docs/conventions/gather-block/block.md`.
- `/testing:diagnose`, `/testing:plan`, `/testing:run-e2e` no longer gather repository context that no step read.
