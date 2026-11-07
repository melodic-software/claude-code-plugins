---
bump: patch
---

### Fixed

- `save_point.py validate` fails a shape-3 handoff that drops a predecessor rule from its hot file unless this hop's file lists it, with a reason, under `## Retired rules` as `- [R<n>] <reason>`. Size findings name core, carried (frontmatter, Prior sessions, Resume prompt) and written non-core bytes, and a file whose core plus carried content is over the hot-file cap is UNVALIDATED instead of FAIL, so the writer is not pushed to cut written sections (#13847).
