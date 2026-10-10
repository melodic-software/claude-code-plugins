---
bump: patch
---

### Fixed

- **stateless points at `claude purge`.** Claude Code 2.1.288 renamed `claude project purge` to `claude purge`, so the skill, its purge flow and its guidance record now name the current command. The record points at the CLI reference and the Clear local data section for the name, flags and former name instead of restating them, and records a source conflict between the changelog and the docs over whether the former name still runs.
- **audit describes path-scoped rule loading correctly.** The audit said a path-scoped rule loads only when Claude reads a matching file, contradicting its own table; since 2.1.288 a write or edit loads it too. The guidance, the R-check notes, R2 and an eval expectation now say Claude working with a matching file, pointing at the memory docs for the exact trigger list, and the nested CLAUDE.md row says read, write or edit.
- **The nested AGENTS.md check stops naming a single trigger.** Its header now records a source conflict between the 2.1.290 changelog and the memory docs over what attaches a subdirectory's AGENTS.md, and leaves the Bash single-file read case open. The check's logic is unchanged.
