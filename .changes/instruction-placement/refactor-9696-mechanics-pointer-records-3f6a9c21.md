---
bump: patch
---

### Changed

- **The loading-mechanics record cites the docs by pointer record** ([#9696](https://github.com/melodic-software/claude-code-plugins/issues/9696)). Each docs-backed cell of the surface table in `context/verified-mechanics.md` now names a record id (`MS-<n>`) instead of a bare *(doc)* marker. The new `context/mechanics-sources.tsv` holds one row per record: the section URL with its anchor, the sentence quoted from that section, and the date it was read. A new "Pointer records" table says what each record decides and when to recheck it. Every measured result now carries the CLI version it ran on, including four that had none. `context/routing-rubric.md` names record ids where it prices a move instead of restating the docs.
- **Cells the docs re-read changed.** The memory page now says a nested `CLAUDE.md` loads on a Read, Write or Edit in its subtree. The skill listing is rebuilt and re-injected after compaction on 2.1.304 and later. A subagent that skips the CLAUDE.md hierarchy (Explore, Plan, `omitClaudeMd`) still loads a nested `CLAUDE.md` or a matching path-scoped rule when it works with files there. A bare nested `AGENTS.md` beside a `CLAUDE.md` never loads only under the default **Project instructions** setting. That a bare nested `AGENTS.md` reloads when its subtree is touched again is now marked inferred, since no docs sentence states it.
