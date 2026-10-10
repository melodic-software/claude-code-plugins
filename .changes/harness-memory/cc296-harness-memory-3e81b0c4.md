---
bump: patch
---

### Fixed

- **stateless points at `claude purge`.** Claude Code 2.1.288 renamed `claude project purge` to `claude purge`, so the skill, its purge flow and its guidance record now name the current command. The record points at the CLI reference and the Clear local data section for the name, flags and former name instead of restating them, and notes that the old name still runs with a notice.
- **audit describes path-scoped rule loading correctly.** The guidance said a path-scoped rule loads only when Claude reads a matching file, contradicting its own table; since 2.1.288 a write or edit loads it too. The guidance now states the audit's working assumption and points at the memory docs for the exact trigger list, and the nested CLAUDE.md row says read or edit.
- **The nested AGENTS.md check records the @-mention trigger.** Its header now names the @-mention trigger from the 2.1.290 changelog as a source conflict with the memory docs, which still name the Read tool only, and leaves the Bash single-file read case open. The check's logic is unchanged.
