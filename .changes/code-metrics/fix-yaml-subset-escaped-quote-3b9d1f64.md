---
bump: patch
---

### Fixed

- The YAML subset reader no longer ends a double-quoted string at a backslash-escaped quote: `x: ["a\",b", c]` now reads as two items, `a",b` and `c`, as the shared `lib/yaml-subset.mjs` reads it, and a `#` comment after such a string is found correctly. The reader stays its own implementation because the plugin requires Python and treats Node as optional.
