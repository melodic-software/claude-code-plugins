---
bump: minor
---

### Added

- `docpage-digest` has a `check-prose-terms.py` standing gate that fails a digest whose prose (outside fences) names pipeline vocabulary, `unit NN` or `SOURCES.md`, reporting file, section and term.

### Changed

- `docpage-digest`'s mechanism-only rule now covers every prose section, "Open questions for interview" included, and names skills, plugins and conventions visible in the digest agent's own session as consuming-org context.
