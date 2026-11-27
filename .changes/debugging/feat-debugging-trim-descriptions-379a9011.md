---
bump: patch
---

### Changed

- Trimmed `/debugging:debug` (1,020 -> 413 chars) and `/debugging:analyze-profile` (630 -> 346 chars) frontmatter descriptions while preserving trigger coverage, `diagnose` no-edit semantics, and sibling boundaries: `/debugging:debug` routes an existing failing test to `/testing:fix-failing` and only a captured profile, trace, or snapshot with no repro to `/debugging:analyze-profile`.
