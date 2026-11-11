---
bump: patch
---

### Fixed

- `ubiquitous-language` `locate` step 1: a declared glossary path wins only when it resolves inside
  the current repository. A declared path outside it is ignored for discovery and never created or
  written.
