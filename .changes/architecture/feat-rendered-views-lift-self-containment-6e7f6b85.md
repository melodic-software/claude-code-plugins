---
bump: patch
---

### Changed

- `improve`'s copy of the rendered-views security baseline states the new network rule: a view may
  load a pinned library from a public CDN with a fallback, and an Artifact view stays
  self-contained. The deepening report still fetches nothing, now as its own choice.
