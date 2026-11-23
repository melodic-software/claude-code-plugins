---
bump: patch
---

### Changed

- `/planning:audit-answers`, `/planning:design`, `/planning:design-handoff`, `/planning:interview`, `/planning:plan`, `/planning:prd` gather their repository context as separate Bash calls sent in parallel in one message, one turn instead of one per command, with the rule text generated from `docs/conventions/gather-block/block.md`.
- `/planning:devils-advocate` no longer gather repository context that no step read.
