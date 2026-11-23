---
bump: patch
---

### Changed

- `/bugs:scan` gather their repository context as separate Bash calls sent in parallel in one message, one turn instead of one per command, with the rule text generated from `docs/conventions/gather-block/block.md`.
- `/bugs:write` no longer gather repository context that no step read.
