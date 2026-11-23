---
bump: patch
---

### Changed

- `/docs-hygiene:audit-noise`, `/docs-hygiene:audit-progressive-disclosure`, `/docs-hygiene:compress`, `/docs-hygiene:rename-references` gather their repository context as separate Bash calls sent in parallel in one message, one turn instead of one per command, with the rule text generated from `docs/conventions/gather-block/block.md`.
- `/docs-hygiene:audit-derivability` no longer gather repository context that no step read.
