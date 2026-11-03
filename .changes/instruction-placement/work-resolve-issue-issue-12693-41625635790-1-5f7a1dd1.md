---
bump: patch
---

### Changed

- **migrate skill**, its shim-droppable reference and the realign apply recipes: the passages that restated Claude Code or Windows documentation now point at the live upstream section with an as-of date and a recheck trigger. The removed passages covered filename case matching, when `InstructionsLoaded` fires, what `/init` writes, the Project instructions values, default and scopes, the import parser and hop limit, the sessions that cannot read `AGENTS.md`, and per-mode load orders. Every condition, operator question and keep-the-shim verdict is unchanged (#12693).
