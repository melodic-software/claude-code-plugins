---
bump: patch
---

### Changed

- `/docs-naming:audit-file-names`, `/docs-naming:realign-file-names` gather their repository context as separate Bash calls sent in parallel in one message, one turn instead of one per command, with the rule text generated from `docs/conventions/gather-block/block.md`.
