---
bump: patch
---

### Changed

- The toolchain prerequisite probe reads ecosystem records from `docs/conventions/ecosystems/`, else the legacy `.claude/ecosystems/`, and names the directory it read in its provenance, plus each legacy file a same-named `docs/conventions/ecosystems/` file shadows.
