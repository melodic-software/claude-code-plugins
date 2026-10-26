---
bump: patch
---

### Fixed

- `scripts/lib/yaml-subset.mjs` reads an empty sequence item (`-` alone) as `null` when the next line is another item at the same indent, instead of nesting the following items under it.
- A quoted key may hold a doubled `''` in single quotes or a `\"` escape in double quotes; such a key no longer fails with `expected a mapping entry`.
