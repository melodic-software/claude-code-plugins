---
bump: patch
---

### Added

- Three eval cases measure whether a project glossary changes the names `testing:write` gives new tests. They share one prompt and one invented tool-library workspace, `evals/fixtures/tool-library.sh`:
  - `wr-glossary-root` puts the glossary at the root, as `GLOSSARY.md`.
  - `wr-glossary-absent` has no glossary and is the control.
  - `wr-glossary-docs-path` puts the glossary at `docs/glossary.md`. It is expected to fail today, because the skill's walk-up lookup never reaches a sibling `docs/` directory.
  - Each case is graded on three things: whether the tests use the canonical term, whether they avoid the glossary's rejected synonyms, and whether the run read the glossary. The control case has no glossary, so it skips the read check.
  - The measurement is the difference in pass rates between cases. It is not the CLI's with-versus-without-plugin delta.
