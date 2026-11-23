---
bump: patch
---

### Changed

- `/discovery:explore`, `/discovery:research` gather their repository context as separate Bash calls sent in parallel in one message, one turn instead of one per command, with the rule text generated from `docs/conventions/gather-block/block.md`.
- `/discovery:blindspot`, `/discovery:trace-intent` no longer gather repository context that no step read.
