---
bump: patch
---

### Fixed

- `reference/adr-discovery.md` Rung 1: a declared ADR path counts, and can be created, only when it
  resolves inside the current repository. A declared path outside it is ignored for discovery and
  never created or written.
- The README no longer says the plugin has no `userConfig`.
- The `rd-audit-lists-gone-record` eval scaffold recreates `src/session` after `git rm` empties it.
