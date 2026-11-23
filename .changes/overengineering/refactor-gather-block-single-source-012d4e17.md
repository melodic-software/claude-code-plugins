---
bump: patch
---

### Changed

- `/overengineering:audit`, `/overengineering:delta`, `/overengineering:justify`, `/overengineering:realign` gather their repository context as separate Bash calls sent in parallel in one message, one turn instead of one per command, with the rule text generated from `docs/conventions/gather-block/block.md`.
