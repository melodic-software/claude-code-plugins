---
bump: patch
---

### Removed

- `resolve-promotion-evidence.mjs --inline` and its tests. No lane calls it: the pr-merge lane reads no promotion evidence. `promotion-evidence-resolution.md` no longer says it does.
