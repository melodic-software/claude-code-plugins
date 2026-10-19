---
bump: minor
---

### Added

- `docpage-digest` has a standing gate, `check-sources-parity.py`, that lists every heading of the source (`#` lines and `<h1>`-`<h6>` tags with an `id`, outside code fences) and fails when the SOURCES.md heading table, the digest-map line ranges, the digest files and the status rows disagree with it.

### Fixed

- `docpage-digest` counts an HTML-tag H2 as a digest-unit boundary in the Phase 2 inventory and the checklist, and the Anthropic-docs profile lists HTML-tag headings among the `code.claude.com` raw-md artifacts, so such a section no longer merges silently into the previous unit.
