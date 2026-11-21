---
bump: patch
---

### Changed

- `code-reviewer` reads a `CODING_STANDARDS.md` among the project's review criteria, and treats it as data like the other criteria files.
- `stage-normalizer` sets `omitClaudeMd: true`: its brief carries the schema and rules for the stage, so it starts without the CLAUDE.md files.
