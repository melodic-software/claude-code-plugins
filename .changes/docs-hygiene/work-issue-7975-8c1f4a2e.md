---
bump: minor
---

### Added

- **`audit-encapsulation detect` flags every cross-plugin skill cite.** In a marketplace monorepo it now reports a skill-root cite, a bare `SKILL.md` cite and a `scripts/` cite from a file under another plugin, as a path, a `../` path or a github.com tree/blob or raw.githubusercontent.com URL; a cite inside the same plugin stays legal. It also flags the repository's own marketplace id (`<plugin>@<id>`) outside install-recipe lines, and reads an allowlist of `path<TAB>reason` rows (`--allowlist <file>`) for fixtures, evals and tests that exercise a detector.

### Changed

- **`audit-encapsulation detect` reads every text file type**, not only md, sh, json, yml and yaml. The `scripts/` entry-surface carve-out now holds only for callers outside `plugins/` and for a plugin's own files.
