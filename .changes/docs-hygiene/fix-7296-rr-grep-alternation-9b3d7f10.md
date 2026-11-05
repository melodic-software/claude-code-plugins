---
bump: patch
---

### Fixed

- `/docs-hygiene:rename-references` lets one Grep combine forms in an alternation, provided every form's regex is in it, instead of requiring one call per form. A token-only grep still does not count as a sweep (#7296).
