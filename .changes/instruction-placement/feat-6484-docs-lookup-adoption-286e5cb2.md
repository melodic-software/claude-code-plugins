---
bump: minor
---

### Changed

- `/instruction-placement:migrate` reads the memory docs page's "Path-specific rules" section through the shared docs lookup ([#6484](https://github.com/melodic-software/claude-code-plugins/issues/6484)): `fetch-docs.sh --cache` fetches and caches it, `docs-cache.sh slice` returns the section, and the page's age is reported. The plugin declares `python3` as an optional prerequisite for pages served only as HTML.
