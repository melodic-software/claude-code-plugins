---
bump: patch
---

### Fixed

- `/instruction-placement:migrate` no longer names only the built-in AGENTS.md plugin's earlier settings ID. The skill body and `reference/sources.md` point at the memory page section that names the current and earlier IDs, and condition B of `reference/shim-droppable.md` reads the **Project instructions** option under both IDs, so a value set under the current ID is no longer missed. The stale quotes about that ID, the `managed-only` loading rule and the unavailable-session list are gone from the record.

### Changed

- The realign recipes point at the live memory page sections for the sessions that lack direct `AGENTS.md` support, how nested instruction files combine, and which rule frontmatter fields Claude Code reads, instead of restating them.
