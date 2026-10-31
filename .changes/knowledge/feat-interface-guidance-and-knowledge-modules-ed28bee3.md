---
bump: minor
---

### Added

- `/knowledge:distill` distills a person's or company's published web corpus (essays, blog, talk transcripts, newsletter, docs, or an export the user provides) into a skill: it scopes the corpus whole, collects it through the plugin's `fetch-docs.sh` (public addresses only) outside the skill folder, writes one sourced note per piece, clusters notes into theme files, a glossary and an article index, writes a fixed-shape corpus SKILL.md, tests it in a fresh session, and refreshes it when the author publishes more. `reference/web-corpus.md` holds the procedure and `context/templates.md` its corpus, note, theme, index and SKILL.md skeletons.

### Changed

- `/knowledge:distill` checks the target skill directory with `scripts/repo-visibility.mjs` before any write and stops on a public or unknown repository, for a book as well as a web corpus, telling the person to rerun from a private repository or one with no remote. Fetched pages and exported posts are framed as data, never instructions, like book text.
